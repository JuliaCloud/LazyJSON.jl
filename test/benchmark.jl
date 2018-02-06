using LazyJSON
using JSON

function go() 

j = String(read("ec2-2016-11-15.normal.json"))


for n in [1, 190]

println("\n")
n > 1 && println("Access value close to start:")

n > 1 && print("LazyerJSON.jl:")
GC.gc()
@time for i in 1:n
    r = string(LazyJSON.LazyerJSON.getpath(j,
               ["operations",
                "AcceptReservedInstancesExchangeQuote",
                "input",
                "shape"]))
    @assert r == "AcceptReservedInstancesExchangeQuoteRequest"
end

n > 1 && print("LazyJSON.jl with path:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j; path = ["operations",
                                  "AcceptReservedInstancesExchangeQuote",
                                  "input",
                                  "shape"])
    @assert r |> String == "AcceptReservedInstancesExchangeQuoteRequest"
end

n > 1 && print("LazyJSON.jl:          ")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j)
    @assert r["operations"
            ]["AcceptReservedInstancesExchangeQuote"
            ]["input"
            ]["shape"] |> String == "AcceptReservedInstancesExchangeQuoteRequest"
end

n > 1 && print("JSON.jl:              ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    @assert r["operations"
            ]["AcceptReservedInstancesExchangeQuote"
            ]["input"
            ]["shape"] |> String == "AcceptReservedInstancesExchangeQuoteRequest"
end

println("\n")
n > 1 && println("Access value close to end:")

n > 1 && print("LazyerJSON.jl:")
GC.gc()
@time for i in 1:n
    r = string(LazyJSON.LazyerJSON.getpath(j,
               ["shapes", "scope", "enum", 1]))
    @assert r == "Availability Zone"
    r = string(LazyJSON.LazyerJSON.getpath(j,
               ["shapes", "scope", "enum", 2]))
    @assert r == "Region"
end

n > 1 && print("LazyerJSON.jl in steps:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.LazyerJSON.getvalue(j)
    r = r["shapes"]["scope"]["enum"]
    @assert string(r[1]) == "Availability Zone"
    @assert string(r[2]) == "Region"
end



n > 1 && print("LazyJSON.jl with path:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j; path = ["shapes", "scope", "enum", 1])
    @assert r |> String == "Availability Zone"
    r = LazyJSON.parse(j; path = ["shapes", "scope", "enum", 2])
    @assert r |> String == "Region"
end

n > 1 && print("LazyJSON.jl:          ")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j)
    r = r["shapes"]["scope"]["enum"]
    @assert r[1] |> String == "Availability Zone"
    @assert r[2] |> String == "Region"
end

n > 1 && print("JSON.jl:              ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    r = r["shapes"]["scope"]["enum"]
    @assert r[1] |> String == "Availability Zone"
    @assert r[2] |> String == "Region"
end

end

end

go()
