module LLMWiki

using Dates
using UUIDs
using SHA
using Logging
using Markdown: Markdown
using FileWatching
using JSON3
using HTTP
using YAML
using Gumbo
using Cascadia
using StringDistances
using PDFIO
using AgentFramework

# Core types and configuration
include("types.jl")
include("config.jl")

# Markdown utilities
include("frontmatter.jl")
include("markdown_utils.jl")

# State management
include("state.jl")
include("hasher.jl")

# Operation log
include("log.jl")

# Source ingestion
include("ingest/ingest.jl")

# LLM prompts
include("prompts/extract.jl")
include("prompts/generate.jl")
include("prompts/query.jl")
include("prompts/lint.jl")

# Compilation pipeline
include("compiler/deps.jl")
include("compiler/extract.jl")
include("compiler/generate.jl")
include("compiler/orphan.jl")
include("compiler/resolver.jl")
include("compiler/indexgen.jl")
include("compiler/compiler.jl")

# Search
include("search/bm25.jl")
include("search/search.jl")

# Query engine
include("query.jl")

# Maintenance
include("lint.jl")
include("watch.jl")

# AgentFramework integration
include("agent.jl")

# Exports — Types
export WikiConfig, WikiState, SourceEntry, ExtractedConcept, PageMeta
export ChangeStatus, NEW, CHANGED, UNCHANGED, DELETED
export SearchResult, LintIssue, LintSeverity, INFO, WARNING, ERROR_SEVERITY

# Exports — Core operations
export compile!, ingest!, query_wiki, lint_wiki, watch_wiki
export init_wiki, wiki_status

# Exports — Search
export search_wiki, bm25_search

# Exports — Utilities
export parse_frontmatter, write_frontmatter, slugify
export load_state, save_state, detect_changes

# Exports — Agent
export create_wiki_agent

# Exports — Config
export load_config, save_config, default_config, resolve_paths!

# Extension stubs — overridden when extensions are loaded
"""
    semantic_search(config::WikiConfig, query::String; top_k::Int=10) -> Vector{SearchResult}

Semantic vector search over wiki pages. Requires `using LLMWiki, Mem0`.
"""
function semantic_search end

"""
    load_state_sqlite(config::WikiConfig) -> WikiState

Load wiki state from SQLite. Requires `using LLMWiki, SQLite`.
"""
function load_state_sqlite end

"""
    save_state_sqlite(config::WikiConfig, state::WikiState)

Save wiki state to SQLite. Requires `using LLMWiki, SQLite`.
"""
function save_state_sqlite end

end # module
