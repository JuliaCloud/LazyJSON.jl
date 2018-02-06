
Base.getindex(a::JSON.Array, i) = getvalue(a.s, getindex_ic(a, i)...)

Base.convert(::Type{T}, a::JSON.Array) where T <: AbstractVector =
    convert(T, collect(a))

#function Base.size(a::JSON.Array) = size(collect(a))


Base.start(j::JSON.Array) = (j.i, Ref(0), 0x00)

function Base.done(j::JSON.Array, (i, n, c))
    i, c = nextindex(j, i, n, c)
    return c == ']' || c == '}'
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

Base.IteratorSize(::Type{JSON.Array{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Array{T}}) where T = Base.EltypeUnknown()


Base.getindex(a::JSON.Array, i) = getvalue(a.s, getindex_ic(a, i)...)
