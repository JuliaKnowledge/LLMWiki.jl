using Test
using LLMWiki

@testset "Log" begin
    @testset "log_operation! — appends to log file" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            LLMWiki.log_operation!(cfg, :compile, "compiled 3 pages")
            @test isfile(cfg.log_file)
            content = read(cfg.log_file, String)
            @test occursin("compile", content)
            @test occursin("compiled 3 pages", content)
        end
    end

    @testset "read_log — reads log entries" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            LLMWiki.log_operation!(cfg, :compile, "compiled 5 pages")
            entries = LLMWiki.read_log(cfg)
            @test length(entries) >= 1
            last_entry = entries[end]
            @test last_entry.operation == "compile"
            @test last_entry.details == "compiled 5 pages"
            @test !isempty(last_entry.timestamp)
        end
    end

    @testset "read_log — multiple entries" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            LLMWiki.log_operation!(cfg, :ingest, "ingested file1.md")
            LLMWiki.log_operation!(cfg, :compile, "compiled 2 pages")
            LLMWiki.log_operation!(cfg, :lint, "found 1 issue")

            entries = LLMWiki.read_log(cfg)
            @test length(entries) >= 3
            ops = [String(e.operation) for e in entries]
            @test "ingest" in ops
            @test "compile" in ops
            @test "lint" in ops
        end
    end

    @testset "read_log — empty log file" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)
            entries = LLMWiki.read_log(cfg)
            @test isempty(entries)
        end
    end

    @testset "read_log — no log file" begin
        mktempdir() do dir
            cfg = default_config(dir)
            entries = LLMWiki.read_log(cfg)
            @test isempty(entries)
        end
    end
end
