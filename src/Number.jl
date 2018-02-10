# Number interface methods

"""
`convert(Base.Number, JSON.Number)` parses the number string and returns
`Int64` or `Float64`.

Methods are also defined for basic arithmetic operators: +, -, *, /, and ^.
Promotion rules are defined to promote JSON.Number to `Int64` and `Float64`.
"""

#FIXME
#https://github.com/JuliaComputing/TextParse.jl
#https://github.com/JuliaLang/julia/issues/24015

Base.convert(::Type{Base.Number}, n::JSON.Number) = parse_number(n.s, n.i)[1]

function parse_number(s, i)
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

function Base.convert(::Type{T}, n::JSON.Number) where T <: Union{Int64, Float64}
    s = string(n)
    v = tryparse(T, s)
    if v == nothing
        throw(InexactError(:convert, T, s))
    end
    return v
end

Base.Number(n::JSON.Number) = convert(Base.Number, n)
Base.Int64(n::JSON.Number) = convert(Base.Int64, n)
Base.Float64(n::JSON.Number) = convert(Base.Float64, n)


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
