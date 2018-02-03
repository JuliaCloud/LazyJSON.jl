"""
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
"""

module LazyJSON

const JSON = LazyJSON

abstract type Value end

parse(s::AbstractString) = Base.parse(JSON.Value, s)

const Bytes = Base.CodeUnits{UInt8,Base.String}

const enable_assertions = false



# Parser Data Structures

"""
The JSON parser encountered invalid input.
"""

struct ParseError <: Exception
    bytes::Bytes
    index::Int
    message::Base.String
end



# JSON Value Data Structures

"""
`JSON.String` stores the start and end indexes of a string within a JSON text.
"""

struct String # FIXME <: AbstractString ?
    bytes::Bytes
    first::Int
    last::Int
    has_escape::Bool
end


"""
`JSON.Number` stores the start and end indexes of a number within a JSON text.
"""

struct Number <: Base.Number
    bytes::Bytes
    first::Int
    last::Int
end


"""
Fields:
 - `task`, runs `parse_value` function as a co-routine.
 - `result`, the top-level JSON value.
 - `error`, exception thrown by `parse_value`.
"""

mutable struct Parser
    task::Task
    result
    error
    wait_count::Int
    Parser() = (p = new(); p.error = nothing; p.wait_count = 0; p)
end


"""
`getjson(v, i)` is used by the `AbstractArray` and `AbstractDict` API methods
to retrieve values from `JSON.Object` and `JSON.Array`.
"""

function getjson end


"""
If `use_promotejson` is `false`: The `getjson(v, i)` function is simply `v[i]`.
In this case numbers and strings are returned as `JSON.Number` and `JSON.String`.

If `use_promotejson` is `true` the `getjson(v, i)` function calls `promotejson`
on the value it retrieves from a collection and replaces the original value
with the promoted value.  In this case numbers and strings are returned as
`Base.Int64`, `Base.Float64` and `Base.SubString`.
"""

const use_promotejson = false

@static if use_promotejson

    function getjson(v, i)
        x = v[i]
        j = promotejson(x)
        if !(x === j)
            v[i] = j
        end
        return j
    end

else

    getjson(v, i) = @inbounds(v[i])

end

promotejson(v) = v
promotejson(v::JSON.String) = convert(SubString, v)
promotejson(v::JSON.Number) = convert(Base.Number, v)


"""
`JSON.Array` implements the `AbstractArray` interface.

The `AbstractArray` methods call `parse_more!` as needed to ensure that the
requested items are available in the array.

The parser task calls `push!` to add parsed values to the array.
`push!` calls `wait` to return control to the main task.
"""

mutable struct Array <: AbstractArray{Any, 1}
    parser::Parser
    v::Vector{Any}
    iscomplete::Bool
    Array(p) = new(p, [], false)
end

Base.push!(a::Array, x) = (push!(a.v, x); wait_for_parse_more(a.parser))


"""
`JSON.Object` implements the `AbstractDict` interface.

The keys an values are stored in a single `Vector`:
`[key1, value2, key2, value2, ...]`

The `AbstractDict` methods call `parse_more!` as needed to ensure that the
requested items are available in the array.

The parser task calls `push!` to add parsed values to the array.
`push!` calls `wait` to return control to the main task.
"""

mutable struct Object <: AbstractDict{AbstractString, Any}
    parser::Parser
    v::Vector{Any}
    iscomplete::Bool
    Object(p) = new(p, [], false)
end

function Base.push!(o::Object, x)
    push!(o.v, x)
    wait_for_parse_more(o.parser)
end


# JSON Parser

"""
Parse JSON text.

Returns a `Bool`, `Number`, `AbstractString`, `AbstractArray`, `AbstractDict` or
`Void`.

The parser runs in a lazy co-routine. If the returned value is a collection
type it will be incomplete. Each call to `parse_more!(::Parser)` causes another
an additional value to be parsed and added to the result collection.
`parse_more!` is called automatically by the `AbstractArray` and `AbstractDict`
interface methods.
"""

function Base.parse(::Type{JSON.Value},
                    as::AbstractString)
    s = codeunits(as)                   # Convert string to byte-vector
    l = length(s)
    p = Parser()                        # Run parse_value() as a co-routine.
    p.task = @task try                  # Pass the parser as the parent value
        i = parse_value(p, s, l, p, 1)  # and start at index 1.
        if enable_assertions
            check_end(p, s, l, i)
        end
    catch e                             # Capturue parse errors to be rethrown
        p.error = e                     # in the main task by parse_more()
    end
    parse_more!(p)                      # Ensure that the top level JSON value
    return p.result                     # is push!-ed into p.result.
end

iscomplete(x) = true
iscomplete(x::JSON.Object) = x.iscomplete
iscomplete(x::JSON.Array) = x.iscomplete

function Base.push!(p::Parser, value)
    p.result = value                    # Store the result value and if parsing
    if !iscomplete(value)               # is incomplete, wait for the next
        wait_for_parse_more(p)          # call to parse_more!().
    end
end

function parse_more!(p::Parser)
    if p.error != nothing               # Don't try to parse more if the last
        throw(p.error)                  # call resulted in an error.
    end

    schedule(current_task())            # Ensure that the main task will restart
    yieldto(p.task)                     # then run the parse_value() co-routine.

    if p.error != nothing               # Rethrow error captured from the
        throw(p.error)                  # parse_value() co-routine.
    end
end

function parse_more!(collection, index)
    while !collection.iscomplete &&     # Keep parsing until a specified index
           index > length(collection.v) # is available, or the end is reached.
        parse_more!(collection.parser)
    end
end

parse_all!(c) = while !c.iscomplete parse_more!(c.parser) end

function wait_for_parse_more(p)
    p.wait_count += 1
    if p.wait_count > 100               # Keep parsing for a while before
        p.wait_count = 0                # yeilding control back to the main
        wait()                          # task to avoid task switching overhead.
    end
end

function check_end(p::Parser, s::Bytes, l, i)
    if !iscomplete(p.result)
        throw(JSON.ParseError(s, i, "unexpected end of input"))
    end
    if i <= l
        i, x = skip_ws(s, l, i)
        if i <= l && !isws(x)
            throw(JSON.ParseError(s, i, "'$(Char(x))' after end of input"))
        end
    end 
end


"""
Throw a JSON.ParseError if the parse function's current character is not `x`.
"""

macro assume(x)
    if !enable_assertions
        return :()
    end
    s = typeof(x) == Char ? "'$x'" : string(x)
    esc(quote
        if i > length(s) || !(s[i] in UInt8[($x)...])
            throw(JSON.ParseError(s, i, "expected $($s)"))
        end
    end)
end


"""
Whitespace

https://tools.ietf.org/html/rfc7159#section-2

      ws = *(
              %x20 /              ; Space
              %x09 /              ; Horizontal tab
              %x0A /              ; Line feed or New line
              %x0D )              ; Carriage return
"""

isws(x) = x == 0x20 ||
          x == 0x09 ||
          x == 0x0A ||
          x == 0x0D

get_x(s, l, i) = i > l ? 0x00 : @inbounds(s[i])

next_x(s, l, i) = (i += 1; (i, get_x(s, l, i)))

function skip_ws(s, l, i)
    x = get_x(s, l, i)
    while isws(x)
        i, x = next_x(s, l, i)
    end
    return i, x
end


"""
Values

https://tools.ietf.org/html/rfc7159#section-3

      value = false / null / true / object / array / number / string

      false = %x66.61.6c.73.65   ; false

      null  = %x6e.75.6c.6c      ; null

      true  = %x74.72.75.65      ; true
"""

parse_false(p, s, l, v, i) = (push!(v, false);   i + 5)
parse_null(p, s, l, v, i)  = (push!(v, nothing); i + 4)
parse_true(p, s, l, v, i)  = (push!(v, true);    i + 4)


"""
Objects

https://tools.ietf.org/html/rfc7159#section-4

      object = begin-object [ member *( value-separator member ) ]
               end-object

      member = string name-separator value
"""

function parse_object(p, s, l, v, i)

    o = Object(p)
    push!(v, o)

    @assume '{'
    i += 1
    i, x = skip_ws(s, l, i)
    while x != UInt8('}')

        i, x = skip_ws(s, l, i)
        i = parse_string(p, s, l, o, i)
        i, x = skip_ws(s, l, i)

        @assume ':'
        i += 1

        i = parse_value(p, s, l, o, i)
        x = get_x(s, l, i)
        if x == UInt8(',')
            i += 1
        else
            @assume '}'
        end
    end

    o.iscomplete = true

    return i + 1
end


"""
Arrays

https://tools.ietf.org/html/rfc7159#section-5

   array = begin-array [ value *( value-separator value ) ] end-array
"""

function parse_array(p, s, l, v, i)

    a = Array(p)
    push!(v, a)

    @assume '['
    i += 1
    i, x = skip_ws(s, l, i)
    while x != UInt8(']')
        i = parse_value(p, s, l, a, i)
        x = get_x(s, l, i)
        if x == UInt8(',')
            i += 1
        else
            @assume ']'
        end
    end

    a.iscomplete = true

    return i + 1
end


"""
Numbers

https://tools.ietf.org/html/rfc7159#section-6

      number = [ minus ] int [ frac ] [ exp ]

      decimal-point = %x2E       ; .

      digit1-9 = %x31-39         ; 1-9

      e = %x65 / %x45            ; e E

      exp = e [ minus / plus ] 1*DIGIT

      frac = decimal-point 1*DIGIT

      int = zero / ( digit1-9 *DIGIT )

      minus = %x2D               ; -

      plus = %x2B                ; +

      zero = %x30                ; 0
"""


function parse_number(p, s, l, v, i)

    start = i

    x = @inbounds(s[i]) 
    if x == UInt8('-')
        i, x = next_x(s, l, i)
    end
    @assume '0':'9'
    prev = x
    i, x = next_x(s, l, i)
    if prev == UInt8('0')
        @assume '.', 'e', 'E', ']', '}', ','
    end

    while !isws(x) &&
          x != UInt8(']') &&
          x != UInt8('}') &&
          x != UInt8(',') &&
          x != 0x00
        prev = x
        i, x = next_x(s, l, i)
        if prev == UInt8('.')
            @assume '0':'9'
        end
    end

    i -= 1
    @assume '0':'9'
    push!(v, JSON.Number(s, start, i))

    return i + 1
end


"""
Strings

https://tools.ietf.org/html/rfc7159#section-7


      string = quotation-mark *char quotation-mark

      char = unescaped /
          escape (
              %x22 /          ; "    quotation mark  U+0022
              %x5C /          ; \\    reverse solidus U+005C
              %x2F /          ; /    solidus         U+002F
              %x62 /          ; b    backspace       U+0008
              %x66 /          ; f    form feed       U+000C
              %x6E /          ; n    line feed       U+000A
              %x72 /          ; r    carriage return U+000D
              %x74 /          ; t    tab             U+0009
              %x75 4HEXDIG )  ; uXXXX                U+XXXX

      escape = %x5C              ; \\

      quotation-mark = %x22      ; "

      unescaped = %x20-21 / %x23-5B / %x5D-10FFFF
"""

function parse_string(p, s, l, v, i)

    start = i
    has_escape = false

    @assume '"'
    i, x = next_x(s, l, i)

    while x != UInt8('"') && x != 0x00
        if x == UInt8('\\')
            has_escape = true
            i, x = next_x(s, l, i)
            @assume '"', '\\', '/', 'b', 'f', 'n', 'r', 't', 'u'
        end
        i, x = next_x(s, l, i)
    end
    @assume '"'

    push!(v, JSON.String(s, start+1, i-1, has_escape))

    return i + 1
end


"""
    parse_value(p::Parser, string::Bytes, parent_value, index)

Parse a [JSON value](https://tools.ietf.org/html/rfc7159#section-3) from a
`string` of bytes starting at `index`. The parsed value is appended to the
parent value (e.g. `push!(parent_value, parsed_value)`).
"""

function parse_value(p::Parser, s::Bytes, l, v, i)

    i, x = skip_ws(s, l, i)

    i = if x == UInt8('f')                       parse_false(p, s, l, v, i)
    elseif x == UInt8('n')                        parse_null(p, s, l, v, i)
    elseif x == UInt8('t')                        parse_true(p, s, l, v, i)
    elseif x == UInt8('{')                      parse_object(p, s, l, v, i)
    elseif x == UInt8('[')                       parse_array(p, s, l, v, i)
    elseif x == UInt8('"')                      parse_string(p, s, l, v, i)
    elseif x >= UInt8('0')  &&
           x <= UInt8('9')  ||
           x == UInt8('-')                      parse_number(p, s, l, v, i)
    else
        throw(JSON.ParseError(s, i, "invalid input"))
    end

    i, x = skip_ws(s, l, i)
    return i
end



# Message Display

Base.show(io::IO, s::JSON.String) =
    print(io, SubString(s.bytes.s, s.first-1, s.last+1))

Base.show(io::IO, n::JSON.Number) = print(io, string(n))

function Base.show(io::IO, e::JSON.ParseError)

    s = Base.String(e.bytes)
    l = findprev(equalto('\n'), s, e.index)
    l = l != nothing ? l + 1 : 1
    r = findnext(equalto('\n'), s, max(1, e.index-1))
    r = r != nothing ? r - 1 : length(s)
    l = min(length(s), l)
    line_number = length(split(SubString(s, 1, l), '\n'))
    col_number = e.index - l + 1
    print(io, "JSON.ParseError: ", e.message, 
              " at line ", line_number, ", col ", col_number, "\n",
              SubString(s, l, r), "\n",
              lpad("", col_number - 1, " "), "^")
end

include("AbstractString.jl")
include("Number.jl")
include("AbstractArray.jl")
include("AbstractDict.jl")



end # module JSON
