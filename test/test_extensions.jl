using Test
using AgentFramework
using LLMWiki
using SQLite

const _semantic_search_test_calls = Ref(0)

function LLMWiki.semantic_search(config::LLMWiki.WikiConfig, query::String; top_k::Int=0)
    _semantic_search_test_calls[] += 1
    return [
        LLMWiki.SearchResult(
            slug="semantic-page",
            title="Semantic Page",
            score=0.99,
            snippet="semantic result",
        ),
    ]
end

@testset "Extension Integration" begin
    @testset "search_wiki delegates to semantic_search" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            _semantic_search_test_calls[] = 0

            semantic = search_wiki(cfg, "semantic query"; method=:semantic)
            hybrid = search_wiki(cfg, "semantic query"; method=:hybrid)

            @test _semantic_search_test_calls[] >= 2
            @test length(semantic) == 1
            @test semantic[1].slug == "semantic-page"
            @test !isempty(hybrid)
            @test hybrid[1].slug == "semantic-page"
        end
    end

    @testset "SQLite state backend roundtrip" begin
        mktempdir() do dir
            cfg = default_config(dir)
            cfg.state_backend = :sqlite
            init_wiki(cfg)

            state = WikiState(
                version=2,
                sources=Dict(
                    "source.md" => SourceEntry(
                        hash="abc123",
                        concepts=["concept-a"],
                        compiled_at="2026-04-06T00:00:00",
                        source_url="https://example.com/source",
                        source_type="web",
                        original_file="source.html",
                    ),
                ),
                frozen_slugs=["frozen-slug"],
                index_hash="index-hash",
            )

            save_state(cfg, state)

            @test !isfile(cfg.state_file)
            @test isfile(joinpath(cfg.state_dir, "state.db"))

            loaded = load_state(cfg)
            @test loaded.version == 2
            @test loaded.index_hash == "index-hash"
            @test loaded.frozen_slugs == ["frozen-slug"]
            @test loaded.sources["source.md"].source_url == "https://example.com/source"
            @test loaded.sources["source.md"].source_type == "web"
            @test loaded.sources["source.md"].original_file == "source.html"

            save_state(cfg, WikiState())
            emptied = load_state(cfg)
            @test isempty(emptied.sources)
        end
    end

    @testset "Azure OpenAI client creation" begin
        mktempdir() do dir
            cfg = default_config(dir)
            cfg.provider = :azure
            cfg.model = "gpt-4o"
            cfg.api_url = "https://example.openai.azure.com"

            withenv("AZURE_OPENAI_API_KEY" => "test-key", "AZURE_OPENAI_API_VERSION" => "2024-10-21") do
                request = LLMWiki._build_chat_request(
                    cfg,
                    "system prompt",
                    "user prompt";
                    temperature=0.2,
                    max_tokens=512,
                )
                @test request.url == "https://example.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21"
                @test ("api-key" => "test-key") in request.headers
                @test request.body["max_tokens"] == 512
                @test request.body["messages"][1]["role"] == "system"
            end
        end
    end

    @testset "AgentFramework integration extension" begin
        mktempdir() do dir
            cfg = default_config(dir)
            agent = create_wiki_agent(cfg)
            @test agent isa AgentFramework.Agent
            @test agent.name == "WikiAgent"
            @test length(agent.tools) == 7
        end
    end
end
