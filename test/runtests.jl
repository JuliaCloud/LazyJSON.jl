using LazyJSON
using Test

using DataStructures

module JSON_jl
    using JSON
end
const JSON = LazyJSON

#FIXME
#include("SplicedStrings.jl")


struct Foo
    a::Int
    b
end

mutable struct Bar
    f::Foo
    v::Vector{Int}
    s::AbstractString
    s2::String
    ov::Vector{Foo}
end

struct Geometry
    _type
    coordinates
end

struct CityLot
    _type
    properties
    geometry::Geometry
end

struct Owner
    login
end

struct Repo
    id
    name
    owner::Owner
    parent
    full_name
    private::Bool
    url
    language
    pushed_at
    permissions
end




include("AbstractString.jl")

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
@testset "convert" begin
#-------------------------------------------------------------------------------

j = LazyJSON.value("""{
    "f": {"a": 1, "b": "foo"},
    "v": [1,2,3,4,5],
    "s": "Hello",
    "s2": "World!",
    "ov": [
        {"a": 1, "b": true},
        {"a": 2, "b": false},
        {"a": 3, "b": null}
    ]
}""")

if LazyJSON.enable_getproperty

@test j isa JSON.Object || j isa JSON.PropertyDict
@test j.f.a == 1
@test j.f.b == "foo"
@test j.v == [1, 2, 3, 4, 5]           ;@test j.v isa JSON.Array
@test j.s == "Hello"                   ;@test j.s isa JSON.String
@test j.s2 == "World!"                 ;@test j.s2 isa JSON.String
@test j.ov[1].a == 1
@test j.ov[1].b == true
@test j.ov[2].a == 2
@test j.ov[2].b == false
@test j.ov[3].a == 3
@test j.ov[3].b == nothing

end


v = convert(Bar, j)

@test v isa Bar
@test v.f.a == 1
@test v.f.b == "foo"
@test v.v == [1, 2, 3, 4, 5]           ;@test v.v isa Vector{Int}
@test v.s == "Hello"                   ;@test v.s isa JSON.String
@test v.s2 == "World!"                 ;@test v.s2 isa Base.String
@test v.ov[1] == Foo(1, true)          ;@test v.ov[1] isa Foo
@test v.ov[2] == Foo(2, false)
@test v.ov[3] == Foo(3, nothing)


d = convert(Dict, j)

@test d isa Dict{AbstractString,Any}
@test d["f"]["a"] == 1
@test d["f"]["b"] == "foo"
@test d["v"] == [1, 2, 3, 4, 5]
@test d["s"] == "Hello"                ;@test d["s"] isa JSON.String
@test d["s2"] == "World!"              ;@test d["s2"] isa JSON.String
@test d["ov"][1]["a"] == 1
@test d["ov"][1]["b"] == true
@test d["ov"][2]["a"] == 2
@test d["ov"][2]["b"] == false
@test d["ov"][3]["a"] == 3
@test d["ov"][3]["b"] == nothing


end #testset



#-------------------------------------------------------------------------------
@testset "RFC7159 example" begin
#-------------------------------------------------------------------------------

v = JSON.parse(rfc_example)

@test v isa JSON.Object || v isa JSON.PropertyDict

x = v["Image"]["Width"]
@test x == 800
@test x isa JSON.Number

x = v["Image"]["Thumbnail"]["Url"]

@test x == "http://www.example.com/image/481989943"

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
    JSON.ParseError: invalid value index at line 15, col 10: 'g'
    , "Bar": garbage!
             ^
    """)
end

end # testset

#-------------------------------------------------------------------------------
@testset "http://www.json.org/JSON_checker" begin
#-------------------------------------------------------------------------------

j = String(read("json_checker.json"))

v = JSON.parse(j)

@test v[1] == "JSON Test Pattern pass1"
@test v[2]["object with 1 member"][1] == "array with 1 element"
@test length(v[3]) == 0
@test v[3] isa JSON.Object || v[3] isa JSON.PropertyDict
@test [x for x in v[4]] == Any[]
@test v[4] isa JSON.Array
@test v[5] == -42
@test v[6]
@test !v[7]
@test v[8] == nothing
@test v[9]["integer"] == 1234567890
@test v[9]["real"] == -9876.543210
@test v[9]["e"] == 0.123456789e-12
@test v[9]["E"] == 1.234567890E+34
@test v[9][""] == 23456789012E66
@test v[9]["zero"] == 0
@test v[9]["one"] == 1
@test v[9]["space"] == " "
@test v[9]["quote"] == "\""
@test v[9]["backslash"] == "\\"
@test v[9]["controls"] == "\b\f\n\r\t"
@test v[9]["slash"] == "/ & /"
@test v[9]["alpha"] == "abcdefghijklmnopqrstuvwyz"
@test v[9]["ALPHA"] == "ABCDEFGHIJKLMNOPQRSTUVWYZ"
@test v[9]["digit"] == "0123456789"
@test v[9]["0123456789"] == "digit"
@test v[9]["special"] == "`1~!@#\$%^&*()_+-={':[,]}|;.</>?"
@test v[9]["hex"] == "\u0123\u4567\u89AB\uCDEF\uabcd\uef4A"
@test v[9]["true"] == true
@test v[9]["false"] == false
@test v[9]["null"] == nothing
@test [x for x in v[9]["array"]] == Any[]
@test [x for x in v[9]["object"]] == Pair[]
@test v[9]["address"] == "50 St. James Street"
@test v[9]["url"] == "http://www.JSON.org/"
@test v[9]["comment"] == "// /* <!-- --"
@test v[9]["# -- --> */"] == " "
@test collect(v[9][" s p a c e d "]) == collect(1:7)
@test collect(v[9]["compact"]) == collect(1:7)
@test v[9]["jsontext"] == "{\"object with 1 member\":[\"array with 1 element\"]}"
@test v[9]["quotes"] == "&#34; \u0022 %22 0x22 034 &#x22;"
@test v[9]["/\\\"\uCAFE\uBABE\uAB98\uFCDE\ubcda\uef4A\b\f\n\r\t`1~!@#\$%^&*()_+-=[]{}|;:',./<>?"] == "A key can be any string"
@test v[10] == 0.5
@test v[11] == 98.6
@test v[12] == 99.44
@test v[13] == 1066
@test v[14] == 1e1
@test v[15] == 0.1e1
@test v[16] == 1e-1
@test v[17] == 1e00
@test v[18] == 2e+00
@test v[19] == 2e-00
@test v[20] == "rosebud"


end # testset


#-------------------------------------------------------------------------------
@testset "Escaped values in keys" begin
#-------------------------------------------------------------------------------

json = Vector{UInt8}(codeunits("""
    {
        "Image\t Tab": {
            "Width":  800,
            "Height": 600,
            "Title":  "View from 15th Floor",
            "Thumb\\nail": {
                "\\ud83e\\udd16 Url": "http://www.example.com/image/481989943",
                "Height": 125,
                "Width":  100
            },
            "Animated" : false,
            "IDs": [116, 943, 234, 38793]
        }
    }
"""))


v = JSON.parse(json)

x = v["Image\t Tab"]["Thumb\nail"]["🤖 Url"]

@test x == "http://www.example.com/image/481989943"


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

jparse(x) = JSON.parse(x; lazy=false)

@test jparse("[123.456e-789]") == Any[BigFloat("1.23456e-787")] # i_number_double_huge_neg_exp.json
@test jparse("[0.4e00669999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999969999999006]") == Any[Inf] # i_number_huge_exp.json
@test jparse("[-1e+9999]") == Any[BigFloat("-1.0e+9999")]
@test jparse("[1.5e+9999]") == Any[BigFloat("1.5e+9999")]
@test jparse("[-123123e100000]") == Any[BigFloat("-123123e100000")]
@test jparse("[123123e100000]") == Any[BigFloat("123123e100000")]
@test jparse("[123e-10000000]") == Any[BigFloat("123e-10000000")]
@test jparse("[-123123123123123123123123123123]") == Any[-123123123123123123123123123123] # i_number_too_big_neg_int.json
@test jparse("[100000000000000000000]") == Any[100000000000000000000] # i_number_too_big_pos_int.json
@test jparse("[-237462374673276894279832749832423479823246327846]") == Any[-237462374673276894279832749832423479823246327846] # i_number_very_big_negative_int.json
@test jparse("{\"\\uDFAA\":0}") == DataStructures.OrderedDict{SubString{String},Any}("\udfaa"=>0) # i_object_key_lone_2nd_surrogate.json
@test jparse("[\"\\uDADA\"]") == Any["\udada"] # i_string_1st_surrogate_but_2nd_missing.json
@test jparse("[\"\\uD888\\u1234\"]") == Any["\ud888ሴ"] # i_string_1st_valid_surrogate_2nd_invalid.json
@test jparse("[\"日ш\xfa\"]") == Any["日ш\xfa"] # i_string_UTF-8_invalid_sequence.json
@test jparse("[\"\ud800\"]") == Any["\ud800"] # i_string_UTF8_surrogate_U+D800.json
@test jparse("[\"\\uD800\\n\"]") == Any["\ud800\n"] # i_string_incomplete_surrogate_and_escape_valid.json
@test jparse("[\"\\uDd1ea\"]") == Any["\udd1ea"] # i_string_incomplete_surrogate_pair.json
@test jparse("[\"\\uD800\\uD800\\n\"]") == Any["\ud800\ud800\n"] # i_string_incomplete_surrogates_escape_valid.json
@test jparse("[\"\\ud800\"]") == Any["\ud800"] # i_string_invalid_lonely_surrogate.json
@test jparse("[\"\\ud800abc\"]") == Any["\ud800abc"] # i_string_invalid_surrogate.json
@test jparse("[\"\xff\"]") == Any["\xff"] # i_string_invalid_utf-8.json
@test jparse("[\"\\uDd1e\\uD834\"]") == Any["\udd1e\ud834"] # i_string_inverted_surrogates_U+1D11E.json
@test jparse("[\"\xe9\"]") == Any["\xe9"] # i_string_iso_latin_1.json
@test jparse("[\"\\uDFAA\"]") == Any["\udfaa"] # i_string_lone_second_surrogate.json
@test jparse("[\"\x81\"]") == Any["\x81"] # i_string_lone_utf8_continuation_byte.json
c = String(UInt8[ 0xf4, 0xbf, 0xbf, 0xbf])
@test jparse("[\"$c\"]") == Any["$c"] # i_string_not_in_unicode_range.json
@test jparse("[\"\xc0\xaf\"]") == Any["\xc0\xaf"] # i_string_overlong_sequence_2_bytes.json
@test jparse("[\"\xfc\x83\xbf\xbf\xbf\xbf\"]") == Any["\xfc\x83\xbf\xbf\xbf\xbf"] # i_string_overlong_sequence_6_bytes.json
@test jparse("[\"\xfc\x80\x80\x80\x80\x80\"]") == Any["\xfc\x80\x80\x80\x80\x80"] # i_string_overlong_sequence_6_bytes_null.json
@test jparse("[\"\xe0\xff\"]") == Any["\xe0\xff"] # i_string_truncated-utf-8.json
@test jparse("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]") == Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[Any[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]] # i_structure_500_nested_arrays.json
@test jparse("[[]   ]") == Any[Any[]] # y_array_arraysWithSpaces.json
@test jparse("[\"\"]") == Any[""] # y_array_empty-string.json
@test jparse("[]") == Any[] # y_array_empty.json
@test jparse("[\"a\"]") == Any["a"] # y_array_ending_with_newline.json
@test jparse("[false]") == Any[false] # y_array_false.json
@test jparse("[null, 1, \"1\", {}]") == Any[nothing, 1, "1", DataStructures.OrderedDict{SubString{String},Any}()] # y_array_heterogeneous.json
@test jparse("[null]") == Any[nothing] # y_array_null.json
@test jparse("[1\n]") == Any[1] # y_array_with_1_and_newline.json
@test jparse(" [1]") == Any[1] # y_array_with_leading_space.json
@test jparse("[1,null,null,null,2]") == Any[1, nothing, nothing, nothing, 2] # y_array_with_several_null.json
@test jparse("[2] ") == Any[2] # y_array_with_trailing_space.json
@test jparse("[123e65]") == Any[1.23e67] # y_number.json
@test jparse("[0e+1]") == Any[0.0] # y_number_0e+1.json
@test jparse("[0e1]") == Any[0.0] # y_number_0e1.json
@test jparse("[ 4]") == Any[4] # y_number_after_space.json
#@test jparse("[-0.000000000000000000000000000000000000000000000000000000000000000000000000000001]\n") == Any[BigFloat("-0.000000000000000000000000000000000000000000000000000000000000000000000000000001")] # y_number_double_close_to_zero.json
@test jparse("[20e1]") == Any[200.0] # y_number_int_with_exp.json
@test jparse("[-0]") == Any[-0.0] # y_number_minus_zero.json
@test jparse("[-123]") == Any[-123] # y_number_negative_int.json
@test jparse("[-1]") == Any[-1] # y_number_negative_one.json
@test jparse("[-0]") == Any[-0.0] # y_number_negative_zero.json
@test jparse("[1E22]") == Any[1.0e22] # y_number_real_capital_e.json
@test jparse("[1E-2]") == Any[0.01] # y_number_real_capital_e_neg_exp.json
@test jparse("[1E+2]") == Any[100.0] # y_number_real_capital_e_pos_exp.json
@test jparse("[123e45]") == Any[1.23e47] # y_number_real_exponent.json
@test jparse("[123.456e78]") == Any[1.23456e80] # y_number_real_fraction_exponent.json
@test jparse("[1e-2]") == Any[0.01] # y_number_real_neg_exp.json
@test jparse("[1e+2]") == Any[100.0] # y_number_real_pos_exponent.json
@test jparse("[123]") == Any[123] # y_number_simple_int.json
@test jparse("[123.456789]") == Any[123.456789] # y_number_simple_real.json
@test jparse("{\"asd\":\"sdf\", \"dfg\":\"fgh\"}") == DataStructures.OrderedDict{SubString{String},Any}("asd"=>"sdf","dfg"=>"fgh") # y_object.json
@test jparse("{\"asd\":\"sdf\"}") == DataStructures.OrderedDict{SubString{String},Any}("asd"=>"sdf") # y_object_basic.json
@test jparse("{\"a\":\"b\",\"a\":\"c\"}") == DataStructures.OrderedDict{SubString{String},Any}("a"=>"c") # y_object_duplicated_key.json
@test jparse("{\"a\":\"b\",\"a\":\"b\"}") == DataStructures.OrderedDict{SubString{String},Any}("a"=>"b") # y_object_duplicated_key_and_value.json
@test jparse("{}") == DataStructures.OrderedDict{SubString{String},Any}() # y_object_empty.json
@test jparse("{\"\":0}") == DataStructures.OrderedDict{SubString{String},Any}(""=>0) # y_object_empty_key.json
@test jparse("{\"foo\\u0000bar\": 42}") == DataStructures.OrderedDict{SubString{String},Any}("foo\0bar"=>42) # y_object_escaped_null_in_key.json
@test jparse("{ \"min\": -1.0e+28, \"max\": 1.0e+28 }") == DataStructures.OrderedDict{SubString{String},Any}("min"=>-1.0e28,"max"=>1.0e28) # y_object_extreme_numbers.json
@test jparse("{\"x\":[{\"id\": \"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}], \"id\": \"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}") == DataStructures.OrderedDict{SubString{String},Any}("x"=>Any[DataStructures.OrderedDict{SubString{String},Any}("id"=>"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")],"id"=>"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") # y_object_long_strings.json
@test jparse("{\"a\":[]}") == DataStructures.OrderedDict{SubString{String},Any}("a"=>Any[]) # y_object_simple.json
@test jparse("{\"title\":\"\\u041f\\u043e\\u043b\\u0442\\u043e\\u0440\\u0430 \\u0417\\u0435\\u043c\\u043b\\u0435\\u043a\\u043e\\u043f\\u0430\" }") == DataStructures.OrderedDict{SubString{String},Any}("title"=>"Полтора Землекопа") # y_object_string_unicode.json
@test jparse("{\n\"a\": \"b\"\n}") == DataStructures.OrderedDict{SubString{String},Any}("a"=>"b") # y_object_with_newlines.json
@test jparse("[\"\\u0060\\u012a\\u12AB\"]") == Any["`Īካ"] # y_string_1_2_3_bytes_UTF-8_sequences.json
@test jparse("[\"\\uD801\\udc37\"]") == Any["𐐷"] # y_string_accepted_surrogate_pair.json
@test jparse("[\"\\ud83d\\ude39\\ud83d\\udc8d\"]") == Any["😹💍"] # y_string_accepted_surrogate_pairs.json
@test jparse("[\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"]") == Any["\"\\/\b\f\n\r\t"] # y_string_allowed_escapes.json
@test jparse("[\"\\\\u0000\"]") == Any["\\u0000"] # y_string_backslash_and_u_escaped_zero.json
@test jparse("[\"\\\"\"]") == Any["\""] # y_string_backslash_doublequotes.json
@test jparse("[\"a/*b*/c/*d//e\"]") == Any["a/*b*/c/*d//e"] # y_string_comments.json
@test jparse("[\"\\\\a\"]") == Any["\\a"] # y_string_double_escape_a.json
@test jparse("[\"\\\\n\"]") == Any["\\n"] # y_string_double_escape_n.json
@test jparse("[\"\\u0012\"]") == Any["\x12"] # y_string_escaped_control_character.json
@test jparse("[\"\\uFFFF\"]") == Any["\uffff"] # y_string_escaped_noncharacter.json
@test jparse("[\"asd\"]") == Any["asd"] # y_string_in_array.json
@test jparse("[ \"asd\"]") == Any["asd"] # y_string_in_array_with_leading_space.json
@test jparse("[\"\\uDBFF\\uDFFF\"]") == Any["\U10ffff"] # y_string_last_surrogates_1_and_2.json
@test jparse("[\"new\\u00A0line\"]") == Any["new line"] # y_string_nbsp_uescaped.json
@test jparse("[\"\U10ffff\"]") == Any["\U10ffff"] # y_string_nonCharacterInUTF-8_U+10FFFF.json
@test jparse("[\"\U1bfff\"]") == Any["\U1bfff"] # y_string_nonCharacterInUTF-8_U+1FFFF.json
@test jparse("[\"\uffff\"]") == Any["\uffff"] # y_string_nonCharacterInUTF-8_U+FFFF.json
@test jparse("[\"\\u0000\"]") == Any["\0"] # y_string_null_escape.json
@test jparse("[\"\\u002c\"]") == Any[","] # y_string_one-byte-utf-8.json
@test jparse("[\"π\"]") == Any["π"] # y_string_pi.json
@test jparse("[\"asd \"]") == Any["asd "] # y_string_simple_ascii.json
@test jparse("\" \"") == " "  # y_string_space.json
@test jparse("[\"\\uD834\\uDd1e\"]") == Any["𝄞"] # y_string_surrogates_U+1D11E_MUSICAL_SYMBOL_G_CLEF.json
@test jparse("[\"\\u0821\"]") == Any["ࠡ"] # y_string_three-byte-utf-8.json
@test jparse("[\"\\u0123\"]") == Any["ģ"] # y_string_two-byte-utf-8.json
@test jparse("[\"\u2028\"]") == Any["\u2028"] # y_string_u+2028_line_sep.json
@test jparse("[\"\u2029\"]") == Any["\u2029"] # y_string_u+2029_par_sep.json
@test jparse("[\"\\u0061\\u30af\\u30EA\\u30b9\"]") == Any["aクリス"] # y_string_uEscape.json
@test jparse("[\"new\\u000Aline\"]") == Any["new\nline"] # y_string_uescaped_newline.json
@test jparse("[\"\x7f\"]") == Any["\x7f"] # y_string_unescaped_char_delete.json
@test jparse("[\"\\uA66D\"]") == Any["ꙭ"] # y_string_unicode.json
@test jparse("[\"\\u005C\"]") == Any["\\"] # y_string_unicodeEscapedBackslash.json
@test jparse("[\"⍂㈴⍂\"]") == Any["⍂㈴⍂"] # y_string_unicode_2.json
@test jparse("[\"\\uDBFF\\uDFFE\"]") == Any["\U10fffe"] # y_string_unicode_U+10FFFE_nonchar.json
@test jparse("[\"\\uD83F\\uDFFE\"]") == Any["\U1fffe"] # y_string_unicode_U+1FFFE_nonchar.json
@test jparse("[\"\\u200B\"]") == Any["\u200b"] # y_string_unicode_U+200B_ZERO_WIDTH_SPACE.json
@test jparse("[\"\\u2064\"]") == Any["\u2064"] # y_string_unicode_U+2064_invisible_plus.json
@test jparse("[\"\\uFDD0\"]") == Any["\ufdd0"] # y_string_unicode_U+FDD0_nonchar.json
@test jparse("[\"\\uFFFE\"]") == Any["\ufffe"] # y_string_unicode_U+FFFE_nonchar.json
@test jparse("[\"\\u0022\"]") == Any["\""] # y_string_unicode_escaped_double_quote.json
@test jparse("[\"€𝄞\"]") == Any["€𝄞"] # y_string_utf8.json
@test jparse("[\"a\x7fa\"]") == Any["a\x7fa"] # y_string_with_del_character.json
@test jparse("false") == false # y_structure_lonely_false.json
@test jparse("42") == 42 # y_structure_lonely_int.json
@test jparse("-0.1") == -0.1 # y_structure_lonely_negative_real.json
@test jparse("null") == nothing # y_structure_lonely_null.json
@test jparse("\"asd\"") == "asd" # y_structure_lonely_string.json
@test jparse("true") == true # y_structure_lonely_true.json
@test jparse("\"\"") == "" # y_structure_string_empty.json
@test jparse("[\"a\"]\n") == Any["a"] # y_structure_trailing_newline.json
@test jparse("[true]") == Any[true] # y_structure_true_in_array.json
@test jparse(" [] ") == Any[] # y_structure_whitespace_array.json

end # testset


#-------------------------------------------------------------------------------
@testset "github.com/nst/JSONTestSuite negative" begin
#-------------------------------------------------------------------------------

    jparse(x) = LazyJSON.parse(x; lazy=false)

    d = "JSONTestSuite/test_parsing"

    for f in readdir("JSONTestSuite/test_parsing")
        class = f[1]
        if class == 'n' #&& JSON.enable_assertions
            continue # FIXME
            if f in pending_unescape || f in passing_but_sloooow
                continue
            end
            @test_throws Union{JSON.ParseError,
                               StackOverflowError,
                               InexactError} begin
                r = JSON.parse(String(read("$d/$f")); lazy=false)
            end
        end
    end

end # testset


#-------------------------------------------------------------------------------
@testset "citylots" begin
#-------------------------------------------------------------------------------

json = """{
"type": "FeatureCollection",
"features": [
{ "type": "Feature", "properties": { "MAPBLKLOT": "0001001", "BLKLOT": "0001001", "BLOCK_NUM": "0001", "LOT_NUM": "001", "FROM_ST": "0", "TO_ST": "0", "STREET": "UNKN
OWN", "ST_TYPE": null, "ODD_EVEN": "E" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -122.422003528252475, 37.808480096967251, 0.0 ], [ -122.42207601332528
1, 37.808835019815085, 0.0 ], [ -122.421102174348633, 37.808803534992904, 0.0 ], [ -122.421062569067274, 37.808601056818148, 0.0 ], [ -122.422003528252475, 37.8084800
96967251, 0.0 ] ] ] } }
,
{ "type": "Feature", "properties": { "MAPBLKLOT": "0002001", "BLKLOT": "0002001", "BLOCK_NUM": "0002", "LOT_NUM": "001", "FROM_ST": "0", "TO_ST": "0", "STREET": "UNKN
OWN", "ST_TYPE": null, "ODD_EVEN": "E" }, "geometry": { "type": "Polygon", "coordinates": [ [ [ -122.42082593937107, 37.808631474146033, 0.0 ], [ -122.420858049679694
, 37.808795641369592, 0.0 ], [ -122.419811958704301, 37.808761809714007, 0.0 ], [ -122.42082593937107, 37.808631474146033, 0.0 ] ] ] } }

]}"""


v = convert(Vector{CityLot}, LazyJSON.value(json, ["features"]))

@test v[1]._type == "Feature"
@test v[1].properties["MAPBLKLOT"] == "0001001"

@test v[2]._type == "Feature"
@test v[2].properties["MAPBLKLOT"] == "0002001"
@test v[2].geometry.coordinates[1][1][1] == -122.42082593937107

end # testset


#-------------------------------------------------------------------------------
@testset "GitHub.jl" begin
#-------------------------------------------------------------------------------

    gist_json = """{
      "id": 1296269,
      "owner": {
        "login": "octocat"
      },
      "parent": {
        "name": "test-parent"
      },
      "full_name": "octocat/Hello-World",
      "private": false,
      "url": "https://api.github.com/repos/octocat/Hello-World",
      "language": null,
      "pushed_at": "2011-01-26T19:06:43Z",
      "permissions": {
        "admin": false,
        "push": false,
        "pull": true
      }
    }"""

v = convert(Repo, LazyJSON.value(gist_json))

@test v.owner.login == "octocat"

s = "XXX $gist_json ~YYY"
s = SubString(s, 5, findfirst(isequal('~'), s) - 2)
@test s == gist_json
@test s isa SubString{String}

v = convert(Repo, LazyJSON.value(s))
@test v.owner.login == "octocat"

end #testset


@static if LazyJSON.enable_iostrings
#-------------------------------------------------------------------------------
@testset "IOString" begin
#-------------------------------------------------------------------------------


@testset "IOString Error" begin
    log = [] ; io = Base.BufferStream()

    @sync begin
        @async begin
            try
                v = LazyJSON.value(io)
                push!(log, Int64(v))
            catch e
                push!(log, e)
            end
        end

        @test isempty(log)
        write(io, "a")
        while isempty(log) sleep(0.01) end; @test log[1] isa LazyJSON.ParseError
        close(io)
    end
end

@testset "IOString Number" begin
    log = [] ; io = Base.BufferStream()

    @sync begin
        @async begin
            v = LazyJSON.value(io)
            push!(log, Int64(v))
        end

        @test isempty(log)
        write(io, "1") ; sleep(0.01)  ;@test isempty(log)
        write(io, "2") ; sleep(0.01)  ;@test isempty(log)
        write(io, "3") ; sleep(0.01)  ;@test isempty(log)
        close(io)      ; while isempty(log) sleep(0.01) end
                                       @test log[1] == 123
    end
end


@testset "IOString String" begin
    log = [] ; io = Base.BufferStream()

    @sync begin
        @async begin
            v = LazyJSON.value(io)
            push!(log, String(v))
        end

        @test isempty(log)
        write(io, "\"1") ; sleep(0.01)  ;@test isempty(log)
        write(io, "2")   ; sleep(0.01)  ;@test isempty(log)
        write(io, "3\"") ; while isempty(log) sleep(0.01) end
                                         @test log[1] == "123"
        close(io)
    end
end

@testset "IOString Lazy String" begin
    log = [] ; io = Base.BufferStream()

    @sync begin
        @async begin
            v = LazyJSON.value(io)
            push!(log, v)
        end

        etb = LazyJSON.IOStrings.ASCII_ETB
        @test isempty(log)
        write(io, "\"") ; sleep(0.01) ;@test log[1] isa JSON.String
                                      ;@test log[1].s.buf.data[1] == UInt8('"')
                                       @test log[1].s.buf.data[2] == etb
        write(io, "12") ; sleep(0.01) ;@test log[1].s.buf.data[1] == UInt8('"')
                                       @test log[1].s.buf.data[2] == etb
        write(io, "3\""); sleep(0.01) ;@test log[1] == "123"
        close(io)
    end
end

@testset "IOString Array" begin
    log = [] ; io = Base.BufferStream()

    @sync begin
        @async begin
            v = LazyJSON.value(io)
            for x in v
                push!(log, Int64(x))
            end
        end

        @test isempty(log)
        write(io, "[")    ; sleep(0.01)  ;@test isempty(log)
        write(io, "1")    ; sleep(0.01)  ;@test isempty(log)
        write(io, ",")    ; sleep(0.01)  ;@test log[1] == 1
        write(io, "2,")   ; sleep(0.01)  ;@test log[2] == 2
        write(io, "3")    ; sleep(0.01)  ;@test length(log) == 2
        write(io, "4")    ; sleep(0.01)  ;@test length(log) == 2
        write(io, "5")    ; sleep(0.01)  ;@test length(log) == 2
        write(io, "]")    ; sleep(0.01)  ;@test log[3] == 345
        close(io)
    end
end



@testset "IOString Object" begin
    log = [] ; io = Base.BufferStream()

    @sync begin
        t = @async begin
            v = LazyJSON.value(io)
            for (k, x) in v
                push!(log, (String(k), String(x)))
            end
        end

        @test isempty(log)
        write(io, "{")            ; sleep(0.01)  ;@test isempty(log)
        write(io, "\"f")          ; sleep(0.01)  ;@test isempty(log)
        write(io, "oo\":")        ; sleep(0.01)  ;@test isempty(log)
        write(io, "\"A")          ; sleep(0.01)  ;@test isempty(log)
        write(io, "\"")           ; sleep(0.01)  ;@test log[1] == ("foo", "A")
        write(io, ",")            ; sleep(0.01)
        write(io, "\"bar\":")
        write(io, "   \"123\"  ,"); sleep(0.01)  ;@test log[2] == ("bar", "123")
        write(io, "}")            ; sleep(0.01)
        close(io)
    end
end


@testset "IOString split" begin
    log = [] ; io = Base.BufferStream()

    gist_json = """{
      "id": 1296269,
      "owner": {
        "login": "octocat"
      },
      "parent": {
        "name": "test-parent"
      },
      "full_name": "octocat/Hello-World",
      "private": false,
      "url": "https://api.github.com/repos/octocat/Hello-World",
      "language": null,
      "pushed_at": "2011-01-26T19:06:43Z",
      "permissions": {
        "admin": false,
        "push": false,
        "pull": true
      }
    }"""
    bytes = Vector{UInt8}(codeunits(gist_json))

    @sync begin
        t = @async begin
            v = LazyJSON.value(io)
            push!(log, v.id)
            push!(log, v.owner.login)
            push!(log, v.private)
            push!(log, v.permissions.admin)
        end

        @test isempty(log)
        write(io, bytes[1:80])    ; sleep(0.01)  ;@test log[1] == 1296269
                                                  @test log[2] == "octocat"
                                                  @test length(log) == 2
        write(io, bytes[81:200])  ; sleep(0.01)  ;@test log[3] == false
                                                  @test length(log) == 3
        write(io, bytes[201:end]) ; sleep(0.01)  ;@test log[4] == false
                                                  @test length(log) == 4
        close(io)
    end
end

end #testset
end #enable_iostring


#=
#-------------------------------------------------------------------------------
@testset "splice" begin
#-------------------------------------------------------------------------------

splice = LazyJSON.splice
value = LazyJSON.value

@test splice("1", [], 7) == "7"
@test splice("\"foo\"", [], "bar") == "\"bar\""
@test splice("[1,2,3]", [3], 4) == "[1,2,4]"
@test splice(" {\"foo\": \"bar\"}", ["foo"], 7) == " {\"foo\": 7}"

@test splice(value("1"), [], 7) == 7
@test splice(value("\"foo\""), [], "bar") == "bar"
@test splice(value("[1,2,3]"), [3], 4) == [1,2,4]
@test splice(value(" {\"foo\": \"bar\"}"), ["foo"], 7) == Dict("foo" => 7)

j = """{
    "id": 1296269,
    "owner": {
        "login": "octocat"
    },
    "parent": {
        "name": "test-parent"
    }
}"""

@test splice(j, ["owner", "login"], "foo") ==
"""{
    "id": 1296269,
    "owner": {
        "login": "foo"
    },
    "parent": {
        "name": "test-parent"
    }
}"""

@test splice(j, ["owner"], "foo") ==
"""{
    "id": 1296269,
    "owner": "foo",
    "parent": {
        "name": "test-parent"
    }
}"""

j = value(j)

@test string(splice(j, ["owner", "login"], "foo")) ==
"""{
    "id": 1296269,
    "owner": {
        "login": "foo"
    },
    "parent": {
        "name": "test-parent"
    }
}"""

a = splice(j, j.owner.login, "foo")
b = splice(j, ["owner", "login"], "foo")

@test a.id == b.id
@test Int(a.id) == Float64(b.id)
@test a.owner.login == b.owner.login
@test a.parent == b.parent
@test a.parent.name == b.parent.name
@test a == b

@test splice(j.owner, j.owner.login, "foo") == Dict("login" => "foo")

@test string(splice(j, j.parent, j.owner)) ==
"""{
    "id": 1296269,
    "owner": {
        "login": "octocat"
    },
    "parent": {
        "login": "octocat"
    }
}"""

@test string(splice(j, j.id, [1,2,3,4,5])) ==
"""{
    "id": [1,2,3,4,5],
    "owner": {
        "login": "octocat"
    },
    "parent": {
        "name": "test-parent"
    }
}"""

end #testset
=#
