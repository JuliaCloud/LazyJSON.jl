"""
`string(::JSON.String)` creates a `Base.SubString` without copying.
This is a verbatim substring of the JSON text.
Escape sequences are not processed.
"""

Base.string(s::JSON.String) = SubString(s.bytes.s, s.first, s.last)


"""
`convert(SubString, s::JSON.String)` processes escape sequences and creates
a `Base.Substring` (without copying where possible).

FIXME:
 - At present unescaping is not implemented.
 - Need to do JIT unescaping in `promotejson`, or 
 - Implement AbstractString with lazy inline unescaping.
"""

function Base.convert(::Type{SubString}, s::JSON.String)
    if s.has_escape
        return unescape(s)
    else
        return string(s)
    end
end

function unescape(s::JSON.String)
    # FIXME
    return s
end

Base.convert(::Type{Base.String}, s::JSON.String) = convert(Base.String,
                                                    convert(Base.SubString, s))

Base.String(s::JSON.String) = convert(Base.String, s)
Base.SubString(s::JSON.String) = convert(Base.SubString, s)
