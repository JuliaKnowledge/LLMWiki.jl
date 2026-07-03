# ──────────────────────────────────────────────────────────────────────────────
# compiler/deps.jl — Cross-source dependency tracking for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Maintains a reverse index from concept slugs to contributing source files
# so the incremental compiler can propagate changes through shared concepts.

"""
    build_concept_to_sources_map(sources::Dict{String,SourceEntry}) -> Dict{String,Vector{String}}

Build a reverse index mapping each concept slug to the source files that
produced it.

# Example
```julia
state.sources = Dict(
    "a.md" => SourceEntry(hash="...", concepts=["foo", "bar"]),
    "b.md" => SourceEntry(hash="...", concepts=["bar", "baz"]),
)
m = build_concept_to_sources_map(state.sources)
# m["bar"] == ["a.md", "b.md"]
```
"""
function build_concept_to_sources_map(sources::Dict{String,SourceEntry})::Dict{String,Vector{String}}
    concept_map = Dict{String,Vector{String}}()
    for (file, entry) in sources
        for slug in entry.concepts
            if haskey(concept_map, slug)
                push!(concept_map[slug], file)
            else
                concept_map[slug] = [file]
            end
        end
    end
    concept_map
end

"""
    extracted_concept_slugs(result::ExtractionResult) -> Set{String}

Normalize one extraction result to the set of concept slugs it produced.
"""
function extracted_concept_slugs(result::ExtractionResult)::Set{String}
    Set{String}(slugify(concept.concept) for concept in result.concepts)
end

"""
    dependent_sources_for_slugs(concept_map, slugs; excluding=Set(), deleted_files=Set()) -> Vector{String}

Return sources from the existing state that own any of `slugs`, excluding files
already processed (or scheduled) and files deleted in the current compile.
"""
function dependent_sources_for_slugs(concept_map::Dict{String,Vector{String}},
                                     slugs;
                                     excluding::AbstractSet{String}=Set{String}(),
                                     deleted_files::AbstractSet{String}=Set{String}())::Vector{String}
    affected = String[]
    seen = Set{String}()

    for slug in slugs
        for file in get(concept_map, slug, String[])
            if file in excluding || file in deleted_files || file in seen
                continue
            end
            push!(affected, file)
            push!(seen, file)
        end
    end

    affected
end

"""
    surviving_sources_for_slug(concept_map, slug; excluding=Set(), deleted_files=Set()) -> Vector{String}

Return the existing-state owners of `slug` that are still expected to survive
the current compile.
"""
function surviving_sources_for_slug(concept_map::Dict{String,Vector{String}},
                                    slug::String;
                                    excluding::AbstractSet{String}=Set{String}(),
                                    deleted_files::AbstractSet{String}=Set{String}())::Vector{String}
    dependent_sources_for_slugs(
        concept_map,
        (slug,);
        excluding=excluding,
        deleted_files=deleted_files,
    )
end

"""
    enqueue_sources!(queue, queued, attempted, candidates) -> Int

Append unseen candidate sources to the extraction work queue.
"""
function enqueue_sources!(queue::Vector{String},
                          queued::Set{String},
                          attempted::Set{String},
                          candidates)::Int
    added = 0
    for file in candidates
        if file in queued || file in attempted
            continue
        end
        push!(queue, file)
        push!(queued, file)
        added += 1
    end
    added
end

"""
    find_shared_concepts(source_file::String, state::WikiState) -> Set{String}

Find concept slugs from `source_file` that are also produced by at least one
other source.  Used to protect shared pages from orphan marking on deletion.
"""
function find_shared_concepts(source_file::String, state::WikiState)::Set{String}
    entry = get(state.sources, source_file, nothing)
    entry === nothing && return Set{String}()

    concept_map = build_concept_to_sources_map(state.sources)
    shared = Set{String}()

    for slug in entry.concepts
        sources_for_slug = get(concept_map, slug, String[])
        if length(sources_for_slug) > 1
            push!(shared, slug)
        end
    end
    shared
end

"""
    find_affected_sources(state::WikiState, direct_changes::Vector{SourceChange}) -> Vector{String}

Find *unchanged* sources that need recompilation because they share concepts
with directly changed (NEW or CHANGED) sources.

Algorithm:
1. Collect all concept slugs owned by changed/new sources.
2. Build the concept→sources reverse index from state.
3. For each slug in (1), collect its contributing sources.
4. Return any source that is not itself directly changed but shares a concept.
"""
function find_affected_sources(state::WikiState, direct_changes::Vector{SourceChange})::Vector{String}
    changed_files = Set{String}()
    for c in direct_changes
        if c.status == NEW || c.status == CHANGED
            push!(changed_files, c.file)
        end
    end

    isempty(changed_files) && return String[]

    concept_map = build_concept_to_sources_map(state.sources)

    # Collect all slugs owned by changed sources
    changed_slugs = Set{String}()
    for file in changed_files
        entry = get(state.sources, file, nothing)
        entry === nothing && continue
        for slug in entry.concepts
            push!(changed_slugs, slug)
        end
    end

    dependent_sources_for_slugs(concept_map, changed_slugs; excluding=changed_files)
end

"""
    find_frozen_slugs(state::WikiState, changes::Vector{SourceChange}) -> Set{String}

Legacy helper: find concept slugs touched by deleted sources that still have at
least one surviving owner in the previous state.  These slugs should be
re-generated from surviving owners, not skipped.
"""
function find_frozen_slugs(state::WikiState, changes::Vector{SourceChange})::Set{String}
    deleted_files = Set{String}()
    surviving_files = Set{String}()
    for c in changes
        if c.status == DELETED
            push!(deleted_files, c.file)
        else
            push!(surviving_files, c.file)
        end
    end

    isempty(deleted_files) && return Set{String}()

    frozen = Set{String}()
    concept_map = build_concept_to_sources_map(state.sources)

    for file in deleted_files
        entry = get(state.sources, file, nothing)
        entry === nothing && continue
        for slug in entry.concepts
            sources_for_slug = get(concept_map, slug, String[])
            # Frozen if at least one non-deleted source also owns this concept
            if any(s -> s ∈ surviving_files && s != file, sources_for_slug)
                push!(frozen, slug)
            end
        end
    end

    frozen
end

"""
    find_late_affected_sources(extractions::Vector{ExtractionResult},
                               state::WikiState,
                               changes::Vector{SourceChange}) -> Vector{String}

Post-extraction pass: find unchanged sources that share concepts with
*newly extracted* concepts (concepts discovered during extraction that
weren't known in the previous state).

This catches transitive dependencies that only become visible after
extraction — e.g., source B produces concept X for the first time, and
an unchanged source A already owns concept X in state.
"""
function find_late_affected_sources(extractions::Vector{ExtractionResult},
                                    state::WikiState,
                                    changes::Vector{SourceChange})::Vector{String}
    # Already-processed files (directly changed + previously affected)
    processed_files = Set{String}()
    for c in changes
        if c.status != UNCHANGED
            push!(processed_files, c.file)
        end
    end
    for ext in extractions
        push!(processed_files, ext.source_file)
    end

    # Collect newly extracted concept slugs
    new_slugs = Set{String}()
    for ext in extractions
        for concept in ext.concepts
            push!(new_slugs, slugify(concept.concept))
        end
    end

    isempty(new_slugs) && return String[]

    concept_map = build_concept_to_sources_map(state.sources)
    dependent_sources_for_slugs(concept_map, new_slugs; excluding=processed_files)
end
