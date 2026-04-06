using Test
using LLMWiki

@testset "Frontmatter" begin
    @testset "parse_frontmatter — valid YAML" begin
        content = """---
title: "Test Page"
summary: "A test summary"
sources:
  - "file1.md"
  - "file2.md"
tags:
  - "julia"
  - "test"
orphaned: false
page_type: concept
created_at: "2024-01-01T00:00:00"
updated_at: "2024-06-15T12:00:00"
---
# Body Content

This is the body."""

        meta, body = parse_frontmatter(content)
        @test meta.title == "Test Page"
        @test meta.summary == "A test summary"
        @test meta.sources == ["file1.md", "file2.md"]
        @test meta.tags == ["julia", "test"]
        @test meta.orphaned == false
        @test meta.page_type == LLMWiki.CONCEPT
        @test meta.created_at == "2024-01-01T00:00:00"
        @test meta.updated_at == "2024-06-15T12:00:00"
        @test occursin("Body Content", body)
        @test occursin("This is the body.", body)
    end

    @testset "parse_frontmatter — no frontmatter" begin
        content = "Just some plain text without frontmatter."
        meta, body = parse_frontmatter(content)
        @test meta.title == ""
        @test body == content
    end

    @testset "parse_frontmatter — empty content" begin
        meta, body = parse_frontmatter("")
        @test meta.title == ""
        @test body == ""
    end

    @testset "parse_frontmatter — unclosed frontmatter" begin
        content = "---\ntitle: \"Oops\"\nNo closing delimiter"
        meta, body = parse_frontmatter(content)
        @test meta.title == ""
        @test body == content
    end

    @testset "PageType handling" begin
        for (type_str, expected) in [
            ("concept", LLMWiki.CONCEPT),
            ("entity", LLMWiki.ENTITY),
            ("query", LLMWiki.QUERY_PAGE),
            ("overview", LLMWiki.OVERVIEW),
        ]
            content = """---
title: "Type Test"
page_type: $type_str
---
Body"""
            meta, _ = parse_frontmatter(content)
            @test meta.page_type == expected
        end
    end

    @testset "write_frontmatter — single arg (meta only)" begin
        meta = PageMeta(
            title="My Page",
            summary="A summary",
            sources=["a.md"],
            tags=["tag1"],
            created_at="2024-01-01",
            updated_at="2024-01-02",
        )
        fm = write_frontmatter(meta)
        @test startswith(fm, "---\n")
        @test endswith(fm, "\n---")
        @test occursin("title: \"My Page\"", fm)
        @test occursin("summary: \"A summary\"", fm)
        @test occursin("- \"a.md\"", fm)
        @test occursin("- \"tag1\"", fm)
        @test occursin("page_type: concept", fm)
        @test occursin("created_at: \"2024-01-01\"", fm)
        @test !occursin("orphaned:", fm)  # false by default, not written
    end

    @testset "write_frontmatter — two args (meta + body)" begin
        meta = PageMeta(title="Test", created_at="2024-01-01", updated_at="2024-01-01")
        full = write_frontmatter(meta, "Hello world")
        @test occursin("---", full)
        @test occursin("title: \"Test\"", full)
        @test occursin("Hello world", full)
    end

    @testset "build_page" begin
        meta = PageMeta(title="Built Page", created_at="2024-01-01", updated_at="2024-01-01")
        page = LLMWiki.build_page(meta, "Some body text.")
        @test startswith(page, "---\n")
        @test occursin("title: \"Built Page\"", page)
        @test occursin("Some body text.", page)
        @test endswith(page, "\n")
    end

    @testset "Roundtrip: parse → write → parse" begin
        meta_orig = PageMeta(
            title="Roundtrip Test",
            summary="Testing roundtrip",
            sources=["source1.md", "source2.md"],
            tags=["tag-a", "tag-b"],
            orphaned=true,
            page_type=LLMWiki.ENTITY,
            created_at="2024-03-15T10:00:00",
            updated_at="2024-03-15T12:00:00",
        )
        body_orig = "# Content\n\nThis is the body."

        page = LLMWiki.build_page(meta_orig, body_orig)
        meta_parsed, body_parsed = parse_frontmatter(page)

        @test meta_parsed.title == meta_orig.title
        @test meta_parsed.summary == meta_orig.summary
        @test meta_parsed.sources == meta_orig.sources
        @test meta_parsed.tags == meta_orig.tags
        @test meta_parsed.orphaned == meta_orig.orphaned
        @test meta_parsed.page_type == meta_orig.page_type
        @test meta_parsed.created_at == meta_orig.created_at
        @test meta_parsed.updated_at == meta_orig.updated_at
        @test occursin("This is the body.", body_parsed)
    end

    @testset "Edge cases — special chars in title" begin
        meta = PageMeta(title="C++ Templates & \"Generics\"", created_at="2024-01-01", updated_at="2024-01-01")
        fm = write_frontmatter(meta)
        @test occursin("C++ Templates", fm)

        # Roundtrip with special chars
        page = LLMWiki.build_page(meta, "body")
        meta2, _ = parse_frontmatter(page)
        @test meta2.title == "C++ Templates & \"Generics\""
    end

    @testset "Edge cases — empty sources and tags" begin
        meta = PageMeta(title="Empty Lists", created_at="2024-01-01", updated_at="2024-01-01")
        fm = write_frontmatter(meta)
        @test !occursin("sources:", fm)
        @test !occursin("tags:", fm)
    end
end
