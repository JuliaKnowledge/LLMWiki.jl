# LLMWiki.jl

*An LLM-maintained, incrementally-compiled knowledge base that compounds over time.*

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaknowledge.github.io/LLMWiki.jl/dev)

LLMWiki.jl is a Julia implementation of [Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern.
Feed raw sources — markdown files, PDFs, or web pages — into the wiki and an LLM automatically
extracts concepts, generates encyclopedia-style articles, cross-links them with `[[wikilinks]]`,
and keeps everything up to date as sources change.

Built on [AgentFramework.jl](https://github.com/JuliaKnowledge/AgentFramework.jl) for LLM orchestration.

## Key Features

- **Incremental compilation** — only recompiles sources that changed (SHA-256 change detection)
- **Cross-source dependencies** — when two sources share a concept, changing one triggers recompilation of both
- **Two-phase pipeline** — Phase 1 extracts all concepts, Phase 2 generates pages (eliminates order-dependence)
- **Bidirectional wikilinks** — automatic `[[wikilink]]` insertion with fuzzy title matching
- **BM25 search** — full-text search over generated wiki pages
- **Lint engine** — detects broken links, orphaned pages, empty content, stale references
- **Multiple providers** — Ollama, OpenAI, Azure AI via AgentFramework.jl
- **Interactive agent** — chat with your wiki using [`create_wiki_agent`](@ref)
- **Extensions** — optional [Mem0.jl](@ref extensions) (semantic search), [SQLite](@ref extensions) (state backend), [RDFLib.jl](@ref extensions) (knowledge graph)

## Quick Start

```julia
using LLMWiki

# Initialize a new wiki
config = default_config("my-wiki")
config.model = "qwen3:8b"
init_wiki(config)

# Add sources and compile
ingest!(config, "path/to/article.md")
compile!(config)

# Search and query
results = search_wiki(config, "memory safety"; method=:bm25)
answer = query_wiki(config, "How does Rust handle memory safety?")
```

See the [Getting Started](@ref getting-started) guide for a full walkthrough.

## Documentation Overview

```@contents
Pages = [
    "guide/getting-started.md",
    "guide/configuration.md",
    "guide/compilation.md",
    "guide/search-query.md",
    "guide/extensions.md",
    "guide/architecture.md",
    "api/types.md",
    "api/operations.md",
    "api/utilities.md",
]
Depth = 1
```

## License

MIT — Copyright 2026 Simon Frost
