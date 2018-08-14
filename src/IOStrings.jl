module IOStrings

using Base: @propagate_inbounds


"""
`IOString` is an abstract string that accumulates bytes from an IO stream.

`IOString(::IO)` creates a new `IOString` connected to an `IO` stream.

`pump(::IOString)` reads bytes from the `IO` stream into the string.

`incomplete(::IOString)` is true until the `IO` stream reaches `eof()`.

`pump(::Function, ::IOString)` runs a `Function` until it returns or throws
a recoverable error. When a recoverable error is thrown, more data is read
from the `IO` stream and the `Function` is restarted (the function is assumed
to be idempotent or free of side effects).

`recoverable(e) -> Bool` defines which errors are recoverable.

It the following example, `parse_item` is called repeatedly to parse items
from the string `s` at index `i`. When the parser gets to the end of the string
and throws an error, the `IOString` is pumped to retrieve more data and the
parsing continues.
```
IOString.recoverable(::MyUnexpectedEndOfInput) = true
s = IOString(socket)
i = 1
while !eof(socket)
    i, v = pump(()->MyParser.parse_item(s, i), s)
    println(v)
end
```
"""
struct IOString{T <: IO} <: AbstractString
    io::T
    buf::IOBuffer
end

struct IncompleteError <: Exception
end

const ASCII_ETB = 0x17

function IOString(io::T) where T <: IO
    ios = IOString{T}(io, IOBuffer())
    Base.ensureroom(ios.buf, 1)
    ios.buf.data[1] = ASCII_ETB
    @assert incomplete(ios)
    return ios
end

Base.convert(::Type{Base.String}, s::IOString) =
    unsafe_string(pointer(s), ncodeunits(s))

Base.String(s::IOString) = convert(Base.String, s)

Base.IteratorSize(::Type{IOString}) = Base.SizeUnknown()
Base.ncodeunits(s::IOString) = s.buf.size
Base.codeunit(s::IOString) = UInt8
@propagate_inbounds Base.codeunit(s::IOString, i::Integer) = s.buf.data[i]

Base.checkbounds(s::IOString, I::Union{Integer,AbstractArray}) =
    checkbounds(Bool, s, I) ? nothing :
              incomplete(s) ? throw(IncompleteError()) :
                              throw(BoundsError(s, I))


Base.pointer(s::IOString) = pointer(s.buf.data)
Base.pointer(s::IOString, i) = pointer(s.buf.data, i)

incomplete(s::IOString) = codeunit(s, ncodeunits(s) + 1) == ASCII_ETB

recoverable(e) = false
recoverable(::IncompleteError) = true

@inline function pump(f::Function, s::IOString)
    while true
        try
            return f()
        catch e
            if recoverable(e)
                pump(s)
            else
                rethrow(e)
            end
        end
    end
end

function pump(s::IOString)
    if eof(s.io)
        Base.ensureroom(s.buf, 1)
        s.buf.data[s.buf.size + 1] = 0x00
        @assert !incomplete(s)
    else
        write(s.buf, readavailable(s.io))
        Base.ensureroom(s.buf, 1)
        s.buf.data[s.buf.size + 1] = ASCII_ETB
        @assert incomplete(s)
    end
end

end # module IOString
