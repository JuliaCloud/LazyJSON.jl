# AbstractArray interface for JSON.Array

Base.IteratorSize(::Type{JSON.Array{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Array{T}}) where T = Base.EltypeUnknown()


# Access

Base.getindex(a::JSON.Array, i::Integer) = getvalue(a.s, getindex_ic(a, i)...)


# Dimensions

Base.length(a::JSON.Array) = collection_length(a)

Base.size(a::JSON.Array) = (length(a), )


# Iterate

function Base.iterate(j::JSON.Array, (i, c) = (j.i, 0x00))
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
    pump(() -> getvalue(x, getindex_ic(j, i)...), j.s)

# FIXME
#Base.done(j::JSON.Array{IOString{T}}, i) where T =
#    pump(() -> _done(j, i), j.s)

#Base.next(j::JSON.Array{IOString{T}}, i) where T =
#    pump(() -> _next(j, i), j.s)
