module SplicedStrings

#=
FIXME

Options for fast parser traversal:

    Codunits iterator with tuple (fragment_n, max_pointer, pointer)

    64-bit index containing [fragment_n, sentinal_bits, p]
        where p is a pointer into s.v[fragment_n]
        and sentinal_bits are the last few bits for the max value of i
        if the sentinal_bits match, check bounds of s.v[fragment_n]
            otherwise, just increment pointer
=#



using Base: @propagate_inbounds

const Fragment = SubString{String}

const index_offset = 0

mutable struct SplicedString <: AbstractString
    v::Vector{Fragment}
    ncodeunits::Int
    SplicedString() = SplicedString([], 0)
    SplicedString(a) = update!(new(splice_vector(a), 0))
    SplicedString(a...) = update!(new(splice_vector(a), 0))
end

function update!(s::SplicedString)
    l = length(s.v)
    s.ncodeunits = l == 0 ? 0 : (l - 1) << fragment_bits | ncodeunits(last(s.v)) + index_offset
    return s
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
Base.keys(s::SubString{SplicedString}) = keys(s.string)


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
64-bit SplicedString index:

    fragment number 24 bits
    fragment index 40 bits
"""
const fragment_bits = 40
const index_mask = 2 ^ fragment_bits - 1
const fragment_mask = ~index_mask

@propagate_inbounds function fragment_si(s::SplicedString, i::Int)
    n = i >> fragment_bits + 1
    v = s.v
    f = @inbounds v[n]
    if i != 1
        i = i & index_mask - index_offset
    end
    return f, i
end

@propagate_inbounds function fragment(s::SplicedString, i::Int)
    n = i >> fragment_bits + 1
    v = s.v
    f = @inbounds v[n]
    if i != 1
        i = i & index_mask - index_offset
    end
    return f, n, i
end



# Non-sparse Code Units view
#=
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
=#


# Index Iteration Interface


#Base.keys(s::SplicedString) = Base.EachStringIndex{SplicedString}(s)

#Base.first(s::Base.EachStringIndex{SplicedString}) = firstindex(s.s)


# Modification Interface

Base.append!(ss::SplicedString, s) = append!(s, string(s))
function Base.append!(ss::SplicedString, s::AbstractString)
    push!(ss.v, s)
    update!(ss)
end

Base.splice!(s::SplicedString, i::UnitRange, x) =
    splice!(s, i.start, i.stop, x)



# Modification Implementation

function Base.splice!(s::SplicedString, i::Int, j::Int, x)

    i_f, i_n, i_i = fragment(s, i)          # Exctract fragment,
    j_f, j_n, j_i = fragment(s, j)          # number and index.

                  isvalid(i_f, i_i) || throw(ArgumentError("invalid `i`"))
    j == i - 1 || isvalid(j_f, j_i) || throw(ArgumentError("invalid `j`"))


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
    update!(s)
end



# AbstractString Interface

Base.codeunit(s::SplicedString) = UInt8

@propagate_inbounds Base.codeunit(s::SplicedString, i::Int)::UInt8 =
    codeunit(fragment_si(s, i)...)

#densecodeunits(s::SplicedString) = SplicedCodeUnits(s)

#Base.firstindex(s::SplicedString) = index_offset + 1
#Base.start(s::SplicedString) = 1

# AbstractString has fixed first index = 1
#Base.checkbounds(::Type{Bool}, s::SplicedString, i::Integer) =
#    firstindex(s) ≤ i ≤ ncodeunits(s)
#
#Base.checkbounds(::Type{Bool}, s::SplicedString, r::AbstractRange{<:Integer}) =
#    isempty(r) || (firstindex(s) ≤ minimum(r) && maximum(r) ≤ ncodeunits(s))

Base.ncodeunits(s::SplicedString) = s.ncodeunits

Base.length(s::SplicedString) = isempty(s.v) ? 0 : sum(length, s.v)

function Base.length(s::SplicedString, i::Int, j::Int)

    i_f, i_n, i_i = fragment(s, i)          # Exctract fragment,
    j_f, j_n, j_i = fragment(s, j)          # number and index.

    if i_n > j_n
        return 0
    end

    if i_n == j_n
        return length(i_f, i_i, j_i)
    end

    return length(i_f, i_i, lastindex(i_f)) +
           (j_n <= i_n + 1 ? 0 : sum(length, view(s.v, i_n+1:j_n-1))) +
           length(j_f, 1, j_i)
end

@propagate_inbounds(
function nextcodeunitindex(s::SplicedString, i::Integer)

#=
A:
    increment encoded_index
    check encoded index for overflow
        ... special case
    decode fragment number
    decode fragment index
    fetch fragment
    fetch character from fragment index

B:
    increment pointer
    fetch char
        check for overflow
=#

    if i == 1
        i += index_offset
    end
    i += 1
    fs, fi = fragment_si(s, i)
    l = ncodeunits(fs)
    if fi > l
        n = i >> fragment_bits + 1
        if n < length(s.v)
            i = n << fragment_bits | 1 + index_offset
        end
    end
    return i
end)

@propagate_inbounds(
function nextcodeunit(s::SplicedString, i::Integer)
    if i == 1
        i += index_offset
    end
    i += 1
    fs, fi = fragment_si(s, i)
    l = ncodeunits(fs)
    if fi > l
        n = i >> fragment_bits + 1
        if n < length(s.v)
            i = n << fragment_bits | 1 + index_offset
            c = @inbounds codeunit(s, i)
        else
            c = 0x00
        end
    else
        c = @inbounds codeunit(fs, fi)
    end
    return i, c
end)

@propagate_inbounds(
function Base.isvalid(s::SplicedString, i::Int)

    if isempty(s.v)
        return false
    end
    if i == 1
        return true
    end
    if i <= index_offset + 1
        return false
    end

    return isvalid(fragment_si(s, i)...)
end)

@propagate_inbounds(
function Base.iterate(s::SplicedString, i::Integer=1)
    if i == index_offset || isempty(s.v)
        return nothing
    end
    fs, fi = fragment_si(s, i)
    c, fi = @inbounds iterate(fs, fi)
    l = ncodeunits(fs)
    i = i & fragment_mask | fi + index_offset
    if fi > l
        n = i >> fragment_bits + 1
        if n < length(s.v)
            i = n << fragment_bits | 1 + index_offset
        else
            i = index_offset
        end
    end
    return c, i
end)

@propagate_inbounds(
function Base.nextind(s::SplicedString, i::Int)::Int
    if i == 0
        return 1
    end
    fs, fi = fragment_si(s, i)
    fi = @inbounds nextind(fs, fi)
    l = ncodeunits(fs)
    if fi > l
        n = i >> fragment_bits + 1
        if n < length(s.v)
            return n << fragment_bits | 1 + index_offset
        end
    end
    return i & fragment_mask | fi + index_offset
end)

@propagate_inbounds(
function Base.thisind(s::SplicedString, i::Int)

    if i <= 1 || isempty(s.v)
        return i
    end

    return i & fragment_mask | thisind(fragment_si(s, i)...) + index_offset
end)

@propagate_inbounds(
function Base.prevind(s::SplicedString, i::Int)
    if i == 1
        return 0
    end
    fs, fi = fragment_si(s, i)
    fi = prevind(fs, fi)
    if fi == 0
        n = (i >> fragment_bits)
        if n == 0
            return 0
        else
            n -= 1
            return n << fragment_bits | lastindex(s.v[n+1]) + index_offset
        end
    end
    return i & fragment_mask | fi + index_offset
end)



end # module SplicedString
