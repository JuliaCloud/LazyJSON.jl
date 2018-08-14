# AbstractDict interface for JSON Object

Base.IteratorSize(::Type{JSON.Object{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Object{T}}) where T = Base.EltypeUnknown()


# Access

function Base.getindex(o::JSON.Object, key)
    v = get(o, key, :not_found)
    if v === :not_found
        throw(KeyError(key))
    end
    return v
end

Base.get(o::JSON.Object, key, default) = _get(o, key, default)
function _get(o::JSON.Object, key, default)
    i, c = get_ic(o, key, (0, 0x00))
    if i == 0
        return default
    end
    return getvalue(o.s, i, c)
end


# Dimensions

Base.length(a::JSON.Object) = div(collection_length(a), 2)


# Iterate

function Base.iterate(j::JSON.Object, (i, c) = (j.i, 0x00))

    i, c = nextindex(j, i, c)

    if c == '}'
        return nothing
    end

    k = getvalue(j.s, i, c)
    i, c = nextindex(j, i, c)
    v = getvalue(j.s, i, c)

    return k => v, (i, c)
end


# Conversion to Dict Types

Base.convert(::Type{Any}, o::JSON.Object) = o

Base.convert(::Type{JSON.Object{T}},
                 o::JSON.Object{T}) where T <: AbstractString = o

Base.convert(::Type{T}, o::JSON.Object) where T <: AbstractDict = T(o)


# Conversion to Struct Types

#https://github.com/JuliaLang/julia/issues/26090
isreserved(s::Symbol) = s in (
    :while, :if, :for, :try, :return, :break, :continue,
    :function, :macro, :quote, :let, :local, :global, :const, :do,
    :struct,
    :type, :immutable, :importall,  # to be deprecated
    :module, :baremodule, :using, :import, :export,
    :end, :else, :catch, :finally, :true, :false)

unmangled_fieldnames(T) = [n[1] == '_' &&
                           isreserved(Symbol(n[2:end])) ?  n[2:end] : n
                           for n in map(Base.String, fieldnames(T))]

"""
Convert a `JSON.Object` to a `struct T`.
Optimised for the case where the order of the JSON fields matches the struct.
"""
@generated function Base.convert(::Type{T}, o::JSON.Object) where T

    fn = fieldnames(T)
    fk = unmangled_fieldnames(T)

    Expr(:block,
         :(    i = o.i                          ),
        (:(    (i, $n) = get_field(o, $k, i)    ) for (n,k) in zip(fn, fk))...,
         :(    $T($(fn...))                     ))
end

"""
Get a `field` from a `JSON.Object` starting at `start_i`.
Returns `start_i` for next field and field value.
"""
function get_field(o::JSON.Object, field, start_i)
    i, c = get_ic(o, field, (0, 0x00), start_i)
    if i == 0
        #throw(KeyError(field))
        v = nothing
        i = start_i
    else
        v = getvalue(o.s, i, c)
        i = lastindex_of_value(o.s, i, c)
    end
    return i, v
end


# IOString Wrappers

#FIXME
#Base.length(j::JSON.Object{IOString{T}}) where T =
#    pump(() -> div(collection_length(j), 2), j.s)

#Base.get(j::JSON.Object{IOString{T}}, key, default) where T =
#    pump(() -> _get(j, key, default), j.s)

#Base.done(j::JSON.Object{IOString{T}}, i) where T =
#    pump(() -> _done(j, i), j.s)

#Base.next(j::JSON.Object{IOString{T}}, i) where T =
#    pump(() -> _next(j, i), j.s)
