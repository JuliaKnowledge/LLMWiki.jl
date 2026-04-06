# YAML frontmatter parsing and writing for wiki pages.

const FRONTMATTER_DELIMITER = "---"

"""
    parse_frontmatter(content::String) -> (meta::PageMeta, body::String)

Parse YAML frontmatter delimited by `---` from a markdown file.
Returns the parsed `PageMeta` and the remaining body text.
If no frontmatter is found, returns a default `PageMeta` with `title=""` and the full content as body.
"""
function parse_frontmatter(content::String)
    lines = split(content, '\n')

    # Must start with ---
    if isempty(lines) || strip(lines[1]) != FRONTMATTER_DELIMITER
        return (PageMeta(title=""), content)
    end

    # Find closing ---
    closing = 0
    for i in 2:length(lines)
        if strip(lines[i]) == FRONTMATTER_DELIMITER
            closing = i
            break
        end
    end

    if closing == 0
        return (PageMeta(title=""), content)
    end

    yaml_str = join(lines[2:closing-1], '\n')
    body = join(lines[closing+1:end], '\n')
    body = lstrip(body, '\n')

    # Parse YAML
    meta = _yaml_to_pagemeta(yaml_str)
    return (meta, body)
end

"""
    _yaml_to_pagemeta(yaml_str::String) -> PageMeta

Convert a YAML string to a PageMeta struct.
"""
function _yaml_to_pagemeta(yaml_str::String)
    d = try
        YAML.load(yaml_str)
    catch
        Dict{String,Any}()
    end

    d === nothing && (d = Dict{String,Any}())

    title = get(d, "title", "")
    summary = get(d, "summary", "")
    sources_raw = get(d, "sources", String[])
    sources = sources_raw isa AbstractVector ? String[string(s) for s in sources_raw] : String[]
    tags_raw = get(d, "tags", String[])
    tags = tags_raw isa AbstractVector ? String[string(t) for t in tags_raw] : String[]
    orphaned = get(d, "orphaned", false)
    page_type = _parse_page_type(get(d, "page_type", "concept"))
    created_at = get(d, "created_at", get(d, "createdAt", string(Dates.now())))
    updated_at = get(d, "updated_at", get(d, "updatedAt", string(Dates.now())))

    return PageMeta(
        title=string(title),
        summary=string(summary),
        sources=sources,
        tags=tags,
        orphaned=Bool(orphaned),
        page_type=page_type,
        created_at=string(created_at),
        updated_at=string(updated_at)
    )
end

"""
    _parse_page_type(s) -> PageType

Parse a string into a PageType enum value.
"""
function _parse_page_type(s)
    str = lowercase(string(s))
    str == "entity" && return ENTITY
    str == "query" && return QUERY_PAGE
    str == "overview" && return OVERVIEW
    return CONCEPT
end

"""
    _page_type_string(pt::PageType) -> String

Convert a PageType enum to its YAML string representation.
"""
function _page_type_string(pt::PageType)
    pt == ENTITY && return "entity"
    pt == QUERY_PAGE && return "query"
    pt == OVERVIEW && return "overview"
    return "concept"
end

"""
    write_frontmatter(meta::PageMeta) -> String

Generate YAML frontmatter string with `---` delimiters.
"""
function write_frontmatter(meta::PageMeta)
    lines = String["---"]
    push!(lines, "title: \"$(escape_yaml_string(meta.title))\"")

    if !isempty(meta.summary)
        push!(lines, "summary: \"$(escape_yaml_string(meta.summary))\"")
    end

    if !isempty(meta.sources)
        push!(lines, "sources:")
        for s in meta.sources
            push!(lines, "  - \"$(escape_yaml_string(s))\"")
        end
    end

    if !isempty(meta.tags)
        push!(lines, "tags:")
        for t in meta.tags
            push!(lines, "  - \"$(escape_yaml_string(t))\"")
        end
    end

    if meta.orphaned
        push!(lines, "orphaned: true")
    end

    push!(lines, "page_type: $(_page_type_string(meta.page_type))")

    push!(lines, "created_at: \"$(meta.created_at)\"")
    push!(lines, "updated_at: \"$(meta.updated_at)\"")
    push!(lines, "---")

    return join(lines, '\n')
end

"""
    write_frontmatter(meta::PageMeta, body::AbstractString) -> String

Serialize frontmatter + body into a complete Markdown document.
"""
function write_frontmatter(meta::PageMeta, body::AbstractString)
    fm = write_frontmatter(meta)
    return fm * "\n" * String(body)
end

"""
    escape_yaml_string(s::String) -> String

Escape special characters for YAML double-quoted string values.
"""
function escape_yaml_string(s::String)
    s = replace(s, "\\" => "\\\\")
    s = replace(s, "\"" => "\\\"")
    s = replace(s, "\n" => "\\n")
    s = replace(s, "\r" => "\\r")
    return s
end

"""
    build_page(meta::PageMeta, body::String) -> String

Combine frontmatter and body into a complete wiki page.
"""
function build_page(meta::PageMeta, body::AbstractString)
    return write_frontmatter(meta) * "\n\n" * rstrip(body) * "\n"
end

"""
    update_frontmatter(content::String, updates::Dict{String,Any}) -> String

Parse existing page, update specific frontmatter fields, return new content.
"""
function update_frontmatter(content::String, updates::Dict{String,Any})
    meta, body = parse_frontmatter(content)

    for (k, v) in updates
        k == "title" && (meta.title = string(v))
        k == "summary" && (meta.summary = string(v))
        k == "sources" && (meta.sources = String[string(s) for s in v])
        k == "tags" && (meta.tags = String[string(t) for t in v])
        k == "orphaned" && (meta.orphaned = Bool(v))
        k == "page_type" && (meta.page_type = _parse_page_type(v))
        k == "created_at" && (meta.created_at = string(v))
        k == "updated_at" && (meta.updated_at = string(v))
    end

    # Auto-refresh updated_at unless explicitly set
    if !haskey(updates, "updated_at")
        meta.updated_at = string(Dates.now())
    end

    return build_page(meta, body)
end
