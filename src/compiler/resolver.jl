# ──────────────────────────────────────────────────────────────────────────────
# compiler/resolver.jl — Bidirectional wikilink resolution for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# After pages are generated, this module wires them together with [[wikilinks]]
# using a two-pass approach: outbound links on changed pages, then inbound
# links on all pages for newly created titles.

"""
    _build_title_index(config::WikiConfig) -> Dict{String,Vector{String}}

Build a mapping from normalized page title (lowercase) → slugs by scanning all
non-orphaned concept pages. Used for wikilink target resolution and ambiguity
detection.
"""
function _build_title_index(config::WikiConfig)::Dict{String,Vector{String}}
    index = Dict{String,Vector{String}}()
    concepts_path = joinpath(config.root, config.concepts_dir)
    isdir(concepts_path) || return index

    for f in readdir(concepts_path)
        endswith(f, ".md") || continue
        content = safe_read(joinpath(concepts_path, f))
        content === nothing && continue
        meta, _ = parse_frontmatter(content)
        meta.orphaned && continue

        slug = replace(f, ".md" => "")
        key = lowercase(meta.title)
        haskey(index, key) || (index[key] = String[])
        slug ∉ index[key] && push!(index[key], slug)
    end

    index
end

function _build_slug_to_title_map(config::WikiConfig)::Dict{String,String}
    slug_to_title = Dict{String,String}()
    concepts_path = joinpath(config.root, config.concepts_dir)
    isdir(concepts_path) || return slug_to_title

    for f in readdir(concepts_path)
        endswith(f, ".md") || continue
        content = safe_read(joinpath(concepts_path, f))
        content === nothing && continue
        meta, _ = parse_frontmatter(content)
        meta.orphaned && continue
        slug_to_title[replace(f, ".md" => "")] = meta.title
    end

    slug_to_title
end

function _ambiguous_title_index(title_index::Dict{String,Vector{String}})::Dict{String,Vector{String}}
    Dict(title => copy(slugs) for (title, slugs) in title_index if length(slugs) > 1)
end

function _filter_renamed_titles(renamed_titles::Dict{String,String},
                                title_index::Dict{String,Vector{String}},
                                slug_to_title::Dict{String,String})::Dict{String,String}
    filtered = Dict{String,String}()

    for (old_title, new_title) in renamed_titles
        key = lowercase(new_title)
        slugs = get(title_index, key, String[])
        length(slugs) == 1 || continue
        canonical_title = get(slug_to_title, only(slugs), new_title)
        old_title == canonical_title && continue
        filtered[old_title] = canonical_title
    end

    filtered
end

function _rewrite_renamed_wikilinks(body::String, renamed_titles::Dict{String,String})::String
    isempty(renamed_titles) && return body

    updated = body
    for old_title in sort(collect(keys(renamed_titles)); by=length, rev=true)
        new_title = renamed_titles[old_title]
        escaped = _regex_escape(old_title)
        rx = Regex("\\[\\[$escaped\\]\\]")
        updated = replace(updated, rx => "[[$new_title]]")
    end

    updated
end

"""
    resolve_links!(config::WikiConfig, changed_slugs::Vector{String},
                   new_slugs::Vector{String}; renamed_titles=Dict()) -> Int

Run bidirectional wikilink resolution across wiki pages.

**Pass 1 — Outbound links on changed pages:**
For every page in `changed_slugs`, scan its body for concept titles and
insert `[[wikilinks]]` where the title appears in prose.

**Pass 2 — Inbound links for new titles:**
For every page *not* in `changed_slugs`, scan for mentions of the
`new_slugs` titles and insert links. This catches references that
existed before the target page was created.

If duplicate live pages share the same title, throws an `ArgumentError`
instead of silently choosing one target.
"""
function resolve_links!(config::WikiConfig,
                        changed_slugs::Vector{String},
                        new_slugs::Vector{String};
                        renamed_titles::Dict{String,String}=Dict{String,String}())::Int
    title_index = _build_title_index(config)
    isempty(title_index) && return 0

    ambiguous = _ambiguous_title_index(title_index)
    if !isempty(ambiguous)
        details = join(
            ["\"$title\" => $(join(slugs, ", "))" for (title, slugs) in sort(collect(ambiguous); by=first)],
            "; ",
        )
        throw(ArgumentError("Ambiguous wiki titles prevent link resolution: $details"))
    end

    slug_to_title = _build_slug_to_title_map(config)
    all_titles = sort!(collect(values(slug_to_title)); by=length, rev=true)
    rename_map = _filter_renamed_titles(renamed_titles, title_index, slug_to_title)

    concepts_path = joinpath(config.root, config.concepts_dir)
    modified_count = 0

    changed_set = Set(changed_slugs)
    for slug in changed_slugs
        page_path = joinpath(concepts_path, "$slug.md")
        content = safe_read(page_path)
        content === nothing && continue

        meta, body = parse_frontmatter(content)
        updated_body = _rewrite_renamed_wikilinks(String(body), rename_map)
        updated_body = add_wikilinks(updated_body, all_titles, get(slug_to_title, slug, slug))
        if updated_body != body
            atomic_write(page_path, build_page(meta, updated_body))
            modified_count += 1
        end
    end

    isempty(new_slugs) && isempty(rename_map) && return modified_count

    new_titles = String[]
    for slug in new_slugs
        title = get(slug_to_title, slug, nothing)
        title !== nothing && push!(new_titles, title)
    end

    for f in readdir(concepts_path)
        endswith(f, ".md") || continue
        slug = replace(f, ".md" => "")
        slug in changed_set && continue

        page_path = joinpath(concepts_path, f)
        content = safe_read(page_path)
        content === nothing && continue

        meta, body = parse_frontmatter(content)
        meta.orphaned && continue

        updated_body = _rewrite_renamed_wikilinks(String(body), rename_map)
        updated_body = add_wikilinks(updated_body, new_titles, get(slug_to_title, slug, slug))
        if updated_body != body
            atomic_write(page_path, build_page(meta, updated_body))
            modified_count += 1
        end
    end

    modified_count
end
