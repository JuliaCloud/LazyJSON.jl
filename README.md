# LazyJSON.jl

[![Build Status](https://travis-ci.org/samoconnor/LazyJSON.jl.svg)](https://travis-ci.org/samoconnor/LazyJSON.jl)


LazyJSON is an interface for reading JSON data in Julia programs.

It provides direct access to values stored in a JSON text though standard Julia
interfaces: `Number`, `AbstractString`, `AbstractVector` and `AbstractDict`.

LazyJSON has a a single interface function `LazyJSON.value` that constructs
an object representing the value(s) from a JSON text.

```julia
LazyJSON.value(jsontext::AbstractString) -> Union{Bool,
                                                  LazyJSON.Number,
                                                  LazyJSON.String,
                                                  LazyJSON.Array,
                                                  LazyJSON.Object,
                                                  Nothing}
LazyJSON.Number <: Base.Number
LazyJSON.String <: AbstractString
LazyJSON.Array  <: AbstractVector{Any}
LazyJSON.Object <: AbstractDict{AbstractString,Any}
```

e.g.
```julia
julia> j = LazyJSON.value("""{
           "foo": [1, 2, 3, "four"]
           "bar": null
       }""")
LazyJSON.Object with 2 entries:
  "foo" => Any[1, 2, 3, "four"]
  "bar" => nothing

julia> j["foo"]
4-element LazyJSON.Array:
 1
 2
 3
  "four"

julia> j["foo"][4]
"four"

julia> typeof(j["bar"])
Nothing
```

The fields of JSON objects can also be accessed using `'.'` (`getproperty`)
syntax.

e.g.
```
julia> j.foo
4-element LazyJSON.Array:
 1
 2
 3
  "four"

julia> j.foo[4]
"four"

julia> typeof(j.bar)
Nothing

julia> j.missing
ERROR: KeyError: key "missing" not found
```

_For compatibility with other JSON interfaces that have a `parse` function,
`LazyJSON.parse` is provided as an alias for `LazyJSON.value`. e.g._

e.g.
```julia
julia> j = LazyJSON.parse("""{
           "foo": [1, 2, 3, "four"]
           "bar": null
       }""")

julia> j["foo"][4]
"four"
```

# Lazyness

LazyJSON is lazy in the sense that it assumes that its input is well formed JSON
text. It does not try to detect every type of JSON syntax error. If security is
a concern, JSON data of unknown providence should probably be validated before
use.

LazyJSON is also lazy in the sense that it does not process any part of the JSON
text until values are requested through the `AbstractVector` and `AbstractDict`
interfaces.

i.e. `j = LazyJSON.value(jsontext)` does no parsing and immediately
returns a thin wrapper object.

`j["foo"]` calls `get(::AbstractDict, "foo")`, which parses just enough to find
the `"foo"` field.

`j["foo"][4]` calls `getindex(::AbstractArray, 4)`, which continues paring up to
the fourth item in the array.

This results in much less memory allocation compared to non-lazy parsers:

JSON.jl:
```julia
j = String(read("ec2-2016-11-15.normal.json"))
julia> function f(json)
           v = JSON.parse(json)
           v["shapes"]["scope"]["enum"][1]
       end

julia> @time f(j)
  0.066773 seconds (66.43 k allocations: 7.087 MiB)
"Availability Zone"
```

LazyJSON.jl:
```julia
julia> function f(json)
           v = LazyJSON.parse(json)
           v["shapes"]["scope"]["enum"][1]
       end

julia> @time f(j)
  0.001392 seconds (12 allocations: 384 bytes)
"Availability Zone"
```

LazyJSON's `AbstractString` and `Number` implementations are lazy too.

The text of a `LazyJSON.Number` is not parsed to `Int64` or `Float64` form
until it is needed for a numeric operation. If the number is only used in a
textual context, it need never be parsed at all. e.g.

```julia
j = LazyJSON.value(jsontext)
html = """<img width=$(j["width"]), height=$(j["height"])>"""
```

Likewise, the content of a `LazyJSON.String` is not interpreted until it is
accessed. If a `LazyJSON.String` containing complex UTF16 escape sequences is
compared to a UTF8 `Base.String`, and the two strings differ in the first
few characters, then the comparison will terminate before the any unescaping
work needs to be done.



# LazyJSON Performance Considerations

## LazyJSON.Array Performance

The `LazyJSON.Array` does not keep track of the indices of its items.
Every `array[i]` access scans all the values in the array until it reaches
the `i`th value. This is fast if you only need to access a single item,
even near the end of the array, because the alternative of transforming the
`LazyJSON.Array` into a `Base.Array` must scan the entire array and allocate
new memory for each item. It is also fast to access multiple items near the
start of the array. However, if you need random access to many items in a large
array it is better to convert it to a `Base.Array`.

e.g.
```
v = LazyJSON.value(jsontext)["foo"]["bar"]["an_array"]
v = convert(Vector{Any}, v)
```

If you need to access the items in the array sequentially, the iteration
interface is very efficient, but incrementing an index is very inefficient.
`length(::LazyJSON.Array)` is also inefficient, in that it must scan the whole
array.

e.g.
```julia
v = LazyJSON.value(jsontext)["foo"]["bar"]["an_array"]
for i in v ✅
    println(i)
end

r = map(i -> f(i), v) ✅

i = 1
while i < length(v) ❌
    println(v[i]) ❌
end
```


## LazyJSON.Object Performance

The performance considerations for `LazyJSON.Object` are similar to those
described above for `LazyJSON.Array`. The `LazyJSON.Object` does not keep a
hash table of keys. Every `object["key"]` access scans all the keys in the
object until it finds a match. Accessing a keys in an object with a small
number of keys is efficient. Accessing a few keys in an object with many keys
is effiecient. However, if you need random acess to many keys in a large object
it is better to convert it to a `Base.Dict`.

e.g.
```julia
v = LazyJSON.value(jsontext)["foo"]["bar"]["an_object_with_many_keys"]
v = convert(Dict, v)
```

`length(::LazyJSON.Object)` is inefficient, in that it must scan the whole
object.
If you need to access the key value pairs sequentially, the iteration
interface is very efficient.

e.g.

```julia
o = LazyJSON.value(jsontext)["foo"]["bar"]["an_object_with_many_keys"]
for (k, v) in o ✅
    println(k, v)
end

r = filter((k, v) -> contains(i, r".jpg$", o)) ✅

for k in long_list_of_keys
    println(o[k]) ❌
end

d = convert(Dict, o)
for k in long_list_of_keys
    println(d[k]) ✅
end
```


## LazyJSON.Number Performance

Whenever a `LazyJSON.Number` is used in a numeric operation it must be parsed
from its string form into an `Int` or a `Float`. If you are only using each
each numetic value once, there is no performance penalty, as the string is only
parsed once. However if you need to use the numeric value many times, it is
better to convert it to a normal `Base` number type.

e.g.
```julia
i = LazyJSON.value(jsontext)["foo"]
x = origin.x + i["width"],  ✅ used once in an addition operation
y = origin.y + i["height"]  ✅
draw(i["data"], x, y)


limit = LazyJSON.value(jsontext)["foo"]["limit"]
i = 0
while i < limit ❌ re-parsed every time the less than operation is evaluated
    i += 1
    ...
end
limit = convert(Int, LazyJSON.value(jsontext)["foo"]["limit"]) ✅


v = LazyJSON.value(jsontext)["foo"]["ammounts"]
total = sum(v) ✅ iteration is efficient, each number is parsed once.


struct Foo
    x::Int
    y::Int
end
i = LazyJSON.value(jsontext)["foo"]
Foo(i["x"], i["y"]) ✅ converted to `Int` on assignment to struct fields.


v = LazyJSON.value(jsontext)["foo"]["values"]
ints = convert(Vector{Int}, v) ✅ manual conversion when needed
```


# Implementation

Values are represented by a reference to the JSON text `String`
and the byte index of the value text. The `LazyJSON.value(jsontext)` function
simply returns a `LazyJSON.Value` object with `s = jsontext` and `i = 1`.

```
    String: {"foo": 1,    "bar": [1, 2, 3, "four"]}
            ▲                    ▲      ▲  ▲
            │                    │      │  │
            ├─────────────────┐  │      │  │
            │ LazyJSON.Array( s, i=9)   │  │   == Any[1, 2, 3, "four"]
            │                           │  │
            ├─────────────────┐  ┌──────┘  │
            │ LazyJSON.Number(s, i=16)     │   == 3
            │                              │
            ├─────────────────┐  ┌─────────┘
            │ LazyJSON.String(s, i=19)         == "four"
            │
            └─────────────────┬──┐
              LazyJSON.Object(s, i=1)
```

LazyJSON does not parse and translate values into concrete Julia `Number`,
`String`, `Array` or `Dict` objects. Instead it provides interface methods that
conform to the protocols of `Base.Number`, `AbstractString`, `AbstractVector`
and `AbstractDict`.  These methods interpret the JSON text on the fly and parse
only as much as is needed return the requested values.



# Large JSON Texts

LazyJSON can process JSON files that are too big to fit in available RAM
by using the `mmap` interface.

e.g.
```julia
using Mmap
f = open("huge_file_that_wont_fit_in_ram.json", "r")
s = String(Mmap.mmap(f))
j = LazyJSON.value(s)
v = j["foo"]["bar"]
```
The operating stytem will lazily load enough chunks of the file into RAM to
reach field `"bar"` of opject `"foo"`.



# Benchmarks

For some workloads lazyness makes LazyJSON faster and less memory intensive
than JSON parsers that parse the entire JSON text and allocate a tree of
collection and value objects.

The `test/benchmark.jl` test uses a [1MB AWS API definition JSON file](https://github.com/samoconnor/jsonhack/blob/master/test/ec2-2016-11-15.normal.json)
to compare performance vs JSON.jl.  When accessing a value close to the
start of the file the lazy parser is orders of magnitude faster than JSON.jl,
for values near then end of the file, the lazy parser is about 6 times faster.
(Each test case is run once for JIT warmup, then 190 times for measurement.)

```
Julia Version 0.7.0-DEV.3761
JSON.jl master Tue Feb 6, 98727675b635c8428effa30a2287a9fe6370e664

Access value close to start:
LazyJSON.jl:  0.000568 seconds (3.42 k allocations: 139.531 KiB)
JSON.jl:      6.410700 seconds (13.28 M allocations: 1.337 GiB, 3.17% gc time)


Access 2 values close to end:
LazyJSON.jl:  0.177059 seconds (7.79 k allocations: 347.344 KiB)
JSON.jl:      6.417241 seconds (13.28 M allocations: 1.337 GiB, 3.18% gc time)
```
_Note, until recently JSON.jl was taking ~1 second for the tests above.
It seems that it may be hampered deprecation of `IOBuffer(maxsize::Integer)`._


The `test/benchmark_geo.jl` test uses a 1.2MB GeoJSON file
to compare performance vs JSON.jl. The first test extracts a country name
near the middle of the file. The second test checks that the country outline
polygon is at the expected coordinates.

```
Country name
LazyJSON.jl:  0.004762 seconds (190 allocations: 5.938 KiB)
JSON.jl:      1.063652 seconds (8.62 M allocations: 373.471 MiB, 11.19% gc time)

Map data
LazyJSON.jl:  0.011075 seconds (27.30 k allocations: 679.547 KiB)
JSON.jl:      1.064750 seconds (8.62 M allocations: 373.541 MiB, 10.75% gc time)
```


# TODO:
 - New Lazyer parser looses some format validation, consider recovering old
   code validation code from `src/OldLazyJSON.jl`


# References

 - Another lazy JSON parser: https://github.com/doubledutch/LazyJSON
 - RFC 7159: https://tools.ietf.org/html/rfc7159
