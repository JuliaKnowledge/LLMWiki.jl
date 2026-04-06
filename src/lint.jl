# ──────────────────────────────────────────────────────────────────────────────
# lint.jl — Wiki health checks for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Structural checks only — no LLM calls.  Detects orphans, broken links,
# missing pages, stale pages, and sourceless pages.

"""
    lint_wiki(config::WikiConfig; verbose::Bool=false) -> Vector{LintIssue}

Run health checks on the wiki and return a list of issues:

- **:orphan_page** — Pages with no inbound wikilinks from other pages.
- **:broken_link** — Wikilinks pointing to non-existent pages.
- **:missing_page** — Concepts referenced in links but without their own page.
- **:stale_page** — Pages whose sources have been modified since last compile.
- **:no_source** — Pages that have no associated source files in state.
- **:empty_page** — Pages with very short body content.
- **:frontmatter_orphan** — Pages explicitly marked orphaned in frontmatter.

If `verbose=true`, INFO-level issues are included; otherwise only
WARNING and ERROR_SEVERITY issues are returned.
"""
function lint_wiki(config::WikiConfig; verbose::Bool=false)::Vector{LintIssue}
    resolve_paths!(config)
    issues = LintIssue[]

    concepts_path = joinpath(config.root, config.concepts_dir)
    queries_path  = joinpath(config.root, config.queries_dir)
    state = load_state(config)

    # Collect all pages and their metadata
    pages = _collect_all_pages(config, concepts_path, queries_path)

    # Build wikilink graph
    slug_set = Set(keys(pages))
    inbound_links = Dict{String,Set{String}}()  # target → {sources}
    outbound_links = Dict{String,Vector{String}}()

    for (slug, info) in pages
        links = find_wikilinks(info.body)
        outbound_links[slug] = links
        for target in links
            target_slug = slugify(target)
            if !haskey(inbound_links, target_slug)
                inbound_links[target_slug] = Set{String}()
            end
            push!(inbound_links[target_slug], slug)
        end
    end

    # Check 1: Broken wikilinks
    for (slug, targets) in outbound_links
        for target in targets
            target_slug = slugify(target)
            if target_slug ∉ slug_set
                push!(issues, LintIssue(
                    severity   = WARNING,
                    category   = :broken_link,
                    page       = slug,
                    message    = "Broken wikilink [[$(target)]] — target page does not exist",
                    suggestion = "Create the page or remove the link"
                ))
            end
        end
    end

    # Check 2: Orphan pages (no inbound links, excluding index-like pages)
    for slug in keys(pages)
        inbound = get(inbound_links, slug, Set{String}())
        if isempty(inbound) && pages[slug].meta.page_type != OVERVIEW
            push!(issues, LintIssue(
                severity   = verbose ? INFO : WARNING,
                category   = :orphan_page,
                page       = slug,
                message    = "Page has no inbound wikilinks from other pages",
                suggestion = "Add [[$(slug)]] links in related pages"
            ))
        end
    end

    # Check 3: Frontmatter-orphaned pages
    for (slug, info) in pages
        if info.meta.orphaned
            push!(issues, LintIssue(
                severity   = WARNING,
                category   = :frontmatter_orphan,
                page       = slug,
                message    = "Page is marked as orphaned in frontmatter",
                suggestion = "Re-ingest the source or delete the page"
            ))
        end
    end

    # Check 4: Stale pages — sources modified since last compile
    for (slug, info) in pages
        for src in info.meta.sources
            entry = get(state.sources, src, nothing)
            entry === nothing && continue
            source_path = joinpath(config.root, config.sources_dir, src)
            isfile(source_path) || continue
            current_hash = hash_file(source_path)
            if current_hash != entry.hash
                push!(issues, LintIssue(
                    severity   = WARNING,
                    category   = :stale_page,
                    page       = slug,
                    message    = "Source '$src' has been modified since last compile",
                    suggestion = "Run compile! to update"
                ))
            end
        end
    end

    # Check 5: Pages without sources
    all_source_concepts = Set{String}()
    for (_, entry) in state.sources
        for slug in entry.concepts
            push!(all_source_concepts, slug)
        end
    end

    for (slug, info) in pages
        if isempty(info.meta.sources) && slug ∉ all_source_concepts &&
           info.meta.page_type != QUERY_PAGE
            push!(issues, LintIssue(
                severity   = INFO,
                category   = :no_source,
                page       = slug,
                message    = "Page has no associated source files",
                suggestion = "This page may have been manually created"
            ))
        end
    end

    # Check 6: Empty/short pages
    for (slug, info) in pages
        body_len = length(strip(info.body))
        if body_len < 50
            push!(issues, LintIssue(
                severity   = WARNING,
                category   = :empty_page,
                page       = slug,
                message    = "Page body is very short ($body_len chars)",
                suggestion = "Consider recompiling or adding more source content"
            ))
        end
    end

    # Filter by verbosity
    if !verbose
        filter!(i -> i.severity != INFO, issues)
    end

    # Sort: errors first, then warnings, then info
    severity_order = Dict(ERROR_SEVERITY => 0, WARNING => 1, INFO => 2)
    sort!(issues; by=i -> severity_order[i.severity])

    if !isempty(issues)
        log_operation!(config, :lint, "found $(length(issues)) issues")
    end

    issues
end

# ── Internal helpers ─────────────────────────────────────────────────────────

"""Page data collected during lint scan."""
struct _PageInfo
    meta::PageMeta
    body::String
    path::String
end

"""
    _collect_all_pages(config, concepts_path, queries_path) -> Dict{String, _PageInfo}

Scan concept and query directories to build a lookup of all wiki pages.
"""
function _collect_all_pages(config::WikiConfig, concepts_path::String,
                            queries_path::String)::Dict{String, _PageInfo}
    pages = Dict{String, _PageInfo}()

    for (dir, _) in ((concepts_path, "concepts"), (queries_path, "queries"))
        isdir(dir) || continue
        for f in readdir(dir)
            endswith(f, ".md") || continue
            full_path = joinpath(dir, f)
            content = safe_read(full_path)
            content === nothing && continue

            slug = replace(f, ".md" => "")
            meta, body = parse_frontmatter(content)
            pages[slug] = _PageInfo(meta, body, full_path)
        end
    end

    pages
end
