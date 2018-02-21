module IOStrings

const ASCII_ETB = 0x17

struct IOString{T <: IO} <: AbstractString
    io::T
    buf::IOBuffer
    etype::Type
end

function IOString(io::T, etype) where T <: IO
    ios = IOString{T}(io, IOBuffer(), etype)
    Base.ensureroom(ios.buf, 1)
    ios.buf.data[1] = ASCII_ETB = 0x17
    @assert incomplete(ios)
    return ios
end

Base.convert(::Type{Base.String}, s::IOString) =
    unsafe_string(pointer(s), ncodeunits(s))

Base.String(s::IOString) = convert(Base.String, s)

Base.IteratorSize(::Type{IOString}) = Base.SizeUnknown()
Base.ncodeunits(s::IOString) = s.buf.size
Base.codeunit(s::IOString) = UInt8
Base.codeunit(s::IOString, i::Integer) = s.buf.data[i]
Base.pointer(s::IOString) = pointer(s.buf.data)
Base.pointer(s::IOString, i) = pointer(s.buf.data, i)

incomplete(s::IOString) = codeunit(s, ncodeunits(s) + 1) == ASCII_ETB

@inline function pump(f::Function, s::IOString)
    while true
        try
            return f()
        catch e
            if e isa s.etype && e.c == ASCII_ETB
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
