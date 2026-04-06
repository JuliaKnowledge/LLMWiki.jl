# [Versioning & Provenance](@id versioning)

LLMWiki includes built-in git-backed versioning and W3C PROV-O provenance tracking,
giving you a full audit trail of how your wiki evolves over time.

## Git-Backed Versioning

When `versioned = true` in your [`WikiConfig`](@ref) (the default), LLMWiki
initialises a git repository inside the wiki directory and creates an atomic commit
after every compilation pass.

### How It Works

1. **`init_wiki`** calls `git_init!` to set up a `.git` inside the wiki root
2. Every `compile!` call stages all changes (`git add -A`) and commits atomically
3. Each commit message records the compilation timestamp and file counts

The git history lives *inside* the wiki directory, separate from your project
repository. This keeps wiki versioning self-contained and portable.

### Configuration

```julia
config = WikiConfig(
    name = "my-wiki",
    versioned = true,   # default — enable git versioning
)
```

Set `versioned = false` to disable automatic git commits.

### Viewing History

```julia
# Full history of a specific page
entries = wiki_history(config, "julia-language")
for e in entries
    println("$(e.date) — $(e.message) [$(e.hash[1:8])]")
end

# Diff between two versions
diff_text = wiki_diff(config, "julia-language"; old="abc1234", new="def5678")
println(diff_text)

# Recent log entries across the whole wiki
log = wiki_log(config; n=10)
for entry in log
    println("$(entry.date): $(entry.message)")
end
```

### VersionEntry

Each history/log entry is a [`VersionEntry`](@ref):

```julia
struct VersionEntry
    hash::String      # Git commit SHA
    message::String   # Commit message
    author::String    # Author name
    date::String      # ISO 8601 timestamp
end
```

### Manual Snapshots

You can trigger a snapshot at any point:

```julia
commit_hash = git_snapshot!(config; message="Manual checkpoint")
```

Returns the commit hash string, or `nothing` if there were no changes to commit.

## W3C PROV-O Provenance

When you use the [RDFLib extension](@ref extensions), the RDF export includes
rich [W3C PROV-O](https://www.w3.org/TR/prov-o/) provenance triples that track
exactly how wiki content was produced.

### Provenance Model

```
Source File (prov:Entity)
    │
    ├─ prov:hadPrimarySource → Original URL (for web-ingested content)
    ├─ prov:alternateOf → Original binary (for PDF→text conversions)
    │
    ▼
Compilation (prov:Activity)
    │
    ├─ prov:wasAssociatedWith → LLMWiki Compiler (prov:SoftwareAgent)
    ├─ prov:startedAtTime / prov:endedAtTime
    │
    ▼
Wiki Concept (skos:Concept)
    ├─ prov:wasDerivedFrom → Source File
    └─ prov:wasGeneratedBy → Compilation Activity
```

When git versioning is enabled, the RDF graph also includes:

```
Git Revision (prov:Entity)
    ├─ rdfs:label → commit hash
    └─ prov:wasGeneratedBy → Compilation Activity
```

### Source Provenance Metadata

When ingesting sources, you can include provenance metadata in the YAML
frontmatter:

```yaml
---
title: "My Source"
source_url: "https://example.com/article"
source_type: "web"
source_file: "original.pdf"
---
Content here...
```

These fields are automatically extracted during compilation and stored in the
[`SourceEntry`](@ref):

| Field | Purpose |
|:------|:--------|
| `source_url` | Original URL for web-sourced content |
| `source_type` | Source type: `"web"`, `"pdf"`, `"local"`, etc. |
| `original_file` | Original filename before conversion (e.g., PDF→text) |

### Querying Provenance

With the RDFLib extension, you can query provenance via SPARQL:

```julia
using LLMWiki, RDFLib

# Which sources contributed to each concept?
results = sparql_wiki(config, """
    PREFIX prov: <http://www.w3.org/ns/prov#>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    SELECT ?concept ?source ?url WHERE {
        ?c skos:prefLabel ?concept .
        ?c prov:wasDerivedFrom ?s .
        ?s rdfs:label ?source .
        OPTIONAL { ?s prov:hadPrimarySource ?url }
    }
""")

# What git revision was the wiki last compiled at?
results = sparql_wiki(config, """
    PREFIX prov: <http://www.w3.org/ns/prov#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    SELECT ?hash WHERE {
        ?rev a prov:Entity .
        ?rev rdfs:label ?hash .
        FILTER(STRLEN(?hash) = 40)
    }
""")

# Which agent performed the compilation?
results = sparql_wiki(config, """
    PREFIX prov: <http://www.w3.org/ns/prov#>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    SELECT ?agent WHERE {
        ?a a prov:Activity .
        ?a prov:wasAssociatedWith ?sw .
        ?sw a prov:SoftwareAgent .
        ?sw rdfs:label ?agent .
    }
""")
```

### Disabling Provenance

To export RDF without provenance triples:

```julia
g = wiki_to_rdf(config; include_provenance=false)
```
