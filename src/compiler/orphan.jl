# ──────────────────────────────────────────────────────────────────────────────
# compiler/orphan.jl — Orphan page management for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# When a source file is deleted, its concept pages become orphans unless
# another source also contributes to them.

"""
    mark_orphaned!(config::WikiConfig, source_file::String, state::WikiState)

Mark wiki pages as orphaned when their source is deleted.
Shared concepts (pages contributed to by multiple sources) are skipped
because they still have a living contributor.
"""
function mark_orphaned!(config::WikiConfig, source_file::String, state::WikiState)
    entry = get(state.sources, source_file, nothing)
    entry === nothing && return

    shared = find_shared_concepts(source_file, state)

    for slug in entry.concepts
        slug in shared && continue
        page_path = joinpath(config.root, config.concepts_dir, "$slug.md")
        content = safe_read(page_path)
        content === nothing && continue

        meta, body = parse_frontmatter(content)
        meta.orphaned = true
        meta.updated_at = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
        atomic_write(page_path, build_page(meta, body))
        @info "Orphaned page" slug=slug reason="source deleted: $source_file"
    end
end

"""
    find_orphan_pages(config::WikiConfig) -> Vector{String}

Scan the concepts directory and return slugs of all pages whose
frontmatter has `orphaned: true`.
"""
function find_orphan_pages(config::WikiConfig)::Vector{String}
    orphans = String[]
    concepts_path = joinpath(config.root, config.concepts_dir)
    isdir(concepts_path) || return orphans

    for f in readdir(concepts_path)
        endswith(f, ".md") || continue
        content = safe_read(joinpath(concepts_path, f))
        content === nothing && continue
        meta, _ = parse_frontmatter(content)
        if meta.orphaned
            push!(orphans, replace(f, ".md" => ""))
        end
    end
    orphans
end
