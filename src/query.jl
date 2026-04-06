# ──────────────────────────────────────────────────────────────────────────────
# query.jl — Two-step LLM query engine for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Step 1: Read the wiki index, ask the LLM to select relevant pages.
# Step 2: Load selected pages, ask the LLM to synthesise an answer.

"""
    query_wiki(config::WikiConfig, question::String;
               save::Bool=false) -> String

Answer a question using the wiki as a knowledge base via a two-step
LLM-driven retrieval-augmented generation (RAG) pipeline:

1. **Page selection** — Present the wiki index to the LLM and ask which
   pages are most relevant to the question.
2. **Answer generation** — Load the selected pages and ask the LLM to
   synthesise a comprehensive answer with wiki-link citations.

If `save=true`, the answer is persisted as a query page in `queries/`
and the wiki index is regenerated.

Returns the generated answer text.
"""
function query_wiki(config::WikiConfig, question::String;
                    save::Bool=false)::String
    # Read the wiki index for page selection
    index_path = joinpath(config.root, config.index_file)
    index_content = safe_read(index_path)
    if index_content === nothing || isempty(strip(index_content))
        return "No wiki index found. Run `compile!` first to build the wiki."
    end

    client = _create_chat_client(config)

    # Step 1: Page selection
    selected_slugs = _select_pages(client, config, question, index_content)

    if isempty(selected_slugs)
        return "I couldn't find any relevant wiki pages for this question. " *
               "Try rephrasing or adding more source material."
    end

    # Step 2: Load selected pages
    page_contents = _load_selected_pages(config, selected_slugs)
    if isempty(page_contents)
        return "Selected pages could not be loaded. The wiki may need recompilation."
    end

    # Step 3: Generate answer
    answer = _generate_answer(client, config, question, page_contents)

    # Optionally save as a query page
    if save
        _save_query_page(config, question, answer, selected_slugs)
    end

    log_operation!(config, :query, "question=\"$(first(question, 80))\" pages=$(length(selected_slugs)) saved=$save")
    answer
end

"""
    _select_pages(client, config, question, index_content) -> Vector{String}

Ask the LLM to select the most relevant page slugs for a question,
given the wiki index.
"""
function _select_pages(client, config::WikiConfig, question::String,
                       index_content::String)::Vector{String}
    prompt = page_selection_prompt(question, index_content,
                                   config.query_page_limit)

    messages = [
        AgentFramework.Message(:system, prompt),
        AgentFramework.Message(:user, question)
    ]

    options = AgentFramework.ChatOptions(
        model       = config.model,
        temperature = 0.2,
        max_tokens  = 1000
    )

    response = AgentFramework.get_response(client, messages, options)
    text = AgentFramework.get_text(response)

    _parse_selected_slugs(text, config)
end

"""
    _parse_selected_slugs(text::String, config::WikiConfig) -> Vector{String}

Parse the LLM page-selection response to extract valid page slugs.
Accepts both JSON array format and newline-separated slug lists.
"""
function _parse_selected_slugs(text::String, config::WikiConfig)::Vector{String}
    slugs = String[]

    # Try JSON parsing first
    json_str = _strip_json_fences(text)
    try
        parsed = JSON3.read(json_str)
        if parsed isa AbstractVector
            for item in parsed
                s = item isa AbstractString ? String(item) : string(item)
                push!(slugs, s)
            end
            return _validate_slugs(slugs, config)
        elseif parsed isa AbstractDict
            # Handle { "pages": [...] } or { "slugs": [...] }
            for key in (:pages, :slugs, :selected)
                if haskey(parsed, key) && parsed[key] isa AbstractVector
                    for item in parsed[key]
                        s = item isa AbstractString ? String(item) : string(item)
                        push!(slugs, s)
                    end
                    return _validate_slugs(slugs, config)
                end
            end
        end
    catch
        # Fall through to line-based parsing
    end

    # Line-based parsing: extract anything that looks like a slug
    for line in split(text, '\n')
        stripped = strip(line)
        isempty(stripped) && continue
        # Strip list markers and quotes
        cleaned = replace(stripped, r"^[-*•]\s*" => "")
        cleaned = replace(cleaned, r"^[\"']|[\"']$" => "")
        cleaned = strip(cleaned)
        # Extract slug from markdown links like [Title](concepts/slug.md)
        m = match(r"\((?:concepts|queries)/([^)]+)\.md\)", cleaned)
        if m !== nothing
            push!(slugs, String(m.captures[1]))
        elseif occursin(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", cleaned) || occursin(r"^[a-z0-9]+$", cleaned)
            push!(slugs, cleaned)
        end
    end

    _validate_slugs(slugs, config)
end

"""
    _validate_slugs(slugs, config) -> Vector{String}

Filter slugs to only those that correspond to existing wiki pages.
"""
function _validate_slugs(slugs::Vector{String}, config::WikiConfig)::Vector{String}
    valid = String[]
    for slug in slugs
        slug = slugify(slug)
        concepts_path = joinpath(config.root, config.concepts_dir, "$slug.md")
        queries_path  = joinpath(config.root, config.queries_dir, "$slug.md")
        if isfile(concepts_path) || isfile(queries_path)
            push!(valid, slug)
        end
    end
    unique(valid)
end

"""
    _load_selected_pages(config, slugs) -> String

Load and concatenate the content of selected wiki pages.
"""
function _load_selected_pages(config::WikiConfig, slugs::Vector{String})::String
    contents = String[]
    for slug in slugs
        # Check concepts dir first, then queries dir
        for dir in (config.concepts_dir, config.queries_dir)
            page_path = joinpath(config.root, dir, "$slug.md")
            content = safe_read(page_path)
            if content !== nothing
                push!(contents, "--- PAGE: $slug ---\n\n$content")
                break
            end
        end
    end
    join(contents, "\n\n")
end

"""
    _generate_answer(client, config, question, page_contents) -> String

Ask the LLM to synthesise an answer from the loaded wiki pages.
"""
function _generate_answer(client, config::WikiConfig, question::String,
                          page_contents::String)::String
    prompt = answer_generation_prompt(question, page_contents)

    messages = [
        AgentFramework.Message(:system, prompt),
        AgentFramework.Message(:user, question)
    ]

    options = AgentFramework.ChatOptions(
        model       = config.model,
        temperature = 0.3,
        max_tokens  = 4000
    )

    response = AgentFramework.get_response(client, messages, options)
    AgentFramework.get_text(response)
end

"""
    _save_query_page(config, question, answer, slugs)

Save a query answer as a wiki page in the queries directory.
"""
function _save_query_page(config::WikiConfig, question::String,
                          answer::String, slugs::Vector{String})
    slug = slugify(question)
    if length(slug) > 60
        slug = slug[1:60]
    end

    now_str = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
    meta = PageMeta(
        title      = question,
        summary    = "Query: $(first(question, 100))",
        sources    = slugs,
        page_type  = QUERY_PAGE,
        created_at = now_str,
        updated_at = now_str
    )

    page_path = joinpath(config.root, config.queries_dir, "$slug.md")
    mkpath(dirname(page_path))
    atomic_write(page_path, build_page(meta, answer))

    # Regenerate index to include the new query page
    try
        generate_index!(config)
    catch e
        @warn "Failed to regenerate index after saving query" exception=(e, catch_backtrace())
    end

    @info "Saved query page" slug=slug
end
