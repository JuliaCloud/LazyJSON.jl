# Base.Number interface for JSON.Number

"""
`convert(Base.Number, JSON.Number)` parses the number string and returns
`Int64`, `Int128`, `Float64`, `BigInt` or `BigFloat`.

Methods are also defined for basic arithmetic operators: +, -, *, /, and ^.
Promotion rules are defined to promote JSON.Number to `Int64` and `Float64`.
"""
Base.convert(::Type{Base.Number}, n::JSON.Number) = parse_number(n.s, n.i)[1]

function old_parse_number(s, i)
    last_i = lastindex_of_number(s, i)
    ss = SubString(s, i, last_i)
    v = tryparse(Int, ss)
    if v == nothing
        v = tryparse(Int128, ss)
    end
    if v == nothing
        v = tryparse(BigInt, ss)
    end
    if v == nothing || v >=0 && getc(s, i) == '-' # for -0
        v = tryparse(Float64, ss)
    end
    if v == nothing
        v = tryparse(BigFloat, ss)
    end
    return v, last_i
end
"""
https://tools.ietf.org/html/rfc7159#section-6

      number = [ minus ] int [ frac ] [ exp ]

      decimal-point = %x2E       ; .

      digit1-9 = %x31-39         ; 1-9

      e = %x65 / %x45            ; e E

      exp = e [ minus / plus ] 1*DIGIT

      frac = decimal-point 1*DIGIT

      int = zero / ( digit1-9 *DIGIT )

      minus = %x2D               ; -

      plus = %x2B                ; +

      zero = %x30                ; 0

"""
function parse_number(s, i)

    start_i = i
    end_i = i

    v = Int64(0)

    # minus
    c = c1 = getc(s, i)
    if c1 == '-'
        i, c = next_ic(s, i)
    end

    # int
    while (decimal = c - UInt8('0')) < UInt8(10)
        end_i = i
        v = 10v + decimal
        if v < 0
            i = lastindex_of_number(s, i)     # If v overflows, give up
            ss = SubString(s, start_i, i)     # and try larger types...
            v = tryparse(Int128, ss)
            if v == nothing
                v = tryparse(BigInt, ss)
                if v == nothing
                    v = tryparse(BigFloat, ss)
                end
            end
            return v, i
        end
        i, c = next_ic(s, i)
    end

    # frac
    if c == UInt8('.')
        f = Int64(0)
        d = 1
        i, c = next_ic(s, i)
        while (decimal = c - UInt8('0')) < UInt8(10)
            end_i = i
            f = 10f + decimal
            d *= 10
            if d > 10 ^ 15
                i = lastindex_of_number(s, i) # If there is too much precision
                ss = SubString(s, start_i, i) # for in Float64, use BigFloat...
                v = tryparse(BigFloat, ss)
                return v, i
            end
            i, c = next_ic(s, i)
        end
        v += f/d
    end

    # exp
    if c == UInt8('e') ||                     # If there is an exponent, give up
       c == UInt8('E')                        # and use the system parser for
        i = lastindex_of_number(s, i)         # Float64, or BigFloat...
        ss = SubString(s, start_i, i)
        v = tryparse(Float64, ss)
        if v == nothing
            v = tryparse(BigFloat, ss)
        end
        return v, i
    end

    # apply minus
    if c1 == '-'
        if v == 0                             # Check for "-0"
            v = Float64(0) * -1
        else
            v *= -1
        end
    end

    if c == IOStrings.ASCII_ETB
        throw(JSON.ParseError(s, i, c, "unexpected end of number"))
    end

    return v, end_i
end

Base.Number(n::JSON.Number) = convert(Base.Number, n)

Base.Int8(n::JSON.Number)::Int8 = Base.Number(n)
Base.Int16(n::JSON.Number)::Int16 = Base.Number(n)
Base.Int32(n::JSON.Number)::Int32 = Base.Number(n)
Base.Int64(n::JSON.Number)::Int64 = Base.Number(n)
Base.Int128(n::JSON.Number)::Int128 = Base.Number(n)
Base.UInt8(n::JSON.Number)::UInt8 = Base.Number(n)
Base.UInt16(n::JSON.Number)::UInt16 = Base.Number(n)
Base.UInt32(n::JSON.Number)::UInt32 = Base.Number(n)
Base.UInt64(n::JSON.Number)::UInt64 = Base.Number(n)
Base.UInt128(n::JSON.Number)::UInt128 = Base.Number(n)
Base.BigInt(n::JSON.Number)::BigInt = Base.Number(n)
Base.Float64(n::JSON.Number)::Float64 = Base.Number(n)
Base.BigFloat(n::JSON.Number)::BigFloat = Base.Number(n)


import Base: +, -, *, /, ^
+(a::T, b::T) where {T <: JSON.Number} = Base.Number(a) + Base.Number(b)
-(a::T, b::T) where {T <: JSON.Number} = Base.Number(a) - Base.Number(b)
*(a::T, b::T) where {T <: JSON.Number} = Base.Number(a) * Base.Number(b)
/(a::T, b::T) where {T <: JSON.Number} = Base.Number(a) / Base.Number(b)
^(a::T, b::T) where {T <: JSON.Number} = Base.Number(a) ^ Base.Number(b)

Base.isless(a::Base.Number, b::JSON.Number) = isless(a, convert(Base.Number, b))
Base.isless(a::JSON.Number, b::Base.Number) = isless(convert(Base.Number, a), b)


Base.promote_rule(
    ::Type{T}, ::Type{JSON.Number{S}}) where {S, T <: Integer} = Int64
Base.promote_rule(
    ::Type{T}, ::Type{JSON.Number{S}}) where {S, T <: AbstractFloat} = Float64

Base.show(io::IO, n::JSON.Number) = print(io, string(n))

module tmp
import Base.==
import ..JSON
==(a::JSON.Number, b::JSON.Number) = convert(Base.Number, a) ==
                                     convert(Base.Number, b)
end


# IOString Wrappers

Base.convert(::Type{Base.Number}, j::JSON.Number{IOString{T}}) where T =
    pump(() -> parse_number(j.s, j.i)[1], j.s)
