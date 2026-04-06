using Test
using LLMWiki

@testset "State" begin
    @testset "load_state — empty state when no file" begin
        mktempdir() do dir
            cfg = default_config(dir)
            state = load_state(cfg)
            @test state.version == 1
            @test isempty(state.sources)
            @test isempty(state.frozen_slugs)
            @test state.index_hash == ""
        end
    end

    @testset "save_state / load_state roundtrip" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            state = WikiState(
                version=2,
                sources=Dict(
                    "file1.md" => SourceEntry(hash="aaa", concepts=["concept-a", "concept-b"], compiled_at="2024-01-01"),
                    "file2.md" => SourceEntry(hash="bbb", concepts=["concept-c"], compiled_at="2024-01-02"),
                ),
                frozen_slugs=["frozen-one"],
                index_hash="indexhash123",
            )
            save_state(cfg, state)
            @test isfile(cfg.state_file)

            loaded = load_state(cfg)
            @test loaded.version == 2
            @test length(loaded.sources) == 2
            @test loaded.sources["file1.md"].hash == "aaa"
            @test loaded.sources["file1.md"].concepts == ["concept-a", "concept-b"]
            @test loaded.sources["file2.md"].hash == "bbb"
            @test loaded.frozen_slugs == ["frozen-one"]
            @test loaded.index_hash == "indexhash123"
        end
    end

    @testset "update_source_state!" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # Add new source
            entry1 = SourceEntry(hash="hash1", concepts=["c1"], compiled_at="2024-01-01")
            LLMWiki.update_source_state!(cfg, "new_file.md", entry1)
            state = load_state(cfg)
            @test haskey(state.sources, "new_file.md")
            @test state.sources["new_file.md"].hash == "hash1"

            # Update existing source
            entry2 = SourceEntry(hash="hash2", concepts=["c1", "c2"], compiled_at="2024-01-02")
            LLMWiki.update_source_state!(cfg, "new_file.md", entry2)
            state2 = load_state(cfg)
            @test state2.sources["new_file.md"].hash == "hash2"
            @test state2.sources["new_file.md"].concepts == ["c1", "c2"]
        end
    end

    @testset "acquire_lock / release_lock" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # Acquire lock succeeds first time
            @test LLMWiki.acquire_lock(cfg) == true

            # Second acquire should fail (lock held)
            @test LLMWiki.acquire_lock(cfg) == false

            # Release and re-acquire
            LLMWiki.release_lock(cfg)
            @test LLMWiki.acquire_lock(cfg) == true

            # Clean up
            LLMWiki.release_lock(cfg)
        end
    end

    @testset "release_lock — safe when no lock" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)
            # Should not error when no lock exists
            LLMWiki.release_lock(cfg)
        end
    end
end
