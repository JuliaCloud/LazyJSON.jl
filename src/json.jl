"""
JSON 

https://tools.ietf.org/html/rfc7159
"""

module JSON


abstract type Value end

parse(s::AbstractString) = Base.parse(JSON.Value, s)

const Bytes = Base.CodeUnits{UInt8,Base.String}

const enable_assertions = true



# Parser Data Structures

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
    Parser() = (p = new(); p.error = nothing; p)
end


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

mutable struct Number <: Base.Number
    bytes::Bytes
    first::Int
    last::Int
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

    getjson(v, i) = v[i]

end

promotejson(v) = v
promotejson(v::String) = convert(SubString, v)
promotejson(v::Number) = convert(Base.Number, v)


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

Base.push!(a::Array, x) = (push!(a.v, x); wait()) # resumed by parse_more!


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

Base.push!(a::Object, x) = (push!(a.v, x); wait()) # resumed by parse_more!


"""
    parse_value(p::Parser, string::Bytes, parent_value, index)

Parse a [JSON value](https://tools.ietf.org/html/rfc7159#section-3) from a
`string` of bytes starting at `index`. The parsed value is appended to the
parent value (e.g. `push!(parent_value, parsed_value)`).

The `parse_vector` contains parse functions indexed on ASCII character code.
"""

function parse_value(p::Parser, s::Bytes, v, n)
    n, x = parse_vector[@inbounds(s[n])](p, s, v, n)
    skip_ws(s, n)
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
                    s::AbstractString)
    bytes = codeunits(s)                # Convert string to byte-vector
    p = Parser()                        # Run parse_value() as a co-routine.
    p.task = @task try                  # Pass the parser as the parent value
        parse_value(p, bytes, p, 1)     # and start at index 1.
    catch e                             # Capturue parse errors to be rethrown
        p.error = e                     # in the main task by parse_more()
    end
    parse_more!(p)                      # Ensure that the top level JSON value
    return p.result                     # is push!-ed into p.result.
end

function Base.push!(p::Parser, value)
    p.result = value                    # Store the result value and wait for
    wait()                              # the next call to parse_more!().
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


"""
Throw a JSON.ParseError if the parse function's current character is not `x`.
"""

macro assume(x)
    if !enable_assertions
        return :()
    end
    s = typeof(x) == Char ? "'$x'" : string(x)
    esc(quote
        if !(s[i] in UInt8[($x)...])
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

next_x(s, i) = (i += 1), @inbounds(s[i])

function skip_ws(s, i)
    x = @inbounds(s[i])
    while isws(x)
        i, x = next_x(s, i)
    end
    i, x
end

function parse_value_after_ws(p, s, v, i)
    i, x = skip_ws(s, i)
    parse_value(p, s, v, i)
end


"""
Values

https://tools.ietf.org/html/rfc7159#section-3

      value = false / null / true / object / array / number / string

      false = %x66.61.6c.73.65   ; false

      null  = %x6e.75.6c.6c      ; null

      true  = %x74.72.75.65      ; true
"""

parse_false(p, s, v, i) = (i += 5; push!(v, false);   (i, @inbounds(s[i])))
parse_null(p, s, v, i)  = (i += 4; push!(v, nothing); (i, @inbounds(s[i])))
parse_true(p, s, v, i)  = (i += 4; push!(v, true);    (i, @inbounds(s[i])))


"""
Objects

https://tools.ietf.org/html/rfc7159#section-4

      object = begin-object [ member *( value-separator member ) ]
               end-object

      member = string name-separator value
"""

function parse_object(p, s, v, i)

    o = Object(p)
    push!(v, o)

    @assume '{'
    i += 1
    i, x = skip_ws(s, i)

    while x != UInt8('}')

        i, x = skip_ws(s, i)
        i, x = parse_string(p, s, o, i)
        i, x = skip_ws(s, i)

        @assume ':'
        i += 1

        i, x = parse_value(p, s, o, i)

        if x == UInt8(',')
            i, x = next_x(s, i)
        else
            @assume '}'
        end
    end

    o.iscomplete = true

    next_x(s, i)
end


"""
Arrays

https://tools.ietf.org/html/rfc7159#section-5

   array = begin-array [ value *( value-separator value ) ] end-array
"""

function parse_array(p, s, v, i)

    a = Array(p)
    push!(v, a)

    @assume '['
    i += 1
    i, x = skip_ws(s, i)

    while x != UInt8(']')

        i, x = parse_value(p, s, a, i)

        if x == UInt8(',')
            i, x = next_x(s, i)
        else
            @assume ']'
        end
    end

    a.iscomplete = true

    next_x(s, i)
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


function parse_number(p, s, v, i)

    start = i

    @assume '-', '0':'9'...
    i += 1
    i, x = skip_ws(s, i)

    while !isws(x) &&
          x != UInt8(']') &&
          x != UInt8('}') &&
          x != UInt8(',') &&
          x != 0x00
        i, x = next_x(s, i)
    end

    push!(v, Number(s, start, i-1))

    return i, x
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

function parse_string(p, s, v, i)

    start = i
    has_escape = false

    @assume '"'
    i, x = next_x(s, i)

    while x != UInt8('"')
        if x == UInt8('\\')
            has_escape = true
            i, x = next_x(s, i)
        end
        i, x = next_x(s, i)
    end

    push!(v, String(s, start+1, i-1, has_escape))

    return next_x(s, i)
end


parse_error(p, s, i) = throw(JSON.ParseError(s, i, "invalid input"))


"""
Vector of parse functions indexed on ASCII character code.
"""

const parse_vector = (()->begin

    v = Vector{Function}(fill(parse_error::Function, typemax(UInt8)))

    v[UInt8(' ')]  = parse_value_after_ws
    v[UInt8('\t')] = parse_value_after_ws
    v[UInt8('\r')] = parse_value_after_ws
    v[UInt8('\n')] = parse_value_after_ws

    v[UInt8('f')]  = parse_false
    v[UInt8('n')]  = parse_null
    v[UInt8('t')]  = parse_true

    v[UInt8('{')]  = parse_object
    v[UInt8('[')]  = parse_array
    v[UInt8('"')]  = parse_string

    for x in ('-', '0':'9'...)
        v[UInt8(x)] = parse_number
    end
    
    return v
end)()



# Message Display

Base.show(io::IO, s::String) =
    print(io, SubString(s.bytes.s, s.first-1, s.last+1))

Base.show(io::IO, n::Number) = print(io, string(n))

function Base.show(io::IO, e::JSON.ParseError)

    s = Base.String(e.bytes)
    l = findprev(equalto('\n'), s, e.index)
    l = l != nothing ? l + 1 : 1
    r = findnext(equalto('\n'), s, e.index-1)
    r = r != nothing ? r - 1 : length(s)
    line_number = length(split(SubString(s, l), '\n'))
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
