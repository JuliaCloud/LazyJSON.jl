# AbstractDict interface for JSON Object

Base.IteratorSize(::Type{JSON.Object}) = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Object}) = Base.EltypeUnknown()


# Access

function Base.getindex(o::JSON.Object, key)
    v = get(o, key, :not_found)
    if v === :not_found
        throw(KeyError(key))
    end
    return v
end

Base.get(o::JSON.Object, key, default) = _get(o, key, default)
function _get(o::JSON.Object{W}, key, default) where W
    i, c = get_ic(o, key, (0, 0x00))
    if i == 0
        return default
    end
    return getvalue(W, o.s, i, c)
end


# Dimensions

Base.length(a::JSON.Object) = div(collection_length(a), 2)


# Iterate

Base.iterate(j::JSON.Object, i = (j.i, 0x00)) = _iterate(j, i)
function _iterate(j::JSON.Object{W}, (i, c)) where W

    i, c = nextindex(j, i, c)

    if c == '}'
        return nothing
    end

    k = getvalue(W, j.s, i, c)
    i, c = nextindex(j, i, c)
    v = getvalue(W, j.s, i, c)

    return k => v, (i, c)
end


# Conversion to Dict Types

Base.convert(::Type{Any}, o::JSON.Object) = o

Base.convert(::Type{JSON.Object{W, T}},
                 o::JSON.Object{W, T}) where W where T <: AbstractString = o

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
function get_field(o::JSON.Object{W}, field, start_i) where W
    i, c = get_ic(o, field, (0, 0x00), start_i)
    if i == 0
        #throw(KeyError(field))
        v = nothing
        i = start_i
    else
        v = getvalue(W, o.s, i, c)
        i = lastindex_of_value(o.s, i, c)
    end
    return i, v
end


# IOString Wrappers

Base.length(j::JSON.Object{W, IOString{T}}) where W where T =
    pump(() -> div(collection_length(j), 2), j.s)

Base.get(j::JSON.Object{W, IOString{T}}, key, default) where W where T =
    pump(() -> _get(j, key, default), j.s)

Base.iterate(j::JSON.Object{W, IOString{T}}, i = (j.i, 0x00)) where W where T =
    pump(() -> _iterate(j, i), j.s)
