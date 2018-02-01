"""
JSON 

https://tools.ietf.org/html/rfc7159
"""

module JSON


const Bytes = Base.CodeUnits{UInt8,String}



# Debug

const enable_assertions = true

macro assume(x)
    if !enable_assertions
        return :()
    end
    s = typeof(x) == Char ? "'$x'" : string(x)
    esc(quote
        if !(s[n] in UInt8[($x)...])
            throw(ParseError(j, s, n, "expected $($s)"))
        end
    end)
end



# Parser State

mutable struct JSONData
    bytes::Bytes
    parser::Task
    stack::Vector{Any}
    field_name
    e
    function JSONData(s::Bytes)
        j = new()
        j.bytes = s
        j.stack = []
        j.field_name = nothing
        j.e = nothing
        j
    end
end



# Error Messages

struct ParseError <: Exception
    j::JSONData
    bytes::Bytes
    n::Int
    message::String
end

function Base.show(io::IO, e::ParseError)

    s = String(e.bytes)
    l = findprev(equalto('\n'), s, e.n)
    l = l != nothing ? l + 1 : 1
    r = findnext(equalto('\n'), s, e.n-1)
    r = r != nothing ? r - 1 : length(s)
    line_number = length(split(SubString(s, l), '\n'))
    col_number = e.n - l + 1
    print(io, "JSON.ParseError: ", e.message, 
              " at line ", line_number, ", col ", col_number, "\n",
              SubString(s, l, r), "\n",
              lpad("", col_number - 1, " "), "^")
end



# Strings

struct JSONString # FIXME <: AbstractString
    bytes::Bytes
    first::Int
    last::Int
end

Base.string(s::JSONString) = SubString(s.bytes.s, s.first, s.last)
Base.show(io::IO, s::JSONString) = print(io, string(s))

convertjson(v) = v
convertjson(v::JSONString) = string(v)


# Numbers

struct JSONNumber
    bytes::Bytes
    first::Int
    last::Int
end

Base.string(s::JSONNumber) = SubString(s.bytes.s, s.first, s.last)
Base.show(io::IO, s::JSONNumber) = print(io, string(s))

function convertjson(v::JSONNumber)
    s = string(v)
    v = tryparse(Int, s)
    if v == nothing
        v = tryparse(Float64, s)
    end
    @assert v != nothing
    return v
end


# Arrays

mutable struct JSONArray <: AbstractArray{Any, 1}
    j::JSONData
    v::Vector{Any}
    iscomplete::Bool
    JSONArray(j) = new(j, [], false)
end


function parse_more!(a, i)
    while !a.iscomplete && i > length(a.v)
        parse_more!(a.j)
    end
end

function parse_all!(a)
    while !a.iscomplete
        parse_more!(a.j)
    end
end

Base.length(a::JSONArray) = (parse_all!(a); length(a.v))
Base.size(a::JSONArray) = (parse_all!(a); size(a.v))

function Base.getindex(a::JSONArray, i::Int) 
    parse_more!(a, i)
    v = a.v[i]
    jv = convertjson(v)
    if !(v === jv)
        a.v[i] = jv
    end
    return jv
end

Base.IteratorSize(::Type{JSONArray}) = Base.SizeUnknown()

Base.start(a::JSONArray) = 1
Base.done(a::JSONArray, i) = (parse_more!(a, i); i > length(a.v))
Base.next(a::JSONArray, i) = (getindex(a, i), i + 1)



# Objects

mutable struct JSONObject <: AbstractDict{AbstractString, Any}
    j::JSONData
    v::Vector{Pair}
    iscomplete::Bool
    JSONObject(j) = new(j, [], false)
end


Base.length(o::JSONObject) = (parse_all!(o); length(o.v))
Base.size(o::JSONObject) = (parse_all!(o); size(o.v))

function Base.get(o::JSONObject, i::Int, d)
    parse_more!(o, i)
    v = get(o.v, i, d)
    jk = convertjson(v.first)
    jv = convertjson(v.second)
    if !(v.first === jk && v.second === jv)
        v = jk => jv
        o.v[i] = v
    end
    return v
end

function Base.get(o::JSONObject, key::AbstractString, default)
    for (k, v) in o
        if k == key
            return v
        end
    end
    return default
end

Base.start(o::JSONObject) = 1
Base.done(o::JSONObject, i) = (parse_more!(o, i); i > length(o.v))
Base.next(o::JSONObject, i) = (getindex(o, i), i + 1)

struct JSONObjectKeys
    o::JSONObject
end

Base.keys(o::JSONObject) = JSONObjectKeys(o)

Base.IteratorSize(::Type{JSONObjectKeys}) = Base.SizeUnknown()

Base.start(k::JSONObjectKeys) = 1
Base.done(k::JSONObjectKeys, i) = (parse_more!(k.o, i); i > length(k.o.v))
Base.next(k::JSONObjectKeys, i) = (getindex(k.o, i).first, i + 1)



# Parsing

function Base.parse(::Type{JSONData}, s::AbstractString)
    bytes = codeunits(s)
    j = JSONData(bytes)
    j.parser = @task try parse_value(j, bytes) catch e j.e = e end
    while isempty(j.stack)
        parse_more!(j)
    end
    return first(j.stack)
end


function parse_more!(j::JSONData)
    if j.e != nothing
        throw(j.e)
    end
    @assert !istaskdone(j.parser)
    schedule(current_task())
    yieldto(j.parser)
    if j.e != nothing
        throw(j.e)
    end
end


function consume!(j::JSONData, x)
    if isempty(j.stack)
        push!(j.stack, x)
    else
        consume!(j, last(j.stack), x)
    end

    # Suspend the parser task, to be woken later by parse_more!(j::JSONData)
    wait()
end

consume!(j::JSONData, a::JSONArray, x) = push!(a.v, x)

function consume!(j::JSONData, o::JSONObject, x)
    if j.field_name == nothing
        j.field_name = x
    else
        push!(o.v, j.field_name => x)
        j.field_name = nothing
    end
end


Base.pop!(j::JSONData) = pop!(j.stack)

Base.push!(j::JSONData, v) =  push!(j.stack, v)


isws(x) = x == 0x20 || # Space
          x == 0x09 || # Horizontal tab
          x == 0x0A || # Line feed or New line
          x == 0x0D    # Carriage return

next_x(s, n) = (n += 1), @inbounds(s[n])

function skip_ws(s, n)
    x = @inbounds(s[n])
    while isws(x)
        n, x = next_x(s, n)
    end
    n, x
end


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


function parse_value(j::JSONData, s::Bytes, n::Int = 1)
    n, x = parse_vector[@inbounds(s[n])](j, s, n)
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

parse_false(j, s, n) = (i = n; n += 5; consume!(j, false); (n, @inbounds(s[n])))
parse_null(j, s, n) = (i = n; n += 4; consume!(j,nothing); (n, @inbounds(s[n])))
parse_true(j, s, n) = (i = n; n += 4; consume!(j, true);   (n, @inbounds(s[n])))


"""

Objects

https://tools.ietf.org/html/rfc7159#section-4

      object = begin-object [ member *( value-separator member ) ]
               end-object

      member = string name-separator value
"""

function parse_object(j, s, n)

    o = JSONObject(j)
    consume!(j, o)
    push!(j, o)

    @assume '{'
    n += 1
    n, x = skip_ws(s, n)

    while x != UInt8('}')

        n, x = skip_ws(s, n)
        n, x = parse_string(j, s, n)
        n, x = skip_ws(s, n)

        @assume ':'
        n += 1

        n, x = parse_value(j, s, n)

        if x == UInt8(',')
            n, x = next_x(s, n)
        else
            @assume '}'
        end
    end

    o.iscomplete = true
    pop!(j)

    next_x(s, n)
end


"""
Arrays

https://tools.ietf.org/html/rfc7159#section-5

   array = begin-array [ value *( value-separator value ) ] end-array

"""

function parse_array(j, s, n)

    a = JSONArray(j)
    consume!(j, a)
    push!(j, a)

    @assume '['
    n += 1
    n, x = skip_ws(s, n)

    while x != UInt8(']')

        n, x = parse_value(j, s, n)

        if x == UInt8(',')
            n, x = next_x(s, n)
        else
            @assume ']'
        end
    end

    a.iscomplete = true
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

    @assume '-', '0':'9'...
    n += 1
    n, x = skip_ws(s, n)

    while !isws(x) &&
          x != UInt8(']') &&
          x != UInt8('}') &&
          x != UInt8(',') &&
          x != 0x00
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

    @assume '"'
    n, x = next_x(s, n)

    while x != UInt8('"')
        if x == UInt8('\\')
            n, x = next_x(s, n)
        end
        n, x = next_x(s, n)
    end

    consume!(j, JSONString(s, i+1, n-1))

    next_x(s, n)
end


parse_error(j, s, n) = throw(ParseError(j, s, n, "unexpected input"))

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

end # module JSON
