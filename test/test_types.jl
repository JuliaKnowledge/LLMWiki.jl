using Test
using LLMWiki
using JSON3

@testset "Types" begin
    @testset "WikiConfig" begin
        cfg = WikiConfig()
        @test cfg.root == "."
        @test cfg.sources_dir == "sources"
        @test cfg.wiki_dir == "wiki"
        @test cfg.concepts_dir == "wiki/concepts"
        @test cfg.queries_dir == "wiki/queries"
        @test cfg.index_file == "wiki/index.md"
        @test cfg.log_file == "wiki/log.md"
        @test cfg.state_dir == ".llmwiki"
        @test cfg.state_file == ".llmwiki/state.json"
        @test cfg.model == "qwen3:8b"
        @test cfg.provider == :ollama
        @test cfg.embedding_model == "nomic-embed-text"
        @test cfg.api_url === nothing
        @test cfg.max_concepts_per_source == 8
        @test cfg.compile_concurrency == 3
        @test cfg.max_related_pages == 5
        @test cfg.query_page_limit == 8
        @test cfg.search_top_k == 10
        @test cfg.similarity_threshold ≈ 0.7

        # Field types
        @test cfg.root isa String
        @test cfg.provider isa Symbol
        @test cfg.max_concepts_per_source isa Int
        @test cfg.similarity_threshold isa Float64
        @test cfg.api_url isa Union{Nothing,String}

        # Construction with kwargs
        cfg2 = WikiConfig(model="gpt-4", provider=:openai, search_top_k=5)
        @test cfg2.model == "gpt-4"
        @test cfg2.provider == :openai
        @test cfg2.search_top_k == 5
    end

    @testset "WikiState" begin
        state = WikiState()
        @test state.version == 1
        @test state.sources isa Dict{String,SourceEntry}
        @test isempty(state.sources)
        @test state.frozen_slugs isa Vector{String}
        @test isempty(state.frozen_slugs)
        @test state.index_hash == ""

        # Construction with values
        entry = SourceEntry(hash="abc123", concepts=["concept-a"], compiled_at="2024-01-01")
        state2 = WikiState(
            version=2,
            sources=Dict("file.md" => entry),
            frozen_slugs=["frozen-page"],
            index_hash="def456"
        )
        @test state2.version == 2
        @test haskey(state2.sources, "file.md")
        @test state2.frozen_slugs == ["frozen-page"]
        @test state2.index_hash == "def456"

        # JSON3 roundtrip
        json = JSON3.write(state2)
        state3 = JSON3.read(json, WikiState)
        @test state3.version == state2.version
        @test state3.index_hash == state2.index_hash
        @test state3.frozen_slugs == state2.frozen_slugs
    end

    @testset "SourceEntry" begin
        entry = SourceEntry()
        @test entry.hash == ""
        @test entry.concepts == String[]
        @test entry.compiled_at == ""

        entry2 = SourceEntry(hash="abc", concepts=["c1", "c2"], compiled_at="2024-01-01")
        @test entry2.hash == "abc"
        @test entry2.concepts == ["c1", "c2"]

        # JSON3 roundtrip
        json = JSON3.write(entry2)
        entry3 = JSON3.read(json, SourceEntry)
        @test entry3.hash == entry2.hash
        @test entry3.concepts == entry2.concepts
        @test entry3.compiled_at == entry2.compiled_at
    end

    @testset "ExtractedConcept" begin
        ec = ExtractedConcept()
        @test ec.concept == ""
        @test ec.summary == ""
        @test ec.is_new == true

        ec2 = ExtractedConcept(concept="Machine Learning", summary="A branch of AI", is_new=false)
        @test ec2.concept == "Machine Learning"
        @test ec2.is_new == false

        # JSON3 roundtrip
        json = JSON3.write(ec2)
        ec3 = JSON3.read(json, ExtractedConcept)
        @test ec3.concept == ec2.concept
        @test ec3.summary == ec2.summary
        @test ec3.is_new == ec2.is_new
    end

    @testset "PageMeta" begin
        pm = PageMeta()
        @test pm.title == ""
        @test pm.summary == ""
        @test pm.sources == String[]
        @test pm.tags == String[]
        @test pm.orphaned == false
        @test pm.page_type == LLMWiki.CONCEPT
        @test !isempty(pm.created_at)
        @test !isempty(pm.updated_at)

        pm2 = PageMeta(
            title="Test Page",
            summary="A test",
            sources=["src.md"],
            tags=["test"],
            orphaned=true,
            page_type=LLMWiki.OVERVIEW,
        )
        @test pm2.title == "Test Page"
        @test pm2.orphaned == true
        @test pm2.page_type == LLMWiki.OVERVIEW
    end

    @testset "ChangeStatus enum" begin
        @test NEW isa ChangeStatus
        @test CHANGED isa ChangeStatus
        @test UNCHANGED isa ChangeStatus
        @test DELETED isa ChangeStatus
        # Ensure they are distinct
        @test NEW != CHANGED
        @test CHANGED != UNCHANGED
        @test UNCHANGED != DELETED
    end

    @testset "SourceChange" begin
        sc = LLMWiki.SourceChange(file="test.md", status=NEW)
        @test sc.file == "test.md"
        @test sc.status == NEW

        sc2 = LLMWiki.SourceChange(file="old.md", status=DELETED)
        @test sc2.status == DELETED
    end

    @testset "SearchResult" begin
        sr = SearchResult(slug="ml-basics", title="ML Basics", score=0.95)
        @test sr.slug == "ml-basics"
        @test sr.title == "ML Basics"
        @test sr.score ≈ 0.95
        @test sr.snippet == ""

        sr2 = SearchResult(slug="dl", title="Deep Learning", score=0.8, snippet="Neural networks...")
        @test sr2.snippet == "Neural networks..."
    end

    @testset "LintIssue" begin
        li = LintIssue(
            severity=WARNING,
            category=:broken_link,
            page="test-page",
            message="Broken link found",
            suggestion="Fix it"
        )
        @test li.severity == WARNING
        @test li.category == :broken_link
        @test li.page == "test-page"
        @test li.message == "Broken link found"
        @test li.suggestion == "Fix it"

        li2 = LintIssue(severity=ERROR_SEVERITY, category=:error, page="p", message="err")
        @test li2.suggestion == ""
    end

    @testset "LintSeverity enum" begin
        @test INFO isa LintSeverity
        @test WARNING isa LintSeverity
        @test ERROR_SEVERITY isa LintSeverity
        @test INFO != WARNING
        @test WARNING != ERROR_SEVERITY
    end
end
