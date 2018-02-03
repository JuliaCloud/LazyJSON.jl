Base.length(o::JSON.Object) = (parse_all!(o); div(length(o.v),2))

function Base.get(o::JSON.Object, i::Int, d)
    i *= 2
    parse_more!(o, i)
    return getjson(o.v, i-1) => getjson(o.v, i)
end

function Base.get(o::JSON.Object, key::AbstractString, default)
    keybytes = codeunits(key)
    v = o.v
    i = 1
    while i < length(v) || !o.iscomplete
        while i+1 > length(v)
            parse_more!(o.parser)
        end
        k = @inbounds(v[i])
        if @inbounds(view(k.bytes, k.first:k.last)) == keybytes
            return v[i+1]
        end
        i += 2
    end
    return default
end


Base.IteratorSize(::Type{JSON.Object}) = Base.SizeUnknown()
Base.start(o::JSON.Object) = 1
Base.done(o::JSON.Object, i) = (parse_more!(o, 2i); 2i > length(o.v))
Base.next(o::JSON.Object, i) = (getindex(o, i), i + 1)


struct ObjectKeys
    o::JSON.Object
end

Base.keys(o::JSON.Object) = ObjectKeys(o)

Base.IteratorSize(::Type{ObjectKeys}) = Base.SizeUnknown()
Base.start(k::ObjectKeys) = 1
Base.done(k::ObjectKeys, i) = (parse_more!(k.o, 2i); 2i > length(k.o.v))
Base.next(k::ObjectKeys, i) = (getindex(k.o.v, 2i-1), i + 1)
