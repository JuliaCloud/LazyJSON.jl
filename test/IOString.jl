using LazyJSON
using Test

const JSON = LazyJSON

@testset "IOString" begin

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
            v = LazyJSON.value(io, getproperty=true)
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

