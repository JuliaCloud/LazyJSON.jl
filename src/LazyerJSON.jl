module LazyerJSON

const JSON = LazyerJSON

import ..ParseError


# JSON Value Types
# Represented by a string and a byte index.

struct String{T <: AbstractString}
    s::T
    i::Int 
end

struct Number{T <: AbstractString}
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

value_string(s, i) = SubString(s, i, lastindex_of_value(s, i))

Base.string(s::JSON.Value) = value_string(s.s, s.i)

function Base.string(s::JSON.String)
    s, i = s.s, s.i
    last_i, has_escape = scan_string(s, i)
    if !has_escape
        return SubString(s, i+1, last_i-1)
    else
        return unescape_string!(s, i+1, last_i-1)
    end
end



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



# JSON Object/Array Iterator

Base.start(j::JSON.Collection) = (j.i, 0x00)

Base.done(j::JSON.Collection, (i, c)) = (c == ']' || c == '}')

function Base.next(j::JSON.Collection, (i, c))
    if i > j.i
        i = lastindex_of_value(j.s, i, c)
    end
    i, c = skip_noise(j.s, i + 1)
    return (i, c), (i, c)
end

Base.IteratorSize(::Type{JSON.Object{T}}) where T = Base.SizeUnknown()
Base.IteratorSize(::Type{JSON.Array{T}}) where T = Base.SizeUnknown()



# JSON Array Lookup

function getindex_ic(a::JSON.Array, n::Int)
    for (i, c) in a
        if c == ']'
           throw(BoundsError(a, n))
        end
        if n == 1
            return i, c
        end
        n -= 1
    end 
end

Base.getindex(a::JSON.Array, i) = getvalue(a.s, getindex_ic(a, i)...)



# JSON Object Field Name Lookup

memcmp(a, b, l) = ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, l)

function keycmp(keyp, keyl, s, l, i)
    last = i + keyl + 1
    vs = value_string(s, i)
    return last < l &&
           getc(s, last) == '"' &&
           memcmp(pointer(s, i + 1), keyp, keyl) == 0
end


function get_ic(o::JSON.Object, key::AbstractString, default)

    keyp = pointer(key)
    keyl = sizeof(key)
    s = o.s
    l = sizeof(s)
    foundkey = false
    count = 1

    for (i, c) in o
        if count % 2 == 1
            foundkey = keycmp(keyp, keyl, s, l, i)
        elseif foundkey
            return i, c
        end
        count += 1
    end
    return default
end

function Base.get(o::JSON.Object, key, default)
    i, c = get_ic(o, key, (0, 0x00))
    if i == 0
        return default
    end
    return getvalue(o.s, i, c)
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


function unescape_string!(s, l, i)

    out = Base.String(Vector{UInt8}(uninitialized, l - i))
    j = 1 

    c = getc(s, i)

    utf16 = 0x0000

    while i <= l
        if c == '\\' && i + 1 <= l
            i, c = next_ic(s, i)
            uc = unescape_c(c)
            if uc == 0x00 || uc == 'u' && i + 4 > l
                j = setc(out, j, UInt8('\\'))
            elseif uc != 'u'
                c = uc
            else
                i, c16 = unescape_hex4(s, i)
                if utf16 != 0x0000
                    c32 = UInt32(utf16 - 0xd7f7) << 10 + c16
                    j = setc_utf8(out, j, c32)
                    utf16 = 0x0000
                elseif (c16 & 0xf800) == 0xd800
                    utf16 = c16
                else
                    j = setc_utf8(out, j, c16)
                end
                i, c = next_ic(s, i)
                continue
            end
        end
        if utf16 != 0x0000
            j = setc_utf8(out, j, utf16)
            utf16 = 0x0000
        end
        j = setc(out, j, c)
        i, c = next_ic(s, i)
    end
    setc(out, j, 0x00)

    return SubString(out, 1, prevind(out, j))
end


function setc_utf8(s, i, u)
    bytes = bswap(reinterpret(UInt32, Char(u)))
    while bytes != 0
        setc(s, i, bytes % UInt8)
        i += 1
        bytes >>= 8
    end
    return i
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


"""
https://tools.ietf.org/html/rfc7159#section-7

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
"""
unescape_c(c) = c == '"'  ? c :
               c == '\\' ? c :
               c == '/'  ? c :
               c == 'b'  ? UInt8('\b') :
               c == 'f'  ? UInt8('\f') :
               c == 'n'  ? UInt8('\n') :
               c == 'r'  ? UInt8('\f') :
               c == 't'  ? UInt8('\t') :
               c == 'u'  ? c : 0x00


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


"""
Lookup tables for hex digits.
"""
hexstring(c) = tryparse(UInt16, "0x$c")
const unhex_1 = [isxdigit(c) ? hexstring(c) : UInt16(0) for c in Char(1):Char(255)]
const unhex_10 = unhex_1 * 0x10
const unhex_100 = unhex_10 * 0x10
const unhex_1000 = unhex_100 * 0x10

function unescape_hex4(s, i)
    i, c = next_ic(s, i) ; u  = @inbounds(unhex_1000[c])
    i, c = next_ic(s, i) ; u += @inbounds(unhex_100[c])
    i, c = next_ic(s, i) ; u += @inbounds(unhex_10[c])
    i, c = next_ic(s, i) ; u += @inbounds(unhex_1[c])
    return i, u
end


# Debug Display

Base.show(io::IO, j::Union{JSON.String, JSON.Number}) = show(io, string(j))

const showmax = 1000

function Base.show(io::IO, j::JSON.Collection)
    s = string(j)
    if length(s) > showmax
        print(io, typeof(j), ": ", SubString(s, 1, showmax), " ...")
    else
        print(io, typeof(j), ": ", s)
    end
end



end # module
