# Markdown and wikilink utilities for LLMWiki.jl

"""
    slugify(title::String) -> String

Convert a concept title to a URL-safe slug.

# Examples
```julia
slugify("Knowledge Compilation") == "knowledge-compilation"
slugify("C++ Templates") == "c-templates"
slugify("  Foo  Bar  ") == "foo-bar"
```
"""
function slugify(title::String)
    s = lowercase(strip(title))
    s = replace(s, r"[^a-z0-9]+" => "-")   # non-ASCII-alphanumeric runs → single hyphen
    s = replace(s, r"-+" => "-")             # collapse multiple hyphens
    s = strip(s, '-')
    return String(s)
end

"""
    find_wikilinks(content::String) -> Vector{String}

Extract all `[[wikilink]]` targets from content.
Returns unique display titles (not slugs).
"""
function find_wikilinks(content::String)
    titles = String[]
    for m in eachmatch(r"\[\[([^\]]+)\]\]", content)
        title = strip(m.captures[1])
        if !isempty(title) && title ∉ titles
            push!(titles, title)
        end
    end
    return titles
end

"""
    _regex_escape(s::String) -> String

Escape regex metacharacters in a string for safe use inside a `Regex` pattern.
"""
function _regex_escape(s::String)
    buf = IOBuffer()
    for c in s
        if c in raw".+*?^${}()|[]\\"
            write(buf, '\\')
        end
        write(buf, c)
    end
    return String(take!(buf))
end

"""
    add_wikilinks(body::String, titles::Vector{String}, self_title::String) -> String

Add `[[wikilinks]]` around mentions of known concept titles in the body text.
Uses exact matching (case-insensitive). Skips:
- Self-references
- Text already inside existing `[[ ]]`
- Text inside code blocks or inline code
- Non-word-boundary matches
"""
function add_wikilinks(body::String, titles::Vector{String}, self_title::String)
    result = body

    # Sort titles longest-first to avoid partial matches
    sorted_titles = sort(titles, by=length, rev=true)

    for title in sorted_titles
        lowercase(title) == lowercase(self_title) && continue

        escaped = _regex_escape(title)
        rx = Regex(escaped, "i")

        # Collect matches from the current result, then apply in reverse
        matches = collect(eachmatch(rx, result))
        for m in reverse(matches)
            start_pos = m.offset
            end_pos   = start_pos + ncodeunits(m.match) - 1

            # Skip if not at word boundary
            is_word_boundary(result, start_pos, end_pos) || continue

            # Skip if inside existing wikilink
            is_inside_wikilink(result, start_pos) && continue

            # Skip if inside code block or inline code
            _is_inside_code(result, start_pos) && continue

            # Build replacement using safe UTF-8 indexing and canonical title
            before = start_pos > firstindex(result) ?
                     result[1:prevind(result, start_pos)] : ""
            after  = nextind(result, end_pos) <= ncodeunits(result) ?
                     result[nextind(result, end_pos):end] : ""
            result = before * "[[" * title * "]]" * after
        end
    end

    return result
end

"""
    is_inside_wikilink(text::String, position::Int) -> Bool

Check if a character position is inside an existing `[[wikilink]]`.
"""
function is_inside_wikilink(text::String, position::Int)
    # Find last [[ before position
    before = findprev("[[", text, position)
    before === nothing && return false
    before_start = first(before)

    # Find the ]] that closes it
    close = findnext("]]", text, before_start + 2)
    close === nothing && return false

    # Position is inside if the closing ]] is at or after position
    return last(close) >= position
end

"""
    _is_inside_code(text::String, position::Int) -> Bool

Check if a byte position falls inside a fenced code block or inline code span.
"""
function _is_inside_code(text::String, position::Int)
    # Fenced code blocks (``` on its own line)
    for m in eachmatch(r"^```[^\n]*\n.*?^```"ms, text)
        m.offset <= position <= m.offset + ncodeunits(m.match) - 1 && return true
    end
    # Inline code spans
    for m in eachmatch(r"`[^`\n]+`", text)
        m.offset <= position <= m.offset + ncodeunits(m.match) - 1 && return true
    end
    return false
end

"""
    is_word_boundary(text::String, start_pos::Int, end_pos::Int) -> Bool

Check if a match spanning byte positions `start_pos:end_pos` sits at word
boundaries.  A word boundary exists when the adjacent character (if any) is not
a letter, digit, or underscore.
"""
function is_word_boundary(text::String, start_pos::Int, end_pos::Int)
    # Check character before start
    if start_pos > firstindex(text)
        c = text[prevind(text, start_pos)]
        (isletter(c) || isdigit(c) || c == '_') && return false
    end
    # Check character after end
    ni = nextind(text, end_pos)
    if ni <= ncodeunits(text)
        c = text[ni]
        (isletter(c) || isdigit(c) || c == '_') && return false
    end
    return true
end

"""
    validate_wiki_page(content::String) -> Bool

Basic validation: has frontmatter, has body, title is non-empty.
"""
function validate_wiki_page(content::String)
    meta, body = parse_frontmatter(content)
    return !isempty(meta.title) && !isempty(strip(body))
end

"""
    atomic_write(path::String, content::String)

Write content to a file atomically (write to `.tmp`, then rename).
Creates parent directories if needed.
"""
function atomic_write(path::String, content::String)
    mkpath(dirname(path))
    tmp = path * ".tmp"
    try
        write(tmp, content)
        mv(tmp, path; force=true)
    catch
        isfile(tmp) && rm(tmp; force=true)
        rethrow()
    end
end

"""
    safe_read(path::String) -> Union{Nothing, String}

Read file contents, return `nothing` if the file doesn't exist.
"""
function safe_read(path::String)
    isfile(path) ? read(path, String) : nothing
end

"""
    fuzzy_match_title(query::String, titles::Vector{String}; threshold::Float64=0.85) -> Union{Nothing, String}

Find the best fuzzy match for a title using `StringDistances.jl`.
Uses Jaro-Winkler similarity. Returns `nothing` if no match exceeds the threshold.
"""
function fuzzy_match_title(query::String, titles::Vector{String}; threshold::Float64=0.85)
    isempty(titles) && return nothing

    best_score = 0.0
    best_match = nothing
    q = lowercase(query)

    for title in titles
        score = compare(q, lowercase(title), JaroWinkler())
        if score > best_score
            best_score = score
            best_match = title
        end
    end

    return best_score >= threshold ? best_match : nothing
end
