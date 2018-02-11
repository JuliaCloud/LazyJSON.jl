# AbstractDict interface for JSON Object

Base.IteratorSize(::Type{JSON.Object{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Object{T}}) where T = Base.EltypeUnknown()


# Access

function Base.getindex(o::JSON.Object, key)
    v = get(o, key, :not_found)
    if v == :not_found
        throw(KeyError(key))
    end
    return v
end

function Base.get(o::JSON.Object, key, default)
    i, c = get_ic(o, key, (0, 0x00))
    if i == 0
        return default
    end
    return getvalue(o.s, i, c)
end


# Dimensions

Base.length(a::JSON.Object) = div(collection_length(a), 2)


# Iterate

Base.start(j::JSON.Object) = (j.i, Ref(0), 0x00)

function Base.done(j::JSON.Object, (i, n, c))
    i, c = nextindex(j, i, n, c)
    return c == '}'
end

function Base.next(j::JSON.Object, (i, n, c))
    i, c = nextindex(j, i, n, c)
    k = getvalue(j.s, i, c)
    i, c = nextindex(j, i, n, c)
    v = getvalue(j.s, i, c)
    return k => v, (i, n, c)
end
