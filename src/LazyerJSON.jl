module LazyerJSON

const JSON = LazyerJSON

import ..ParseError


# Byte Wrangling Utilities

# Allow comparison of UInt8 with Char (e.g. c == '{')
==(a, b) = Base.isequal(a, b)
!=(a, b) = !(a == b)
==(i::T, c::Char) where T <: Integer = Base.isequal(i, T(c))


# Access bytes of string without bounds checking
macro getc(s, i)
    esc(:(unsafe_load(pointer($s), $i)))
end

macro next_ic(s, i, c)
    esc(quote
        $i += 1
        $c = @getc($s, $i)
    end)
end



# JSON Value Types
# Represented by a string and a byte index.

struct String{T}
    s::T
    i::Int 
end

struct Number{T}
    s::T
    i::Int 
end

struct Object{T}
    s::T
    i::Int 
end

struct Array{T}
    s::T
    i::Int 

end

const Collection = Union{JSON.Object, JSON.Array}


Base.string(s::JSON.Collection) = SubString(s.s, s.i)
Base.string(s::JSON.String) = SubString(s.s, s.i, find_end_of_string(s.s, s.i))
Base.string(s::JSON.Number) = SubString(s.s, s.i, find_end_of_number(s.s, s.i))



"""
Get a JSON value object for a value in a JSON text.
 - `i`, byte index of the value in JSON text.
 - `c`, first byte of the value.
"""

function getvalue(s, i, c=@getc(s, i))
        if c == '{'                     JSON.Object(s, i)
    elseif c == '['                     JSON.Array(s, i)
    elseif c == '"'                     JSON.String(s, i)
    elseif isnum(c)                     JSON.Number(s, i)
    elseif c == 'f'                     false
    elseif c == 'n'                     nothing
    elseif c == 't'                     true
    elseif c == ']'                     ;:end_of_array
    elseif c == '}'                     ;:end_of_object
    else
        throw(ParseError(s, i, "invalid value index"))
    end
end



# JSON Object/Array Iterator

Base.start(j::JSON.Collection) = (0, j.i, @getc(j.s, j.i))
Base.done(j::JSON.Collection, (nest, i, c)) = (c == ']' || c == '}')
function Base.next(j::JSON.Collection, (nest, i, c))
    nest, i, c = next_token(j.s, nest, i, c)
    while nest > 1
        nest, i, c = next_token(j.s, nest, i, c)
    end
    return (i, c), (nest, i, c)
end

Base.IteratorSize(::Type{JSON.Object{T}}) where T = Base.SizeUnknown()
Base.IteratorSize(::Type{JSON.Array{T}}) where T = Base.SizeUnknown()



# JSON Array Lookup

function Base.getindex(a::JSON.Array, n::Int)
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



# JSON Object Field Name Lookup

memcmp(a, b, l) = ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, l)

function keycmp(keyp, keyl, s, l, i)
    last = i + keyl + 1
    return last < l &&
           @getc(s, last) == '"' &&
           memcmp(pointer(s, i + 1), keyp, keyl) == 0
end


function Base.get(o::JSON.Object, key::AbstractString, default)

    keyp = pointer(key)
    keyl = sizeof(key)
    l = sizeof(o.s)
    foundkey = false
    count = 1

    for (i, c) in o
        if count % 2 == 1
            foundkey = keycmp(keyp, keyl, o.s, l, i)
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

function getpath(s, path, i::Int, c::UInt8)
    
    v = getvalue(s, i, c)

    for key in path
        if v isa JSON.Array && key isa Integer
            i, c = getindex(v, key)
        elseif v isa JSON.Object && key isa AbstractString
            i, c = get(v, key, :notfound)
        else
            throw(KeyError(key))
        end
        v = getvalue(s, i, c)
    end
    return v
end

getpath(s, path=[]) = getpath(s, path, skip_ws(s)...)

function skip_ws(s, i = 1)
    c = @getc(s, i)
    while isws(c)
        @next_ic(s, i, c)
    end
    return i, c
end



# JSON Token Scanner

"""
Find index of the next value or array/object begin/end in a JSON text.
 - `s`, a JSON text
 - `nest`, array/object nesting count
 - `i`, start index
 - `c`, byte at index `i`

Returns (nest, i, c)
"""

function next_token(s, nest::Int, i::Int, c::UInt8)

    i = if c == '{' || c == '['         nest += 1; i
    elseif c == ']' || c == '}'         nest -= 1; i
    elseif c == '"'                     find_end_of_string(s, i)
    elseif isnum(c)                     find_end_of_number(s, i)
    elseif c == 'f'                     i + 4
    elseif c == 'n'                     i + 3
    elseif c == 't'                     i + 3
    elseif c == 0x00                    i
    else
        throw(ParseError(s, i, "invalid input"))
    end

    @next_ic(s, i, c)
    while (isws(c) || c == ',' || c == ':')
        @next_ic(s, i, c)
    end

    return nest, i, c
end


"""
Find index of last byte of a JSON String.
"""

function find_end_of_string(s, i)::Int

    @next_ic(s, i, c)

    while !isnull(c) && c != '"'
        escape = c == '\\'
        @next_ic(s, i, c)
        if escape && !isnull(c)
            @next_ic(s, i, c)
        end
    end

    return i
end


"""
Find index of last byte of a JSON Number.
"""

function find_end_of_number(s, i)::Int

    last = i
    @next_ic(s, i, c)
    
    while !isnull(c) &&
          !isws(c)   &&
          c != ']'   &&
          c != '}'   &&
          c != ','
        last = i
        @next_ic(s, i, c)
    end

    return last
end


# Check for null terminator.
# jl_alloc_string allocates n + 1 bytes and sets the last byte to 0x00
# https://github.com/JuliaLang/julia/blob/master/src/array.c#L464
isnull(c) = c == 0x00

isws(x) = x == ' '  ||
          x == '\t' ||
          x == '\r' ||
          x == '\n'

isnum(c) = c == '-' ||
           c in UInt8('0'):UInt8('9')



end # module
