module PropertyDicts

"""
    PropertyDict(::AbstactDict)

Wraps an `AbstractDict` to add `getproperty` support for `Symbol` and
`AbstractString` keys.

e.g.
```
> julia d = PropertyDict(Dict("foo" => 1, :bar => 2))
PropertyDict with 2 entries:
  :bar  => 2
  "foo" => 1

julia> d.foo, d.bar, d."foo"
(1, 2, 1)

julia> d."bar"
ERROR: KeyError: key "bar" not found
```
"""
struct PropertyDict{K, V, T <: AbstractDict{K, V}} <: AbstractDict{K, V}
    d::T
    PropertyDict(d::T) where {T <: AbstractDict} =
        new{keytype(d), valtype(d), T}(d)
end


unwrap(d::PropertyDict) = getfield(d, :d)


Base.getproperty(d::PropertyDict{AbstractString}, n::Symbol) =
    getindex(d, String(n))

function Base.getproperty(d::PropertyDict, n::Symbol)
    v = get(d, n, Base.secret_table_token)
    if v != Base.secret_table_token
        return v
    end
    return getindex(d, String(n))
end

Base.getproperty(d::PropertyDict, n) = getindex(d, n)


Base.IteratorSize(::Type{PropertyDict{K,V,T}}) where {K,V,T} = Base.IteratorSize(T)
Base.IteratorEltype(::Type{PropertyDict{K,V,T}}) where {K,V,T} = Base.IteratorEltype(T)
Base.getindex(d::PropertyDict, i) = getindex(unwrap(d), i)
Base.get(d::PropertyDict, k, default) = get(unwrap(d), k, default)
Base.length(d::PropertyDict) = length(unwrap(d))
Base.start(d::PropertyDict) = start(unwrap(d))
Base.done(d::PropertyDict, i) = done(unwrap(d), i)
Base.next(d::PropertyDict, i) = next(unwrap(d), i)


Base.convert(::Type{Any}, d::PropertyDict) = d
Base.convert(::Type{PropertyDict{K,V,T}}, d::PropertyDict{K,V,T}) where {K,V,T<:AbstractDict{K,V}} = d
Base.convert(T::Type, d::PropertyDict) = convert(T, PropertyDicts.unwrap(d))



end # module PropertyDicts
