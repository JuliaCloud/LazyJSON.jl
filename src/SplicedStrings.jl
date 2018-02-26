module SplicedStrings

using Base: @propagate_inbounds


struct SplicedString <: AbstractString
    v::Vector{AbstractString}
    SplicedString() = new([])
    SplicedString(a) = new(splice_vector(a))
    SplicedString(a...) = new(splice_vector(a))
end

SplicedString(s::SplicedString) = s

splice_vector(s::SplicedString) = s.v
splice_vector(s::AbstractString) = splice_item(s)
splice_vector(s) = mapreduce(splice_item, vcat, s)

splice_item(i::SplicedString) = i.v
splice_item(i::AbstractString) = isempty(i) ? [] : [i]
splice_item(i) = splice_item(string(i))

function splice_item(ss::SubString{SplicedString})
    sp = ss.string
    i = 1 + ss.offset
    j = ss.offset + ss.ncodeunits
    i_f, i_n, i_i = fragment(sp, i)
    j_f, j_n, j_i = fragment(sp, j)
    if i_f === j_f
        return[SubString(i_f, i_i, j_i)]
    end
    return vcat([SubString(i_f, i_i)],
                view(sp.v, i_n+1:j_n-1),
                [SubString(j_f, 1, j_i)])
end


#https://github.com/JuliaLang/julia/issues/26200
Base.promote_rule(::Type{<:AbstractString},
                  ::Type{<:AbstractString}) = AbstractString

#https://github.com/JuliaLang/julia/issues/26202
Base.nextind(s::SubString{SplicedString}, i::Int) = nextind(s.string, i)
Base.prevind(s::SubString{SplicedString}, i::Int) = prevind(s.string, i)

function convert(::Type{String}, ss::SplicedString)
    buf = IOBuffer()
    for i in ss.v
        write(buf, i)
    end
    return String(take!(buf))
end

Base.String(ss::SplicedString) =  convert(String, ss)



# Indexing Implementation

"""
64-bit SplicedString index: [24 bit fragment number][40 bit fragment index]
"""
const fragment_bits = 40
const index_mask = 2 ^ fragment_bits - 1
const fragment_mask = ~index_mask

function fragment_si(s::SplicedString, i)
    n = i >> fragment_bits + 1
    @inbounds f = s.v[n]
    i = i & index_mask
    return f, i
end

function fragment(s::SplicedString, i)
    n = i >> fragment_bits + 1
    f = s.v[n]
    i = i & index_mask
    return f, n, i
end



# Non-sparse Code Units view

mutable struct SplicedCodeUnits <: DenseVector{UInt8}
    s::SplicedString
    v::Vector{AbstractString}
    ncodeunits::Int
    fragment_i::Int
    offset::Int
    codeunits::Vector{UInt8}
    last_i::Int
    function SplicedCodeUnits(s)
        ncu = isempty(s.v) ? 0 : sum(ncodeunits, s.v)
        cu = isempty(s.v) ? UInt8[] : codeunits(s.v[1])
        new(s, s.v, ncu, 1, 0, cu, length(cu))
    end
end

Base.String(cu::SplicedCodeUnits) = cu.s

Base.length(s::SplicedCodeUnits) = s.ncodeunits
Base.sizeof(s::SplicedCodeUnits) = length(s)
Base.size(s::SplicedCodeUnits) = (length(s),)
Base.strides(s::SplicedCodeUnits) = (1,)
Base.IndexStyle(::Type{<:SplicedCodeUnits}) = IndexLinear()

@propagate_inbounds function Base.getindex(s::SplicedCodeUnits, i::Int)

    while i > s.last_i
        if i > s.ncodeunits
            return 0x00
            throw(BoundsError(s, i))
        end
        s.offset = s.last_i
        s.fragment_i += 1
        cu = codeunits(s.v[s.fragment_i])
        s.codeunits = cu
        s.last_i += length(cu)
    end
    while i - 1 < s.offset
        if i < 1
            throw(BoundsError(s, i))
        end
        s.last_i = s.offset
        s.fragment_i -= 1
        s.codeunits = codeunits(s.v[s.fragment_i])
        s.offset -= length(s.codeunits)
    end

    return s.codeunits[i - s.offset]
end

Base.start(s::SplicedCodeUnits) = 1
@propagate_inbounds Base.next(s::SplicedCodeUnits, i) = (s[i], i+1)
@inline Base.done(s::SplicedCodeUnits, i) = i == s.ncodeunits+1

function next_ichar(s::SplicedCodeUnits, i::Int)
    i -= s.offset
    f = s.v[s.fragment_i]
    c = f[i]
    return s.offset + nextind(f, i) - 1, c
end


function sparseindex(s::SplicedCodeUnits, i)
    getindex(s, i)
    return (s.fragment_i - 1) << fragment_bits | i - s.offset
end




# Modification Interface

Base.append!(ss::SplicedString, s) = append!(s, string(s))
Base.append!(ss::SplicedString, s::AbstractString) = push!(ss.v, s)

Base.splice!(s::SplicedString, i::UnitRange, x) =
    splice!(s, i.start, i.stop, x)



# Modification Implementation

function Base.splice!(s::SplicedString, i::Int, j::Int, x)

    i_f, i_n, i_i = fragment(s, i)          # Exctract fragment,
    j_f, j_n, j_i = fragment(s, j)          # number and index.

                  isvalid(i_f, i_i)      || throw(ArgumentError("invalid `i`"))
    j == i - 1 || isvalid(s.v[j_n], j_i) || throw(ArgumentError("invalid `j`"))


    if i_i > 1
        i_i = prevind(i_f, i_i)             # Extract head of fragment
        s.v[i_n] = SubString(i_f, 1, i_i)   # at the start of the splice.
        i_n += 1
    end

    if j_i > 0
        j_i = nextind(j_f, j_i)             # Extract tail of fragment
        if isvalid(j_f, j_i)                # at the end of the splice.
            s.v[j_n] = SubString(j_f, j_i)
        else                                # If the enitre tail is replaced
            j_n += 1                        # skip to the next fragment.
        end
    end

    v = splice_vector(x)                    # No nested SplicedStrings!
    @assert  all(i -> i isa AbstractString, v)
    @assert !any(isempty, v)
    @assert !any(i -> i isa SplicedString, v)
    @assert !any(i -> i isa SubString{SplicedString}, v)

    splice!(s.v, i_n:j_n-1, v)              # Splice the new fragments into `s`.
end



# AbstractString Interface

Base.codeunit(s::SplicedString) = UInt8

@propagate_inbounds Base.codeunit(s::SplicedString, i::Int) =
    codeunit(fragment_si(s, i)...)

densecodeunits(s::SplicedString) = SplicedCodeUnits(s)

function Base.ncodeunits(s::SplicedString)
    l = length(s.v)
    return l == 0 ? 0 : (l - 1) << fragment_bits | ncodeunits(last(s.v))
end

Base.length(s::SplicedString) = isempty(s.v) ? 0 : sum(length, s.v)

@propagate_inbounds Base.isvalid(s::SplicedString, i::Int) =
    isempty(s.v) ? false : isvalid(fragment_si(s, i)...)

@propagate_inbounds function Base.next(s::SplicedString, i::Integer)
    fs, fi = fragment_si(s, i)
    c, fi = next(fs, fi)
    l = ncodeunits(fs)
    if fi <= l
        i = i & fragment_mask | fi
    else
        i = nextind(s, i)
    end
    return c, i
end


function Base.nextind(s::SplicedString, i::Int)
    fs, fi = fragment_si(s, i)
    if fi == 0
        return i | 1
    end
    fi = nextind(fs, fi)
    l = ncodeunits(fs)
    if fi > l
        n = i >> fragment_bits + 1
        if n < length(s.v)
            return n << fragment_bits | 1
        end
    end
    return i & fragment_mask | fi
end

Base.thisind(s::SplicedString, i::Int) = i & fragment_mask |
                                         thisind(fragment_si(s, i)...)

function Base.prevind(s::SplicedString, i::Int)
    fs, fi = fragment_si(s, i)
    fi = prevind(fs, fi)
    if fi == 0
        n = (i >> fragment_bits)
        if n == 0
            return 0
        else
            n -= 1
            return n << fragment_bits | lastindex(s.v[n+1])
        end
    end
    return i & fragment_mask | fi
end



end # module SplicedString
