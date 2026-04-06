# [Extensions](@id extensions)

LLMWiki uses Julia's package extension mechanism to provide optional integrations.
Extensions are loaded automatically when you import the relevant package alongside LLMWiki.

## How Extensions Work

Julia 1.9+ supports [package extensions](https://pkgdocs.julialang.org/v1/creating-packages/#Conditional-loading-of-code-in-packages-(Extensions)):
code that is loaded only when specific "weak dependencies" are available. LLMWiki defines
extension stubs in the main module that are overridden when extensions load.

For example, `semantic_search` is defined as an empty stub:

```julia
function semantic_search end  # overridden by LLMWikiMem0Ext
```

When you do `using LLMWiki, Mem0`, Julia automatically loads `ext/LLMWikiMem0Ext.jl`,
which provides the real implementation.

## Mem0.jl — Semantic Search

Adds vector-based semantic search using [Mem0.jl](https://github.com/svilupp/Mem0.jl)
embeddings.

### Setup

```julia
using Pkg
Pkg.add("Mem0")

using LLMWiki, Mem0
```

### Usage

```julia
# Semantic search
results = search_wiki(config, "memory management"; method=:semantic)

# Hybrid search (BM25 + semantic with RRF fusion)
results = search_wiki(config, "memory management"; method=:hybrid)
```

The extension uses `config.embedding_model` (default: `"nomic-embed-text"`) and
respects `config.similarity_threshold` (default: `0.7`) to filter low-confidence matches.

For Ollama, the embedding endpoint is derived from `config.api_url`.
For OpenAI, set `OPENAI_API_KEY` in your environment.

## SQLite — State Persistence

Replaces the default JSON-based state storage with a SQLite database, providing
durable, queryable state.

### Setup

```julia
using Pkg
Pkg.add("SQLite")

using LLMWiki, SQLite
```

### What Changes

When loaded, the extension provides:

- `load_state_sqlite(config)` — Load [`WikiState`](@ref) from `state.db`
- `save_state_sqlite(config, state)` — Persist state to `state.db`

The SQLite database is stored at `.llmwiki/state.db` and contains tables:

| Table | Purpose |
|:------|:--------|
| `sources` | Per-file hash, concepts list, and compilation timestamp |
| `wiki_meta` | Key-value metadata (index hash, version) |
| `frozen_slugs` | Slugs shared between deleted and surviving sources |

### Benefits

- **Durability** — ACID transactions protect against corruption
- **Queryability** — Run SQL queries directly against wiki state
- **Concurrency** — SQLite handles concurrent readers safely

## RDFLib.jl — Knowledge Graphs

Planned integration with [RDFLib.jl](https://github.com/JuliaKnowledge/RDFLib.jl) for
exporting the wiki as a knowledge graph.

### Planned Features

- Export wiki concepts as RDF triples (concepts as resources, wikilinks as predicates)
- SPARQL queries over the wiki knowledge graph
- PROV ontology for source provenance tracking
- SHACL validation for wiki page schemas

!!! note
    The RDFLib extension is currently a stub. Check the repository for updates.

## WikiAgent — AgentFramework.jl Integration

LLMWiki includes a built-in agent that wraps wiki operations as tools for an
LLM-powered conversational interface.

```julia
using LLMWiki, AgentFramework

config = load_config("my-wiki")
agent = create_wiki_agent(config)
```

The agent provides these tools:

| Tool | Description |
|:-----|:------------|
| `wiki_ingest(path_or_url)` | Ingest a source file or URL |
| `wiki_compile()` | Run the compilation pipeline |
| `wiki_query(question)` | Query the wiki knowledge base |
| `wiki_search(query)` | Search pages by keyword |
| `wiki_lint()` | Run health checks |
| `wiki_read(slug)` | Read a specific wiki page |
| `wiki_status()` | Show wiki statistics |

See [`create_wiki_agent`](@ref) for the full API.
