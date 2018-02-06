
Base.convert(::Type{T}, o::JSON.Object) where T <: AbstractDict =
    convert(T, Dict(convert(SubString, k) => v for (k,v) in o))

Base.Dict(o::JSON.Object) = convert(Dict, o)


Base.start(j::JSON.Object) = (j.i, Ref(0), 0x00)

function Base.done(j::JSON.Object, (i, n, c))
    i, c = nextindex(j, i, n, c)
    return c == ']' || c == '}'
end

function Base.next(j::JSON.Object, (i, n, c))
    i, c = nextindex(j, i, n, c)
    k = getvalue(j.s, i, c)
    i, c = nextindex(j, i, n, c)
    v = getvalue(j.s, i, c)
    return k => v, (i, n, c)
end

Base.IteratorSize(::Type{JSON.Object{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Object{T}}) where T = Base.EltypeUnknown()


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


function Base.length(a::JSON.Object)
    count = 0
    for i in a
        count += 1
    end
    return count
end


#=
function Base.get(o::JSON.Object, i::Int, d)
#=    i *= 2
    parse_more!(o, i)
    return getjson(o.v, i-1) => getjson(o.v, i) =#
end

function Base.get(o::JSON.Object, key::AbstractString, default)
#=    keybytes = codeunits(key)
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
    return default =#
end


Base.IteratorSize(::Type{JSON.Object}) = Base.SizeUnknown()
Base.start(o::JSON.Object) = 1
#Base.done(o::JSON.Object, i) = (parse_more!(o, 2i); 2i > length(o.v))
Base.next(o::JSON.Object, i) = (getindex(o, i), i + 1)


struct ObjectKeys
    o::JSON.Object
end

Base.keys(o::JSON.Object) = ObjectKeys(o)

Base.IteratorSize(::Type{ObjectKeys}) = Base.SizeUnknown()
Base.start(k::ObjectKeys) = 1
#Base.done(k::ObjectKeys, i) = (parse_more!(k.o, 2i); 2i > length(k.o.v))
Base.next(k::ObjectKeys, i) = (getindex(k.o.v, 2i-1), i + 1)
=#
