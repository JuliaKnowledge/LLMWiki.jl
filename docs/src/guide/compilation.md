# [Compilation Pipeline](@id compilation)

The compilation pipeline is the core of LLMWiki. It transforms raw source documents into
a structured, cross-linked wiki through a deterministic 12-step process.

## Overview

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

## The 12 Steps

```julia
result = compile!(config)
```

The [`compile!`](@ref) function executes these steps in order:

### Step 1: Acquire Lock

A filesystem lock (`.llmwiki/lock`) prevents concurrent compilations. Stale locks
older than 10 minutes are automatically broken.

### Step 2: Load State & Detect Changes

The compiler loads the persisted [`WikiState`](@ref) from `.llmwiki/state.json`, then walks the
`sources/` directory, computing SHA-256 hashes for every file. Each source is classified as:

| Status | Meaning |
|:-------|:--------|
| [`NEW`](@ref ChangeStatus) | File not seen before |
| [`CHANGED`](@ref ChangeStatus) | Hash differs from last compile |
| [`UNCHANGED`](@ref ChangeStatus) | Hash matches — skip unless affected |
| [`DELETED`](@ref ChangeStatus) | Previously tracked file no longer on disk |

### Step 3: Find Affected Sources

Even unchanged sources may need recompilation if they share concepts with a changed source.
The compiler builds a concept-overlap graph and marks these as "affected".

### Step 4: Phase 1 — Extract Concepts

For each changed or affected source, the LLM extracts up to `max_concepts_per_source`
key concepts. Each concept becomes an [`ExtractedConcept`](@ref) with a title and summary.

### Step 5: Find Late-Affected Sources

After extraction, newly discovered concept overlaps may affect additional sources.
A second pass catches these "late-affected" sources and extracts their concepts too.

### Step 6: Merge Extractions

When multiple sources mention the same concept, their extractions are merged into
a single `MergedConcept` that combines content from all contributing sources.

### Step 7: Phase 2 — Generate Pages

The LLM generates or updates wiki pages for each merged concept. Each page includes:
- YAML frontmatter with metadata (title, summary, sources, tags)
- Encyclopedia-style body content
- `[[wikilinks]]` to related concepts

### Step 8: Handle Deletions

Pages whose only source was deleted are marked as orphaned in their frontmatter.

### Step 9: Resolve Wikilinks

Bidirectional wikilink resolution scans all generated and existing pages, adding
`[[wikilinks]]` around mentions of known concept titles using fuzzy matching.

### Step 10: Regenerate Index

The `wiki/index.md` file is regenerated with a table of contents listing all
concept and query pages.

### Step 11: Log Operation

The compilation result is appended to `wiki/log.md` as an audit trail entry.

### Step 12: Save State & Release Lock

Updated source hashes and concept mappings are persisted to `state.json`,
and the filesystem lock is released.

## Two-Phase Design

The pipeline uses a two-phase approach to eliminate order-dependence:

1. **Phase 1 (Extract)** — Process all sources and extract concepts *before* generating any pages.
   This ensures every source's concepts are known upfront.
2. **Phase 2 (Generate)** — Generate pages with full knowledge of all concepts across all sources.
   Each page can reference concepts from any source.

This avoids the problem where processing Source A before Source B would miss cross-references
that only become apparent after both are processed.

## Incremental Compilation

Only sources whose content has changed (different SHA-256 hash) are reprocessed.
The [`detect_changes`](@ref) function classifies each source file:

```julia
changes = detect_changes(config, state)
# Vector{SourceChange} — each with .file and .status
```

## Cross-Source Dependencies

When Source A and Source B both contribute to the concept "machine learning", modifying
Source A triggers recompilation of Source B as well. This ensures the shared concept
page reflects the latest information from all contributing sources.

## Forced Recompilation

Pass `force=true` to recompile all sources regardless of hash changes:

```julia
result = compile!(config; force=true)
```

This is useful after changing the LLM model or compilation prompts.

## Concept Merging

When the same concept is extracted from multiple sources, the compiler merges them:

- Concept titles are normalized via [`slugify`](@ref) to detect duplicates
- Content from all contributing sources is concatenated
- The LLM generates a unified page that synthesizes information from all sources
