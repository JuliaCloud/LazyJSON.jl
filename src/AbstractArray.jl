Base.length(a::JSON.Array) = (parse_all!(a); length(a.v))

Base.size(a::JSON.Array) = (parse_all!(a); size(a.v))

Base.getindex(a::JSON.Array, i::Int) = (parse_more!(a, i); getjson(a.v, i))

Base.IteratorSize(::Type{JSON.Array}) = Base.SizeUnknown()

Base.start(a::JSON.Array) = 1
Base.done(a::JSON.Array, i) = (parse_more!(a, i); i > length(a.v))
Base.next(a::JSON.Array, i) = (getindex(a, i), i + 1)
