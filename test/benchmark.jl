using LazyJSON
using JSON

function go() 

j = String(read("ec2-2016-11-15.normal.json"))


for n in [1, 190]

println("\n")
n > 1 && println("Access value close to start:")

n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    r = SubString(LazyJSON.parse(j,
               ["operations",
                "AcceptReservedInstancesExchangeQuote",
                "input",
                "shape"]))
    @assert r == "AcceptReservedInstancesExchangeQuoteRequest"
end

n > 1 && print("JSON.jl:    ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    @assert r["operations"
            ]["AcceptReservedInstancesExchangeQuote"
            ]["input"
            ]["shape"] |> String == "AcceptReservedInstancesExchangeQuoteRequest"
end

println("\n")
n > 1 && println("Access 2 values close to end:")

n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j, ["shapes", "scope"]; lazy=false)
    r = r["enum"]
    @assert SubString(r[1]) == "Availability Zone"
    @assert SubString(r[2]) == "Region"
end


n > 1 && print("JSON.jl:    ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    r = r["shapes"]["scope"]["enum"]
    @assert r[1] |> String == "Availability Zone"
    @assert r[2] |> String == "Region"
end


println("\n")
n > 1 && println("Recursive promotion of all values to Julia objects.:")

n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j; lazy = false)
    r = r["shapes"]["scope"]["enum"]
    @assert SubString(r[1]) == "Availability Zone"
    @assert SubString(r[2]) == "Region"
end


n > 1 && print("JSON.jl:    ")
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
