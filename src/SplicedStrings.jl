module SplicedStrings

export SplicedString


struct SplicedString <: AbstractString
    v::Vector{SubString}
    SplicedString(v::Vector{SubString{S}}) where S = new(v)
end

SplicedString(s::SplicedString) = s
SplicedString(a) = SplicedString(splice_vector(a))
SplicedString(a...) = SplicedString(splice_vector(a))

splice_vector(s::SplicedString) = s.v
splice_vector(s::AbstractString) = splice_item(s)
splice_vector(s) = mapreduce(splice_item, vcat, s)

splice_item(i::SplicedString) = i.v
splice_item(i::SubString) = [i]
splice_item(i) = [SubString(string(i))]


#https://github.com/JuliaLang/julia/issues/26200
Base.promote_rule(::Type{<:AbstractString},
                  ::Type{<:AbstractString}) = AbstractString

#https://github.com/JuliaLang/julia/issues/26202
Base.nextind(s::SubString{SplicedString}, i::Int) = nextind(s.string, i)
Base.prevind(s::SubString{SplicedString}, i::Int) = prevind(s.string, i)

function convert(::Type{String}, ss::SplicedString)
    buf = IOBuffer()
    for i in ss.v
        write(buf, i)
    end
    return String(take!(buf))
end

Base.String(ss::SplicedString) =  convert(String, ss)



# Indexing Implementation

"""
64-bit SplicedString index: [24 bit fragment number][40 bit fragment index]
"""
const fragment_bits = 40
const index_mask = 2 ^ fragment_bits - 1
const fragment_mask = ~index_mask

fragment_si(s::SplicedString, i) = (s.v[i >> fragment_bits + 1], i & index_mask)

function fragment(s::SplicedString, i)
    n = i >> fragment_bits + 1
    f = s.v[n]
    i = i & index_mask
    return f, n, i
end



# Modification Interface

Base.append!(ss::SplicedString, s) = append!(s, SubString(s))
Base.append!(ss::SplicedString, s::SubString) = push!(ss.v, s)

Base.splice!(s::SplicedString, i::UnitRange, x) =
    splice!(s, i.start, i.stop, x)



# Modification Implementation

function Base.splice!(s::SplicedString, i::Int, j::Int, x)

    i_f, i_n, i_i = fragment(s, i)          # Exctract fragment SubString,
    j_f, j_n, j_i = fragment(s, j)          # number and index.

                  isvalid(i_f, i_i)      || throw(ArgumentError("invalid `i`"))
    j == i - 1 || isvalid(s.v[j_n], j_i) || throw(ArgumentError("invalid `j`"))


    if i_i > 1                             
        i_i = prevind(i_f, i_i)             # Extract head of fragment
        s.v[i_n] = SubString(i_f, 1, i_i)   # at the start of the splice.
        i_n += 1
    end    

    if j_i > 0 
        j_i = nextind(j_f, j_i)             # Extract tail of fragment
        if isvalid(j_f, j_i)                # at the end of the splice.
            s.v[j_n] = SubString(j_f, j_i)
        else                                # If the enitre tail is replaced
            j_n += 1                        # skip to the next fragment.
        end
    end

    v = splice_vector(x)
    @assert all(i -> i isa SubString, v)    # No nested SplicedStrings!
    @assert !any(i -> i isa
            SubString{SplicedString}, v)

    splice!(s.v, i_n:j_n-1, v)              # Splice the new fragments into `s`.
end



# AbstractString Interface

Base.codeunit(s::SplicedString) = UInt8

Base.codeunit(s::SplicedString, i::Int) = codeunit(fragment_si(s, i)...)

Base.ncodeunits(s::SplicedString) = ((length(s.v) - 1) << fragment_bits) |
                                    ncodeunits(last(s.v))

Base.length(s::SplicedString) = sum(length, s.v)

Base.isvalid(s::SplicedString, i::Int) = isvalid(fragment_si(s, i)...)


function Base.next(s::SplicedString, i::Integer)
    fs, fi = fragment_si(s, i)
    c, fi = next(fs, fi)
    l = ncodeunits(fs)
    if fi <= l
        i = i & fragment_mask | fi
    else
        i = nextind(s, i)
    end
    return c, i
end

                                                        
function Base.nextind(s::SplicedString, i::Int)
    fs, fi = fragment_si(s, i)
    if fi == 0
        return i | 1
    end
    fi = nextind(fs, fi)
    l = ncodeunits(fs)
    if fi > l
        n = i >> fragment_bits + 1
        if n < length(s.v)
            return n << fragment_bits | 1
        end
    end
    return i & fragment_mask | fi
end

Base.thisind(s::SplicedString, i::Int) = i & fragment_mask |
                                         thisind(fragment_si(s, i)...)

function Base.prevind(s::SplicedString, i::Int)
    fs, fi = fragment_si(s, i)
    fi = prevind(fs, fi)
    if fi == 0
        n = (i >> fragment_bits)
        if n == 0
            return 0
        else
            n -= 1
            return n << fragment_bits | lastindex(s.v[n+1])
        end
    end
    return i & fragment_mask | fi
end



end # module SplicedString


using Test

using .SplicedStrings

sv = SplicedStrings.splice_vector
SS = SplicedStrings.SplicedString

@test SS("Foo").v == ["Foo"]
@test SS(SubString("Foo")).v == ["Foo"]
@test SS("Foo", "Bar").v == ["Foo", "Bar"]
@test SS(SS("Foo", "Bar")).v == ["Foo", "Bar"]

@test sv(         "Foo"                              ) == ["Foo"]
@test sv(   [     "Foo",       "Bar"                ]) == ["Foo", "Bar"]
@test sv(   (     "Foo",       "Bar"                )) == ["Foo", "Bar"]
@test sv(     SS(["Foo",       "Bar"])               ) == ["Foo", "Bar"]
@test sv(   [ SS(["Foo"]), SS(["Bar"])              ]) == ["Foo", "Bar"]
@test sv(   [ SS( "Foo",       "Bar" ), SS( "Boo" ) ]) == ["Foo", "Bar", "Boo"]
@test sv(   [ SS(["Foo",       "Bar"]), SS( "Boo" ) ]) == ["Foo", "Bar", "Boo"]
@test sv(   [ SS(["Foo",       "Bar"]), SS(["Boo"]) ]) == ["Foo", "Bar", "Boo"]
@test sv(   [ SS(["Foo",       "Bar"]),     "Boo"   ]) == ["Foo", "Bar", "Boo"]
@test sv(   [     "Foo",   SS(["Bar",       "Boo"]) ]) == ["Foo", "Bar", "Boo"]

@test SS(         "Foo"                              ) == "Foo"
@test SS(   [     "Foo"                             ]) == "Foo"
@test SS(         "Foo",       "Bar"                 ) == "FooBar"
@test SS(   [     "Foo",       "Bar"                ]) == "FooBar"
@test SS(     SS(["Foo",       "Bar"])               ) == "FooBar"
@test SS(   [ SS(["Foo",       "Bar"])              ]) == "FooBar"
@test SS(     SS(["Foo"]), SS(["Bar"])               ) == "FooBar"
@test SS(   [ SS(["Foo"]), SS(["Bar"])              ]) == "FooBar"
@test SS(     SS(["Foo",       "Bar"]), SS(["Boo"])  ) == "FooBarBoo"
@test SS(         "Foo",       "Bar",       "Boo"    ) == "FooBarBoo"
@test SS(     SS(["Foo",       "Bar"]),     "Boo"    ) == "FooBarBoo"
@test SS(   [ SS(["Foo",       "Bar"]),     "Boo"   ]) == "FooBarBoo"
@test SS(         "Foo",   SS(["Bar",       "Boo"])  ) == "FooBarBoo"
@test SS(   [     "Foo",   SS(["Bar",       "Boo"]) ]) == "FooBarBoo"
@test SS(   [     "Foo",   SS(["Bar",       "Boo"]) ]) == "FooBarBoo"


# Simple insert 
ss = SS("Foo", "Bar")
splice!(ss, 1 << 40 | 1, 1 << 40 | 0, "d")
@test ss == "FoodBar"
@test ss.v == ["Foo", "d", "Bar"]

# Replace fragment prefix
ss = SS("Foo", "Bar")
splice!(ss, 1 << 40 | 1, 1 << 40 | 1, "Be")
@test ss == "FooBear"
@test ss.v == ["Foo", "Be", "ar"]

# Replace whole fragment
splice!(ss, 1 << 40 | 1, 1 << 40 | 2, "C")
@test ss == "FooCar"
@test ss.v == ["Foo", "C", "ar"]

# Replace two whole fragments
ss = SS("Foo", "XXX", "YYY", "Bar")
splice!(ss, 1 << 40 | 1, 2 << 40 | 3, "_")
@test ss == "Foo_Bar"
@test ss.v == ["Foo", "_", "Bar"]

# Replace three whole fragments
ss = SS("Foo", "XXX", "YYY", "Bar")
splice!(ss, 1 << 40 | 1, 3 << 40 | 3, "_")
@test ss == "Foo_"
@test ss.v == ["Foo", "_"]

# Replace all fragments
ss = SS("Foo", "XXX", "YYY", "Bar")
splice!(ss, 1 : 3 << 40 | 3, "_")
@test ss == "_"
@test ss.v == ["_"]

# Replace all fragments with nothing
ss = SS("Foo", "XXX", "YYY", "Bar")
splice!(ss, 1 , lastindex(ss), "")
@test ss == ""
@test ss.v == [""]

# Replace two whole fragments and part of another
ss = SS("Foo", "XXX", "YYY", "Bar")
splice!(ss, 1 << 40 | 1, 3 << 40 | 2, "u")
@test ss == "Foour"
@test ss.v == ["Foo", "u", "r"]

# Replace fragment suffix
ss = SS("Foo", "Bar")
splice!(ss, 3, 3, "g")
@test ss == "FogBar"
@test ss.v == ["Fo", "g", "Bar"]

# Replace fragment suffix and prefix
ss = SS("Foo", "Bar")
splice!(ss, 3, 1 << 40 | 2, "lde")
@test ss == "Folder"
@test ss.v == ["Fo", "lde", "r"]

# Replace fragment suffix and whole fragment and prefix
ss = SS("Foo", "XXX", "Bar")
splice!(ss, 3, 2 << 40 | 2, "lde")
@test ss == "Folder"
@test ss.v == ["Fo", "lde", "r"]

# Replace fragment suffix and whole fragment and prefix with multiple others
ss = SS("Foo", "XXX", "Bar")
splice!(ss, 2, 2 << 40 | 2, ["w", "oooo", "aaaaaa", "rr"])
@test ss == "Fwooooaaaaaarrr"
@test ss.v == ["F", "w", "oooo", "aaaaaa", "rr", "r"]

ss = SS("Foo", "XXX", "Bar")
splice!(ss, 2, 2 << 40 | 2, SS(SS("w", "oooo"), "aaaaaa", "rr"))
@test ss == "Fwooooaaaaaarrr"
@test ss.v == ["F", "w", "oooo", "aaaaaa", "rr", "r"]

ss = SS("Foo", "XXX", "Bar")
splice!(ss, 2, 2 << 40 | 2, [SS("w", "oooo"), "aaaaaa", SS("rr")])
@test ss == "Fwooooaaaaaarrr"
@test String(ss) == "Fwooooaaaaaarrr"
@test ss.v == ["F", "w", "oooo", "aaaaaa", "rr", "r"]


ss = SplicedString(["Hello", " ", "world", "!"])
@test ss == "Hello world!"
@test String(ss) == "Hello world!"

i = 0 << 40 | 0 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('H')
i = 0 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('e')
i = 0 << 40 | 3 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('l')
i = 0 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('l')
i = 0 << 40 | 5 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1 ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('o')
i = 1 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 2 << 40 | 1 ; @test prevind(ss, i) == 0 << 40 | 5 ; @test codeunit(ss, i) == UInt8(' ')
i = 2 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == 1 << 40 | 1 ; @test codeunit(ss, i) == UInt8('w')
i = 2 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('o')
i = 2 << 40 | 3 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('r')
i = 2 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('l')
i = 2 << 40 | 5 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 3 << 40 | 1 ; @test prevind(ss, i) == i - 1       ; @test codeunit(ss, i) == UInt8('d')
i = 3 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1       ; @test prevind(ss, i) == 2 << 40 | 5 ; @test codeunit(ss, i) == UInt8('!')
i = 3 << 40 | 2 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i)                                       ; @test prevind(ss, i) == i - 1
                  @test ncodeunits(ss) == 3 << 40 | 1
                  @test length(ss) == 12


ss = SplicedString(["\u1234x", "x\u1234"])
@test ss == "ሴxxሴ"

i = 0 << 40 | 0 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 3
i = 0 << 40 | 2 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 2
i = 0 << 40 | 3 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 1 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 3
i = 1 << 40 | 3 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 2
i = 1 << 40 | 4 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 5 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i)
                  @test ncodeunits(ss) == 1 << 40 | 4
                  @test length(ss) == 4


ss = SplicedString(["x\u1234", "\u1234x"])
@test ss == "xሴሴx"

i = 0 << 40 | 0 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 0 << 40 | 2 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 0 << 40 | 3 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 0 << 40 | 4 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == 1 << 40 | 1
i = 1 << 40 | 1 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 3
i = 1 << 40 | 2 ; @test thisind(ss, i) == i - 1 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 2
i = 1 << 40 | 3 ; @test thisind(ss, i) == i - 2 ; @test !isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 4 ; @test thisind(ss, i) == i     ; @test  isvalid(ss, i) ; @test nextind(ss, i) == i + 1
i = 1 << 40 | 5 ; @test thisind(ss, i) == i     ; @test !isvalid(ss, i)
                  @test ncodeunits(ss) == 1 << 40 | 4
                  @test length(ss) == 4


ss = SS("one", "two", "three")
@test 'o' in ss
@test 'n' in ss
@test 'e' in ss
@test 't' in ss
@test 'w' in ss
@test 'o' in ss
@test 'h' in ss
@test 'r' in ss
i = findfirst(equalto('w'), ss)
@test ss[i] == 'w'
