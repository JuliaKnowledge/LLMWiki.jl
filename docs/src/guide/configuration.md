# [Configuration](@id configuration)

LLMWiki is configured through the [`WikiConfig`](@ref) struct, which can be set programmatically or persisted as a YAML file.

## WikiConfig Fields

| Field | Type | Default | Description |
|:------|:-----|:--------|:------------|
| `root` | `String` | `"."` | Root directory for the wiki |
| `sources_dir` | `String` | `"sources"` | Directory for raw input documents |
| `wiki_dir` | `String` | `"wiki"` | Output directory for generated pages |
| `concepts_dir` | `String` | `"wiki/concepts"` | Directory for concept pages |
| `queries_dir` | `String` | `"wiki/queries"` | Directory for saved query pages |
| `index_file` | `String` | `"wiki/index.md"` | Path to the auto-generated index |
| `log_file` | `String` | `"wiki/log.md"` | Path to the operation log |
| `state_dir` | `String` | `".llmwiki"` | Directory for state and config files |
| `state_file` | `String` | `".llmwiki/state.json"` | Path to the compilation state file |
| `model` | `String` | `"qwen3:8b"` | LLM model name |
| `provider` | `Symbol` | `:ollama` | LLM provider (`:ollama`, `:openai`, `:azure`) |
| `embedding_model` | `String` | `"nomic-embed-text"` | Model for semantic embeddings |
| `api_url` | `Union{Nothing,String}` | `nothing` | Custom API URL (`nothing` = provider default) |
| `max_concepts_per_source` | `Int` | `8` | Maximum concepts extracted per source |
| `compile_concurrency` | `Int` | `3` | Concurrency limit for compilation |
| `max_related_pages` | `Int` | `5` | Related pages loaded as context for generation |
| `query_page_limit` | `Int` | `8` | Max pages selected per query |
| `search_top_k` | `Int` | `10` | Default number of search results |
| `similarity_threshold` | `Float64` | `0.7` | Minimum similarity for semantic search |

## Programmatic Configuration

```julia
using LLMWiki

config = default_config("my-wiki")

# LLM settings
config.model = "qwen3:8b"
config.provider = :ollama
config.api_url = "http://localhost:11434"

# Compilation tuning
config.max_concepts_per_source = 10
config.max_related_pages = 8

# Search
config.search_top_k = 20
config.similarity_threshold = 0.8

# Persist to disk
save_config(config)
```

## YAML Configuration File

Configuration is stored at `.llmwiki/config.yaml`. Only non-default values are written:

```yaml
model: "gpt-4o"
provider: "openai"
max_concepts_per_source: 10
search_top_k: 20
```

### Loading from YAML

```julia
# Load existing config (falls back to defaults if file missing)
config = load_config("my-wiki")
```

## Provider Setup

### Ollama (Local)

```julia
config.provider = :ollama
config.model = "qwen3:8b"
config.api_url = "http://localhost:11434"  # default, can omit
config.embedding_model = "nomic-embed-text"
```

### OpenAI

```julia
config.provider = :openai
config.model = "gpt-4o"
config.embedding_model = "text-embedding-3-small"
# Set OPENAI_API_KEY environment variable
```

### Azure AI

```julia
config.provider = :azure
config.model = "gpt-4o"
config.api_url = "https://your-resource.openai.azure.com/"
# Set AZURE_OPENAI_API_KEY environment variable
```

## Directory Layout

After [`init_wiki`](@ref) creates the structure:

```
my-wiki/                       # config.root
├── sources/                   # config.sources_dir — raw input documents
│   ├── article.md
│   ├── paper.pdf
│   └── webpage.md
├── wiki/                      # config.wiki_dir — generated output
│   ├── concepts/              # config.concepts_dir — concept pages
│   │   ├── machine-learning.md
│   │   ├── neural-networks.md
│   │   └── backpropagation.md
│   ├── queries/               # config.queries_dir — saved query answers
│   │   └── how-does-backprop-work.md
│   ├── index.md               # config.index_file — table of contents
│   └── log.md                 # config.log_file — operation log
└── .llmwiki/                  # config.state_dir — internal state
    ├── config.yaml            # persisted configuration
    ├── state.json             # compilation state (source hashes, concepts)
    └── lock                   # filesystem lock during compilation
```

## Path Resolution

All directory and file paths in `WikiConfig` can be relative or absolute.
Use [`resolve_paths!`](@ref) to make them absolute relative to `config.root`:

```julia
config = WikiConfig(root="my-wiki", sources_dir="sources")
resolve_paths!(config)
# config.sources_dir is now an absolute path like ".../my-wiki/sources"
```

[`default_config`](@ref) and [`init_wiki`](@ref) call `resolve_paths!` automatically.
