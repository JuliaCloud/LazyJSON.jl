"""
Processes escape sequences and return a `Base.Substring`
(without copying where possible).
"""
function Base.convert(::Type{SubString}, s::JSON.String)
    s, i = s.s, s.i
    last_i, has_escape = scan_string(s, i)
    if !has_escape
        return SubString(s, i+1, prevind(s, last_i))
    else
        return unescape_string!(s, i+1, last_i-1)
    end
end

Base.convert(::Type{AbstractString}, s::JSON.String) =
    convert(Base.SubString, s)

Base.convert(::Type{Base.String}, s::JSON.String) =
    convert(Base.String, convert(Base.SubString, s))

Base.String(s::JSON.String) = convert(Base.String, s)
Base.SubString(s::JSON.String) = convert(Base.SubString, s)



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
               c == 'r'  ? UInt8('\f') :
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


"""
Write a Unicode chatacter `c` into a String `s` at byte index `i`.
"""
function setc_utf8(s, i, c)
    bytes = bswap(reinterpret(UInt32, Char(c)))
    while bytes != 0
        setc(s, i, bytes % UInt8)
        i += 1
        bytes >>= 8
    end
    return i
end
