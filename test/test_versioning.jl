using Test
using LLMWiki

@testset "Versioning" begin

    @testset "git_init! creates repo" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)
        @test isdir(joinpath(config.wiki_dir, ".git"))
        @test isfile(joinpath(config.wiki_dir, ".gitignore"))
    end

    @testset "git_init! is idempotent" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)
        # Second call should not error
        git_init!(config)
        @test isdir(joinpath(config.wiki_dir, ".git"))
    end

    @testset "versioned=false skips git" begin
        dir = mktempdir()
        config = default_config(dir)
        config.versioned = false
        init_wiki(config)
        @test !isdir(joinpath(config.wiki_dir, ".git"))
    end

    @testset "git_snapshot! creates commit" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        cp = joinpath(dir, config.concepts_dir)
        write(joinpath(cp, "test.md"), "# Test\nHello")
        hash = git_snapshot!(config, "Add test")
        @test hash !== nothing
        @test length(hash) >= 7
    end

    @testset "git_snapshot! returns nothing when no changes" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        cp = joinpath(dir, config.concepts_dir)
        write(joinpath(cp, "test.md"), "# Test")
        git_snapshot!(config, "Add test")

        # No new changes
        result = git_snapshot!(config, "No changes")
        @test result === nothing
    end

    @testset "git_snapshot! with custom author" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        write(joinpath(dir, config.concepts_dir, "a.md"), "# A")
        git_snapshot!(config, "Custom author"; author="Alice <sdwfrost@users.noreply.github.com>")

        hist = wiki_log(config; limit=1)
        @test length(hist) >= 1
        @test contains(hist[1].author, "Alice")
    end

    @testset "git_snapshot! without git is no-op" begin
        dir = mktempdir()
        config = default_config(dir)
        config.versioned = false
        init_wiki(config)

        result = git_snapshot!(config, "No git")
        @test result === nothing
    end

    @testset "wiki_history" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        cp = joinpath(dir, config.concepts_dir)

        write(joinpath(cp, "page.md"), "# V1")
        git_snapshot!(config, "Version 1")

        write(joinpath(cp, "page.md"), "# V2")
        git_snapshot!(config, "Version 2")

        write(joinpath(cp, "page.md"), "# V3")
        git_snapshot!(config, "Version 3")

        hist = wiki_history(config, "page")
        @test length(hist) == 3
        @test hist[1].message == "Version 3"  # most recent first
        @test hist[3].message == "Version 1"

        # Each entry has all fields
        for entry in hist
            @test !isempty(entry.hash)
            @test !isempty(entry.author)
            @test !isempty(entry.date)
            @test !isempty(entry.message)
        end
    end

    @testset "wiki_history with limit" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        cp = joinpath(dir, config.concepts_dir)
        for i in 1:5
            write(joinpath(cp, "page.md"), "# V$i")
            git_snapshot!(config, "V$i")
        end

        hist = wiki_history(config, "page"; limit=2)
        @test length(hist) == 2
        @test hist[1].message == "V5"
    end

    @testset "wiki_history for nonexistent slug" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)
        @test isempty(wiki_history(config, "nonexistent"))
    end

    @testset "wiki_history without git" begin
        dir = mktempdir()
        config = default_config(dir)
        config.versioned = false
        init_wiki(config)
        @test isempty(wiki_history(config, "anything"))
    end

    @testset "wiki_diff between versions" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        cp = joinpath(dir, config.concepts_dir)

        write(joinpath(cp, "page.md"), "Line 1\nLine 2\n")
        git_snapshot!(config, "V1")

        write(joinpath(cp, "page.md"), "Line 1\nLine 2 modified\nLine 3\n")
        git_snapshot!(config, "V2")

        d = wiki_diff(config, "page"; from="HEAD~1", to="HEAD")
        @test !isempty(d)
        @test contains(d, "modified") || contains(d, "Line 3")
    end

    @testset "wiki_diff with no changes" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        write(joinpath(dir, config.concepts_dir, "page.md"), "content")
        git_snapshot!(config, "V1")

        d = wiki_diff(config, "page"; from="HEAD", to="HEAD")
        @test isempty(d)
    end

    @testset "wiki_diff nonexistent slug" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)
        @test isempty(wiki_diff(config, "nonexistent"))
    end

    @testset "wiki_log" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        cp = joinpath(dir, config.concepts_dir)
        write(joinpath(cp, "a.md"), "# A")
        git_snapshot!(config, "First commit")
        write(joinpath(cp, "b.md"), "# B")
        git_snapshot!(config, "Second commit")

        log = wiki_log(config)
        @test length(log) >= 2
        # Most recent first
        @test log[1].message == "Second commit"
    end

    @testset "wiki_log with limit" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        cp = joinpath(dir, config.concepts_dir)
        for i in 1:5
            write(joinpath(cp, "page$i.md"), "# $i")
            git_snapshot!(config, "Commit $i")
        end

        log = wiki_log(config; limit=3)
        @test length(log) == 3
    end

    @testset "VersionEntry fields" begin
        e = LLMWiki.VersionEntry(hash="abc123", author="Test <sdwfrost@users.noreply.github.com>",
                                  date="2026-01-01", message="test")
        @test e.hash == "abc123"
        @test e.author == "Test <sdwfrost@users.noreply.github.com>"
        @test e.date == "2026-01-01"
        @test e.message == "test"
    end

    @testset "SourceEntry provenance fields" begin
        # Default values
        e1 = SourceEntry()
        @test e1.source_url === nothing
        @test e1.source_type == "file"
        @test e1.original_file === nothing

        # Web source
        e2 = SourceEntry(hash="a", source_url="https://example.com",
                          source_type="web")
        @test e2.source_url == "https://example.com"
        @test e2.source_type == "web"

        # PDF source
        e3 = SourceEntry(hash="b", source_type="pdf",
                          original_file="paper.pdf")
        @test e3.source_type == "pdf"
        @test e3.original_file == "paper.pdf"
    end

end
