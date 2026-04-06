# ──────────────────────────────────────────────────────────────────────────────
# search/search.jl — Unified search interface for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────

"""
    search_wiki(config::WikiConfig, query::String;
                method::Symbol=:bm25, top_k::Int=0) -> Vector{SearchResult}

Unified search over wiki pages.

# Methods
- `:bm25` — BM25 keyword search (default, no external dependencies).
- `:semantic` — Semantic vector search (requires Mem0 extension).
- `:hybrid` — Combination of BM25 and semantic scores.

`top_k` defaults to `config.search_top_k` when 0.
"""
function search_wiki(config::WikiConfig, query::String;
                     method::Symbol=:bm25, top_k::Int=0)::Vector{SearchResult}
    resolve_paths!(config)
    k = top_k > 0 ? top_k : config.search_top_k

    if method == :bm25
        return _search_bm25(config, query; top_k=k)
    elseif method == :semantic
        return _search_semantic(config, query; top_k=k)
    elseif method == :hybrid
        return _search_hybrid(config, query; top_k=k)
    else
        @warn "Unknown search method, falling back to BM25" method=method
        return _search_bm25(config, query; top_k=k)
    end
end

"""
    _search_bm25(config, query; top_k) -> Vector{SearchResult}

Build a BM25 index and search it.  The index is rebuilt on each call;
for repeated searches, consider caching the index externally.
"""
function _search_bm25(config::WikiConfig, query::String; top_k::Int)::Vector{SearchResult}
    index = build_bm25_index(config)
    bm25_search(index, query; top_k=top_k)
end

"""
    _search_semantic(config, query; top_k) -> Vector{SearchResult}

Semantic search stub.  Returns empty results unless the Mem0 extension
is loaded (which overrides this method).
"""
function _search_semantic(config::WikiConfig, query::String; top_k::Int)::Vector{SearchResult}
    @warn "Semantic search requires the Mem0 extension (add Mem0.jl to your project)"
    SearchResult[]
end

"""
    _search_hybrid(config, query; top_k) -> Vector{SearchResult}

Hybrid search combining BM25 and semantic scores via reciprocal rank fusion.
Falls back to BM25-only if semantic search is unavailable.
"""
function _search_hybrid(config::WikiConfig, query::String; top_k::Int)::Vector{SearchResult}
    bm25_results = _search_bm25(config, query; top_k=top_k * 2)
    semantic_results = _search_semantic(config, query; top_k=top_k * 2)

    if isempty(semantic_results)
        return first(bm25_results, top_k)
    end

    # Reciprocal Rank Fusion (RRF)
    rrf_k = 60  # standard RRF constant
    slug_scores = Dict{String,Float64}()
    slug_data   = Dict{String,SearchResult}()

    for (rank, r) in enumerate(bm25_results)
        slug_scores[r.slug] = get(slug_scores, r.slug, 0.0) + 1.0 / (rrf_k + rank)
        slug_data[r.slug] = r
    end
    for (rank, r) in enumerate(semantic_results)
        slug_scores[r.slug] = get(slug_scores, r.slug, 0.0) + 1.0 / (rrf_k + rank)
        if !haskey(slug_data, r.slug)
            slug_data[r.slug] = r
        end
    end

    sorted = sort(collect(slug_scores); by=p -> -p.second)
    results = SearchResult[]
    for (slug, score) in first(sorted, top_k)
        base = slug_data[slug]
        push!(results, SearchResult(
            slug    = slug,
            title   = base.title,
            score   = round(score; digits=4),
            snippet = base.snippet
        ))
    end

    results
end
