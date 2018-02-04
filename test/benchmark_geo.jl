using LazyJSON
using JSON

function go() 

# From https://geojson-maps.ash.ms
j = String(read("geo.json"))


for n in [1, 19]

n > 1 && println("")
n > 1 && println("Country name")

n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j; path = ["features", 15, "properties", "formal_en"])
    @assert r |> String == "Republic of Palau"
end


n > 1 && print("JSON.jl:    ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    @assert r["features"][15]["properties"]["formal_en"] == "Republic of Palau"
end


n > 1 && println("")
n > 1 && println("Map data")
n > 1 && print("LazyJSON.jl:")
GC.gc()
@time for i in 1:n
    r = LazyJSON.parse(j; path = ["features", 15, "geometry", "coordinates", 6, 1])
    @assert r[1][1] == 134.41651451900023
    for (x, y) in r
       @assert 134.2 < x < 134.5
       @assert 7.21 < y < 7.32
    end
end


n > 1 && print("JSON.jl:    ")
GC.gc()
@time for i in 1:n
    r = JSON.parse(j)
    r = r["features"][15]["geometry"]["coordinates"][6][1]
    @assert r[1][1] == 134.41651451900023
    for (x, y) in r
       @assert 134.2 < x < 134.5
       @assert 7.21 < y < 7.32
    end
end

end

end

go()
