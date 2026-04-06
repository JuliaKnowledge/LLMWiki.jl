# ──────────────────────────────────────────────────────────────────────────────
# agent.jl — AgentFramework WikiAgent for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Wraps wiki operations as AgentFramework tools so an LLM agent can
# manage a wiki through natural-language conversation.

const _WIKI_AGENT_INSTRUCTIONS = """
You are a wiki maintainer agent for LLMWiki. You manage a knowledge wiki
that is compiled from source documents using LLM-powered extraction and
generation.

Your capabilities:
- **Ingest** new sources (files or URLs) into the wiki
- **Compile** sources into wiki pages (extract concepts, generate pages, resolve links)
- **Query** the wiki to answer questions using its knowledge base
- **Search** for specific pages by keyword
- **Lint** the wiki to find structural issues
- **Read** individual wiki pages
- **Status** to show wiki statistics

When answering questions, use the wiki_query tool to search the knowledge base.
When asked about wiki health, use wiki_lint.
When asked to add new content, use wiki_ingest followed by wiki_compile.
Always provide helpful, concise responses.
"""

"""
    create_wiki_agent(config::WikiConfig) -> AgentFramework.Agent

Create an AgentFramework `Agent` with tools for managing a LLMWiki instance.

# Tools
- `wiki_ingest(path_or_url)` — Ingest a source file or URL
- `wiki_compile()` — Run the compilation pipeline
- `wiki_query(question)` — Query the wiki knowledge base
- `wiki_search(query)` — Search wiki pages by keyword
- `wiki_lint()` — Run health checks
- `wiki_read(slug)` — Read a specific wiki page
- `wiki_status()` — Show wiki statistics

# Example
```julia
config = load_config("./my-wiki")
agent = create_wiki_agent(config)
response = run_agent(agent, "What concepts are in the wiki?")
println(response.text)
```
"""
function create_wiki_agent(config::WikiConfig)
    client = _create_chat_client(config)

    tools = FunctionTool[
        _make_ingest_tool(config),
        _make_compile_tool(config),
        _make_query_tool(config),
        _make_search_tool(config),
        _make_lint_tool(config),
        _make_read_tool(config),
        _make_status_tool(config),
    ]

    AgentFramework.Agent(
        name         = "WikiAgent",
        description  = "LLMWiki knowledge base management agent",
        instructions = _WIKI_AGENT_INSTRUCTIONS,
        client       = client,
        tools        = tools,
    )
end

# ── Tool factories ───────────────────────────────────────────────────────────

function _make_ingest_tool(config::WikiConfig)
    FunctionTool(
        name        = "wiki_ingest",
        description = "Ingest a source file or URL into the wiki. Accepts local file paths or HTTP/HTTPS URLs.",
        func        = function(path_or_url::String)
            try
                filename = ingest!(config, path_or_url)
                return "Successfully ingested: $filename"
            catch e
                return "Ingestion failed: $(sprint(showerror, e))"
            end
        end,
        parameters  = Dict{String,Any}(
            "type"       => "object",
            "properties" => Dict{String,Any}(
                "path_or_url" => Dict{String,Any}(
                    "type"        => "string",
                    "description" => "Local file path or HTTP/HTTPS URL to ingest"
                )
            ),
            "required" => ["path_or_url"]
        )
    )
end

function _make_compile_tool(config::WikiConfig)
    FunctionTool(
        name        = "wiki_compile",
        description = "Run the wiki compilation pipeline: extract concepts, generate pages, resolve links, and regenerate the index.",
        func        = function()
            try
                result = compile!(config)
                return "Compilation complete: $(result.compiled) compiled, $(result.skipped) skipped, $(result.deleted) deleted"
            catch e
                return "Compilation failed: $(sprint(showerror, e))"
            end
        end,
        parameters  = Dict{String,Any}(
            "type"       => "object",
            "properties" => Dict{String,Any}()
        )
    )
end

function _make_query_tool(config::WikiConfig)
    FunctionTool(
        name        = "wiki_query",
        description = "Answer a question using the wiki knowledge base. Uses a two-step RAG pipeline: page selection then answer synthesis.",
        func        = function(question::String)
            try
                return query_wiki(config, question)
            catch e
                return "Query failed: $(sprint(showerror, e))"
            end
        end,
        parameters  = Dict{String,Any}(
            "type"       => "object",
            "properties" => Dict{String,Any}(
                "question" => Dict{String,Any}(
                    "type"        => "string",
                    "description" => "The question to answer using the wiki"
                )
            ),
            "required" => ["question"]
        )
    )
end

function _make_search_tool(config::WikiConfig)
    FunctionTool(
        name        = "wiki_search",
        description = "Search wiki pages by keyword using BM25 ranking. Returns the most relevant pages.",
        func        = function(query::String)
            try
                results = search_wiki(config, query)
                if isempty(results)
                    return "No results found for: $query"
                end
                buf = IOBuffer()
                for (i, r) in enumerate(results)
                    println(buf, "$i. **$(r.title)** ($(r.slug)) — score: $(r.score)")
                    if !isempty(r.snippet)
                        println(buf, "   $(r.snippet)")
                    end
                end
                return String(take!(buf))
            catch e
                return "Search failed: $(sprint(showerror, e))"
            end
        end,
        parameters  = Dict{String,Any}(
            "type"       => "object",
            "properties" => Dict{String,Any}(
                "query" => Dict{String,Any}(
                    "type"        => "string",
                    "description" => "Search query keywords"
                )
            ),
            "required" => ["query"]
        )
    )
end

function _make_lint_tool(config::WikiConfig)
    FunctionTool(
        name        = "wiki_lint",
        description = "Run structural health checks on the wiki. Reports orphan pages, broken links, stale pages, and other issues.",
        func        = function()
            try
                issues = lint_wiki(config; verbose=true)
                if isempty(issues)
                    return "No issues found — wiki is healthy!"
                end
                buf = IOBuffer()
                println(buf, "Found $(length(issues)) issue(s):\n")
                for issue in issues
                    severity_str = issue.severity == ERROR_SEVERITY ? "ERROR" :
                                   issue.severity == WARNING ? "WARN" : "INFO"
                    println(buf, "[$severity_str] $(issue.category) — $(issue.page): $(issue.message)")
                    if !isempty(issue.suggestion)
                        println(buf, "  → $(issue.suggestion)")
                    end
                end
                return String(take!(buf))
            catch e
                return "Lint failed: $(sprint(showerror, e))"
            end
        end,
        parameters  = Dict{String,Any}(
            "type"       => "object",
            "properties" => Dict{String,Any}()
        )
    )
end

function _make_read_tool(config::WikiConfig)
    FunctionTool(
        name        = "wiki_read",
        description = "Read the content of a specific wiki page by its slug (e.g., 'machine-learning').",
        func        = function(slug::String)
            # Try concepts dir then queries dir
            for dir in (config.concepts_dir, config.queries_dir)
                page_path = joinpath(config.root, dir, "$slug.md")
                content = safe_read(page_path)
                if content !== nothing
                    return content
                end
            end
            # Fuzzy match suggestion
            available = _list_all_slugs(config)
            if !isempty(available)
                best = fuzzy_match_title(slug, available)
                if best !== nothing
                    return "Page '$slug' not found. Did you mean '$best'?"
                end
            end
            return "Page '$slug' not found."
        end,
        parameters  = Dict{String,Any}(
            "type"       => "object",
            "properties" => Dict{String,Any}(
                "slug" => Dict{String,Any}(
                    "type"        => "string",
                    "description" => "The page slug (URL-safe name) to read"
                )
            ),
            "required" => ["slug"]
        )
    )
end

function _make_status_tool(config::WikiConfig)
    FunctionTool(
        name        = "wiki_status",
        description = "Show current wiki statistics: source count, page count, query count, orphans, links, and last compilation time.",
        func        = function()
            try
                stats = wiki_status(config)
                return """Wiki Status:
- Sources: $(stats.source_count)
- Pages: $(stats.page_count)
- Queries: $(stats.query_count)
- Orphans: $(stats.orphan_count)
- Links: $(stats.link_count)
- Last compiled: $(something(stats.last_compiled, "never"))"""
            catch e
                return "Status check failed: $(sprint(showerror, e))"
            end
        end,
        parameters  = Dict{String,Any}(
            "type"       => "object",
            "properties" => Dict{String,Any}()
        )
    )
end

# ── Helpers ──────────────────────────────────────────────────────────────────

"""
    _list_all_slugs(config::WikiConfig) -> Vector{String}

List all wiki page slugs across concepts and queries directories.
"""
function _list_all_slugs(config::WikiConfig)::Vector{String}
    slugs = String[]
    for dir in (config.concepts_dir, config.queries_dir)
        full_dir = joinpath(config.root, dir)
        isdir(full_dir) || continue
        for f in readdir(full_dir)
            endswith(f, ".md") || continue
            push!(slugs, replace(f, ".md" => ""))
        end
    end
    slugs
end
