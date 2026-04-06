# [Getting Started](@id getting-started)

This guide walks you through creating your first LLM-maintained wiki.

## Prerequisites

- **Julia 1.9+** (1.10+ recommended)
- An **LLM backend** — one of:
  - [Ollama](https://ollama.ai) (local, free) — easiest to get started
  - [OpenAI](https://platform.openai.com/) — requires an API key
  - [Azure AI](https://azure.microsoft.com/en-us/products/ai-services/) — enterprise option

### Setting up Ollama

```bash
# Install Ollama (macOS)
brew install ollama

# Pull a model
ollama pull qwen3:8b
```

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaKnowledge/LLMWiki.jl")
```

## Creating Your First Wiki

### 1. Initialize

```julia
using LLMWiki

# Create a default config rooted at ./my-wiki
config = default_config("my-wiki")
config.model = "qwen3:8b"  # or "gpt-4o" for OpenAI

# Create the directory structure
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
    └── state.json      # Compilation state
```

### 2. Add Sources

You can ingest local files (Markdown, PDF) and web pages:

```julia
# Ingest a local Markdown file
ingest!(config, "path/to/article.md")

# Ingest a PDF
ingest!(config, "path/to/paper.pdf")

# Ingest a web page (fetched and converted to Markdown)
ingest!(config, "https://example.com/article")

# Batch ingest
ingest_batch!(config, [
    "file1.md",
    "file2.pdf",
    "https://example.com/page",
])
```

Each call copies the source into `sources/` and returns the resulting filename.

### 3. Compile

Run the compilation pipeline to extract concepts and generate wiki pages:

```julia
result = compile!(config)
# (compiled = 6, skipped = 0, deleted = 0)
```

The compiler will:
1. Detect which sources changed since the last compile
2. Extract key concepts from changed sources via LLM
3. Generate or update wiki pages for each concept
4. Resolve `[[wikilinks]]` between pages
5. Regenerate the index

### 4. Search

```julia
# Full-text BM25 search
results = search_wiki(config, "memory safety"; method=:bm25)
for r in results
    println("$(r.slug) (score: $(round(r.score, digits=3)))")
end
```

### 5. Query

Use the two-step RAG query engine to ask questions:

```julia
answer = query_wiki(config, "How does Rust handle memory safety?")
println(answer)

# Save the answer as a query page
answer = query_wiki(config, "Compare Rust and C++ memory models"; save=true)
```

### 6. Lint

Check your wiki for structural issues:

```julia
issues = lint_wiki(config)
for issue in issues
    println("[$(issue.severity)] $(issue.page): $(issue.message)")
end
```

### 7. Watch for Changes

Auto-recompile when sources change:

```julia
watch_wiki(config) do result
    println("Compiled $(result.compiled) pages")
end
# Press Ctrl-C to stop
```

## Full Worked Example

```julia
using LLMWiki

# Setup
config = default_config("rust-wiki")
config.model = "qwen3:8b"
init_wiki(config)

# Add some sources about Rust
ingest!(config, "https://doc.rust-lang.org/book/ch04-01-what-is-ownership.html")
ingest!(config, "https://doc.rust-lang.org/book/ch10-02-traits.html")

# Compile the wiki
result = compile!(config)
println("Generated $(result.compiled) pages")

# Check wiki health
issues = lint_wiki(config)
println("Found $(length(issues)) issues")

# Search
results = search_wiki(config, "ownership")
for r in results
    println("  $(r.title) — $(r.score)")
end

# Query
answer = query_wiki(config, "What is Rust's ownership model?")
println(answer)

# Check status
stats = wiki_status(config)
println("$(stats.page_count) pages from $(stats.source_count) sources")
```

## Next Steps

- [Configuration](@ref configuration) — customize LLM settings, paths, and tuning parameters
- [Compilation Pipeline](@ref compilation) — understand the 12-step pipeline
- [Search & Query](@ref search-query) — BM25, semantic, and hybrid search
- [Extensions](@ref extensions) — add semantic search, SQLite persistence, or knowledge graphs
