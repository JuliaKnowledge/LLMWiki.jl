# ──────────────────────────────────────────────────────────────────────────────
# compiler/compiler.jl — Main compilation orchestrator for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Drives the full incremental compilation pipeline:
#   detect → extract → merge → generate → orphan → link → index → log

"""
    compile!(config::WikiConfig; force::Bool=false) -> NamedTuple

Run the full compilation pipeline:

1. **Lock** — Acquire filesystem lock to prevent concurrent compiles.
2. **Detect** — Load state, hash sources, classify changes.
3. **Affected** — Find unchanged sources sharing concepts with changed ones.
4. **Extract** — Call LLM to extract concepts from all changed+affected sources.
5. **Late-affected** — Post-extraction pass for newly discovered overlaps.
6. **Merge** — Merge extraction results by concept slug.
7. **Generate** — Call LLM to generate/update wiki pages.
8. **Delete** — Mark orphaned pages for deleted sources.
9. **Resolve** — Bidirectional wikilink resolution.
10. **Index** — Regenerate `wiki/index.md`.
11. **Log** — Append compile operation to the log.
12. **Save** — Persist updated state and release lock.

If `force=true`, all sources are recompiled regardless of hash changes.

Returns `(compiled=N, skipped=N, deleted=N)`.
"""
function compile!(config::WikiConfig; force::Bool=false)
    resolve_paths!(config)
    # Step 1: Acquire lock
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

function _compile_inner!(config::WikiConfig; force::Bool)
    # Step 2: Load state and detect changes
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

    # Step 3: Find affected unchanged sources (share concepts with changed)
    affected_files = find_affected_sources(state, changes)
    if !isempty(affected_files)
        @info "Affected unchanged sources" count=length(affected_files) files=affected_files
    end

    # Frozen slugs — shared between deleted and surviving sources
    frozen = find_frozen_slugs(state, changes)
    if !isempty(frozen)
        @info "Frozen slugs (shared with deleted)" slugs=frozen
    end

    # Step 4: Phase 1 — Extract concepts for changed + affected sources
    sources_to_extract = unique(vcat(
        [c.file for c in direct_changed],
        affected_files
    ))

    extractions = ExtractionResult[]
    failed_sources = String[]

    for source_file in sources_to_extract
        source_path = joinpath(config.root, config.sources_dir, source_file)
        if !isfile(source_path)
            @warn "Source file missing during extraction" source=source_file
            continue
        end
        try
            result = extract_for_source(config, source_file)
            push!(extractions, result)
        catch e
            @warn "Extraction failed for source" source=source_file exception=(e, catch_backtrace())
            push!(failed_sources, source_file)
        end
    end

    # Step 5: Find late-affected sources
    late_affected = find_late_affected_sources(extractions, state, changes)
    if !isempty(late_affected)
        @info "Late-affected sources" count=length(late_affected) files=late_affected
        for source_file in late_affected
            source_path = joinpath(config.root, config.sources_dir, source_file)
            isfile(source_path) || continue
            try
                result = extract_for_source(config, source_file)
                push!(extractions, result)
            catch e
                @warn "Late extraction failed" source=source_file exception=(e, catch_backtrace())
                push!(failed_sources, source_file)
            end
        end
    end

    # Step 6: Merge extractions
    merged = merge_extractions(extractions, frozen)
    @info "Merged concepts" count=length(merged)

    # Step 7: Generate pages
    generated_slugs = String[]
    new_slugs = String[]

    for entry in merged
        try
            slug = generate_page(config, entry)
            push!(generated_slugs, slug)
            # Track truly new pages (slug didn't exist before)
            page_path = joinpath(config.root, config.concepts_dir, "$slug.md")
            if !any(c -> c.status != NEW && slug in get(state.sources, c.file, SourceEntry()).concepts, changes)
                push!(new_slugs, slug)
            end
        catch e
            @warn "Page generation failed" concept=entry.concept.concept exception=(e, catch_backtrace())
        end
    end

    # Step 8: Handle deletions — orphan pages from deleted sources
    for c in deleted_list
        mark_orphaned!(config, c.file, state)
        delete!(state.sources, c.file)
    end

    # Update state with new extraction results (including provenance metadata)
    now_str = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
    for ext in extractions
        concept_slugs = [slugify(c.concept) for c in ext.concepts]

        # Extract provenance from ingested source frontmatter
        source_url = nothing
        source_type = "file"
        original_file = nothing
        try
            fm_data = YAML.load(match(r"^---\s*\n(.*?)\n---"s, ext.source_content))
            if fm_data isa Dict
                source_url = get(fm_data, "source_url", nothing)
                source_type = get(fm_data, "source_type", "file")
                original_file = get(fm_data, "source_file", nothing)
            end
        catch; end

        state.sources[ext.source_file] = SourceEntry(
            hash          = hash_file(joinpath(config.root, config.sources_dir, ext.source_file)),
            concepts      = concept_slugs,
            compiled_at   = now_str,
            source_url    = source_url,
            source_type   = String(source_type),
            original_file = original_file isa String ? original_file : nothing,
        )
    end
    state.frozen_slugs = collect(frozen)

    # Step 9: Resolve wikilinks
    link_count = 0
    try
        link_count = resolve_links!(config, generated_slugs, new_slugs)
        @info "Resolved wikilinks" modified_pages=link_count
    catch e
        @warn "Wikilink resolution failed" exception=(e, catch_backtrace())
    end

    # Step 10: Regenerate index
    try
        generate_index!(config)
    catch e
        @warn "Index generation failed" exception=(e, catch_backtrace())
    end

    # Step 11: Log and save
    compiled = length(generated_slugs)
    skipped  = length(unchanged_list) - length(affected_files) - length(late_affected)
    skipped  = max(skipped, 0)
    deleted  = length(deleted_list)

    details = "compiled=$compiled skipped=$skipped deleted=$deleted links=$link_count"
    if !isempty(failed_sources)
        details *= " failed=$(length(failed_sources))"
    end
    log_operation!(config, :compile, details)

    save_state(config, state)

    # Step 12: Git snapshot — atomic commit of all changes
    if config.versioned && _has_git(config) && compiled + deleted > 0
        src_list = join(sources_to_extract, ", ")
        msg = "Compile: $compiled pages, $deleted deleted\n\nSources: $src_list"
        git_snapshot!(config, msg; author="LLMWiki Compiler <llmwiki@localhost>")
    end

    @info "Compilation complete" compiled=compiled skipped=skipped deleted=deleted

    (compiled=compiled, skipped=skipped, deleted=deleted)
end
