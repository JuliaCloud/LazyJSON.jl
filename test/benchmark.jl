using LazyJSON
using JSON

function go() 

j = String(read("ec2-2016-11-15.normal.json"))


for n in [1, 50]

n > 1 && println("Access value close to start:")
n > 1 && print("LazyJSON.jl: ")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j)
    @assert r["operations"
            ]["AcceptReservedInstancesExchangeQuote"
            ]["input"
            ]["shape"] |> String == "AcceptReservedInstancesExchangeQuoteRequest"
end

n > 1 && print("JSON.jl:      ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    @assert r["operations"
            ]["AcceptReservedInstancesExchangeQuote"
            ]["input"
            ]["shape"] |> String == "AcceptReservedInstancesExchangeQuoteRequest"
end

n > 1 && println("Access value close to end:")
n > 1 && print("LazyJSON.jl: ")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j)
    @assert r["shapes"
            ]["scope"
            ]["enum"
            ][1] |> String == "Availability Zone"
end

n > 1 && print("JSON.jl:      ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    @assert r["shapes"
            ]["scope"
            ]["enum"
            ][1] |> String == "Availability Zone"
end

end

end

go()
