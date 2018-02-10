# AbstractArray interface methods

Base.IteratorSize(::Type{JSON.Array{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Array{T}}) where T = Base.EltypeUnknown()


# Access

Base.getindex(a::JSON.Array, i::Integer) = getvalue(a.s, getindex_ic(a, i)...)


# Dimensions

Base.length(a::JSON.Array) = collection_length(a)

Base.size(a::JSON.Array) = (length(a), )


# Iterate

Base.start(j::JSON.Array) = (j.i, Ref(0), 0x00)

function Base.done(j::JSON.Array, (i, n, c))
    i, c = nextindex(j, i, n, c)
    return c == ']'
end

function Base.next(j::JSON.Array, (i, n, c))
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
