# AbstractString interface methods

"""
Processes escape sequences and return a `Base.Substring`
(without copying where possible).
"""
Base.convert(::Type{SubString}, s::JSON.String) = parse_string(s.s, s.i)[1]

function parse_string(s, i)
    last_i, has_escape = scan_string(s, i)
    if !has_escape
        return SubString(s, i+1, prevind(s, last_i)), last_i
    else
        return unescape_string!(s, i+1, last_i-1), last_i
    end
end


Base.convert(::Type{AbstractString}, s::JSON.String) =
    convert(Base.SubString, s)

Base.convert(::Type{Base.String}, s::JSON.String) =
    convert(Base.String, convert(Base.SubString, s))

Base.String(s::JSON.String) = convert(Base.String, s)
Base.SubString(s::JSON.String) = convert(Base.SubString, s)


Base.IteratorSize(::Type{JSON.String{T}}) where T = Base.SizeUnknown()

Base.ncodeunits(s::JSON.String) = scan_string(s.s, s.i)[1] - s.i - 1

Base.isvalid(s::JSON.String, i::Integer) = string_index_isvalid(s.s, s.i + i)

Base.codeunit(s::JSON.String, i::Integer) = codeunit(s.s, s.i + i)

function Base.next(s::JSON.String, i::Integer)
    i, c = json_char(s.s, s.i + i)
    #println("next(::JSON.String, $i) -> $(Char(c)), $(i - s.i + 1)")
    return c, i - s.i + 1
end


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
Read 4HEXDIG from a String `s` at byte index `i`.
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
function unescape_string!(s, i, l)

    out = Base.String(Vector{UInt8}(uninitialized, l - i))
    j = 1

    local c = getc(s, i)

    while i <= l
        if c != '\\' || i + 1 > l
            j = setc(out, j, c)
        else
            last_i, cp = json_unescape_char(s, i, c, l)
            if i == last_i
                j = setc(out, j, cp)
            else
                i = last_i
                j = setc_utf8(out, j, cp)
            end
        end
        i, c = next_ic(s, i)
    end

    return SubString(out, 1, prevind(out, j))
end

function json_char(s, i, c = getc(s,i), l = sizeof(s))::Tuple{Int, Char}

    if c != '\\' || i + 1 > l
        c = s[i]
        return nextind(s, i) - 1, s[i]
    end

    i, c = json_unescape_char(s, i, c, l)
    return i, Char(c)
end

function json_unescape_char(s, i, c, l)::Tuple{Int, Union{UInt8,UInt16,UInt32}}

    i, c = next_ic(s, i)
    uc = unescape_c(c)
    if uc == 0x00 || uc == 'u' && i + 4 > l
        return i, UInt8('\\')
    end

    if uc != 'u'
        return i, uc
    end

    i, c16 = unescape_hex4(s, i)
    if c16 in 0xd800:0xdbff &&
       i + 6 <= l           &&
       getc(s, i+1) == '\\' &&
       getc(s, i+2) == 'u'

        j, tail = unescape_hex4(s, i+2)
        if tail in 0xdc00:0xdfff
            c32 = UInt32(c16 - 0xd7f7) << 10 + tail
            return j, c32
        end
    end
    return i, c16
end

function isescape(s, i)
    if getc(s, i) != '\\'
        return false
    end
    j = i - 1
    while j > 0 && getc(s, j) == '\\'
        j -= 1   
    end
    return (i - j) % 2 != 0
end

ishexdigit(c::UInt8) = c in UInt8('0'):UInt8('9') ||
                       c in UInt8('A'):UInt8('F') ||
                       c in UInt8('a'):UInt8('f')


function string_index_isvalid(s, i)

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

    if c == '\\' &&                     # \uXXXX sequence is invalid if it
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


"""
Write a Unicode chatacter `c` into a String `s` at byte index `i`.
"""
function setc_utf8(s, i, c)
    bytes = bswap(reinterpret(UInt32, Char(c)))
    while true
        setc(s, i, bytes % UInt8)
        i += 1
        bytes >>= 8
        if bytes == 0
            return i
        end
    end
end
