# LLMWiki.jl

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaknowledge.github.io/LLMWiki.jl/dev)

A Julia implementation of [Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern — an LLM-maintained, incrementally-compiled knowledge base that compounds over time.

Feed raw sources (markdown, PDFs, web pages) into the wiki and an LLM automatically extracts concepts, generates encyclopedia-style articles, cross-links them with `[[wikilinks]]`, and keeps everything up to date as sources change.

LLMWiki includes built-in provider clients for compilation/query workflows and an
optional [AgentFramework.jl](https://github.com/JuliaKnowledge/AgentFramework.jl)
extension for interactive agents.

## Key Features

- **Incremental compilation** — only recompiles sources that changed (SHA-256 change detection)
- **Cross-source dependencies** — when two sources share a concept, changing one triggers recompilation of both
- **Two-phase pipeline** — Phase 1 extracts all concepts, Phase 2 generates pages (eliminates order-dependence)
- **Bidirectional wikilinks** — automatic `[[wikilink]]` insertion with fuzzy title matching
- **BM25 search** — full-text search over generated wiki pages
- **Lint engine** — detects broken links, orphaned pages, empty content, stale references
- **Multiple providers** — Ollama, OpenAI, Anthropic, and Azure OpenAI
- **Interactive agent** — optional AgentFramework extension via `create_wiki_agent()`
- **Extensions** — optional Mem0.jl (semantic search), SQLite (state backend), RDFLib.jl (knowledge graph)

## Quick Start

### Installation

LLMWiki currently targets **Julia 1.11+**.

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaKnowledge/LLMWiki.jl")
```

### Prerequisites

You need an LLM backend. The easiest option is [Ollama](https://ollama.ai):

```bash
# Install Ollama, then pull a model
ollama pull qwen3:8b
```

### Create a Wiki

```julia
using LLMWiki

# Initialize a new wiki in the current directory
config = default_config("my-wiki")
config.model = "qwen3:8b"
init_wiki(config)
```

This creates:
```
my-wiki/
├── sources/            # Raw input documents (you add these)
├── wiki/
│   ├── concepts/       # LLM-generated concept pages
│   ├── queries/        # Saved query results
│   ├── index.md        # Auto-generated table of contents
│   └── log.md          # Operation log
└── .llmwiki/
    ├── config.yaml     # Wiki configuration
    └── state.json      # Compilation state (or state.db when using SQLite)
```

### Add Sources

```julia
# Ingest a local file
ingest!(config, "path/to/article.md")

# Ingest a PDF
ingest!(config, "path/to/paper.pdf")

# Ingest a web page
ingest!(config, "https://example.com/article")
```

### Compile the Wiki

```julia
# Run the full compilation pipeline
result = compile!(config)
# (compiled = 6, skipped = 0, deleted = 0)
```

The compiler will:
1. Detect which sources changed since the last compile
2. Extract key concepts from changed sources via LLM
3. Generate or update wiki pages for each concept
4. Resolve `[[wikilinks]]` between pages
5. Regenerate the index

### Search

```julia
# Full-text BM25 search
results = search_wiki(config, "memory safety"; method=:bm25)
for r in results
    println("$(r.slug) (score: $(round(r.score, digits=3)))")
end
```

### Query the Wiki

```julia
# Two-step query: page selection → answer synthesis
answer = query_wiki(config, "How does Rust handle memory safety?")
println(answer)
```

### Lint

```julia
# Check wiki health
issues = lint_wiki(config)
for issue in issues
    println("[$(issue.severity)] $(issue.page): $(issue.message)")
end
```

### Interactive Agent (Optional)

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaKnowledge/AgentFramework.jl")

using LLMWiki, AgentFramework

agent = create_wiki_agent(config)
# The agent has tools for searching, querying, compiling, and ingesting
```

## Configuration

All options can be set on the `WikiConfig` struct or in `.llmwiki/config.yaml`:

```julia
config = default_config("my-wiki")

# LLM settings
config.model = "qwen3:8b"          # Model name
config.provider = :ollama          # :ollama, :openai, :anthropic, :azure
config.api_url = "http://localhost:11434"  # Provider URL (nil = default)

# Compilation
config.max_concepts_per_source = 8  # Max concepts extracted per source
config.max_related_pages = 5        # Related pages loaded for context

# Search
config.search_top_k = 10            # Default results per search
config.similarity_threshold = 0.7   # Semantic search threshold

# State backend
config.state_backend = :json        # :json (default) or :sqlite
```

## Architecture

```
Sources (immutable)          Wiki (LLM-generated)         Schema
┌──────────────┐     ┌──────────────────────────┐    ┌──────────┐
│ article.md   │     │ wiki/concepts/            │    │ config   │
│ paper.pdf    │────▶│   rust-lang.md            │    │ state    │
│ website.html │     │   ownership.md            │    │ log      │
└──────────────┘     │   type-system.md          │    └──────────┘
                     │ wiki/index.md             │
                     └──────────────────────────┘
```

**Compilation pipeline** (12 steps):
1. Acquire lock → 2. Load state → 3. SHA-256 change detection → 4. Find affected sources (shared concepts) → 5. Phase 1: Extract concepts → 6. Find late-affected sources → 7. Merge extractions → 8. Phase 2: Generate pages → 9. Handle deletions → 10. Resolve wikilinks → 11. Regenerate index → 12. Save state

## Extensions

### Semantic Search (Mem0.jl)

```julia
using LLMWiki, Mem0
results = search_wiki(config, "memory safety"; method=:semantic)
```

### SQLite State Backend

```julia
using LLMWiki, SQLite

config.state_backend = :sqlite
save_config(config)  # optional, persists the backend choice to config.yaml
```

### Azure OpenAI

```julia
config.provider = :azure
config.model = "my-deployment-name"
config.api_url = "https://your-resource.openai.azure.com"
# Set AZURE_OPENAI_API_KEY
```

## API Reference

### Core Operations

| Function | Description |
|----------|-------------|
| `init_wiki(config)` | Create wiki directory structure |
| `compile!(config)` | Run full compilation pipeline |
| `ingest!(config, path)` | Add a source (file, PDF, or URL) |
| `query_wiki(config, question)` | Ask a question, get a synthesized answer |
| `search_wiki(config, query)` | Search wiki pages (BM25/semantic/hybrid) |
| `lint_wiki(config)` | Check wiki health |
| `watch_wiki(config)` | Auto-recompile on source changes |
| `wiki_status(config)` | Get wiki statistics |

### Configuration

| Function | Description |
|----------|-------------|
| `default_config(root)` | Create config with absolute paths |
| `load_config(root)` | Load config from `.llmwiki/config.yaml` |
| `save_config(config)` | Persist config to YAML |
| `resolve_paths!(config)` | Make all paths absolute |

### Utilities

| Function | Description |
|----------|-------------|
| `parse_frontmatter(content)` | Parse YAML frontmatter → `(PageMeta, body)` |
| `write_frontmatter(meta, body)` | Serialize page with frontmatter |
| `slugify(title)` | Convert title to URL-safe slug |
| `detect_changes(config, state)` | Find changed source files |
| `create_wiki_agent(config)` | Create the optional AgentFramework wiki agent |

## License

MIT — Copyright 2026 Simon Frost
