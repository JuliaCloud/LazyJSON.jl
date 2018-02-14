module LazyJSON

using DataStructures: OrderedDict

const JSON = LazyJSON



# JSON Value Types

"""
Values are represented by a reference to the JSON text `String`
and the byte index of the value text.

    String: {"foo": 1, "bar": [1, 2, 3, "four"]}
            ▲                 ▲      ▲  ▲
            │                 │      │  │
            ├──────────────┐  │      │  │
            │   JSON.Array(s, i=9)   │  │   == Any[1, 2, 3, "four"]
            │                        │  │
            ├───────────────┐  ┌─────┘  │
            │   JSON.Number(s, i=16)    │   == 3
            │                           │
            ├───────────────┐  ┌────────┘
            │   JSON.String(s, i=19)        == "four"
            │
            └───────────────┬──┐
                JSON.Object(s, i=1)
"""
struct String{T <: AbstractString} <: AbstractString
    s::T
    i::Int
end

struct Number{T <: AbstractString} <: Base.Number
    s::T
    i::Int
end

struct Object{T <: AbstractString} <: AbstractDict{AbstractString, Any}
    s::T
    i::Int
end

struct Array{T <: AbstractString}  <: AbstractArray{Any, 1}
    s::T
    i::Int
end

const Value = Union{JSON.String, JSON.Number, JSON.Object, JSON.Array}
const Collection = Union{JSON.Object, JSON.Array}

"""
Verbatim JSON text of a `JSON.Value`
"""
Base.string(s::JSON.Value) = SubString(s.s, s.i, lastindex_of_value(s.s, s.i))



# Get Typed JSON Value

"""
    value(jsontext) -> JSON.Value
    JSON.Value <: Union{Number, AbstractString, AbstractVector, AbstractDict}

Create a `JSON.Value` object from a JSON text.
"""
function value(s::Union{Base.String,SubString{String}}, path=nothing; lazy=true)
    i, c = skip_whitespace(s)
    if path != nothing
        v = getpath(s, path, i, c)
    else
        v = getvalue(s, i, c)
    end
    return lazy ? v : flatten(v)
end

struct ParseError <: Exception
    bytes::Base.String
    index::Int
    message::Base.String
end



"""
Get a JSON value object for a value in a JSON text.
 - `s`, the JSON text.
 - `i`, byte index of the value in JSON text.
 - `c`, first byte of the value.
"""
function getvalue(s, i, c=getc(s, i))
        if c == '{'                     JSON.Object(s, i)
    elseif c == '['                     JSON.Array(s, i)
    elseif c == '"'                     JSON.String(s, i)
    elseif isnum(c)                     JSON.Number(s, i)
    elseif c == 'f'                     false
    elseif c == 'n'                     nothing
    elseif c == 't'                     true
    else
        throw(ParseError(s, i, "invalid value index"))
    end
end


"""
See `LazyJSON.value(jsontext) -> JSON.Value`.
"""
parse(a...; kw...) = value(a...; kw...)



# Promotion to Base Container types

"""
Promote a JSON.Vaue to an equivalent Base type.
"""
promotejson(x; kw...) = x
promotejson(n::JSON.Number) = convert(Base.Number, n)
promotejson(s::JSON.String) = convert(AbstractString, s)
promotejson(a::JSON.Array)  = convert(Vector, a)
promotejson(o::JSON.Object) = convert(OrderedDict, o)



# Flattening to Base Container types

"""
Get a flattened (non-lazy) Julia object for a value in a JSON text;
and the index of the last character of the value.
"""
function getflat(s, i, c = getc(s, i))
        if c == '{'                     flat_object(s, i)
    elseif c == '['                     flat_array(s, i)
    elseif c == '"'                     parse_string(s, i)
    elseif isnum(c)                     parse_number(s, i)
    elseif c == 'f'                     false, i + 4
    elseif c == 'n'                     nothing, i + 3
    elseif c == 't'                     true, i + 3
    else
        throw(ParseError(s, i, "invalid value index"))
    end
end

flatten(v) = v
flatten(v::Value) = getflat(v.s, v.i)[1]


function flat_object(s, i)
    o = OrderedDict{SubString{Base.String},Any}()
    i, c = skip_noise(s, i + 1)
    while c != '}'
        k, i = parse_string(s, i)
        i, c = skip_noise(s, i + 1)
        v, i = getflat(s, i, c)
        o[k] = v
        i, c = skip_noise(s, i + 1)
    end
    return o, i
end

function flat_array(s, i)
    a = Any[]
    i, c = skip_noise(s, i + 1)
    while c != ']'
        v, i = getflat(s, i, c)
        push!(a, v)
        i, c = skip_noise(s, i + 1)
    end
    return a, i
end



# JSON Object/Array Iterator

"""
Iterate over the byte-indexes of the values in a JSON Array,
or the byte-indexes of the alternating field names and values in a JSON Object.
"""
struct Indexes{T}
    j::T
end

Base.IteratorSize(::Type{Indexes{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{Indexes{T}}) where T = Base.EltypeUnknown()

indexes(j::T) where T <: JSON.Collection = Indexes{T}(j)

Base.start(j::Indexes) = (j.j.i, 0x00)
Base.done(j::Indexes, (i, c)) = (c == ']' || c == '}')
function Base.next(j::Indexes, (i, c))
    i, c = nextindex(j.j, i, c)
    return (i, c), (i, c)
end

function nextindex(j, i, c)
    if i > j.i
        i = lastindex_of_value(j.s, i, c)
    end
    i, c = skip_noise(j.s, i + 1)
    return i, c
end


"""
Count the number of values in an Array or Object.
For an Object, the count includes the field names.
"""
function collection_length(c::JSON.Collection)
    count = -1
    for i in indexes(c)
        count += 1
    end
    return count
end


# JSON Array Lookup

"""
Get the index `i` and first byte `c` of the `n`th value in an Array.
"""
function getindex_ic(a::JSON.Array, n::Int)
    for (i, c) in indexes(a)            # Iterate over byte-indexs of array
        if c == ']'                     # values until the end byte ']'.
           throw(BoundsError(a, n))
        end
        if n == 1
            return i, c                 # Return the byte-index of the nth value
        end
        n -= 1
    end
end



# JSON Object Field Name Lookup

memcmp(a, b, l) = ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, l)

"""
Get the index `i` and first byte `c` of the field value for `key` in an Object.
"""
function get_ic(o::JSON.Object, key::AbstractString, default)

    key1 = getc(key, 1)                           # Extract 1st byte of key.
    keyp = pointer(key, 2)                        # Cache pointer to remainder
    keyl = sizeof(key)                            # of key and length of key.

    s = o.s                                       # Skip from "begin" byte '{'
    i, c = skip_noise(s, o.i + 1)                 # to first field name byte.

    while c != '}'
        last_i, has_escape = scan_string(s, i)    # Find end of field name and
        if keyl == 0                              # compare to `key.
            foundkey = last_i == i + 1
        elseif has_escape
            foundkey = key == JSON.String(s, i)           # {"key": ...}
        else                                              #  ^   ^
            foundkey = last_i == i + 1 + keyl &&          #  i   last_i
                       key1 == getc(s, i + 1) &&
                       (keyl == 1 || memcmp(pointer(s, i+2), keyp, keyl-1) == 0)
        end

        i, c = skip_noise(s, last_i + 1)          # Skip ':' and whitespace.

        if foundkey                               # If the key matched, return
            return i, c                           # index of first value byte.
        end

        i = lastindex_of_value(s, i, c)           # Skip over the value and the
        i, c = skip_noise(s, i + 1)               # ',' and whitespace.
    end

    return default
end



# JSON Key Path Search

"""
Find the value at a specified key `path` in a JSON text.
 - `s`, a JSON text
 - `path`, A vector of Ints and Strings representing JSON Array indexes and
           JSON Object field names.
 - `i`, start index
 - `c`, byte at index `i`
"""
function getpath(s, path, i::Int, c::UInt8=getc(s, i))

    v = getvalue(s, i, c)

    for key in path
        if v isa JSON.Array && key isa Integer
            i, c = getindex_ic(v, key)
        elseif v isa JSON.Object && key isa AbstractString
            i, c = get_ic(v, key, (0, 0x00))
            if i == 0
                throw(KeyError(key))
            end
        else
            throw(KeyError(key))
        end
        v = getvalue(s, i, c)
    end
    return v
end

getpath(j::JSON.Collection, path) = getpath(j.s, path, j.i)



# JSON Token Scanner

"""
Find last index of a value or collection begin/end token end in a JSON text.
 - `s`, a JSON text
 - `i`, token start index
 - `c`, byte at index `i`
"""
function lastindex_of_token(s, i, c)::Int

        if c == '{' ||
           c == '}' ||
           c == '[' ||
           c == ']' ||
           c == 0x00                    i
    elseif c == '"'                     lastindex_of_string(s, i)
    elseif isnum(c)                     lastindex_of_number(s, i)
    elseif c == 'f'                     i + 4
    elseif c == 'n'                     i + 3
    elseif c == 't'                     i + 3
    else
        throw(ParseError(s, i, "invalid input"))
    end
end


"""
Find index of last byte of a JSON value.
 - `s`, a JSON text
 - `i`, value start index
 - `c`, byte at index `i`
"""
function lastindex_of_value(s, i, c=getc(s, i))::Int
    if c == '{' || c == '['
        lastindex_of_collection(s, i, c)
    else
        lastindex_of_token(s, i, c)
    end
end


"""
Find index of last byte of a JSON Collection.
"""
function lastindex_of_collection(s, i, c)::Int

    nest = 1

    while nest > 0
        i, c = skip_noise(s, i + 1)
        if isbegin(c)
            nest += 1
        elseif isend(c)
            nest -= 1
        end
        i = lastindex_of_token(s, i, c)
    end

    return i
end


"""
Find index of last byte of a JSON String.
"""
function lastindex_of_string(s, i)::Int
    i, has_escape = scan_string(s, i)
    return i
end


"""
Find index of last byte of a JSON String
and check for existence of the escape character.

https://tools.ietf.org/html/rfc7159#section-7

    string = quotation-mark *char quotation-mark
    char = unescaped / escape ( ... )
"""
function scan_string(s, i)

    i, c = next_ic(s, i)

    has_escape = false
    while !isnull(c) && c != '"'
        escape = c == '\\'
        i, c = next_ic(s, i)
        if escape && !isnull(c)
            has_escape = true
            i, c = next_ic(s, i)
        end
    end

    return i, has_escape
end


"""
Find index of last byte of a JSON Number.
"""
function lastindex_of_number(s, i)::Int

    last = i
    i, c = next_ic(s, i)

    while !isnull(c) && !isnoise(c) && !isend(c)
        last = i
        i, c = next_ic(s, i)
    end

    return last
end


"""
Skip over whitespace in String `s` starting at index `i`.
"""
function skip_whitespace(s, i = 1)
    c = getc(s, i)
    while iswhitespace(c)
        i, c = next_ic(s, i)
    end
    return i, c
end


"""
Skip over non-value characters in String `s` starting at index `i`.
"""
function skip_noise(s, i)
    c = getc(s, i)
    while isnoise(c)
        i, c = next_ic(s, i)
    end
    return i, c
end



# JSON Character Classes

"""
https://tools.ietf.org/html/rfc7159#section-2

    These are the six structural characters:
        begin-array     = ws %x5B ws  ; [ left square bracket
        begin-object    = ws %x7B ws  ; { left curly bracket
        end-array       = ws %x5D ws  ; ] right square bracket
        end-object      = ws %x7D ws  ; } right curly bracket
        name-separator  = ws %x3A ws  ; : colon
        value-separator = ws %x2C ws  ; , comma
"""
isbegin(c) = c == '{' ||
             c == '['

isend(c) = c == '}' ||
           c == ']'

"""
First character of a Start of a JSON Number
https://tools.ietf.org/html/rfc7159#section-6
"""
isnum(c) = c == '-' ||
           c in UInt8('0'):UInt8('9')


"""
https://tools.ietf.org/html/rfc7159#section-2

    Insignificant whitespace is allowed before or after any of the six
    structural characters.

    ws = *(
            %x20 /              ; Space
            %x09 /              ; Horizontal tab
            %x0A /              ; Line feed or New line
            %x0D )              ; Carriage return
"""
iswhitespace(c) = c == ' '  ||
                  c == '\t' ||
                  c == '\r' ||
                  c == '\n'

"""
The tokeniser ignores whitespace and separators between values.
"""
isnoise(c) = c == ',' ||
             c == ':' ||
             iswhitespace(c)




# Byte Wrangling Utilities

"""
`jl_alloc_string` allocates `n + 1` bytes and sets the last byte to `0x00`
https://github.com/JuliaLang/julia/blob/master/src/array.c#L464
"""
isnull(c)  = c == 0x00


"""
Get byte `i` in string `s` without bounds checking.
"""
getc(s, i) = unsafe_load(pointer(s), i)


"""
Increment `i` and get byte `i` in string `s` without bounds checking.
"""
next_ic(s, i) = (i + 1, getc(s, i + 1))


"""
Store byte `c` at index `i` in string `s` without bounds checking.
"""
setc(s, i, c) = (unsafe_store!(pointer(s), c, i); i + 1)


# Allow comparison of UInt8 with Char (e.g. c == '{')
==(a, b) = Base.isequal(a, b)
!=(a, b) = !(a == b)
==(i::T, c::Char) where T <: Integer = Base.isequal(i, T(c))



# Debug Display

function Base.show(io::IO, e::JSON.ParseError)

    s = e.bytes
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



# Interface Protocols

include("AbstractString.jl")
include("Number.jl")
include("AbstractArray.jl")
include("AbstractDict.jl")


end # module
