module LLMWiki

using Dates
using UUIDs
using SHA
using Logging
using Markdown: Markdown
using FileWatching
using JSON3
using HTTP
using Requires
using YAML
using Gumbo
using Cascadia
using StringDistances
using PDFIO

# Core types and configuration
include("types.jl")
include("config.jl")

# Markdown utilities
include("frontmatter.jl")
include("markdown_utils.jl")

# State management
include("state.jl")
include("hasher.jl")
include("llm.jl")

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

# Versioning
include("versioning.jl")

# Exports — Types
export WikiConfig, WikiState, SourceEntry, ExtractedConcept, PageMeta
export ChangeStatus, NEW, CHANGED, UNCHANGED, DELETED
export SearchResult, LintIssue, LintSeverity, INFO, WARNING, ERROR_SEVERITY
export VersionEntry

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

# Exports — Versioning
export git_init!, git_snapshot!, wiki_history, wiki_diff, wiki_log

# Exports — RDFLib extension stubs
export wiki_to_rdf, sparql_wiki, export_rdf, validate_wiki_shacl, rdf_search, rdf_graph_stats

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

"""
    create_wiki_agent(config::WikiConfig)

Create an interactive AgentFramework wiki agent. Requires `using LLMWiki, AgentFramework`.
"""
function create_wiki_agent end

"""
    wiki_to_rdf(config::WikiConfig; include_provenance::Bool=true) -> RDFGraph

Export the wiki as an RDF knowledge graph using SKOS, PROV, and Dublin Core
vocabularies. Requires `using LLMWiki, RDFLib`.
"""
function wiki_to_rdf end

"""
    sparql_wiki(config::WikiConfig, query::String; include_provenance::Bool=true)

Execute a SPARQL query against the wiki's RDF knowledge graph.
Requires `using LLMWiki, RDFLib`.
"""
function sparql_wiki end

"""
    export_rdf(config::WikiConfig, path::String; format=TurtleFormat(), include_provenance::Bool=true)

Serialize the wiki knowledge graph to a file in the given RDF format.
Requires `using LLMWiki, RDFLib`.
"""
function export_rdf end

"""
    validate_wiki_shacl(config::WikiConfig) -> ValidationReport

Validate the wiki knowledge graph against SHACL shapes.
Requires `using LLMWiki, RDFLib`.
"""
function validate_wiki_shacl end

"""
    rdf_search(config::WikiConfig, query::String; top_k::Int=10) -> Vector{SearchResult}

Search the wiki using SPARQL over the RDF knowledge graph.
Requires `using LLMWiki, RDFLib`.
"""
function rdf_search end

"""
    rdf_graph_stats(config::WikiConfig) -> Dict{String, Any}

Return statistics about the wiki RDF knowledge graph.
Requires `using LLMWiki, RDFLib`.
"""
function rdf_graph_stats end

function __init__()
    @require AgentFramework="8d84e483-4b84-4e3c-9ca2-3749d621083b" include("../ext/LLMWikiAgentFrameworkExt.jl")
    @require RDFLib="a0e68e5a-3a1c-4e72-9e58-7b3f0e842d1a" include("../ext/LLMWikiRDFLibExt.jl")
    @require SQLite="0aa819cd-b072-5ff4-a722-6bc24af294d9" include("../ext/LLMWikiSQLiteExt.jl")
    @require Mem0="111c52c1-a189-4018-bb23-b883ef531b41" include("../ext/LLMWikiMem0Ext.jl")
end

end # module
