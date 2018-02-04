"""
LazyJSON.jl

See README.md
"""

module LazyJSON

const JSON = LazyJSON

abstract type Value end

const Key = Union{Int, Base.CodeUnits{UInt8,Base.String}}

parse(s::AbstractString; path=[]) = Base.parse(JSON.Value, s;
                                               path=mkpath(path))

mkpath(p) = Key[x isa AbstractString ? codeunits(x) : x for x in p]

const Bytes = Base.CodeUnits{UInt8,Base.String}

const enable_assertions = false

const disable_coroutine = false


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

Base.push!(a::JSON.Array, x) = (push!(a.v, x); wait_for_parse_more(a.parser))


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
`Nothing`.

The parser runs in a lazy co-routine. If the returned value is a collection
type it will be incomplete. Each call to `parse_more!(::Parser)` causes another
an additional value to be parsed and added to the result collection.
`parse_more!` is called automatically by the `AbstractArray` and `AbstractDict`
interface methods.
"""

function Base.parse(::Type{JSON.Value},
                    as::AbstractString;
                    path::Vector{Key}=[])
    s = codeunits(as)                   # Convert string to byte-vector
    l = length(s)
    p = Parser()                        # Run parse_value() as a co-routine.
    v = isempty(path) ? p : path
    @static if disable_coroutine
    parse_value(p, s, l, v, 1)
    else
    p.task = @task try                  # Pass the parser as the parent value
        i = parse_value(p, s, l, v, 1)  # and start at index 1.
        if enable_assertions
            check_end(p, s, l, i)
        end
    catch e                             # Capturue parse errors to be rethrown
        p.error = e                     # in the main task by parse_more()
    end
    end
    parse_more!(p)                      # Ensure that the top level JSON value
    return p.result                     # is push!-ed into p.result.
end

iscomplete(x) = true
iscomplete(x::JSON.Object) = x.iscomplete
iscomplete(x::JSON.Array) = x.iscomplete

function Base.push!(p::Parser, value)
    p.result = value                    # Store the result value and wait for
    disable_coroutine || wait()         # the next call to parse_more!().
end

@static if disable_coroutine
parse_more!(p::Parser) = nothing
else
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
end

function parse_more!(collection, index)
    while !collection.iscomplete &&     # Keep parsing until a specified index
           index > length(collection.v) # is available, or the end is reached.
        parse_more!(collection.parser)
    end
end

parse_all!(c) = while !c.iscomplete parse_more!(c.parser) end

@static if disable_coroutine
wait_for_parse_more(p) = nothing
else
function wait_for_parse_more(p)
    p.wait_count += 1
    if p.wait_count > 100               # Keep parsing for a while before
        p.wait_count = 0                # yeilding control back to the main
        wait()                          # task to avoid task switching overhead.
    end
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

parse_false(p, s, l, v, i) = (v != nothing && push!(v, false);   i + 5)
parse_null(p, s, l, v, i)  = (v != nothing && push!(v, nothing); i + 4)
parse_true(p, s, l, v, i)  = (v != nothing && push!(v, true);    i + 4)


"""
Objects

https://tools.ietf.org/html/rfc7159#section-4

      object = begin-object [ member *( value-separator member ) ]
               end-object

      member = string name-separator value
"""

function parse_object(p, s, l, v, i)

    if v isa AbstractVector{Key}
        key = v[1]
        if key isa Base.CodeUnits
            vl = length(v)
            path = vl > 1 ? view(v, 2:vl) : p
        else
            key = nothing
        end
    else
        key = nothing
    end
    if v == nothing || v isa AbstractVector{Key}
        o = nothing
    else
        o = Object(p)
        push!(v, o)
    end

    @assume '{'
    i += 1
    i, x = skip_ws(s, l, i)
    while x != UInt8('}')

        i, x = skip_ws(s, l, i)
        k = i
        i = parse_string(p, s, l, o, i)
        oo = key != nothing && view(s, k+1:i-2) == key ? path : o
        i, x = skip_ws(s, l, i)
        @assume ':'
        i += 1

        i = parse_value(p, s, l, oo, i)
        x = get_x(s, l, i)
        if x == UInt8(',')
            i += 1
        else
            @assume '}'
        end
    end

    if o isa Object
        o.iscomplete = true
    end

    return i + 1
end


"""
Arrays

https://tools.ietf.org/html/rfc7159#section-5

   array = begin-array [ value *( value-separator value ) ] end-array
"""

function parse_array(p, s, l, v, i)

    if v isa AbstractVector{Key}
        key = v[1]
        if key isa Int
            vl = length(v)
            path = vl > 1 ? view(v, 2:vl) : p
        else
            key = 0
        end
    else
        key = 0
    end
    if v == nothing || v isa AbstractVector{Key}
        a = nothing
    else
        a = JSON.Array(p)
        push!(v, a)
    end

    @assume '['
    i += 1
    i, x = skip_ws(s, l, i)
    count = 1
    while x != UInt8(']')
        aa = key != 0 && count == key ? path : a
        i = parse_value(p, s, l, aa, i)
        x = get_x(s, l, i)
        if x == UInt8(',')
            i += 1
        else
            @assume ']'
        end
        count += 1
    end

    if a isa JSON.Array
        a.iscomplete = true
    end

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
    if v != nothing
        push!(v, JSON.Number(s, start, i))
    end

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

    if v != nothing
        push!(v, JSON.String(s, start+1, i-1, has_escape))
    end

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
