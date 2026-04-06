# ──────────────────────────────────────────────────────────────────────────────
# types.jl — Core type definitions for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# All structs use Base.@kwdef for keyword construction and Union{Nothing,T}
# for optional fields, following the project's Julia conventions.

# ── Enums ────────────────────────────────────────────────────────────────────

"""Status of a source file relative to the last compiled state."""
@enum ChangeStatus NEW CHANGED UNCHANGED DELETED

"""Severity level for lint findings."""
@enum LintSeverity INFO WARNING ERROR_SEVERITY

"""Type of wiki page."""
@enum PageType CONCEPT ENTITY QUERY_PAGE OVERVIEW

# ── WikiConfig ───────────────────────────────────────────────────────────────

"""
    WikiConfig

Global configuration for a LLMWiki instance.  Controls directory layout,
LLM provider settings, compilation limits, and search parameters.
"""
Base.@kwdef mutable struct WikiConfig
    # Directory layout
    root::String              = "."
    sources_dir::String       = "sources"
    wiki_dir::String          = "wiki"
    concepts_dir::String      = "wiki/concepts"
    queries_dir::String       = "wiki/queries"
    index_file::String        = "wiki/index.md"
    log_file::String          = "wiki/log.md"
    state_dir::String         = ".llmwiki"
    state_file::String        = ".llmwiki/state.json"

    # LLM provider
    model::String             = "qwen3:8b"
    provider::Symbol          = :ollama
    embedding_model::String   = "nomic-embed-text"
    api_url::Union{Nothing,String} = nothing

    # Compilation
    max_concepts_per_source::Int = 8
    compile_concurrency::Int     = 3
    max_related_pages::Int       = 5

    # Query
    query_page_limit::Int     = 8

    # Search
    search_top_k::Int         = 10
    similarity_threshold::Float64 = 0.7
end

# ── SourceEntry ──────────────────────────────────────────────────────────────

"""
    SourceEntry

Per-source state entry that records the content hash and list of concepts
extracted from a single source file.
"""
Base.@kwdef mutable struct SourceEntry
    hash::String              = ""
    concepts::Vector{String}  = String[]
    compiled_at::String       = ""
end

# ── WikiState ────────────────────────────────────────────────────────────────

"""
    WikiState

Persistent state for the entire wiki.  Serialised to `.llmwiki/state.json`
and used for incremental change detection.
"""
Base.@kwdef mutable struct WikiState
    version::Int                          = 1
    sources::Dict{String,SourceEntry}     = Dict{String,SourceEntry}()
    frozen_slugs::Vector{String}          = String[]
    index_hash::String                    = ""
end

# ── ExtractedConcept ─────────────────────────────────────────────────────────

"""
    ExtractedConcept

A single concept extracted from a source file by the LLM.
"""
Base.@kwdef mutable struct ExtractedConcept
    concept::String = ""
    summary::String = ""
    is_new::Bool = true
end

# ── PageMeta ─────────────────────────────────────────────────────────────────

"""
    PageMeta

YAML frontmatter metadata for a wiki page.
"""
Base.@kwdef mutable struct PageMeta
    title::String              = ""
    summary::String            = ""
    sources::Vector{String}    = String[]
    tags::Vector{String}       = String[]
    orphaned::Bool             = false
    page_type::PageType        = CONCEPT
    created_at::String         = string(Dates.now())
    updated_at::String         = string(Dates.now())
end

# ── SourceChange ─────────────────────────────────────────────────────────────

"""
    SourceChange

Result of comparing a source file against the previously recorded state.
"""
Base.@kwdef mutable struct SourceChange
    file::String
    status::ChangeStatus
end

# ── SearchResult ─────────────────────────────────────────────────────────────

"""
    SearchResult

A single search hit returned by `search_wiki`.
"""
Base.@kwdef mutable struct SearchResult
    slug::String
    title::String
    score::Float64
    snippet::String = ""
end

# ── LintIssue ────────────────────────────────────────────────────────────────

"""
    LintIssue

A single lint finding produced by `lint_wiki`.
"""
Base.@kwdef mutable struct LintIssue
    severity::LintSeverity
    category::Symbol
    page::String
    message::String
    suggestion::String = ""
end

# ── ExtractionResult ─────────────────────────────────────────────────────────

"""
    ExtractionResult

Full extraction output for one source file, including the raw content and
the list of concepts extracted by the LLM.
"""
Base.@kwdef mutable struct ExtractionResult
    source_file::String
    source_path::String
    source_content::String
    concepts::Vector{ExtractedConcept} = ExtractedConcept[]
end

# ── MergedConcept ────────────────────────────────────────────────────────────

"""
    MergedConcept

A concept after merging contributions from all source files that mention it.
"""
Base.@kwdef mutable struct MergedConcept
    slug::String
    concept::ExtractedConcept
    source_files::Vector{String}
    combined_content::String
end

# ── WikiStats ────────────────────────────────────────────────────────────────

"""
    WikiStats

Summary statistics for the current wiki state, returned by `wiki_status`.
"""
Base.@kwdef mutable struct WikiStats
    source_count::Int                  = 0
    page_count::Int                    = 0
    query_count::Int                   = 0
    orphan_count::Int                  = 0
    link_count::Int                    = 0
    last_compiled::Union{Nothing,String} = nothing
end

# ── JSON3 StructTypes ────────────────────────────────────────────────────────
# Enable JSON3 round-trip serialisation for types persisted to disk.

# Use Struct() (positional) for types where all fields have defaults or are
# always present, and Mutable() for types with optional fields that JSON3
# needs to construct then mutate.

JSON3.StructTypes.StructType(::Type{SourceEntry})      = JSON3.StructTypes.Mutable()
JSON3.StructTypes.StructType(::Type{WikiState})         = JSON3.StructTypes.Mutable()
JSON3.StructTypes.StructType(::Type{ExtractedConcept})  = JSON3.StructTypes.Mutable()
JSON3.StructTypes.StructType(::Type{PageMeta})          = JSON3.StructTypes.Mutable()

# All @kwdef structs now have defaults on every field, so no-arg constructors
# are generated automatically for JSON3 Mutable() deserialization.
