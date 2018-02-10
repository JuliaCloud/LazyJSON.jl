# jsonhack

LazyJSON.jl

This is an experimental lazy JSON parser. It attempts to parse JSON
with minimal allocation of buffers; it delays parsing until values
are requested through the `AbstractArray` and `AbstractDict`
interfaces; and it does not interpret the content of string or
numeric values until they are requested through the `AbstractString`
and `Number` interfaces.

The motivation for tying this began with a JSON file from a JavaScript
system that was rejected by JSON.jl.
https://github.com/JuliaIO/JSON.jl/issues/232#issuecomment-359675596

The issue was the presence of \\uXXXX string sequences that did not
produce valid unicode characters. The file contained a test suite
for URI parsing. The intention was to feed the "invalid" \\uXXXX
sequences into a URI parser to test for proper error handling. There
was no intention to attempt to render the "invalid" sequences as
characters, so it seemed unfortunate that JSON.jl rejected them as
being bad characters. It also seemed unfortunate that the entire JSON
file was rejected due to a few characters in a few strings.

Thinking about a better way to handle this situation led to the
idea that it might be better for the parser not to try to interpret
characters at all, and that it might be nice to be able to access a few
fields in a large file without having to validate every aspect of the
entire file.

Rather than eagerly converting every detail of the JSON format to Julia
types, the output of this lazy parser consists of byte indexes that
refer to the location of string and numeric values within the JSON text.
Interpretation of the content of the strings and numbers and conversion
to normal Julia types is deferred until the values are accessed.
e.g. an image_data.json file might contain hundreds of fields but if we
only need to access the `width` and `height` fields, then there is no
need to parse all the other fields. In fact if the end use of the `width`
and `height` fields is to generate a html tag `"img width=\$w height=\$h ..."`
there is no need to parse the numeric content of the strings at all.
Similarity, we might extract some strings from a JSON source and write
them to another JSON record as-is with no need to interpret escape
sequences or care if the characters are "valid".

```
┌───────────────────────────────┐                               ┌───────────┐
│ JSON.String <: AbstractString │                               │ SubString │
│  s::String                    ├─────────────────────────────▶ └───────────┘
│  i::Int                       │     convert, unescape,        ┌───────────┐
│                               │    constructors etc...        │ String    │
└───────────────────────────────┘                               └───────────┘
┌───────────────────────────────┐                               ┌───────────┐
│ JSON.Number <: Number         │                               │ Int64     │
│  s::String                    ├─────────────────────────────▶ └───────────┘
│  i::Int                       │   convert, promote_rule,      ┌───────────┐
│                               │   +, -, *, /, ^, etc...       │ Float64   │
└───────────────────────────────┘                               └───────────┘
```


The Array and Object collection types are also represneted as byte indexs.
When a JSON file containing an Array of values is processed the parser stops
and returns and empty array object as soon as it sees the '[`' at
the start of the input.  As the user requests particular values in
the array, the parser processes just enough to return the requested
values. The same pattern of just in time parsing applies recursively
to nested Objects and Arrays.

```
┌───────────────────────────────┐
│ JSON.Array <: AbstractArray   │                               ┌───────────┐
│  s::String                    ├─────────────────────────────▶ │ Array     │
│  i::Int                       │       length, getindex,       └───────────┘
│                               │   start, done, next, etc...
└───────────────────────────────┘
┌───────────────────────────────┐                               ┌───────────┐
│ JSON.Object <: AbstractDict   │                               │ Dict      │
│  s::String                    ├─────────────────────────────▶ └───────────┘
│  i::Int                       │      keys, length, get,       ┌───────────┐
│                               │   start, done, next, etc...   │ Pairs     │
└───────────────────────────────┘                               └───────────┘
```


The main `parse` function simply returns a wrapper object for index 1.

The `enable_assertions::Bool` setting controls checks that are not
necessary if the input is known to be valid JSON.

The test cases cover https://github.com/nst/JSONTestSuite [FIXME
update for revised "lazyer" parser, but no
real-world testing or performance measurement has been done yet.

The `test/benchmark.jl` test uses a [1MB AWS API definition JSON file](https://github.com/samoconnor/jsonhack/blob/master/test/ec2-2016-11-15.normal.json)
to compare performance vs JSON.jl.  When accessing a value close to the
start of the file the lazy parser is ~2000 times faster than JSON.jl,
for values near then end of the file, the lazy parser is ~6 times faster.

```
Access value close to start:
LazyJSON.jl:  0.000558 seconds (3.23 k allocations: 121.719 KiB)
JSON.jl:      1.025800 seconds (9.34 M allocations: 913.682 MiB, 12.53% gc time)


Access 2 values close to end:
LazyJSON.jl:  0.162446 seconds (2.66 k allocations: 71.250 KiB)
JSON.jl:      1.019581 seconds (9.34 M allocations: 913.682 MiB, 12.22% gc time)
```


The `test/benchmark_geo.jl` test uses a 1.2MB GeoJSON file
to compare performance vs JSON.jl. The first test extracts a country name 
near the middle of the file. The second test checks that the country outline
polygon is at the expected coordinates. [FIXME update for revised parser]

```
Country name
LazyJSON.jl:  0.011174 seconds (1.06 k allocations: 112.516 KiB)
JSON.jl:      1.067171 seconds (8.62 M allocations: 373.471 MiB, 9.21% gc time)

Map data
LazyJSON.jl:  0.086771 seconds (7.64 k allocations: 371.391 KiB)
JSON.jl:      1.033109 seconds (8.62 M allocations: 373.541 MiB, 9.13% gc time)
```


TODO:
 - New Lazyer parser looses some format validation, consider recovering old code.

See also:
 - Another lazy JSON parser: https://github.com/doubledutch/LazyJSON
 - RFC 7159: https://tools.ietf.org/html/rfc7159
