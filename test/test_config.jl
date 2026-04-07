using Test
using LLMWiki

@testset "Config" begin
    @testset "default_config" begin
        mktempdir() do dir
            cfg = default_config(dir)
            @test cfg.root == abspath(dir)
            @test cfg.sources_dir == joinpath(abspath(dir), "sources")
            @test cfg.wiki_dir == joinpath(abspath(dir), "wiki")
            @test cfg.concepts_dir == joinpath(abspath(dir), "wiki", "concepts")
            @test cfg.queries_dir == joinpath(abspath(dir), "wiki", "queries")
            @test cfg.index_file == joinpath(abspath(dir), "wiki", "index.md")
            @test cfg.log_file == joinpath(abspath(dir), "wiki", "log.md")
            @test cfg.state_dir == joinpath(abspath(dir), ".llmwiki")
            @test cfg.state_file == joinpath(abspath(dir), ".llmwiki", "state.json")
            # All paths are absolute
            @test isabspath(cfg.root)
            @test isabspath(cfg.sources_dir)
            @test isabspath(cfg.concepts_dir)
        end
    end

    @testset "resolve_paths!" begin
        cfg = WikiConfig(root="myproject", sources_dir="src")
        resolve_paths!(cfg)
        @test isabspath(cfg.root)
        @test isabspath(cfg.sources_dir)
        @test isabspath(cfg.wiki_dir)
        @test isabspath(cfg.concepts_dir)
        @test isabspath(cfg.state_file)
    end

    @testset "init_wiki" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)
            @test isdir(cfg.sources_dir)
            @test isdir(cfg.concepts_dir)
            @test isdir(cfg.queries_dir)
            @test isdir(cfg.state_dir)
            @test isfile(cfg.log_file)
            # Config file should be saved
            @test isfile(joinpath(cfg.state_dir, "config.yaml"))
        end
    end

    @testset "save_config / load_config roundtrip" begin
        mktempdir() do dir
            cfg = default_config(dir)
            cfg.model = "custom-model"
            cfg.search_top_k = 20
            cfg.versioned = false
            cfg.state_backend = :sqlite
            init_wiki(cfg)
            save_config(cfg)

            cfg2 = load_config(dir)
            @test cfg2.model == "custom-model"
            @test cfg2.search_top_k == 20
            @test cfg2.versioned == false
            @test cfg2.state_backend == :sqlite
        end
    end

    @testset "load_config — no config file returns defaults" begin
        mktempdir() do dir
            cfg = load_config(dir)
            @test cfg.model == "qwen3:8b"
            @test cfg.search_top_k == 10
        end
    end

    @testset "wiki_status" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            stats = wiki_status(cfg)
            @test stats.source_count == 0
            @test stats.page_count == 0
            @test stats.query_count == 0
            @test stats.orphan_count == 0
            @test stats.link_count == 0
            @test stats.last_compiled === nothing

            # Add a source and a page to verify counting
            write(joinpath(cfg.sources_dir, "test.md"), "# Test source")
            write(joinpath(cfg.concepts_dir, "test-concept.md"), """---
title: "Test Concept"
page_type: concept
---
Body with [[Another Page]] link.""")

            stats2 = wiki_status(cfg)
            @test stats2.source_count == 1
            @test stats2.page_count == 1
            @test stats2.link_count == 1
        end
    end
end
