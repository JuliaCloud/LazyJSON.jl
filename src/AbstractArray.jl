# AbstractArray interface for JSON.Array

Base.IteratorSize(::Type{JSON.Array{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Array{T}}) where T = Base.EltypeUnknown()


# Access

Base.getindex(a::JSON.Array, i::Integer) = getvalue(a.s, getindex_ic(a, i)...)


# Dimensions

Base.length(a::JSON.Array) = collection_length(a)

Base.size(a::JSON.Array) = (length(a), )


# Iterate

Base.iterate(j::JSON.Array, i = (j.i, 0x00)) = _iterate(j, i)
function _iterate(j::JSON.Array, (i, c))
    i, c = nextindex(j, i, c)
    if c == ']'
        return nothing
    end
    return getvalue(j.s, i, c), (i, c)
end


# IOString Wrappers

Base.length(j::JSON.Array{IOString{T}}) where T =
    pump(() -> collection_length(j), j.s)

Base.getindex(j::JSON.Array{IOString{T}}, i::Integer) where T =
    pump(() -> getvalue(j.s, getindex_ic(j, i)...), j.s)

Base.iterate(j::JSON.Array{IOString{T}}, i = (j.i, 0x00)) where T =
    pump(() -> _iterate(j, i), j.s)
