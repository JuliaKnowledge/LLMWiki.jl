module LLMWikiMem0Ext

using LLMWiki

const Mem0 = Base.root_module(
    Base.PkgId(Base.UUID("111c52c1-a189-4018-bb23-b883ef531b41"), "Mem0"),
)

"""
    LLMWiki.semantic_search(config::LLMWiki.WikiConfig, query::String; top_k::Int=10) -> Vector{LLMWiki.SearchResult}

Semantic search over wiki pages using Mem0.jl embeddings.
Requires the Mem0 extension to be loaded (`using LLMWiki, Mem0`).
"""
function LLMWiki.semantic_search(config::LLMWiki.WikiConfig, query::String; top_k::Int=0)
    top_k = top_k > 0 ? top_k : config.search_top_k

    # Create embedder from Mem0
    embedder = if config.provider == :ollama
        url = something(config.api_url, "http://localhost:11434")
        Mem0.OllamaEmbedding(model=config.embedding_model, base_url=url)
    else
        Mem0.OpenAIEmbedding(model=config.embedding_model)
    end

    # Embed the query
    query_vec = Mem0.embed(embedder, query)

    # Load and embed all wiki pages, compute similarity
    results = LLMWiki.SearchResult[]
    concepts_path = joinpath(config.root, config.concepts_dir)
    isdir(concepts_path) || return results

    for file in readdir(concepts_path)
        endswith(file, ".md") || continue
        content = read(joinpath(concepts_path, file), String)
        meta, body = LLMWiki.parse_frontmatter(content)
        meta.orphaned && continue

        # Embed page content (use title + summary for efficiency)
        page_text = meta.title * " " * meta.summary * " " * first(body, 500)
        page_vec = Mem0.embed(embedder, page_text)

        score = Mem0.cosine_similarity(query_vec, page_vec)
        if score >= config.similarity_threshold
            slug = replace(file, ".md" => "")
            snippet = first(strip(body), 200)
            push!(results, LLMWiki.SearchResult(slug=slug, title=meta.title, score=score, snippet=snippet))
        end
    end

    sort!(results, by=r -> r.score, rev=true)
    return first(results, top_k)
end

end # module
