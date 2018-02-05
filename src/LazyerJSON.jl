module LazyerJSON

import ..ParseError

# Allow comparison of UInt8 with Char (e.g. c == '{')
==(a, b) = Base.isequal(a, b)
!=(a, b) = !(a == b)
==(i::T, c::Char) where T <: Integer = Base.isequal(i, T(c))
in(a, b) = Base.in(a, b)
in(a::T, b::StepRange{Char,S}) where {S, T <: Integer} =
    Base.in(a, StepRange{T, S}(b))


# Check for null terminator.
# jl_alloc_string allocates n + 1 bytes and sets the last byte to 0x00
# https://github.com/JuliaLang/julia/blob/master/src/array.c#L464
ischar(c) = c != 0x00

isws(x) = x == ' '  ||
          x == '\t' ||
          x == '\r' ||
          x == '\n'

isnum(c) = c == '-' ||
           c in '0':'9'


const LazyIndex = Int32

# Access bytes of string without bounds checking
getc(s, i) = unsafe_load(pointer(s, i))

nexti(i, n=LazyIndex(1)) = i += LazyIndex(n)

nextc(s, i) = (i = nexti(i); (i, getc(s, i)))

function skip_ws(s, i=LazyIndex(1))
    c = getc(s, i)
    while isws(c)
        i, c = nextc(s, i)
    end
    return i, c
end

function skip_delim(s, i)
    c = getc(s, i)
    while (isws(c) || c == ',' || c == ':')
        i, c = nextc(s, i)
    end
    return i, c
end

abstract type LazyerCollection end

const LazyerInput = Union{String,SubString{String}}

struct LazyerString{T}
    s::T
    i::LazyIndex 
end

struct LazyerNumber{T}
    s::T
    i::LazyIndex 
end

struct LazyerObject{T} <: LazyerCollection
    s::T
    i::LazyIndex 
end

struct LazyerArray{T} <: LazyerCollection
    s::T
    i::LazyIndex 
end

Base.string(s::LazyerCollection) = SubString(s.s, s.i)
Base.string(s::LazyerString) = SubString(s.s, s.i, lazyer_string(s.s, s.i))
Base.string(s::LazyerNumber) = SubString(s.s, s.i, lazyer_number(s.s, s.i))

function lazyer_get(s, i, c=getc(s, i))
        if c == '{'                     LazyerObject(s, i)
    elseif c == '['                     LazyerArray(s, i)
    elseif c == '"'                     LazyerString(s, i)
    elseif isnum(c)                     LazyerNumber(s, i)
    elseif c == 'f'                     false
    elseif c == 'n'                     nothing
    elseif c == 't'                     true
    elseif c == ']'                     ;:end_of_array
    elseif c == '}'                     ;:end_of_object
    else
        throw(ParseError(s, i, "invalid value index"))
    end
end


Base.IteratorSize(::Type{LazyerObject{T}}) where T = Base.SizeUnknown()
Base.IteratorSize(::Type{LazyerArray{T}}) where T = Base.SizeUnknown()

Base.start(j::LazyerCollection) = (LazyIndex[], j.i, getc(j.s, j.i))
Base.done(j::LazyerCollection, (k, i, c)) = (c == ']' || c == '}')
function Base.next(j::LazyerCollection, (k, i, c))
    k, i, c = lazyer(j.s, k, i, c)
    while length(k) > 1
        k, i, c = lazyer(j.s, k, i, c)
    end
    return (i, c), (k, i, c)
end


function Base.getindex(a::LazyerArray, n::Int)
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


memcmp(a, b, l) = ccall(:memcmp, Int32, (Ptr{UInt8}, Ptr{UInt8}, UInt), a, b, l)

function keycmp(keyp, keyl, s, l, i)
    last = i + keyl + 1
    return last < l &&
           getc(s, last) == '"' &&
           memcmp(pointer(s, i + 1), keyp, keyl) == 0
end


function Base.get(o::LazyerObject, key::AbstractString, default)

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



lazyer_getpath(s, path=[]) = lazyer_getpath(s, path, skip_ws(s)...)

function lazyer_getpath(s, path, i, c)
    
    v = lazyer_get(s, i, c)

    for key in path
        if v isa LazyerArray && key isa Integer
            i, c = getindex(v, key)
        elseif v isa LazyerObject && key isa AbstractString
            i, c = get(v, key, :notfound)
        else
            throw(KeyError(key))
        end
        v = lazyer_get(s, i, c)
    end
    return v
end

function lazyer(s::LazyerInput, k, i, c)

    i = if c == '{'                     push!(k, i); i
    elseif c == '['                     push!(k, i); i
    elseif isnum(c)                     lazyer_number(s, i)
    elseif c == '"'                     lazyer_string(s, i)
    elseif c == 'f'                     nexti(i, 5)
    elseif c == 'n'                     nexti(i, 4)
    elseif c == 't'                     nexti(i, 4)
    elseif c == ']'                     pop!(k); i
    elseif c == '}'                     pop!(k); i
    elseif c == 0x00                    i
    else
        throw(ParseError(s, i, "invalid input"))
    end

    i, c = skip_delim(s, nexti(i))

    return k, i, c
end


function lazyer_string(s, i)

    i, c = nextc(s, i)

    while ischar(c) && c != '"'
        escape = c == '\\'
        i, c = nextc(s, i)
        if escape && ischar(c)
            i, c = nextc(s, i)
        end
    end

    return i
end


function lazyer_number(s, i)

    j, c = nextc(s, i)
    
    while ischar(c) &&
         !isws(c)   &&
          c != ']'  &&
          c != '}'  &&
          c != ','
        i = j
        j, c = nextc(s, i)
    end

    return i
end



mutable struct Lazyer
    s::String
end


Base.IteratorSize(::Type{Lazyer}) = Base.SizeUnknown()

Base.start(j::Lazyer) = (LazyIndex[], skip_delim(j.s, LazyIndex(1))...)
Base.done(j::Lazyer, (k, i, c)) = !ischar(c)
Base.next(j::Lazyer, (k, i, c)) = ((k, i, c), lazyer(j.s, k, i, c))

end # module
