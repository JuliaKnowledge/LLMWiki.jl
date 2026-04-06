using Test
using LLMWiki

@testset "Search" begin
    @testset "BM25Index construction" begin
        idx = LLMWiki.BM25Index()
        @test isempty(idx.docs)
        @test isempty(idx.doc_lengths)
        @test idx.avg_doc_length == 0.0
        @test isempty(idx.term_doc_freq)
        @test idx.total_docs == 0
        @test idx.k1 == 1.5
        @test idx.b == 0.75
    end

    @testset "tokenize" begin
        tokens = LLMWiki.tokenize("Machine learning is a branch of artificial intelligence.")
        @test "machine" in tokens
        @test "learning" in tokens
        @test "branch" in tokens
        @test "artificial" in tokens
        @test "intelligence" in tokens
        # Stopwords removed
        @test "is" ∉ tokens
        @test "a" ∉ tokens
        @test "of" ∉ tokens

        # Empty input
        @test isempty(LLMWiki.tokenize(""))

        # Code blocks stripped
        tokens2 = LLMWiki.tokenize("```\ncode here\n```\nActual content words")
        @test "actual" in tokens2
        @test "content" in tokens2
        @test "words" in tokens2
    end

    @testset "build_bm25_index" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "machine-learning.md"), """---
title: "Machine Learning"
page_type: concept
---
# Machine Learning

Machine learning is a subset of artificial intelligence that enables systems to learn from data.""")

            write(joinpath(cfg.concepts_dir, "neural-networks.md"), """---
title: "Neural Networks"
page_type: concept
---
# Neural Networks

Neural networks are computing systems inspired by biological networks. They use machine learning.""")

            index = LLMWiki.build_bm25_index(cfg)
            @test index.total_docs == 2
            @test haskey(index.docs, "machine-learning")
            @test haskey(index.docs, "neural-networks")
            @test index.avg_doc_length > 0
        end
    end

    @testset "build_bm25_index — skips orphaned pages" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "orphan.md"), """---
title: "Orphan"
orphaned: true
page_type: concept
---
Should be skipped.""")

            write(joinpath(cfg.concepts_dir, "active.md"), """---
title: "Active"
page_type: concept
---
Active page content.""")

            index = LLMWiki.build_bm25_index(cfg)
            @test index.total_docs == 1
            @test haskey(index.docs, "active")
            @test !haskey(index.docs, "orphan")
        end
    end

    @testset "bm25_search — returns relevant results" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "machine-learning.md"), """---
title: "Machine Learning"
page_type: concept
---
# Machine Learning

Machine learning algorithms learn patterns from training data to make predictions.""")

            write(joinpath(cfg.concepts_dir, "database-systems.md"), """---
title: "Database Systems"
page_type: concept
---
# Database Systems

Database systems manage structured data storage and retrieval using SQL queries.""")

            index = LLMWiki.build_bm25_index(cfg)
            results = LLMWiki.bm25_search(index, "machine learning algorithms")
            @test length(results) >= 1
            @test results[1].slug == "machine-learning"
            @test results[1].score > 0.0
            @test !isempty(results[1].title)
        end
    end

    @testset "bm25_search — empty query" begin
        idx = LLMWiki.BM25Index()
        results = LLMWiki.bm25_search(idx, "")
        @test isempty(results)
    end

    @testset "bm25_search — stopword-only query" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "test.md"), """---
title: "Test"
page_type: concept
---
Some content here.""")

            index = LLMWiki.build_bm25_index(cfg)
            results = LLMWiki.bm25_search(index, "the is a")
            @test isempty(results)
        end
    end

    @testset "search_wiki with :bm25 method" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "julia-lang.md"), """---
title: "Julia Language"
page_type: concept
---
# Julia Language

Julia is a high-performance programming language for numerical computing.""")

            results = search_wiki(cfg, "Julia programming language"; method=:bm25)
            @test length(results) >= 1
            @test results[1].slug == "julia-lang"
        end
    end

    @testset "search_wiki — empty wiki" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)
            results = search_wiki(cfg, "anything"; method=:bm25)
            @test isempty(results)
        end
    end
end
