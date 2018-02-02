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
and `height` fields is to generate a html tag `"<img width=\$w height=\$h ...>"
there is no need to parse the numeric content of the strings at all.
Similarity, we might extract some strings from a JSON source and write
them to another JSON record as-is with no need to interpret escape
sequences or care if the characters are "valid".

```
┌───────────────────────────────┐                               ┌───────────┐
│ JSON.String <: AbstractString │                               │ SubString │
│  bytes::CodeUnits             ├─────────────────────────────▶ └───────────┘
│  first::Int                   │     convert, unescape,        ┌───────────┐
│  last::Int                    │    constructors etc...        │ String    │
└───────────────────────────────┘                               └───────────┘
┌───────────────────────────────┐                               ┌───────────┐
│ JSON.Number <: Number         │                               │ Int64     │
│  bytes::CodeUnits             ├─────────────────────────────▶ └───────────┘
│  first::Int                   │   convert, promote_rule,      ┌───────────┐
│  last::Int                    │   +, -, *, /, ^, etc...       │ Float64   │
└───────────────────────────────┘                               └───────────┘
```


The Array and Object collection types are implemented as flat vectors
wrapped with AbstractArray and AbstractDict interfaces. When a JSON
file containing an Array of values is processed the parser stops
and returns and empty array object as soon as it sees the '[`' at
the start of the input.  As the user requests particular values in
the array, the parser processes just enough to return the requested
values. The same pattern of just in time parsing applies recursively
to nested Objects and Arrays.

```
┌───────────────────────────────┐
│ JSON.Array <: AbstractArray   │                               ┌───────────┐
│  v::Vector{Any}               ├─────────────────────────────▶ │ Array     │
│  iscomplete{Bool}             │       length, getindex,       └───────────┘
│                               │   start, done, next, etc...
└───────────────────────────────┘
┌───────────────────────────────┐                               ┌───────────┐
│ JSON.Object <: AbstractDict   │                               │ Dict      │
│  v::Vector{Any}               ├─────────────────────────────▶ └───────────┘
│  iscomplete{Bool}             │      keys, length, get,       ┌───────────┐
│                               │   start, done, next, etc...   │ Pairs     │
└───────────────────────────────┘                               └───────────┘
```


The main `parse_value` function runs as a co-routine. Whenever it
finishes parsing a value-fragment it yields control back to the
main application task and waits. When some application code calls
`getindex(::JSON.Array, ::Int)` the `parse_value` co-routine is
resumed until the value at the requested index has been parsed.

The `use_promotejson::Bool` setting enables optional caching of values
that have been promoted to normal Julia types as they are accessed.

The `enable_assertions::Bool` setting controls checks that are not
necessary if the input is known to be valid JSON.

The test cases cover https://github.com/nst/JSONTestSuite, but no
real-world testing or performance measurement has been done yet.

TODO:
 - Performance measurement and tuning
 - Large input test cases
 - Implement the AbstractString interface for JSON.String
 - Implement un-escaping

See also:
 - Another lazy JSON parser: https://github.com/doubledutch/LazyJSON
 - RFC 7159: https://tools.ietf.org/html/rfc7159
