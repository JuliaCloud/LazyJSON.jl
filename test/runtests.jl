using LazyJSON
using Test

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

v = JSON.parse(rfc_example)

@test v isa JSON.Object

x = v["Image"]["Width"]
@test x == 800
@test x isa JSON.Number

x = v["Image"]["Thumbnail"]["Url"]

# JSON.String does not yet implement AbstractString
@test_broken x == "http://www.example.com/image/481989943"

@test SubString(x) == "http://www.example.com/image/481989943"

x = v["Image"]["IDs"]
@test collect(x) == [116, 943, 234, 38793]
@test length(collect(x)) == 4

v = JSON.parse(rfc_example)
x = v["Image"]["IDs"]
@test sum(x) == 40086


end # testset



#-------------------------------------------------------------------------------
@testset "RFC7159 example with trailing garbage" begin
#-------------------------------------------------------------------------------

v = JSON.parse("""{"Foo": $rfc_example, "Bar": garbage!""")
@test sum(v["Foo"]["Image"]["IDs"]) == 40086

@test_throws JSON.ParseError v["Bar"]
try
    v["Bar"]
catch e
    @test "$e" == strip("""
    JSON.ParseError: invalid value index at line 15, col 10
    , "Bar": garbage!
             ^
    """)
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
        println(f)
        class = f[1]
        if class == 'y' || class == 'i'
            if f in i_not_passing
                continue
            end
            r = JSON.parse(String(read("$d/$f")))
            @show LazyJSON.promotejson(r)
        end
        if class == 'n' #&& JSON.enable_assertions
            if f in pending_unescape || f in passing_but_sloooow
                continue
            end
            @test_throws Union{JSON.ParseError,
                               StackOverflowError,
                               InexactError} begin
                r = JSON.parse(String(read("$d/$f")))
                @show LazyJSON.rpromotejson(r)
            end
        end
    end

end # testset



#-------------------------------------------------------------------------------
end # top level testset JSON
#-------------------------------------------------------------------------------
