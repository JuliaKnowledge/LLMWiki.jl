# ──────────────────────────────────────────────────────────────────────────────
# compiler/resolver.jl — Bidirectional wikilink resolution for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# After pages are generated, this module wires them together with [[wikilinks]]
# using a two-pass approach: outbound links on changed pages, then inbound
# links on all pages for newly created titles.

"""
    _build_title_index(config::WikiConfig) -> Dict{String,String}

Build a mapping from page title (lowercase) → slug by scanning all
non-orphaned concept pages.  Used for wikilink target resolution.
"""
function _build_title_index(config::WikiConfig)::Dict{String,String}
    index = Dict{String,String}()
    concepts_path = joinpath(config.root, config.concepts_dir)
    isdir(concepts_path) || return index

    for f in readdir(concepts_path)
        endswith(f, ".md") || continue
        content = safe_read(joinpath(concepts_path, f))
        content === nothing && continue
        meta, _ = parse_frontmatter(content)
        meta.orphaned && continue
        slug = replace(f, ".md" => "")
        index[lowercase(meta.title)] = slug
    end
    index
end

"""
    resolve_links!(config::WikiConfig, changed_slugs::Vector{String},
                   new_slugs::Vector{String}) -> Int

Run bidirectional wikilink resolution across wiki pages.

**Pass 1 — Outbound links on changed pages:**
For every page in `changed_slugs`, scan its body for concept titles and
insert `[[wikilinks]]` where the title appears in prose.

**Pass 2 — Inbound links for new titles:**
For every page *not* in `changed_slugs`, scan for mentions of the
`new_slugs` titles and insert links.  This catches references that
existed before the target page was created.

Returns the total number of pages modified across both passes.
"""
function resolve_links!(config::WikiConfig, changed_slugs::Vector{String},
                        new_slugs::Vector{String})::Int
    title_index = _build_title_index(config)
    isempty(title_index) && return 0

    # Invert the index to get slug → title
    slug_to_title = Dict{String,String}()
    for (title, slug) in title_index
        slug_to_title[slug] = title
    end

    # Build the list of all known titles for link detection
    all_titles = collect(keys(title_index))
    concepts_path = joinpath(config.root, config.concepts_dir)
    modified_count = 0

    # Pass 1: add outbound links on changed pages
    changed_set = Set(changed_slugs)
    for slug in changed_slugs
        page_path = joinpath(concepts_path, "$slug.md")
        content = safe_read(page_path)
        content === nothing && continue

        meta, body = parse_frontmatter(content)
        self_title = get(slug_to_title, slug, slug)
        updated_body = add_wikilinks(String(body), all_titles, self_title)
        if updated_body != body
            atomic_write(page_path, build_page(meta, updated_body))
            modified_count += 1
        end
    end

    # Pass 2: add inbound links for new titles on all other pages
    isempty(new_slugs) && return modified_count

    new_titles = String[]
    for slug in new_slugs
        title = get(slug_to_title, slug, nothing)
        title !== nothing && push!(new_titles, title)
    end
    isempty(new_titles) && return modified_count

    for f in readdir(concepts_path)
        endswith(f, ".md") || continue
        slug = replace(f, ".md" => "")
        slug in changed_set && continue  # already handled in pass 1

        page_path = joinpath(concepts_path, f)
        content = safe_read(page_path)
        content === nothing && continue

        meta, body = parse_frontmatter(content)
        meta.orphaned && continue

        updated_body = add_wikilinks(String(body), new_titles, get(slug_to_title, slug, slug))
        if updated_body != body
            atomic_write(page_path, build_page(meta, updated_body))
            modified_count += 1
        end
    end

    modified_count
end
