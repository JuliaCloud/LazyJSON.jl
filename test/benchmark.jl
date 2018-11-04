#module LazyJSONBenchmark

using LazyJSON
using DataFrames
using JSON
using JSON2

using Mmap

#j = String(read("ec2-2016-11-15.normal.json"))
f = open("ec2-2016-11-15.normal.json", "r")
j = String(Mmap.mmap(f));

j = string("[", join(fill(j, 10), ", "), "]")

j2 = String(read("geo.json"))


struct HTTP
    method::String
    requestUri::String
end

struct IOType
    shape::String
end

Base.convert(::Type{IOType}, ::Nothing) = IOType("")

struct Operation
    name::String
    http::HTTP
    input::IOType
    output::IOType
    documentation::String
end

JSON2.@format Operation begin
    output => (default=IOType(""),)
end

struct TestLazyA end
struct TestLazyB end
struct TestLazyC end
struct TestJSON end
struct TestJSON2 end

name(::Type{TestLazyA}) = "Lazy"
name(::Type{TestLazyB}) = "Lazy (B)"
name(::Type{TestLazyC}) = "Lazy (C)"
name(::Type{TestJSON}) = "JSON"
name(::Type{TestJSON2}) = "JSON2"


println("""
    For these tests, the content of `ec2-2016-11-15.normal.json` has been
    duplicated 10 times into a top level JSON array "[ , , , ...]" this
    results in an overall input data size of ~10MB.

    ## test1
    Reads `ec2-2016-11-15.normal.json` and extracts a single value:
    `operations.AcceptReservedInstancesExchangeQuote.input.shape`.
    This value is close to the start of the input data.

    Variants:
     - Lazy: LazyJSON.jl `AbstractDict` interface.
     - Lazy (B): LazyJSON.jl `getproperty` interface.
     - Lazy (C): LazyJSON.jl `lazy=false` (parse whole input to Dicts etc)
     - JSON: JSON.jl `parse` interface.
     - JSON2: JSON2.jl `read -> NamedTuple` interface.

    """)

test1(::Type{TestLazyA}, j) =
    LazyJSON.parse(j)[1]["operations"
                    ]["AcceptReservedInstancesExchangeQuote"
                    ]["input"
                    ]["shape"]

test1(::Type{TestLazyB}, j) =
    LazyJSON.parse(j; getproperty=true)[1].
                      operations.
                      AcceptReservedInstancesExchangeQuote.
                      input.
                      shape

test1(::Type{TestLazyC}, j) =
    LazyJSON.parse(j; lazy=false)[1]["operations"
                ]["AcceptReservedInstancesExchangeQuote"
                ]["input"
                ]["shape"]

test1(::Type{TestJSON}, j) =
    JSON.parse(j)[1]["operations"
                ]["AcceptReservedInstancesExchangeQuote"
                ]["input"
                ]["shape"]

test1(::Type{TestJSON2}, j) =
    JSON2.read(j)[1].operations.
                  AcceptReservedInstancesExchangeQuote.
                  input.
                  shape

const n = 10

results = DataFrame(Test=String[],
                    Variant=String[],
                    µs=Int[],
                    bytes=Int[],
                    poolalloc=Int[],
                    bigalloc=Int[])

function run_test1(T, j; warmup=false)

    count = 0
    val, t, bytes, gctime, memallocs = @timed for i in 1:n
        v = test1(T, j)
        if v == "AcceptReservedInstancesExchangeQuoteRequest"
            count += 1
        end
    end
    @assert count == n

    if !warmup
        t = round(Int, t/n * 1000000)
        push!(results, ["test1", name(T), t, bytes/n,
                        round(Int, memallocs.poolalloc/n),
                        round(Int, memallocs.bigalloc/n)])
    end
end

tests = (TestLazyA,
         TestLazyB,
         TestLazyC,
         TestJSON,
         TestJSON2)

for warmup in [true, false]
    for t in tests
        run_test1(t, j; warmup=warmup)
    end
end

println("```")
@show results
println("```\n")
println("""
    Note: LazyJSON.jl is similar to JSON.jl in speed and memory use in non-lazy mode.

    """)
results = results[1:0,:]


println("""
    ## test2
    Read `ec2-2016-11-15.normal.json` and extracts an array value:
    `shapes.scope.enum`
    This value is close to the end of the input data.

    Variants:
     - Lazy: LazyJSON.jl `AbstractDict` interface.
     - Lazy (B): LazyJSON.jl `getproperty` interface.
     - Lazy (C): LazyJSON.jl `lazy=false` (parse whole input to Dicts etc)
     - JSON: JSON.jl `parse` interface.
     - JSON2: JSON2.jl `read -> NamedTuple` interface.
    """)


test2(::Type{TestLazyA}, j) =
    LazyJSON.parse(j)[10]["shapes"]["scope"]["enum"]

test2(::Type{TestLazyB}, j) =
        LazyJSON.parse(j; getproperty=true)[10].shapes.scope.enum

test2(::Type{TestLazyC}, j) =
        LazyJSON.parse(j; lazy=false)[10]["shapes"]["scope"]["enum"]

test2(::Type{TestJSON}, j) =
    JSON.parse(j)[10]["shapes"]["scope"]["enum"]

test2(::Type{TestJSON2}, j) =
    JSON2.read(j)[10].shapes.scope.enum


function run_test2(T, j; warmup=false)

    count = 0
    val, t, bytes, gctime, memallocs = @timed for i in 1:n
        v = test2(T, j)
        if v[1] == "Availability Zone" && v[2] == "Region"
            count += 1
        end
    end
    @assert count == n

    if !warmup
        t = round(Int, t/n * 1000000)
        push!(results, ["test2", name(T), t, bytes/n,
                        round(Int, memallocs.poolalloc/n),
                        round(Int, memallocs.bigalloc/n)])
    end
end

for warmup in [true, false]
    for t in tests
        run_test2(t, j; warmup=warmup)
    end
end

println("```")
@show results
println("```\n")
println("""
    Note: It takes LazyJSON.jl a bit longer to access values near the end of
    the input.

    """)

results = results[1:0,:]

println("""
    ## test3
    Modifes `ec2-2016-11-15.normal.json` by replacing a value near the
    start of the file and two values near the end.

    Variants:
     - Lazy: LazyJSON.jl `getproperty` interface finds values and
             `LazyJSON.splice` modifies the JSON data in-place.
     - JSON: JSON.jl `parse` to `Dict`, modify, then write new JSON text.
     - JSON2: _Parses to immutable `NamedTuples`. Modificaiton not supported._
    """)

function test3(::Type{TestLazyA}, j)
    r = LazyJSON.value(j; getproperty=true)
    r = LazyJSON.splice(r, r[10].shapes.ZoneNameStringList.member.shape, "foo")
    r = LazyJSON.splice(r, r[10].shapes.scope.enum[1], "bar")
    r = LazyJSON.splice(r, r[10].shapes.scope.enum[2], "fum")
    r = LazyJSON.value(string(r); getproperty=true)
    return r[10].shapes.scope.enum[1]
end

function test3(::Type{TestJSON}, j)
    r = JSON.parse(j)
    r[10]["shapes"]["ZoneNameStringList"]["member"]["shape"] = "foo"
    r[10]["shapes"]["scope"]["enum"][1] = "bar"
    r[10]["shapes"]["scope"]["enum"][2] = "fum"
    s = JSON.json(r)
    r = JSON.parse(s)
    return r[10]["shapes"]["scope"]["enum"][1]
end

tests = (TestLazyA,
         TestJSON)

function run_test3(T, j; warmup=false)

    count = 0
    val, t, bytes, gctime, memallocs = @timed for i in 1:n
        v = test3(T, j)
        if v == "bar"
            count += 1
        end
    end
    @assert count == n

    if !warmup
        t = round(Int, t/n * 1000000)
        push!(results, ["test3", name(T), t, bytes/n,
                        round(Int, memallocs.poolalloc/n),
                        round(Int, memallocs.bigalloc/n)])
    end
end

for warmup in [true, false]
    for t in tests
        run_test3(t, j; warmup=warmup)
    end
end

println("```")
@show results
println("```\n")
results = results[1:0,:]

println("""
    ## test4
    Reads a 1.2MB GeoJSON file an extracts a country name near the middle
    of the file.

    Variants:
     - Lazy: LazyJSON.jl `AbstractDict` interface.
       `LazyJSON.parse(j)["features"][15]["properties"]["formal_en"]`
     - Lazy (B): LazyJSON.jl `getproperty` interface.
       `LazyJSON.parse(j; getproperty=true).features[15].properties.formal_en`
     - Lazy (C): LazyJSON.jl `lazy=false` (parse whole input to Dicts etc)
       `LazyJSON.parse(j; lazy=false)["features"][15]["properties"]["formal_en"]`
     - JSON: JSON.jl `parse` interface.
       `JSON.parse(j)["features"][15]["properties"]["formal_en"]`
     - JSON2: JSON2.jl `read -> NamedTuple` interface.
       `JSON2.read(j).features[15].properties.formal_en`
    """)

test4(::Type{TestLazyA}, j) =
    LazyJSON.parse(j)["features"][15]["properties"]["formal_en"]

test4(::Type{TestLazyB}, j) =
    LazyJSON.parse(j; getproperty=true).features[15].properties.formal_en

test4(::Type{TestLazyC}, j) =
    LazyJSON.parse(j; lazy=false)["features"][15]["properties"]["formal_en"]

test4(::Type{TestJSON}, j) =
    JSON.parse(j)["features"][15]["properties"]["formal_en"]

test4(::Type{TestJSON2}, j) =
    JSON2.read(j).features[15].properties.formal_en


function run_test4(T, j; warmup=false)

    count = 0
    val, t, bytes, gctime, memallocs = @timed for i in 1:n
        v = test4(T, j)
        if v == "Republic of Palau"
            count += 1
        end
    end
    @assert count == n

    if !warmup
        t = round(Int, t/n * 1000000)
        push!(results, ["test4", name(T), t, bytes/n,
                        round(Int, memallocs.poolalloc/n),
                        round(Int, memallocs.bigalloc/n)])
    end
end

tests = (TestLazyA,
         TestLazyB,
         TestLazyC,
         TestJSON,
         TestJSON2)

for warmup in [true, false]
    for t in tests
        run_test4(t, j2; warmup=warmup)
    end
end

println("```")
@show results
println("```\n")

println("""
    Note: LazyJSON.jl in non-lazy mode is a bit faster than JSON.jl for this
    input.

    """)

results = results[1:0,:]

println("""
    ## test5
    Reads a 1.2MB GeoJSON file and checks that the outline polygon for
    a single country is within an expected lat/lon range.
    ```
    r = r["features"][15]["geometry"]["coordinates"][6][1]
    @assert r[1][1] == 134.41651451900023
    for (x, y) in r
       @assert 134.2 < x < 134.5
       @assert 7.21 < y < 7.32
    end
    ```
    """)

function test5(::Type{TestLazyA}, j)
    r = LazyJSON.parse(j)
    r = r["features"][15]["geometry"]["coordinates"][6][1]
    @assert r[1][1] == 134.41651451900023
    for (x, y) in r
       @assert 134.2 < x < 134.5
       @assert 7.21 < y < 7.32
    end
end

function test5(::Type{TestJSON}, j)
    r = JSON.parse(j)
    r = r["features"][15]["geometry"]["coordinates"][6][1]
    @assert r[1][1] == 134.41651451900023
    for (x, y) in r
       @assert 134.2 < x < 134.5
       @assert 7.21 < y < 7.32
    end
end

function test5(::Type{TestJSON2}, j)
    r = JSON2.read(j)
    r = r.features[15].geometry.coordinates[6][1]
    @assert r[1][1] == 134.41651451900023
    for (x, y) in r
       @assert 134.2 < x < 134.5
       @assert 7.21 < y < 7.32
    end
end

function run_test5(T, j; warmup=false)

    val, t, bytes, gctime, memallocs = @timed for i in 1:n
        test5(T, j)
    end

    if !warmup
        t = round(Int, t/n * 1000000)
        push!(results, ["test5", name(T), t, bytes/n,
                        round(Int, memallocs.poolalloc/n),
                        round(Int, memallocs.bigalloc/n)])
    end
end

tests = (TestLazyA,
         TestJSON,
         TestJSON2)

for warmup in [true, false]
    for t in tests
        run_test5(t, j2; warmup=warmup)
    end
end

println("```")
@show results
println("```\n")
results = results[1:0,:]

println("""
    ## test6
    Defines `struct Operation`, `struct IOType` and `struct HTTP` with
    fields that match the API operations data in `ec2-2016-11-15.normal.json`.
    It then does JSON2-style direct-to-struct parsing to read the JSON data
    into a Julia object `Dict{String,Operation}`
    (LazyJSON provides `@generated` `Base.convert` methods for this).

    Variants:
     - Lazy: LazyJSON.jl `AbstractDict` interface.
        `convert(Dict{String,Operation}, LazyJSON.parse(j))`
     - JSON2: JSON2.jl `read -> NamedTuple` interface.
        `JSON2.read(j, Dict{String,Operation})`
    """)


function test6(::Type{TestLazyA}, j)
    v = convert(Dict{String,Operation}, LazyJSON.parse(j))
    return v["AcceptReservedInstancesExchangeQuote"].input.shape
end

function test6(::Type{TestJSON2}, j)
    v = JSON2.read(j, Dict{String,Operation})
    return v["AcceptReservedInstancesExchangeQuote"].input.shape
end

function run_test6(T, j; warmup=false)

    count = 0
    val, t, bytes, gctime, memallocs = @timed for i in 1:n
        v = test6(T, j)
        if v == "AcceptReservedInstancesExchangeQuoteRequest"
            count += 1
        end
    end

    if !warmup
        t = round(Int, t/n * 1000000)
        push!(results, ["test6", name(T), t, bytes/n,
                        round(Int, memallocs.poolalloc/n),
                        round(Int, memallocs.bigalloc/n)])
    end
end

tests = (TestLazyA,
         TestJSON2)

jops = string(LazyJSON.parse(j)[1]["operations"])

for warmup in [true, false]
    for t in tests
        run_test6(t, jops; warmup=warmup)
    end
end
display(results)
println("```")
@show results
println("```\n")
#end
