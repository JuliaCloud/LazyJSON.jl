"""
`string(::JSON.Number)` creates a `Base.SubString` without copying.
This is a verbatim substring of the JSON text.
"""

Base.string(n::JSON.Number) = SubString(n.bytes.s, n.first, n.last)


"""
`convert(Base.Number, JSON.Number)` parses the number string and returns
`Int64` or `Float64`.

Methods are also defined for basic arithmetic operators: +, -, *, /, and ^.
Promotion rules are defined to promote JSON.Number to `Int64` and `Float64`.
"""

function Base.convert(::Type{Base.Number}, n::JSON.Number)
    s = string(n)
    v = tryparse(Int, s)
    if v == nothing
        v = tryparse(Float64, s)
    end
    if v == nothing
        throw(InexactError(:convert, Base.Number, s))
    end
    return v
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
Base.Int(n::JSON.Number) = convert(Base.Int, n)
Base.Int64(n::JSON.Number) = convert(Base.Int64, n)
Base.Float64(n::JSON.Number) = convert(Base.Float64, n)


import Base: +, -, *, /, ^
+(a::T, b::T) where {T <: JSON.Number} = promotejson(a) + promotejson(b)
-(a::T, b::T) where {T <: JSON.Number} = promotejson(a) - promotejson(b)
*(a::T, b::T) where {T <: JSON.Number} = promotejson(a) * promotejson(b)
/(a::T, b::T) where {T <: JSON.Number} = promotejson(a) / promotejson(b)
^(a::T, b::T) where {T <: JSON.Number} = promotejson(a) ^ promotejson(b)


Base.promote_rule(::Type{T}, ::Type{JSON.Number}) where T <: Integer = Int64
Base.promote_rule(::Type{T}, ::Type{JSON.Number}) where T <: AbstractFloat = Float64
