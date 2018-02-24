module SplicedStrings

export SplicedString

struct SplicedString <: AbstractString
    v::Vector{SubString}
end


Base.append!(ss::SplicedString, s) = append!(s, SubString(s))
Base.append!(ss::SplicedString, s::SubString) = push!(ss.v, s)

splice(s::AbstractString, i, x::AbstractString) =
    SplicedString([SubString(s, 1, i), x, SubString(s, i+1)])

function splice(s::SplicedString, i, j, x::AbstractString)
    check for i being on boundary and splice into v
    otherwise split
end

"""
64-bit SplicedString index: [24 bit fragment number][40 bit fragment index]
"""
const fragment_bits = 40
const index_mask = UInt(2 ^ fragment_bits - 1)
const fragment_mask = ~index_mask

fragment(s::SplicedString, i) = (s.v[i >> fragment_bits + 1], i & index_mask)

Base.codeunit(s::SplicedString) = UInt8

Base.codeunit(s::SplicedString, i::Int) = codeunit(fragment(s, i)...)
Base.ncodeunits(s::SplicedString) = ((length(s.v) - 1) << fragment_bits) |
                                    ncodeunits(last(s.v))
Base.length(s::SplicedString) = sum(length, s.v)
Base.isvalid(s::SplicedString, i::Int) = isvalid(fragment(s, i)...)

function Base.next(s::SplicedString, i::Integer)
    fs, fi = fragment(s, i)
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
    fs, fi = fragment(s, i)
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
                                         thisind(fragment(s, i)...)

function Base.prevind(s::SplicedString, i::Int)
    fs, fi = fragment(s, i)
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


using Test

using .SplicedStrings

ss = SplicedString(["Hello", " ", "world", "!"])

i = 0 << 40 | 0 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('H')
i = 0 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('e')
i = 0 << 40 | 3 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('l')
i = 0 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('l')
i = 0 << 40 | 5 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1 ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('o')
i = 1 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 2 << 40 | 1 ; @test prevind(ss, i) == 0 << 40 | 5 ; @test codeunit(ss, i) == UInt8(' ')
i = 2 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == 1 << 40 | 1 ; @test codeunit(ss, i) == UInt8('w')
i = 2 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('o')
i = 2 << 40 | 3 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('r')
i = 2 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('l')
i = 2 << 40 | 5 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 3 << 40 | 1 ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('d')
i = 3 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == 2 << 40 | 5 ; @test codeunit(ss, i) == UInt8('!')
i = 3 << 40 | 2 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i)                                       ; @test prevind(ss, i) == i - 1
                  @test ncodeunits(ss) == 3 << 40 | 1
                  @test length(ss) == 12
@show ss


ss = SplicedString(["\u1234x", "x\u1234"])

i = 0 << 40 | 0 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 3
i = 0 << 40 | 2 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 2
i = 0 << 40 | 3 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 1 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 3
i = 1 << 40 | 3 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 2
i = 1 << 40 | 4 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 5 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i)
                  @test ncodeunits(ss) == 1 << 40 | 4
                  @test length(ss) == 4
@show ss


ss = SplicedString(["x\u1234", "\u1234x"])

i = 0 << 40 | 0 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 0 << 40 | 3 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 0 << 40 | 4 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 1 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 3
i = 1 << 40 | 2 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 2
i = 1 << 40 | 3 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 5 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i)
                  @test ncodeunits(ss) == 1 << 40 | 4
                  @test length(ss) == 4
@show ss
