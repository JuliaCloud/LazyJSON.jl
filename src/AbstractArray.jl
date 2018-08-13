# AbstractArray interface for JSON.Array

Base.IteratorSize(::Type{JSON.Array{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Array{T}}) where T = Base.EltypeUnknown()


# Access

Base.getindex(a::JSON.Array, i::Integer) = getvalue(a.s, getindex_ic(a, i)...)


# Dimensions

Base.length(a::JSON.Array) = collection_length(a)

Base.size(a::JSON.Array) = (length(a), )


# Iterate

#Base.start(j::JSON.Array) = (j.i, Ref(0), 0x00)
#Base.done(j::JSON.Array, i) = _done(j, i)
#Base.next(j::JSON.Array, i) = _next(j, i)

function Base.iterate(j::JSON.Array, i = (j.i, Ref(0), 0x00))
    if _done(j, i)
        return nothing
    end
    return _next(j, i)
end

function _done(j::JSON.Array, (i, n, c))
    i, c = nextindex(j, i, n, c)
    n[] = i
    return c == ']'
end

function _next(j::JSON.Array, (i, n, c))
    i, c = nextindex(j, i, n, c)
    return getvalue(j.s, i, c), (i, n, c)
end

function nextindex(j, i, n, c)
    if n[] > 0
        i = n[]
        n[] = 0
        c = getc(j.s, i)
    else
        i, c = nextindex(j, i, c)
    end
    return i, c
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
