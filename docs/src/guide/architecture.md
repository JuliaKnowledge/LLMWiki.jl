# [Architecture](@id architecture)

This page describes the internal architecture of LLMWiki.jl.

## Three-Layer Design

LLMWiki is organized into three layers:

### 1. Sources Layer (Immutable)

Raw input documents in `sources/`. These are never modified by the compiler.
Supported formats:
- **Markdown** (`.md`) — copied directly
- **PDF** (`.pdf`) — text extracted via PDFIO.jl
- **Web pages** (HTTP/HTTPS URLs) — fetched and converted to Markdown via Gumbo.jl + Cascadia.jl

### 2. Wiki Layer (LLM-Generated)

The output of compilation, stored in `wiki/`:
- **`concepts/`** — One Markdown file per concept, with YAML frontmatter
- **`queries/`** — Saved query answers
- **`index.md`** — Auto-generated table of contents
- **`log.md`** — Operation audit trail

### 3. Schema Layer (Metadata)

Internal state stored in `.llmwiki/`:
- **`config.yaml`** — [`WikiConfig`](@ref) settings
- **`state.json`** — [`WikiState`](@ref) with source hashes, concept mappings, and frozen slugs
- **`lock`** — Filesystem lock for concurrent compilation prevention

## Content Types

Wiki pages have a `page_type` field in their frontmatter:

| Type | Enum | Description |
|:-----|:-----|:------------|
| Concept | `CONCEPT` | Main wiki articles about extracted concepts |
| Entity | `ENTITY` | Pages about specific named entities |
| Query | `QUERY_PAGE` | Saved query answers |
| Overview | `OVERVIEW` | High-level summary pages |

## State Management

The [`WikiState`](@ref) struct tracks:

- **`sources`** — `Dict{String, SourceEntry}` mapping each source file to its last-known
  SHA-256 hash and the list of concept slugs extracted from it
- **`frozen_slugs`** — Slugs shared between deleted and surviving sources (preserved during
  deletion to avoid losing shared content)
- **`index_hash`** — Hash of the last generated index
- **`version`** — State format version for future migrations

State is serialized to JSON via JSON3.jl with `StructTypes.Mutable()` for round-trip fidelity.

## Frontmatter Format

Every wiki page has YAML frontmatter between `---` delimiters:

```yaml
---
title: "Machine Learning"
summary: "An overview of machine learning concepts and techniques"
sources:
  - "intro-to-ml.md"
  - "deep-learning-paper.pdf"
tags:
  - "ai"
  - "data-science"
orphaned: false
page_type: concept
created_at: "2026-04-06T19:00:00"
updated_at: "2026-04-06T19:30:00"
---
```

The [`PageMeta`](@ref) struct represents this metadata. Use [`parse_frontmatter`](@ref) and
[`write_frontmatter`](@ref) to read/write it.

## Wikilink Resolution Algorithm

The wikilink resolver adds `[[wikilinks]]` around mentions of known concept titles:

1. Collect all known concept titles from existing wiki pages
2. Sort titles longest-first (to avoid partial matches)
3. For each title, scan page bodies for case-insensitive matches
4. Skip matches that are:
   - Self-references (same page)
   - Already inside `[[ ]]` delimiters
   - Inside code blocks or inline code
   - Not at word boundaries
5. Wrap valid matches in `[[Title]]`

Fuzzy matching (via Jaro-Winkler similarity from StringDistances.jl) is used to handle
minor title variations, with a configurable threshold (default: 0.85).

## Lint Checks

The [`lint_wiki`](@ref) function performs structural health checks:

| Category | Severity | Description |
|:---------|:---------|:------------|
| `:broken_link` | WARNING | `[[wikilink]]` points to a non-existent page |
| `:orphan_page` | WARNING | Page has no inbound links from other pages |
| `:frontmatter_orphan` | WARNING | Page explicitly marked `orphaned: true` |
| `:stale_page` | WARNING | Source modified since last compilation |
| `:no_source` | INFO | Page has no associated source files |
| `:empty_page` | WARNING | Page body is very short (< 50 chars) |

## Module Dependencies

```
LLMWiki.jl
├── HTTP.jl            — LLM provider and web ingestion requests
├── JSON3.jl           — State serialization
├── YAML.jl            — Config and frontmatter parsing
├── SHA.jl             — Change detection hashing
├── Gumbo.jl           — HTML parsing
├── Cascadia.jl        — CSS selectors for HTML
├── PDFIO.jl           — PDF text extraction
├── StringDistances.jl — Fuzzy title matching
└── AgentFramework.jl  — Optional interactive-agent extension
├── FileWatching.jl    — File change monitoring
├── Dates.jl           — Timestamps
└── UUIDs.jl           — Unique identifiers
```
