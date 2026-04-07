using Test
using LLMWiki

@testset "Ingest" begin
    @testset "ingest! with markdown file" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # Create a source markdown file outside sources dir
            src_file = joinpath(dir, "my_doc.md")
            write(src_file, "# My Document\n\nSome content here.")

            result = ingest!(cfg, src_file)
            @test result == "my_doc.md"
            @test isfile(joinpath(cfg.sources_dir, "my_doc.md"))
            @test read(joinpath(cfg.sources_dir, "my_doc.md"), String) == "# My Document\n\nSome content here."
        end
    end

    @testset "ingest! with text file" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            src_file = joinpath(dir, "notes.txt")
            write(src_file, "Plain text notes.")

            result = ingest!(cfg, src_file)
            @test result == "notes.md"  # .txt → .md
            @test isfile(joinpath(cfg.sources_dir, "notes.md"))
        end
    end

    @testset "ingest! with same-dir file (realpath fix)" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # Create file directly in sources dir
            src_file = joinpath(cfg.sources_dir, "already_here.md")
            write(src_file, "# Already in sources")

            # Should not error (the realpath check prevents self-copy)
            result = ingest!(cfg, src_file)
            @test result == "already_here.md"
            @test isfile(src_file)
            @test read(src_file, String) == "# Already in sources"
        end
    end

    @testset "ingest! with custom filename" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            src_file = joinpath(dir, "original.md")
            write(src_file, "Content")

            result = ingest!(cfg, src_file; filename="custom_name.md")
            @test result == "custom_name.md"
            @test isfile(joinpath(cfg.sources_dir, "custom_name.md"))
        end
    end

    @testset "ingest! — non-existent file errors" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)
            @test_throws Exception ingest!(cfg, joinpath(dir, "does_not_exist.md"))
        end
    end

    @testset "ingest_batch!" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            files = String[]
            for i in 1:3
                fpath = joinpath(dir, "doc$i.md")
                write(fpath, "# Document $i")
                push!(files, fpath)
            end

            results = LLMWiki.ingest_batch!(cfg, files)
            @test length(results) == 3
            @test "doc1.md" in results
            @test "doc2.md" in results
            @test "doc3.md" in results
            for r in results
                @test isfile(joinpath(cfg.sources_dir, r))
            end
        end
    end

    @testset "_build_ingested_source_markdown escapes YAML-sensitive fields" begin
        content = LLMWiki._build_ingested_source_markdown(
            "Body text";
            title="Rust: The Book",
            source_type="web",
            source_url="https://example.com/article?x=1&y=2",
            source_file="original:file.pdf",
        )

        meta, body = parse_frontmatter(content)
        raw = LLMWiki.parse_frontmatter_data(content)

        @test meta.title == "Rust: The Book"
        @test body == "Body text"
        @test raw["source_type"] == "web"
        @test raw["source_url"] == "https://example.com/article?x=1&y=2"
        @test raw["source_file"] == "original:file.pdf"
    end
end
