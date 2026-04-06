using Test
using LLMWiki

@testset "Hasher" begin
    @testset "hash_file — consistent for same content" begin
        mktempdir() do dir
            path = joinpath(dir, "test.txt")
            write(path, "Hello, World!")
            h1 = LLMWiki.hash_file(path)
            h2 = LLMWiki.hash_file(path)
            @test h1 == h2
            @test length(h1) == 64  # SHA-256 hex digest
        end
    end

    @testset "hash_file — different content gives different hash" begin
        mktempdir() do dir
            path1 = joinpath(dir, "file1.txt")
            path2 = joinpath(dir, "file2.txt")
            write(path1, "Content A")
            write(path2, "Content B")
            @test LLMWiki.hash_file(path1) != LLMWiki.hash_file(path2)
        end
    end

    @testset "detect_changes — new files" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.sources_dir, "new_file.md"), "# New content")
            state = WikiState()

            changes = detect_changes(cfg, state)
            @test length(changes) == 1
            @test changes[1].file == "new_file.md"
            @test changes[1].status == NEW
        end
    end

    @testset "detect_changes — unchanged files" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            content = "# Same content"
            path = joinpath(cfg.sources_dir, "same.md")
            write(path, content)
            hash = LLMWiki.hash_file(path)

            state = WikiState(sources=Dict(
                "same.md" => SourceEntry(hash=hash, concepts=["c1"], compiled_at="2024-01-01")
            ))

            changes = detect_changes(cfg, state)
            @test length(changes) == 1
            @test changes[1].status == UNCHANGED
        end
    end

    @testset "detect_changes — changed files" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            path = joinpath(cfg.sources_dir, "changed.md")
            write(path, "# Updated content")

            state = WikiState(sources=Dict(
                "changed.md" => SourceEntry(hash="old_hash_value", concepts=["c1"], compiled_at="2024-01-01")
            ))

            changes = detect_changes(cfg, state)
            @test length(changes) == 1
            @test changes[1].status == CHANGED
        end
    end

    @testset "detect_changes — deleted files" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # No files on disk, but state records a file
            state = WikiState(sources=Dict(
                "gone.md" => SourceEntry(hash="some_hash", concepts=["c1"], compiled_at="2024-01-01")
            ))

            changes = detect_changes(cfg, state)
            @test length(changes) == 1
            @test changes[1].file == "gone.md"
            @test changes[1].status == DELETED
        end
    end

    @testset "detect_changes — mixed statuses" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # Create unchanged and new files
            unchanged_path = joinpath(cfg.sources_dir, "unchanged.md")
            write(unchanged_path, "Same")
            unchanged_hash = LLMWiki.hash_file(unchanged_path)

            write(joinpath(cfg.sources_dir, "new.md"), "Brand new")

            state = WikiState(sources=Dict(
                "unchanged.md" => SourceEntry(hash=unchanged_hash, concepts=[], compiled_at=""),
                "deleted.md" => SourceEntry(hash="x", concepts=[], compiled_at=""),
            ))

            changes = detect_changes(cfg, state)
            statuses = Dict(c.file => c.status for c in changes)
            @test statuses["unchanged.md"] == UNCHANGED
            @test statuses["new.md"] == NEW
            @test statuses["deleted.md"] == DELETED
        end
    end
end
