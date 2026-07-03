# ──────────────────────────────────────────────────────────────────────────────
# compiler/compiler.jl — Main compilation orchestrator for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Drives the full incremental compilation pipeline:
#   detect → extract (fixed-point) → merge → generate → orphan → link → index → log

"""
    compile!(config::WikiConfig; force::Bool=false) -> NamedTuple

Run the full compilation pipeline:

1. **Lock** — Acquire filesystem lock to prevent concurrent compiles.
2. **Detect** — Load state, hash sources, classify changes.
3. **Queue** — Seed a work queue with changed sources and surviving owners of deleted slugs.
4. **Extract** — Re-extract sources until dependency propagation reaches a fixed point.
5. **Cleanup** — Regenerate removed/deleted slugs from surviving owners or orphan them.
6. **Merge** — Merge extraction results by concept slug.
7. **Generate** — Call LLM to generate/update wiki pages.
8. **Resolve** — Bidirectional wikilink resolution.
9. **Index** — Regenerate `wiki/index.md`.
10. **Log** — Append compile operation to the log.
11. **Save** — Persist updated state and release lock.

If `force=true`, all sources are recompiled regardless of hash changes.

Returns `(compiled=N, skipped=N, deleted=N)`.
"""
function compile!(config::WikiConfig; force::Bool=false)
    resolve_paths!(config)
    if !acquire_lock(config)
        @warn "Cannot acquire lock — another compilation may be running"
        return (compiled=0, skipped=0, deleted=0)
    end

    try
        return _compile_inner!(config; force=force)
    catch e
        @error "Compilation failed" exception=(e, catch_backtrace())
        log_operation!(config, :compile_error, "$(sprint(showerror, e))")
        rethrow(e)
    finally
        release_lock(config)
    end
end

function _source_slug_set(state::WikiState, source_file::String)::Set{String}
    entry = get(state.sources, source_file, nothing)
    entry === nothing && return Set{String}()
    Set{String}(entry.concepts)
end

function _infer_renamed_titles(config::WikiConfig,
                               state::WikiState,
                               extraction::ExtractionResult)::Dict{String,String}
    old_slugs = _source_slug_set(state, extraction.source_file)
    new_titles = Dict{String,String}(slugify(concept.concept) => concept.concept for concept in extraction.concepts)

    removed = setdiff(old_slugs, Set(keys(new_titles)))
    added = setdiff(Set(keys(new_titles)), old_slugs)
    (length(removed) == 1 && length(added) == 1) || return Dict{String,String}()

    old_slug = first(removed)
    new_slug = first(added)
    old_page = safe_read(joinpath(config.root, config.concepts_dir, "$old_slug.md"))
    old_title = old_page === nothing ? old_slug : parse_frontmatter(old_page)[1].title
    isempty(strip(old_title)) && return Dict{String,String}()

    Dict(old_title => new_titles[new_slug])
end

function _live_page_slugs(config::WikiConfig)::Set{String}
    slugs = Set{String}()
    isdir(config.concepts_dir) || return slugs

    for f in readdir(config.concepts_dir)
        endswith(f, ".md") || continue
        content = safe_read(joinpath(config.concepts_dir, f))
        content === nothing && continue
        meta, _ = parse_frontmatter(content)
        meta.orphaned && continue
        push!(slugs, replace(f, ".md" => ""))
    end

    slugs
end

function _compile_inner!(config::WikiConfig; force::Bool)
    state = load_state(config)
    changes = detect_changes(config, state)

    if force
        for c in changes
            if c.status == UNCHANGED
                c.status = CHANGED
            end
        end
    end

    new_changes    = filter(c -> c.status == NEW, changes)
    changed_list   = filter(c -> c.status == CHANGED, changes)
    deleted_list   = filter(c -> c.status == DELETED, changes)
    unchanged_list = filter(c -> c.status == UNCHANGED, changes)

    direct_changed = vcat(new_changes, changed_list)
    if isempty(direct_changed) && isempty(deleted_list)
        @info "No changes detected" sources=length(unchanged_list)
        return (compiled=0, skipped=length(unchanged_list), deleted=0)
    end

    @info "Detected changes" new=length(new_changes) changed=length(changed_list) deleted=length(deleted_list) unchanged=length(unchanged_list)

    deleted_files = Set{String}(c.file for c in deleted_list)
    concept_map = build_concept_to_sources_map(state.sources)

    # Step 3: Seed the fixed-point extraction queue.
    extraction_queue = String[]
    queued_sources = Set{String}()
    attempted_sources = Set{String}()
    orphaned_slugs = Set{String}()

    enqueue_sources!(extraction_queue, queued_sources, attempted_sources, [c.file for c in direct_changed])

    for c in deleted_list
        entry = get(state.sources, c.file, nothing)
        entry === nothing && continue
        for slug in entry.concepts
            owners = surviving_sources_for_slug(
                concept_map,
                slug;
                excluding=Set([c.file]),
                deleted_files=deleted_files,
            )
            if isempty(owners)
                push!(orphaned_slugs, slug)
            else
                enqueue_sources!(extraction_queue, queued_sources, attempted_sources, owners)
            end
        end
    end

    if !isempty(extraction_queue)
        @info "Queued sources for extraction" count=length(extraction_queue) files=extraction_queue
    end

    # Step 4: Re-extract until no more dependent sources are discovered.
    extractions = ExtractionResult[]
    failed_sources = Set{String}()
    rename_map = Dict{String,String}()

    queue_index = 1
    while queue_index <= length(extraction_queue)
        source_file = extraction_queue[queue_index]
        queue_index += 1
        source_file in attempted_sources && continue
        push!(attempted_sources, source_file)

        source_path = joinpath(config.root, config.sources_dir, source_file)
        if !isfile(source_path)
            @warn "Source file missing during extraction" source=source_file
            push!(failed_sources, source_file)
            continue
        end

        try
            result = extract_for_source(config, source_file)
            push!(extractions, result)
            merge!(rename_map, _infer_renamed_titles(config, state, result))

            new_slugs = extracted_concept_slugs(result)
            old_slugs = _source_slug_set(state, source_file)
            removed_slugs = setdiff(old_slugs, new_slugs)

            dependents = dependent_sources_for_slugs(
                concept_map,
                new_slugs;
                excluding=Set([source_file]),
                deleted_files=deleted_files,
            )
            enqueue_sources!(extraction_queue, queued_sources, attempted_sources, dependents)

            for slug in removed_slugs
                owners = surviving_sources_for_slug(
                    concept_map,
                    slug;
                    excluding=Set([source_file]),
                    deleted_files=deleted_files,
                )
                if isempty(owners)
                    push!(orphaned_slugs, slug)
                else
                    enqueue_sources!(extraction_queue, queued_sources, attempted_sources, owners)
                end
            end
        catch e
            @warn "Extraction failed for source" source=source_file exception=(e, catch_backtrace())
            push!(failed_sources, source_file)
        end
    end

    if !isempty(orphaned_slugs)
        @info "Slugs scheduled for orphaning" slugs=collect(orphaned_slugs)
    end

    # Step 5/6: Merge all successfully re-extracted concepts.
    merged = merge_extractions(extractions, Set{String}())
    @info "Merged concepts" count=length(merged)

    # Step 7: Generate pages.
    generated_slugs = String[]
    new_slugs = String[]
    generated_slug_set = Set{String}()
    failed_generation_sources = Set{String}()
    preexisting_pages = _live_page_slugs(config)

    for entry in merged
        try
            slug = generate_page(config, entry)
            if slug === nothing
                union!(failed_generation_sources, entry.source_files)
                continue
            end

            push!(generated_slugs, slug)
            push!(generated_slug_set, slug)
            if slug ∉ preexisting_pages
                push!(new_slugs, slug)
            end
        catch e
            @warn "Page generation failed" concept=entry.concept.concept exception=(e, catch_backtrace())
            union!(failed_generation_sources, entry.source_files)
        end
    end

    # Step 8: Orphan only slugs whose final owner disappeared.
    resolved_orphaned_slugs = Set{String}()
    for slug in orphaned_slugs
        try
            mark_slug_orphaned!(config, slug; reason="last owner removed during compile")
            push!(resolved_orphaned_slugs, slug)
        catch e
            @warn "Failed to orphan page" slug=slug exception=(e, catch_backtrace())
        end
    end
    resolved_slugs = union(generated_slug_set, resolved_orphaned_slugs)

    removed_deleted_sources = 0
    for c in deleted_list
        entry = get(state.sources, c.file, nothing)
        entry === nothing && continue

        unresolved = setdiff(Set(entry.concepts), resolved_slugs)
        if isempty(unresolved)
            delete!(state.sources, c.file)
            removed_deleted_sources += 1
        else
            @warn "Retaining deleted source in state until affected slugs are rebuilt" source=c.file unresolved=collect(unresolved)
        end
    end

    # Update state with new extraction results (including provenance metadata).
    now_str = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
    for ext in extractions
        if ext.source_file in failed_generation_sources
            @warn "Skipping state update because one or more generated pages failed validation" source=ext.source_file
            continue
        end

        concept_slugs = [slugify(c.concept) for c in ext.concepts]

        fm_data = parse_frontmatter_data(ext.source_content)
        source_url = get(fm_data, "source_url", nothing)
        source_type = get(fm_data, "source_type", "file")
        original_file = get(fm_data, "source_file", nothing)

        state.sources[ext.source_file] = SourceEntry(
            hash          = hash_file(joinpath(config.root, config.sources_dir, ext.source_file)),
            concepts      = concept_slugs,
            compiled_at   = now_str,
            source_url    = source_url,
            source_type   = String(source_type),
            original_file = original_file isa String ? original_file : nothing,
        )
    end
    state.frozen_slugs = String[]

    # Step 9: Resolve wikilinks.
    link_count = 0
    try
        link_count = resolve_links!(config, generated_slugs, new_slugs; renamed_titles=rename_map)
        @info "Resolved wikilinks" modified_pages=link_count
    catch e
        @warn "Wikilink resolution failed" exception=(e, catch_backtrace())
    end

    # Step 10: Regenerate index.
    try
        generate_index!(config)
    catch e
        @warn "Index generation failed" exception=(e, catch_backtrace())
    end

    # Step 11: Log and save.
    compiled = length(generated_slugs)
    reprocessed_unchanged = intersect(Set(c.file for c in unchanged_list), attempted_sources)
    skipped = max(length(unchanged_list) - length(reprocessed_unchanged), 0)
    deleted = removed_deleted_sources

    details = "compiled=$compiled skipped=$skipped deleted=$deleted links=$link_count"
    if !isempty(failed_sources)
        details *= " failed=$(length(failed_sources))"
    end
    if !isempty(failed_generation_sources)
        details *= " generation_failed=$(length(failed_generation_sources))"
    end
    log_operation!(config, :compile, details)

    save_state(config, state)

    if config.versioned && _has_git(config) && compiled + deleted > 0
        src_list = join(extraction_queue, ", ")
        msg = "Compile: $compiled pages, $deleted deleted\n\nSources: $src_list"
        git_snapshot!(config, msg; author="LLMWiki Compiler <sdwfrost@users.noreply.github.com>")
    end

    @info "Compilation complete" compiled=compiled skipped=skipped deleted=deleted

    (compiled=compiled, skipped=skipped, deleted=deleted)
end
