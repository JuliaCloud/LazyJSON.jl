module LazyJSONBenchmark

using LazyJSON
using JSON
#using JSON2

using Mmap

function go()

#j = String(read("ec2-2016-11-15.normal.json"))
f = open("ec2-2016-11-15.normal.json", "r")
j = String(Mmap.mmap(f))


for n in [1, 190]

println("\n")
n > 1 && println("Access value close to start:")

n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j,
               ["operations",
                "AcceptReservedInstancesExchangeQuote",
                "input",
                "shape"])
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

#=
n > 1 && print("JSON2.jl:    ")
GC.gc()
@time for i in 1:n
    r = JSON2.read(j)
    @assert r.operations.AcceptReservedInstancesExchangeQuote.input.shape ==
           "AcceptReservedInstancesExchangeQuoteRequest"
end
=#

println("\n")
n > 1 && println("Access 2 values close to end:")

n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    if LazyJSON.enable_getproperty
        r = LazyJSON.parse(j).shapes.scope.enum
    else
        r = LazyJSON.parse(j, ["shapes", "scope", "enum"])
    end
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

#=
n > 1 && print("JSON2.jl:    ")
GC.gc()
@time for i in 1:n
    r = JSON2.read(j)
    r = r.shapes.scope.enum
    @assert r[1] == "Availability Zone"
    @assert r[2] == "Region"
end
=#


println("\n")
n > 1 && println("Update a value:")

n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.value(j)
    r = LazyJSON.splice(r, r.shapes.ZoneNameStringList.member.shape, "foo")
    r = LazyJSON.splice(r, r.shapes.scope.enum[1], "bar")
    r = LazyJSON.splice(r, r.shapes.scope.enum[2], "fum")
    r = LazyJSON.value(string(r))
    @assert r.shapes.scope.enum[1] == "bar"
end


n > 1 && print("JSON.jl:    ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    r["shapes"]["ZoneNameStringList"]["member"]["shape"] = "foo"
    r["shapes"]["scope"]["enum"][1] = "bar"
    r["shapes"]["scope"]["enum"][2] = "fum"
    s = JSON.json(r)
    r = JSON.parse(s)
    @assert r["shapes"]["scope"]["enum"][1] == "bar"
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

end

LazyJSONBenchmark.go()
