# AbstractString interface for JSON.String

"""
Processes escape sequences and return a `Base.Substring`
(without copying where possible).
"""
Base.convert(::Type{SubString}, s::JSON.String) = parse_string(s.s, s.i)[1]

function parse_string(s, i)
    last_i, has_escape = scan_string(s, i)
    if !has_escape
        return SubString(s, next_i(s, i), prevind(s, last_i)), last_i
    else
        return unescape_json_string(s, i, last_i), last_i
    end
end


Base.convert(::Type{Base.String}, s::JSON.String) =
    convert(Base.String, convert(Base.SubString, s))

Base.String(s::JSON.String) = convert(Base.String, s)
Base.SubString(s::JSON.String) = convert(Base.SubString, s)



# Abstract String Interface

Base.IteratorSize(::Type{JSON.String{T}}) where T = Base.SizeUnknown()

Base.ncodeunits(s::JSON.String) = scan_string(s.s, s.i)[1] - s.i - 1

@propagate_inbounds(
Base.isvalid(s::JSON.String, i::Integer) = string_index_isvalid(s.s, s.i + i))


Base.codeunit(s::JSON.String) = codeunit(s.s)

@propagate_inbounds(
Base.codeunit(s::JSON.String, i::Integer) = codeunit(s.s, s.i + i))

@propagate_inbounds(
Base.iterate(s::JSON.String, i::Integer=1) = _iterate(s, i))
@propagate_inbounds(
function _iterate(s::JSON.String, i)
    i, c = json_char(s.s, s.i + i)
    if c == nothing
        return nothing
    end
    return c, i - s.i
end)


# Unescaping JSON Strings

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
               c == 'r'  ? UInt8('\r') :
               c == 't'  ? UInt8('\t') :
               c == 'u'  ? c : 0x00


"""
Lookup tables for hex digits.
"""
hexvalue(c)      = isxdigit(c) ? tryparse(UInt16, "0x$c") : UInt16(0)
const unhex_1    = [hexvalue(c) for c in Char(1):Char(255)]
const unhex_10   = unhex_1 * 0x10
const unhex_100  = unhex_1 * 0x100
const unhex_1000 = unhex_1 * 0x1000


"""
Read 4HEXDIG from a String `s` at byte index `i` + 1.
FIXME more instructions but less memory access might be faster. Need to test.
"""
function unescape_hex4(s, i)
    i, c = next_ic(s, i) ; u  = @inbounds(unhex_1000[c])
    i, c = next_ic(s, i) ; u += @inbounds(unhex_100[c])
    i, c = next_ic(s, i) ; u += @inbounds(unhex_10[c])
    i, c = next_ic(s, i) ; u += @inbounds(unhex_1[c])
    return i, u
end


"""
Unescape bytes of a String `s` up to byte index `l`, starting at byte index `i`.
Return a new String.
"""
function unescape_json_string(s, i, l)

    i, c = next_ic(s, i)

    out = Base.StringVector(l - i)      # Larger than needed because escape
    j = 1                               # characters will be removed.

    while i < l
        if c != '\\'
            @inbounds out[j] = c
            j += 1
        else
            last_i, cp = json_unescape_char(s, i, c, l)
            if i == last_i
                @inbounds out[j] = cp
                j += 1
            else
                i = last_i
                j = setc_utf8(out, j, cp)
            end
        end
        i, c = next_ic(s, i)
    end

    s = Base.String(out)
    return SubString(s, 1, prevind(s, j))
end


"""
Return a `Char` from a JSON string `s` at index `i`.
Unescpe character if needed.
"""
@propagate_inbounds(
function json_char(s, i)::Tuple{Int, Union{Char,Nothing}}

    c = getc(s, i)
    l = ncodeunits(s)

    if c != '\\' || next_i(s, i) > l
        c = s[i]
        if c == '"'
            c = nothing
        end
        return nextind(s, i), c
    end

    i, c = json_unescape_char(s, i, c, l)
    return next_i(s, i), Char(c)
end)


"""
Return the character code for an escaped character in a JSON string `s`
starting at index `i` (the `\\` character).
"""
function json_unescape_char(s, i, c, l)::Tuple{Int, Union{UInt8,UInt16,UInt32}}

    i, c = next_ic(s, i)
    uc = unescape_c(c)
    if uc == 0x00 ||                    # If the character after '\' was not
       uc == 'u' && next_i(s, i, 4) > l # escapable, or if there aren't enough
        return i, UInt8('\\')           # bytes for \uXXXX, leave the \ as is.
    end

    if uc != 'u'                        # Simple single ecaped character.
        return i, uc                    # Return 7-bit character code.
    end

    i, c16 = unescape_hex4(s, i)        # \uXXXX escaped UTF16 codepoint.
    if c16 in 0xd800:0xdbff          && # Check for surrogate pair...
       next_i(s, i, 6) <= l          &&
       getc(s, next_i(s, i)) == '\\' &&
       getc(s, next_i(s, i, 2)) == 'u'

        j = next_i(s, i, 2)
        j, tail = unescape_hex4(s, j)
        if tail in 0xdc00:0xdfff
            c32 = UInt32(c16 - 0xd7f7)  # Recombine surrogate pair to produce
            c32 <<= 10                  # 32-bit character code.
            c32 += tail
            return j, c32
        end
    end
    return i, c16                       # Return 16-bit character code.
end


"""
Is `i` the index of the start of an escape sequence in a JSON string `s`?
Yes if s[i] == '\\', unless the escape is escaped itself.
"""
function isescape(s, i)
    if getc(s, i) != '\\'               # Check for the escape character.
        return false
    end
    j = i - 1
    while j > 0 && getc(s, j) == '\\'   # Count the number of preceding escapes.
        j -= 1                          # "foo \\\\\uXXXX"
    end                                 #     ^    ^
    return (i - j) % 2 == 1             #     j    i  -- (i - j)=5 % 2 = 1
end


"""
Is `i` the index of the start of a character sequence in a JSON string `s`?
A valid `i` can point to:
 - a single-byte (7-bit) character;
 - a '\\X' escaped 7-bit character;
 - the start of a multi-byte UTF8 character;
 - the start of a `\\uXXXX` escaped UTF16 character;
"""
function string_index_isvalid(s, i)

# FIXME assumes dense indexes

    c = getc(s, i)

    if (c == '"'  ||
        c == '\\' ||
        c == '/'  ||
        c == 'n'  ||
        c == 'r'  ||
        c == 't'  ||
        c == 'b'  ||
        c == 'f'  ||
        c == 'u') &&                    # Escapable character preceded by
        isescape(s, i - 1)              # escape are not a valid index.

        return false
    end

    if c == '\\' &&                     # \uXXXX sequence is invalid if
       getc(s, i + 1) == 'u' &&         # it is preceded by another \uXXXX
       i > 6 &&                         # sequence ...
       getc(s, i - 5) == 'u' &&
       isescape(s, i - 6)

        _, a = unescape_hex4(s, i - 5)
        _, b = unescape_hex4(s, i + 1)

        if a in 0xd800:0xdbff &&        # ... and if the two form a valid UTF16
           b in 0xdc00:0xdfff           # surrogate pair.

            return false
        end
    end

    if ishexdigit(c)                    # A index pointing to a hex digit is
        j = i                           # invalid if part of a \uXXXX sequence.
        m = max(3, i - 3)
        while (c = getc(s, j); ishexdigit(c)) && j >= m
            j -= 1
        end
        if c == 'u' && isescape(s, j - 1)
           return false
        end
    end

    return isvalid(s, i)
end

ishexdigit(c::UInt8) =
    c in UInt8('0'):UInt8('9') ||
    c in UInt8('A'):UInt8('F') ||
    c in UInt8('a'):UInt8('f')


"""
Write a Unicode chatacter `c` into a String `s` as UTF8 at byte index `i`.
"""
function setc_utf8(s::Vector{UInt8}, i, c)
    bytes = bswap(reinterpret(UInt32, Char(c)))
    while true
        @inbounds s[i] = bytes % UInt8
        i += 1
        bytes >>= 8
        if bytes == 0
            return i
        end
    end
end



# IOString Wrappers

#FIXME
#https://github.com/JuliaLang/julia/commit/1f0c6fa35ab64ad66a5bb413fad474e2c722c290#r27686527
@propagate_inbounds function Base.iterate(s::IOString, i::Int = 1)
    b = codeunit(s, i)
    i > ncodeunits(s) && return nothing
    u = UInt32(b) << 24
    Base.between(b, 0x80, 0xf7) || return reinterpret(Char, u), i+1
    return next_continued(s, i, u)
end

function Base.next_continued(s::IOString, i::Int, u::UInt32)
    u < 0xc0000000 && (i += 1; @goto ret)
    n = ncodeunits(s)
    # first continuation byte
    (i += 1) > n && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 16
    # second continuation byte
    ((i += 1) > n) | (u < 0xe0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b) << 8
    # third continuation byte
    ((i += 1) > n) | (u < 0xf0000000) && @goto ret
    @inbounds b = codeunit(s, i)
    b & 0xc0 == 0x80 || @goto ret
    u |= UInt32(b); i += 1
@label ret
    return reinterpret(Char, u), i
end

#FIXME
#https://github.com/JuliaLang/julia/commit/8de25f5ac6c8a8ef9a8872f2d9aaaee9ddbf6bf7#r27684956
Base.isvalid(s::IOString, i::Integer) = Base._thisind_str(s, i) == i


Base.convert(::Type{SubString}, j::JSON.String{IOString{T}}) where T =
    pump(() -> parse_string(j.s, j.i)[1], j.s)

Base.ncodeunits(j::JSON.String{IOString{T}}) where T =
    pump(() -> scan_string(j.s, j.i)[1] - j.i - 1, j.s)

Base.iterate(j::JSON.String{IOString{T}}, i::Integer=1) where T =
    pump(() -> _iterate(j, i), j.s)
