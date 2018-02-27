module LazyJSON

module JSONjl
    using JSON
end

using DataStructures: OrderedDict
using Base: @propagate_inbounds

const JSON = LazyJSON

const enable_getproperty = true

include("SplicedStrings.jl")            ; using .SplicedStrings: SplicedString
include("PropertyDicts.jl")             ; using .PropertyDicts: PropertyDict
include("IOStrings.jl")                 ; using .IOStrings: IOString, pump


@static if enable_getproperty
    wrap_object(o) = PropertyDict(o)
else
    wrap_object(o) = o
end


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

struct Number{T <: AbstractString} <: Base.Real
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


"""
JSON text representation of `x`
"""
jsonstring(d::PropertyDict) = jsonstring(PropertyDicts.unwrap(d))
jsonstring(x::JSON.Value) = string(x)
jsonstring(x) = JSONjl.JSON.json(x)


"""
Replace value `v` with `x`.
"""
splice(j::JSON.Value, v::JSON.Value, x) = value(splice(j.s, v.i, x, j.i))

splice(j::JSON.Value, path::Vector, x) =
    value(splice(j.s, getpath(j.s, path, j.i)[1], x, j.i))

splice(s::AbstractString, path::Vector, x) = splice(s, getpath(s, path)[1], x)

splice(s::AbstractString, i::Int, x, start_i = 1) =
    SplicedString(SubString(s, start_i, prevind(s, i)),
                  jsonstring(x),
                  SubString(s, next_i(s, lastindex_of_value(s, i))))

splice(d::PropertyDict, v::PropertyDict, x) = splice(PropertyDicts.unwrap(d),
                                                     PropertyDicts.unwrap(v), x)
splice(d::PropertyDict, v, x) = splice(PropertyDicts.unwrap(d), v, x)


# Get Typed JSON Value

const SupportedString = Union{IOString,
                              SplicedString,
                              Base.String}

"""
    value(jsontext) -> JSON.Value
    JSON.Value <: Union{Number, AbstractString, AbstractVector, AbstractDict}

Create a `JSON.Value` object from a JSON text.
"""
function value(s::SupportedString, path=nothing, i = 1; lazy=true)

    # Check that the string has a C-style termination characer.
    @assert (c = getc(s, ncodeunits(s) + 1); c == 0x00 || c == IOStrings.ASCII_ETB)

    i, c = skip_whitespace(s, i)
    if path != nothing
        i, c = getpath(s, path, i, c)
    end
    v = getvalue(s, i, c)
    return lazy ? v : flatten(v)
end

struct ParseError <: Exception
    bytes::Base.String
    index::Int
    c::UInt8
    message::Base.String
end

value(ss::SubString{<:SupportedString}, path=nothing; kw...) =
    value(ss.string, path, 1 + ss.offset; kw...)

value(bytes, path=nothing; kw...) = value(Base.String(bytes), path; kw...)

function value(io::IO, path=nothing; kw...)
    s = IOString(io)
    return pump(() -> value(s, path; kw...), s)
end

IOStrings.recoverable(e::JSON.ParseError) = e.c == IOStrings.ASCII_ETB

Base.string(j::Union{JSON.String{T},
                     JSON.Number{T},
                     JSON.Object{T},
                     JSON.Array{T}}) where T <: IOString =
    pump(() -> SubString(j.s, j.i, lastindex_of_value(j.s, j.i)), j.s)


"""
Get a JSON value object for a value in a JSON text.
 - `s`, the JSON text.
 - `i`, byte index of the value in JSON text.
 - `c`, first byte of the value.
"""
function getvalue(s, i, c=getc(s, i))
        if c == '{'                     wrap_object(JSON.Object(s, i))
    elseif c == '['                     JSON.Array(s, i)
    elseif c == '"'                     JSON.String(s, i)
    elseif isnum(c)                     JSON.Number(s, i)
    elseif c == 'f'                     false
    elseif c == 'n'                     nothing
    elseif c == 't'                     true
    else
        throw(JSON.ParseError(s, i, c, "invalid value index"))
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
    elseif c == 'f'                     false, next_i(s, i, 4)
    elseif c == 'n'                     nothing, next_i(s, i, 3)
    elseif c == 't'                     true, next_i(s, i, 3)
    else
        throw(JSON.ParseError(s, i, c, "invalid value index"))
    end
end

flatten(v) = v
flatten(v::PropertyDict) = flatten(PropertyDicts.unwrap(v))
flatten(v::Value) = getflat(v.s, v.i)[1]


function flat_object(s, i)
    o = OrderedDict{SubString{Base.String},Any}()
    i, c = skip_noise(s, i)
    while c != '}'
        k, i = parse_string(s, i)
        i, c = skip_noise(s, i)
        v, i = getflat(s, i, c)
        o[k] = v
        i, c = skip_noise(s, i)
    end
    return o, i
end

function flat_array(s, i)
    a = Any[]
    i, c = skip_noise(s, i)
    while c != ']'
        v, i = getflat(s, i, c)
        push!(a, v)
        i, c = skip_noise(s, i)
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
    i, c = skip_noise(j.s, i)
    if c == IOStrings.ASCII_ETB
        throw(JSON.ParseError(j.s, i, c, "input incomplete"))
    end
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
function get_ic(o::JSON.Object, key::AbstractString, default, start::Int=o.i)

    keyl = sizeof(key)                            # Extract length of key and
    key1 = keyl == 0 ? 0x00 : key1 = getc(key, 1) # first byte of key.

    s = o.s                                       # Skip from "begin" byte '{'
    i, c = skip_noise(s, start)                   # to first field name byte.

    while c != '}'
        last_i, has_escape = scan_string(s, i)    # Find end of field name and
        if keyl == 0                              # compare to `key.
            foundkey = last_i == next_i(s, i)
        elseif has_escape || !applicable(pointer, o.s)
            foundkey = key == JSON.String(s, i)
        elseif key1 != next_c(s, i) ||            # {"key": ...}
               last_i != next_i(s, i, 1 + keyl)   #  ^   ^
            foundkey = false                      #  i   last_i
        else
            foundkey = memcmp(pointer(s, i+1),
                              pointer(key), keyl) == 0
        end

        i, c = skip_noise(s, last_i)              # Skip ':' and whitespace.

        if foundkey                               # If the key matched, return
            return i, c                           # index of first value byte.
        end

        i = lastindex_of_value(s, i, c)           # Skip over the value and the
        i, c = skip_noise(s, i)                   # ',' and whitespace.
    end

    if start != o.i
        return get_ic(o, key, default, o.i)
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
function getpath(s, path, i::Int=1, c::UInt8=getc(s, i))

    i, c = skip_whitespace(s, i, c)

    for key in path
        if c == '[' && key isa Integer
            i, c = getindex_ic(JSON.Array(s, i), key)
        elseif c == '{' && key isa AbstractString
            i, c = get_ic(JSON.Object(s, i), key, (0, 0x00))
            if i == 0
                throw(KeyError(key))
            end
        else
            throw(KeyError(key))
        end
    end
    return i, c
end



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
    elseif c == 'f'                     next_i(s, i, 4)
    elseif c == 'n'                     next_i(s, i, 3)
    elseif c == 't'                     next_i(s, i, 3)
    else
        throw(JSON.ParseError(s, i, c, "invalid input"))
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
        i, c = skip_noise(s, i)
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
    while c != '"'
        if isnull(c) || c == IOStrings.ASCII_ETB
            throw(JSON.ParseError(s, i, c, "input incomplete"))
        end
        escape = c == '\\'
        i, c = next_ic(s, i)
        if escape && !(isnull(c) || c == IOStrings.ASCII_ETB)
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
        if c == IOStrings.ASCII_ETB
            throw(JSON.ParseError(s, i, c, "input incomplete"))
        end
        last = i
        i, c = next_ic(s, i)
    end

    return last
end


"""
Skip over whitespace in String `s` starting at index `i`.
"""
function skip_whitespace(s, i, c = getc(s, i))
    while iswhitespace(c)
        i, c = next_ic(s, i)
    end
    return i, c
end


"""
Skip over non-value characters in String `s` starting at index `i` + 1.
"""
function skip_noise(s, i)
    i, c = next_ic(s, i)
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
isnull(c) = c == 0x00


"""
Get byte `i` in string `s` without bounds checking.
"""
@generated function getc(s, i)
    if hasmethod(pointer, (s,))
        :(unsafe_load(pointer(s), i))
    else
        :(i > ncodeunits(s) ? 0x00 : @inbounds codeunit(s, i))
    end
end

#getc(s, i) = @inbounds codeunit(s, i)
# FIXME this causes Pkg.test("LazyJSON") to fail becuase the --check-bounds
#       option is passed to the test process.


"""
Increment `i` and get byte `i` in string `s` without bounds checking.
"""
next_ic(s, i) = (i = next_i(s, i); (i, getc(s, i)))
next_c(s, i) = getc(s, next_i(s, i))
next_i(s, i) = i + 1
next_i(s, i, n) = i + n

next_ic(s::SplicedString, i) = SplicedStrings.nextcodeunit(s, i)
next_i(s::SplicedString, i) = SplicedStrings.nextcodeunitindex(s, i)

const Unsafe = Union{SplicedString}
#next_i(s::Unsafe, i) = @inbounds nextind(s, i)
next_i(s::Unsafe, i, n) = @inbounds nextind(s, i, n) # FIXME byte index?


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
    col_number = min(length(s), e.index) - l + 1
    c = escape_string(string(Char(e.c)))
    print(io, "JSON.ParseError: ", e.message,
              " at line ", line_number, ", col ", col_number, ": '", c, "'\n",
              SubString(s, max(1, l), r), "\n",
              lpad("", col_number - 1, " "), "^")
end



# Interface Protocols

include("AbstractString.jl")
include("Number.jl")
include("AbstractArray.jl")
include("AbstractDict.jl")


end # module
