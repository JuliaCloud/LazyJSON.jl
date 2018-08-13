using LazyJSON
using Test

const JSON = LazyJSON

@testset "AbstractString" begin

function validmap(s)
    s = String([s...])
    return map(i->JSON.string_index_isvalid(s, i) ? 1 : 0, 1:sizeof(s))
end

s =                  ['\\' '"']
@test validmap(s) == [  1,  0 ]

s =                  [' ' '\\' '"']
@test validmap(s) == [ 1,   1,  0]

s =                  ['\\' '\\' '\\' '\\' '\\' '\\' '\\']
@test validmap(s) == [  1,   0,   1,   0,   1,   0,   1 ]

s =                  ['\\' '\\' 'n' '\\' '\\' '\\' '\\' '\\']
@test validmap(s) == [  1,   0,  1,   1,   0,   1,   0,   1 ]

s =                  ['\\' '\\' '\\' 'n' '\\' '\\' '\\' '\\' '\\']
@test validmap(s) == [  1,   0,   1,  0,   1,   0,   1,   0,   1 ]

s =                  [' ' '\\' '\\' '\\' '\\' '\\' '\\' '\\']
@test validmap(s) == [ 1,   1,   0,   1,   0,   1,   0,   1 ]

s =                  [' ' '\\' '\\' 'n' '\\' '\\' '\\' '\\' '\\']
@test validmap(s) == [ 1,   1,   0,  1,   1,   0,   1,   0,   1 ]

s =                  [' ' '\\' '\\' '\\' 'n' '\\' '\\' '\\' '\\' '\\']
@test validmap(s) == [ 1,   1,   0,   1,  0,   1,   0,   1,   0,   1 ]

s =                  ['\\' '\\' '\\' '/' '\\' 'n' '\\' 'r' '\\' 't']
@test validmap(s) == [ 1,   0,   1,   0,  1,   0,   1,  0,   1,  0 ]

s =                  ['\\' 'b' '\\' 'f' '\\' 'u']
@test validmap(s) == [ 1,   0,   1,  0,   1,  0 ]

s =                  ['\\' 'a' '\\' 'c' '\\' 'd' '\\' 'e' '\\' 'g' '\\' 'h']
@test validmap(s) == [ 1,   1,   1,  1,   1,  1,   1,  1,   1,  1,   1,  1 ]

s =                  [' ' '\\' '\\' '\\' '/' '\\' 'n' '\\' 'r' '\\' 't']
@test validmap(s) == [ 1,   1,   0,   1,   0,  1,   0,   1,  0,   1,  0 ]

s =                  [' ' '\\' 'b' '\\' 'f' '\\' 'u']
@test validmap(s) == [ 1,   1,   0,   1,  0,   1,  0 ]

s =                  [' ' '\\' 'a' '\\' 'c' '\\' 'd' '\\' 'e' '\\' 'g' '\\' 'h']
@test validmap(s) == [ 1,   1,   1,   1,  1,   1,  1,   1,  1,   1,  1,   1,  1 ]


s =                  ['\\' 'u' '1' '2' '3' '4' '!']
@test validmap(s) == [ 1,   0,  0,  0,  0,  0,  1 ]

s =                  ['\\' 'u' '1' '2' '3' '!']
@test validmap(s) == [ 1,   0,  0,  0,  0,  1 ] # FIXME invalid hex ?

s =                  ['\\' 'u' '!' '2' '3' '4']
@test validmap(s) == [ 1,   0,  1,  1,  1,  1 ] # FIXME invalid hex ?

s =                  ['\\' 'u' '1' '2' '3']
@test validmap(s) == [ 1,   0,  0,  0,  0,] # FIXME truncated ?

s =                  [' ' '\\' 'u' 'a' 'b' 'c' 'd' '!']
@test validmap(s) == [ 1,   1,  0,  0,  0,  0,  0,  1 ]

s =                  ['\\' 'u' 'f' 'g' 'h' 'i' '!']
@test validmap(s) == [  1,  0,  0,  1,  1,  1,  1 ] # FIXME invalid hex ?

s =                  ['\\' 'u' 'd' '8' '0' '0' '\\' 'u' 'd' '8' '0' '0']
@test validmap(s) == [  1,  0,  0,  0,  0,  0,   1,  0,  0,  0,  0,  0 ]

s =                  ['\\' 'u' 'd' '8' '0' '0' '\\' 'u' '1' '2' '3' '4']
@test validmap(s) == [  1,  0,  0,  0,  0,  0,   1,  0,  0,  0,  0,  0 ]

s =                  ['\\' 'u' 'd' '8' '0' '1' '\\' 'u' 'd' 'c' '3' '7'] # pair
@test validmap(s) == [  1,  0,  0,  0,  0,  0,   0,  0,  0,  0,  0,  0 ]

s =                  ['\\' 'u' 'd' '8' '0' '0' '\\' '\\' '\\' '\\' 'u' '1' ]
@test validmap(s) == [  1,  0,  0,  0,  0,  0,   1,   0,   1,   0,  1,  1  ]

s =                  ['\\' 'u' 'd' '8' '0' '0' '\\' '\\' '\\' 'u' '1' ]
@test validmap(s) == [  1,  0,  0,  0,  0,  0,   1,   0,   1,  0,  0  ]

s =                  [' ' '\\' '"' ' ' '\u1234' '!' ]
@test validmap(s) == [ 1,   1,  0,  1,  1, 0, 0, 1  ]


j = "\"Hello!\""

js = JSON.String(j, 1)
@test ncodeunits(js) == 6
@test js == "Hello!"

c, i = iterate(js)
@test c == 'H'
@test i == 2
c, i = iterate(js, i)
@test c == 'e'

@test isvalid(js, 1)
@test codeunit(js, 1) == UInt8('H')
@test js[1] == 'H'
@test isvalid(js, 2)
@test codeunit(js, 2) == UInt8('e')
@test js[2] == 'e'

@test [c for c in js] == ['H', 'e', 'l', 'l', 'o', '!']
@test '"' * String([c for c in js]) * '"' == j

js = JSON.String("""{"foo": "Foo\\u1234Bar"}""", 9)
@test convert(SubString, js) == "FooሴBar"
@test ncodeunits(js) == 12
@test codeunit(js, 1) == UInt8('F')
@test js[1] == 'F'
@test isvalid(js, 2)
@test codeunit(js, 2) == UInt8('o')
@test js[2] == 'o'
@test codeunit(js, 3) == UInt8('o')
@test js[3] == 'o'
@test codeunit(js, 4) == UInt16('\\')
@test js[4] == '\u1234'
@test !isvalid(js, 5)

@test String([c for c in js]) == "Foo\u1234Bar"
@test js == "Foo\u1234Bar"
@test String([c for c in js]) == "FooሴBar"
@test js == "FooሴBar"

js = JSON.String("\"\\ud801\\udc37\"", 1)
@test String([c for c in js]) == "𐐷"
@test js == "𐐷"

js = JSON.String("\"\\ud83e\\udd16\"", 1)
@test String([c for c in js]) == "🤖"

js = JSON.String("\"🤖\"", 1)
@test String([c for c in js]) == "🤖"

js = JSON.String("\"$(Char(129302))\"", 1)
@test String([c for c in js]) == "🤖"
@test js == "🤖"


end # testset
