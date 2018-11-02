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

@show results


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

@show results

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

@show results

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

@show results

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
@show results

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
println()
#end
