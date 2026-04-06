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

Exports the wiki as an RDF knowledge graph using standard vocabularies
([SKOS](https://www.w3.org/2004/02/skos/), [PROV](https://www.w3.org/TR/prov-o/),
[Dublin Core](https://www.dublincore.org/specifications/dublin-core/dcmi-terms/)),
enabling SPARQL queries, SHACL validation, and serialization to Turtle, JSON-LD,
and other RDF formats.

### Setup

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaKnowledge/RDFLib.jl")

using LLMWiki, RDFLib
```

### Ontology Mapping

| Wiki concept | RDF representation |
|:-------------|:-------------------|
| Wiki page | `skos:Concept` |
| Page title | `skos:prefLabel` |
| Page summary | `skos:definition` |
| Wikilink | `skos:related` |
| Tag | `dcterms:subject` |
| Source file | `prov:Entity` |
| Source → concept | `prov:wasDerivedFrom` |
| Compilation | `prov:Activity` |
| Created date | `dcterms:created` |
| Updated date | `dcterms:modified` |
| Page type | Custom class under `skos:Concept` |

### Export to RDF Graph

```julia
# Export as in-memory RDF graph
g = wiki_to_rdf(config)

# Without provenance triples
g = wiki_to_rdf(config; include_provenance=false)
```

### SPARQL Queries

```julia
# Find all concept titles
results = sparql_wiki(config, """
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    SELECT ?title WHERE {
        ?c a skos:Concept .
        ?c skos:prefLabel ?title .
    }
    ORDER BY ?title
""")
for row in results
    println(row["title"].lexical)
end

# Provenance: which sources contributed to each concept?
results = sparql_wiki(config, """
    PREFIX prov: <http://www.w3.org/ns/prov#>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    SELECT ?concept ?source WHERE {
        ?c skos:prefLabel ?concept .
        ?c prov:wasDerivedFrom ?s .
        ?s rdfs:label ?source .
    }
""")

# ASK queries return a Bool
has_julia = sparql_wiki(config, """
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    ASK { ?c skos:prefLabel "Julia" }
""")

# CONSTRUCT queries return an RDFGraph
subgraph = sparql_wiki(config, """
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    CONSTRUCT { ?c skos:prefLabel ?t }
    WHERE { ?c a skos:Concept . ?c skos:prefLabel ?t }
""")
```

### RDF Search

Search using SPARQL substring matching on titles and summaries:

```julia
results = rdf_search(config, "dispatch")
for r in results
    println("$(r.title) (score=$(r.score))")
end
```

### Serialize to File

```julia
# Turtle (default)
export_rdf(config, "wiki.ttl")

# N-Triples
export_rdf(config, "wiki.nt"; format=NTriplesFormat())

# JSON-LD
export_rdf(config, "wiki.jsonld"; format=JSONLDFormat())

# RDF/XML
export_rdf(config, "wiki.rdf"; format=RDFXMLFormat())
```

### SHACL Validation

Validate wiki structure against built-in SHACL shapes:

```julia
report = validate_wiki_shacl(config)
println("Valid: ", report.conforms)
for r in report.results
    println("  Issue: ", r.message)
end
```

The built-in shapes enforce:
- Every concept must have exactly one `skos:prefLabel`
- Every concept should have a `skos:definition` (warning)
- `skos:related` targets must be `skos:Concept` instances
- Timestamps must be `xsd:dateTime`

### Graph Statistics

```julia
stats = rdf_graph_stats(config)
# Dict with keys: "total_triples", "concepts", "sources",
#                 "wikilinks", "orphans", "tags"
```

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
