"""
JSON 

https://tools.ietf.org/html/rfc7159


JSON Grammar

https://tools.ietf.org/html/rfc7159#section-2

      JSON-text = ws value ws
"""

const begin_array     = UInt8('[')
const begin_object    = UInt8('{')
const end_array       = UInt8(']')
const end_object      = UInt8('}')
const name_separator  = UInt8(':')
const value_separator = UInt8(',')

const quotation_mark  = UInt8('"')
const escape          = UInt8('\\')

const Bytes = Base.CodeUnits{UInt8,String}


struct JSONString
    json::Bytes
    first::Int
    last::Int
end

Base.string(s::JSONString) = SubString(s.json.s, s.first, s.last)
Base.show(io::IO, s::JSONString) = print(io, string(s))


struct JSONNumber
    json::Bytes
    first::Int
    last::Int
end

Base.string(s::JSONNumber) = SubString(s.json.s, s.first, s.last)
Base.show(io::IO, s::JSONNumber) = print(io, string(s))


const JSONArray = Vector{Any}


const JSONObject = Vector{Pair{JSONString,Any}}


mutable struct JSONState
    stack::Vector{Any}
    name::Union{JSONString,Nothing}
    JSONState() = new([], nothing)
end


consume!(j::JSONState, a::JSONArray, x) = push!(a, x)

function consume!(j::JSONState, o::JSONObject, x)
    if j.name == nothing
        j.name = x
    else
        push!(o, j.name => x)
        j.name = nothing
    end
end

function consume!(j::JSONState, x)
    if isempty(j.stack)
        push!(j.stack, x)
    else
        consume!(j, last(j.stack), x)
    end
end

Base.pop!(j::JSONState) = pop!(j.stack)

Base.push!(j::JSONState, v) =  push!(j.stack, v)


isws(x) = x == 0x20 || # Space
          x == 0x09 || # Horizontal tab
          x == 0x0A || # Line feed or New line
          x == 0x0D    # Carriage return

next_x(s, n) = (n += 1), @inbounds s[n]

skip_ws(s, n) = (x = @inbounds s[n]; while isws(x) n, x = next_x(s, n) end; (n, x))


tmpin = """
      {
        "Image": {
            "Width":  800,
            "Height": 600,
            "Title":  "View from 15th Floor",
            "Thumbnail": {
                "Url":    "http://www.example.com/image/481989943",
                "Height": 125,
                "Width":  100
            },
            "Animated" : false,
            "IDs": [116, 943, 234, 38793]
          }
      }
"""

function parse_value(s::AbstractString)
    j = JSONState()
    parse_value(j, codeunits(s))
    return j
end

function parse_value(j::JSONState, s::Bytes, n = 1)
    n, x = parse_vector[s[n]](j, s, n)
    skip_ws(s, n)
end


function parse_value_after_ws(j, s, n)
    n, x = skip_ws(s, n)
    parse_value(j, s, n)
end


"""

Values

https://tools.ietf.org/html/rfc7159#section-3

      value = false / null / true / object / array / number / string

      false = %x66.61.6c.73.65   ; false

      null  = %x6e.75.6c.6c      ; null

      true  = %x74.72.75.65      ; true

"""

parse_false(j, s, n) = (i = n; n += 5; consume!(j, false)  ; (n, s[n]))
parse_null(j, s, n)  = (i = n; n += 4; consume!(j, nothing); (n, s[n]))
parse_true(j, s, n)  = (i = n; n += 4; consume!(j, true)   ; (n, s[n]))


"""

Objects

https://tools.ietf.org/html/rfc7159#section-4

      object = begin-object [ member *( value-separator member ) ]
               end-object

      member = string name-separator value
"""

function parse_object(j, s, n)

    o = JSONObject()
    consume!(j, o)
    push!(j, o)

    # '{'
    n += 1
    n, x = skip_ws(s, n)

    while x != end_object

        n, x = parse_value(j, s, n)

        # ':'
        n += 1

        n, x = parse_value(j, s, n)

        # ',' or '}'
        if x == value_separator
            n, x = next_x(s, n)
        end
    end

    pop!(j)

    next_x(s, n)
end


"""
Arrays

https://tools.ietf.org/html/rfc7159#section-5

   array = begin-array [ value *( value-separator value ) ] end-array

"""

function parse_array(j, s, n)

    a = JSONArray()
    consume!(j, a)
    push!(j, a)

    # '['
    n += 1
    n, x = skip_ws(s, n)

    while x != end_array

        n, x = parse_value(j, s, n)

        # ',' or ']'
        if x == value_separator
            n, x = next_x(s, n)
        end
    end

    pop!(j)

    next_x(s, n)
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


function parse_number(j, s, n)

    i = n

    # '-' or '0'-'9'
    n += 1
    n, x = skip_ws(s, n)

    while !isws(x) &&
          x != end_array &&
          x != end_object &&
          x != value_separator
        n, x = next_x(s, n)
    end

    consume!(j, JSONNumber(s, i, n-1))

    n, x
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

function parse_string(j, s, n)

    i = n

    # '"'
    n, x = next_x(s, n)

    while x != quotation_mark
        if x == escape
            n, x = next_x(s, n)
        end
        n, x = next_x(s, n)
    end

    consume!(j, JSONString(s, i+1, n-1))

    next_x(s, n)
end


"""
Examples

https://tools.ietf.org/html/rfc7159#section-13

   This is a JSON object:

      {
        "Image": {
            "Width":  800,
            "Height": 600,
            "Title":  "View from 15th Floor",
            "Thumbnail": {
                "Url":    "http://www.example.com/image/481989943",
                "Height": 125,
                "Width":  100
            },
            "Animated" : false,
            "IDs": [116, 943, 234, 38793]
          }
      }

   Its Image member is an object whose Thumbnail member is an object and
   whose IDs member is an array of numbers.

   This is a JSON array containing two objects:

      [
        {
           "precision": "zip",
           "Latitude":  37.7668,
           "Longitude": -122.3959,
           "Address":   "",
           "City":      "SAN FRANCISCO",
           "State":     "CA",
           "Zip":       "94107",
           "Country":   "US"
        },
        {
           "precision": "zip",
           "Latitude":  37.371991,
           "Longitude": -122.026020,
           "Address":   "",
           "City":      "SUNNYVALE",
           "State":     "CA",
           "Zip":       "94085",
           "Country":   "US"
        }
      ]

"""

struct ParseError <: Exception
    j::JSONState
    s::Bytes
    n::Int
end


parse_error(j, s, n) = throw(ParseError(j, s, n))

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
    
#    v[UInt8(']')] 
#    v[UInt8('}')]
#    v[UInt8(':')]
#    v[UInt8(',')]

    return v
end)()
