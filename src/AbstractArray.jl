# AbstractArray interface for JSON.Array

Base.IteratorSize(::Type{JSON.Array{W, T}}) where W where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{JSON.Array{W, T}}) where W where T = Base.EltypeUnknown()


# Access

Base.getindex(a::JSON.Array{W}, i::Integer) where W =
    getvalue(W, a.s, getindex_ic(a, i)...)


# Dimensions

function Base.length(a::JSON.Array)
    @lazywarn "length(::JSON.Array) is slow!" stacktrace()
    collection_length(a)
end

Base.size(a::JSON.Array) = (length(a), )


# Iterate

Base.iterate(j::JSON.Array, i = (j.i, 0x00)) = _iterate(j, i)
function _iterate(j::JSON.Array{W}, (i, c)) where W
    i, c = nextindex(j, i, c)
    if c == ']'
        return nothing
    end
    return getvalue(W, j.s, i, c), (i, c)
end


# IOString Wrappers

Base.length(j::JSON.Array{W, IOString{T}}) where W where T =
    pump(() -> collection_length(j), j.s)

Base.getindex(j::JSON.Array{W, IOString{T}}, i::Integer) where W where T =
    pump(() -> getvalue(W, j.s, getindex_ic(j, i)...), j.s)

Base.iterate(j::JSON.Array{W, IOString{T}}, i = (j.i, 0x00)) where W where T =
    pump(() -> _iterate(j, i), j.s)
