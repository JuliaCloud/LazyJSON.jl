module LazyJSON

const JSON = LazyJSON

const enable_assertions = false



# JSON Value Types
# Represented by a string and a byte index.

struct String{T <: AbstractString} #<: AbstractString
    s::T
    i::Int
end

struct Number{T <: AbstractString} <: Base.Number
    s::T
    i::Int
end

struct Object{T <: AbstractString} #<: AbstractDict{AbstractString, Any}
    s::T
    i::Int
end

struct Array{T <: AbstractString}  #<: AbstractArray{Any, 1}
    s::T
    i::Int
end

const Value = Union{JSON.String, JSON.Number, JSON.Object, JSON.Array}
const Collection = Union{JSON.Object, JSON.Array}

struct ParseError <: Exception
    bytes::Base.String
    index::Int
    message::Base.String
end


"""
Verbatim JSON text of a `JSON.Value`
"""
Base.string(s::JSON.Value) = SubString(s.s, s.i, lastindex_of_value(s.s, s.i))


promotejson(x; kw...) = x
promotejson(n::JSON.Number) = convert(Base.Number, n)
promotejson(s::JSON.String) = convert(AbstractString, s)
promotejson(a::JSON.Array)  = convert(Vector, a)
promotejson(o::JSON.Object) = convert(Dict, o)

rpromotejson(x) = promotejson(x)
rpromotejson(a::JSON.Array) = [rpromotejson(x) for x in a]
rpromotejson(o::JSON.Object) = [rpromotejson(k) => rpromotejson(v)
                                for (k,v) in o]



# Get Typed JSON Value

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

getvalue(s) = getvalue(s, skip_whitespace(s)...)

parse(s) = getvalue(s)


# JSON Object/Array Iterator

struct Indexes{T}
    j::T
end

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


Base.IteratorSize(::Type{Indexes{T}}) where T = Base.SizeUnknown()
Base.IteratorEltype(::Type{Indexes{T}}) where T = Base.EltypeUnknown()



# JSON Array Lookup

function getindex_ic(a::JSON.Array, n::Int)
    for (i, c) in indexes(a)
        if c == ']'
           throw(BoundsError(a, n))
        end
        if n == 1
            return i, c
        end
        n -= 1
    end
end



# JSON Object Field Name Lookup

memcmp(a, b, l) = ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, l)

function keycmp(keyp, keyl, s, l, i)
    last = i + keyl + 1
    return last < l &&
           getc(s, last) == '"' &&
           memcmp(pointer(s, i + 1), keyp, keyl) == 0
#= FIXME
 - compare up to first escape sequence?
 - compare function that transparently evaluates escapes?
=#
end


function get_ic(o::JSON.Object, key::AbstractString, default)

    keyp = pointer(key)
    keyl = sizeof(key)
    s = o.s
    l = sizeof(s)
    foundkey = false
    count = 1

    for (i, c) in indexes(o)
        if count % 2 == 1
            foundkey = keycmp(keyp, keyl, s, l, i)
        elseif foundkey
            return i, c
        end
        count += 1
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

getpath(s, path) = getpath(s, path, skip_whitespace(s)...)



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

Base.show(io::IO, j::Union{JSON.String, JSON.Number}) =
    show(io, promotejson(j))

const showmax = 1000

function Base.show(io::IO, j::JSON.Collection)
    s = string(j)
    if length(s) > showmax
        print(io, typeof(j), ": ", SubString(s, 1, showmax), " ...")
    else
        print(io, typeof(j), ": ", s)
    end
end


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



include("AbstractString.jl")
include("Number.jl")
include("AbstractArray.jl")
include("AbstractDict.jl")



end # module
