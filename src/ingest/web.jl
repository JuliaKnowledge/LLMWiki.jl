# ──────────────────────────────────────────────────────────────────────────────
# ingest/web.jl — Web URL ingestion (fetch, parse HTML, convert to markdown)
# ──────────────────────────────────────────────────────────────────────────────

"""
    ingest_web!(config::WikiConfig, url::String; filename::Union{Nothing,String}=nothing) -> String

Fetch a URL and convert its content to markdown. Uses Gumbo.jl for HTML
parsing and Cascadia.jl for content extraction.

Returns the target filename in `sources/`.
"""
function ingest_web!(config::WikiConfig, url::String;
                     filename::Union{Nothing,String}=nothing)
    sources_path = joinpath(config.root, config.sources_dir)

    @info "Fetching URL" url=url
    response = HTTP.get(url; status_exception=false, readtimeout=30)

    if response.status != 200
        error("Failed to fetch URL (status $(response.status)): $url")
    end

    html_content = String(response.body)

    title, text = extract_html_content(html_content)

    # Generate filename from title/URL if not provided
    if filename === nothing
        slug = slugify(isempty(title) ? url_to_slug(url) : title)
        target_name = slug * ".md"
    else
        target_name = endswith(filename, ".md") ? filename : filename * ".md"
    end

    target = joinpath(sources_path, target_name)

    content = _build_ingested_source_markdown(
        text;
        title=title,
        source_type="web",
        source_url=url,
    )

    write(target, content)
    @info "Ingested URL" url=url target=target_name chars=length(text)
    return target_name
end

# ── HTML content extraction ──────────────────────────────────────────────────

"""
    extract_html_content(html::String) -> Tuple{String,String}

Parse HTML and extract the main content as clean text.
Returns `(title, text)` where `title` is the `<title>` element content
and `text` is a markdown-like rendering of the primary content area.
"""
function extract_html_content(html::String)
    doc = parsehtml(html)

    # Extract <title>
    title_nodes = eachmatch(Selector("title"), doc.root)
    title = isempty(title_nodes) ? "" : strip(node_text(first(title_nodes)))

    # Try progressively broader content selectors
    content_selectors = [
        Selector("article"),
        Selector("main"),
        Selector("[role=main]"),
        Selector(".content"),
        Selector(".post-content"),
        Selector("#content"),
    ]

    content_node = nothing
    for sel in content_selectors
        matches = eachmatch(sel, doc.root)
        if !isempty(matches)
            content_node = first(matches)
            break
        end
    end

    # Fall back to <body>
    if content_node === nothing
        body_nodes = eachmatch(Selector("body"), doc.root)
        content_node = isempty(body_nodes) ? doc.root : first(body_nodes)
    end

    text = html_to_text(content_node)
    return (title, text)
end

# ── HTML → markdown-like text ────────────────────────────────────────────────

"""
    html_to_text(node) -> String

Recursively convert an HTML node tree to markdown-like plain text.
Handles headings, paragraphs, lists, links, emphasis, code, and blockquotes.
"""
function html_to_text(node)
    buf = IOBuffer()
    _html_to_text!(buf, node)
    return strip(String(take!(buf)))
end

const _SKIP_TAGS = Set([
    "script", "style", "nav", "footer", "header", "aside",
    "noscript", "svg", "iframe", "form",
])

const _BLOCK_TAGS = Set(["p", "div", "section", "article", "main"])

function _html_to_text!(buf::IOBuffer, node::HTMLElement)
    tag = string(Gumbo.tag(node))

    # Skip non-content elements
    tag in _SKIP_TAGS && return

    # Headings
    if length(tag) == 2 && tag[1] == 'h' && tag[2] in '1':'6'
        level = parse(Int, tag[2:2])
        write(buf, "\n" * "#"^level * " ")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "\n\n")
        return
    end

    # Block-level containers
    if tag in _BLOCK_TAGS
        write(buf, "\n")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "\n")
        return
    end

    # Line break
    if tag == "br"
        write(buf, "\n")
        return
    end

    # Lists
    if tag in ("ul", "ol")
        write(buf, "\n")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "\n")
        return
    end

    if tag == "li"
        write(buf, "- ")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "\n")
        return
    end

    # Bold
    if tag in ("strong", "b")
        write(buf, "**")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "**")
        return
    end

    # Italic
    if tag in ("em", "i")
        write(buf, "*")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "*")
        return
    end

    # Links — extract text only
    if tag == "a"
        for child in node.children
            _html_to_text!(buf, child)
        end
        return
    end

    # Code / preformatted
    if tag in ("code", "pre")
        write(buf, "`")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "`")
        return
    end

    # Blockquote
    if tag == "blockquote"
        write(buf, "> ")
        for child in node.children
            _html_to_text!(buf, child)
        end
        write(buf, "\n")
        return
    end

    # Default: recurse into children
    for child in node.children
        _html_to_text!(buf, child)
    end
end

function _html_to_text!(buf::IOBuffer, node::HTMLText)
    text = replace(node.text, r"\s+" => " ")
    write(buf, text)
end

# Ignore comments and other node types
_html_to_text!(buf::IOBuffer, ::Any) = nothing

# ── Text extraction (simple) ────────────────────────────────────────────────

"""
    node_text(node) -> String

Collect all raw text content from an HTML node and its descendants,
without any markdown formatting.
"""
function node_text(node)
    buf = IOBuffer()
    _collect_text!(buf, node)
    return String(take!(buf))
end

function _collect_text!(buf::IOBuffer, node::HTMLElement)
    for child in node.children
        _collect_text!(buf, child)
    end
end

function _collect_text!(buf::IOBuffer, node::HTMLText)
    write(buf, node.text)
end

_collect_text!(buf::IOBuffer, ::Any) = nothing

# ── URL helpers ──────────────────────────────────────────────────────────────

"""
    url_to_slug(url::String) -> String

Convert a URL to a reasonable filename slug by stripping the protocol,
replacing path separators with hyphens, and truncating.
"""
function url_to_slug(url::String)
    slug = replace(url, r"^https?://(www\.)?" => "")
    slug = replace(slug, r"[/\?&#=]+" => "-")
    slug = strip(slug, '-')
    if length(slug) > 60
        slug = slug[1:60]
    end
    return strip(slug, '-')
end
