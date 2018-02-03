using LazyJSON
using Test

module JSON_jl
    using JSON
end

const JSONjl = JSON_jl.JSON

const JSON = LazyJSON

@testset "JSON" begin

"""
https://tools.ietf.org/html/rfc7159#section-13
"""

rfc_example = """
    {
        "Image": {
            "Width":  800,
            "Height": 600,
            "Title":  "View from 15th Floor",
            "Thumbnail": {
                "Url":    "http://www.example.com/image/481989943",
                "Height": 125,
                "Width":  100
            },
            "Animated" : false,
            "IDs": [116, 943, 234, 38793]
        }
    }
"""


#-------------------------------------------------------------------------------
@testset "RFC7159 example" begin
#-------------------------------------------------------------------------------

if JSON.wait_after_each_value

v = JSON.parse(rfc_example)

@test v isa JSON.Object
@test !v.iscomplete
@test length(v.v) == 0

x = v["Image"]["Width"]
@test x == 800
@test !v.iscomplete
@test convert(String, v.v[1]) == "Image"
@test convert(SubString, v.v[2].v[1]) == "Width"
@test string(v.v[2].v[2]) == "800"
@test length(v.v) == 2
@test length(v.v[2].v) == 2
@test typeof(x) == JSON.Number
@test x.bytes.s[x.first:x.last] == "800"

@test !v.iscomplete
@test !v["Image"].iscomplete

x = v["Image"]["Thumbnail"]["Url"]

# JSON.String does not yet implement AbstractString
@test_broken x == "http://www.example.com/image/481989943"

@test SubString(x) == "http://www.example.com/image/481989943"
@test !v.iscomplete
@test !v["Image"]["Thumbnail"].iscomplete
@test length(v["Image"].v) == 8
@test v["Image"]["Animated"] === false
@test v["Image"]["Thumbnail"].iscomplete
@test length(v["Image"].v) == 10
@test !v["Image"].iscomplete

x = v["Image"]["IDs"]
@test !x.iscomplete
@test length(x.v) == 0
@test x[2] == 943
@test length(x.v) == 2
@test !x.iscomplete
@test x == [116, 943, 234, 38793]
@test length(x.v) == 4
@test x.iscomplete

v = JSON.parse(rfc_example)
x = v["Image"]["IDs"]
@test length(x.v) == 0
@test sum(x) == 40086
@test length(x.v) == 4

@test length(v) == 1
@test v.iscomplete

end

end # testset



#-------------------------------------------------------------------------------
@testset "RFC7159 example with trailing garbage" begin
#-------------------------------------------------------------------------------

if JSON.wait_after_each_value

v = JSON.parse("""{"Foo": $rfc_example, "Bar": garbage!""")
@test sum(v["Foo"]["Image"]["IDs"]) == 40086

@test_throws JSON.ParseError length(v)
try
    length(v)
catch e
    @test "$e" == strip("""
    JSON.ParseError: invalid input at line 15, col 10
    , "Bar": garbage!
             ^
    """)
end

end

end # testset



#-------------------------------------------------------------------------------
@testset "ec2-2016-11-15.normal.json" begin
#-------------------------------------------------------------------------------

j = String(read("ec2-2016-11-15.normal.json"))

r = JSON.parse(j)
@test r["operations"
      ]["AcceptReservedInstancesExchangeQuote"
      ]["input"
      ]["shape"] |> String == "AcceptReservedInstancesExchangeQuoteRequest"

@test r["shapes"
      ]["scope"
      ]["enum"
      ][1] |> String == "Availability Zone"

end # testset



#-------------------------------------------------------------------------------
@testset "github.com/nst/JSONTestSuite" begin
#-------------------------------------------------------------------------------

    pending_unescape = [
        "n_string_1_surrogate_then_escape_u.json",
        "n_string_1_surrogate_then_escape_u1.json",
        "n_string_1_surrogate_then_escape_u1x.json",
        "n_string_incomplete_escaped_character.json",
        "n_string_incomplete_surrogate.json",
        "n_string_invalid-utf-8-in-escape.json",
        "n_string_invalid_unicode_escape.json",
        "n_string_unescaped_newline.json",
        "n_string_unescaped_tab.json"
    ]

    i_not_passing = [
        "i_string_UTF-16LE_with_BOM.json",
        "i_string_utf16BE_no_BOM.json",
        "i_string_utf16LE_no_BOM.json",
        "i_structure_UTF-8_BOM_empty_object.json"
    ]

    passing_but_sloooow = [
        "n_structure_open_array_object.json",
        "n_structure_100000_opening_arrays.json"
    ]

    d = "JSONTestSuite/test_parsing"
    for f in readdir("JSONTestSuite/test_parsing")
        #println(f)
        class = f[1] 
        if class == 'y' || class == 'i'
            if f in i_not_passing
                continue
            end
            r = JSON.parse(String(read("$d/$f")))
            if r isa JSON.Object || r isa JSON.Array
                JSON.parse_all!(r)
            end
            @test JSON.iscomplete(r)
        end
        if class == 'n' && JSON.enable_assertions
            if f in pending_unescape || f in passing_but_sloooow
                continue
            end
            @test_throws Union{JSON.ParseError,
                               StackOverflowError,
                               InexactError} begin
                r = JSON.parse(String(read("$d/$f")))
                if r isa JSON.Object || r isa JSON.Array
                    JSON.parse_all!(r)
                end
                if r isa JSON.Array
                    for i in r
                        JSON.promotejson(i)
                    end
                end
            end
        end
    end

end # testset



#-------------------------------------------------------------------------------
end # top level testset JSON
#-------------------------------------------------------------------------------
