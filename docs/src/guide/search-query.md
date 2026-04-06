# [Search & Query](@id search-query)

LLMWiki provides both keyword-based search and LLM-powered question answering.

## Search

The [`search_wiki`](@ref) function supports three search methods:

### BM25 Full-Text Search

The default search method. Uses the [Okapi BM25](https://en.wikipedia.org/wiki/Okapi_BM25)
ranking algorithm for fast, dependency-free keyword search.

```julia
results = search_wiki(config, "memory safety"; method=:bm25)
for r in results
    println("$(r.title) ($(r.slug)) — score: $(round(r.score, digits=3))")
    println("  $(r.snippet)")
end
```

BM25 search works by:
1. Building an in-memory index of all wiki pages (`LLMWiki.build_bm25_index`)
2. Tokenizing the query (lowercasing, stopword removal, markdown stripping)
3. Scoring each document using BM25 term frequency × inverse document frequency
4. Returning the top-k results with snippets

You can also use [`bm25_search`](@ref) directly on a pre-built index:

```julia
index = LLMWiki.build_bm25_index(config)
results = bm25_search(index, "ownership model"; top_k=5)
```

### Semantic Search

Vector-based semantic search using embeddings. Requires the [Mem0.jl extension](@ref extensions):

```julia
using LLMWiki, Mem0
results = search_wiki(config, "memory safety"; method=:semantic)
```

Semantic search embeds the query and all wiki pages, then ranks by cosine similarity.
Results with similarity below `config.similarity_threshold` are filtered out.

### Hybrid Search

Combines BM25 and semantic results using Reciprocal Rank Fusion (RRF):

```julia
using LLMWiki, Mem0
results = search_wiki(config, "memory safety"; method=:hybrid)
```

RRF merges ranked lists from both methods using the formula:

```
score(d) = Σ 1/(k + rank_i(d))
```

where `k=60` is a standard smoothing constant. This ensures that documents ranked highly
by either method appear near the top, while documents ranked highly by both methods
are boosted further.

If semantic search is unavailable, hybrid search falls back to BM25-only.

### Search Parameters

- `top_k` — Number of results to return (default: `config.search_top_k`, which is 10)
- `method` — `:bm25`, `:semantic`, or `:hybrid`

Each result is a [`SearchResult`](@ref) with fields: `slug`, `title`, `score`, and `snippet`.

## Query Engine

The [`query_wiki`](@ref) function implements a two-step retrieval-augmented generation (RAG) pipeline:

### Step 1: Page Selection

The wiki index is presented to the LLM, which selects the most relevant pages
for the question (up to `config.query_page_limit` pages).

### Step 2: Answer Synthesis

The selected pages are loaded and sent to the LLM along with the question.
The LLM synthesizes a comprehensive answer with `[[wikilink]]` citations back
to the source pages.

```julia
# Basic query
answer = query_wiki(config, "How does Rust handle memory safety?")
println(answer)
```

### Saving Query Results

Pass `save=true` to persist the answer as a query page in `wiki/queries/`:

```julia
answer = query_wiki(config, "Compare Rust and C++ memory models"; save=true)
```

Saved queries:
- Appear in the wiki index
- Can be found by search
- Have their own frontmatter with `page_type: query`
- Track which pages were used as sources
