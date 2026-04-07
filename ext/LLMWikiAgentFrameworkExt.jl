module LLMWikiAgentFrameworkExt

using LLMWiki

const AgentFramework = Base.root_module(
    Base.PkgId(Base.UUID("8d84e483-4b84-4e3c-9ca2-3749d621083b"), "AgentFramework"),
)

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

function LLMWiki.create_wiki_agent(config::LLMWiki.WikiConfig)
    client = _create_agentframework_chat_client(config)

    tools = AgentFramework.FunctionTool[
        _make_ingest_tool(config),
        _make_compile_tool(config),
        _make_query_tool(config),
        _make_search_tool(config),
        _make_lint_tool(config),
        _make_read_tool(config),
        _make_status_tool(config),
    ]

    return AgentFramework.Agent(
        name="WikiAgent",
        description="LLMWiki knowledge base management agent",
        instructions=_WIKI_AGENT_INSTRUCTIONS,
        client=client,
        tools=tools,
    )
end

function _create_agentframework_chat_client(config::LLMWiki.WikiConfig)
    if config.provider == :ollama
        url = something(config.api_url, "http://localhost:11434")
        return AgentFramework.OllamaChatClient(model=config.model, base_url=url)
    elseif config.provider == :openai
        return AgentFramework.OpenAIChatClient(
            model=config.model,
            base_url=something(config.api_url, LLMWiki.DEFAULT_OPENAI_URL),
        )
    elseif config.provider == :azure
        endpoint = something(config.api_url, get(ENV, "AZURE_OPENAI_ENDPOINT", nothing))
        endpoint !== nothing && !isempty(strip(endpoint)) || error(
            "Azure OpenAI endpoint not set. Provide config.api_url or set AZURE_OPENAI_ENDPOINT.",
        )
        api_key = get(ENV, "AZURE_OPENAI_API_KEY", "")
        !isempty(api_key) || error(
            "Azure OpenAI authentication not configured. Set AZURE_OPENAI_API_KEY.",
        )
        return AgentFramework.AzureOpenAIChatClient(
            model=config.model,
            endpoint=endpoint,
            api_key=api_key,
            api_version=get(ENV, "AZURE_OPENAI_API_VERSION", LLMWiki.DEFAULT_AZURE_OPENAI_API_VERSION),
        )
    elseif config.provider == :anthropic
        return AgentFramework.AnthropicChatClient(model=config.model)
    else
        error("Unknown LLM provider: $(config.provider)")
    end
end

function _make_ingest_tool(config::LLMWiki.WikiConfig)
    return AgentFramework.FunctionTool(
        name="wiki_ingest",
        description="Ingest a source file or URL into the wiki. Accepts local file paths or HTTP/HTTPS URLs.",
        func=function(path_or_url::String)
            try
                filename = LLMWiki.ingest!(config, path_or_url)
                return "Successfully ingested: $filename"
            catch e
                return "Ingestion failed: $(sprint(showerror, e))"
            end
        end,
        parameters=Dict{String,Any}(
            "type" => "object",
            "properties" => Dict{String,Any}(
                "path_or_url" => Dict{String,Any}(
                    "type" => "string",
                    "description" => "Local file path or HTTP/HTTPS URL to ingest",
                ),
            ),
            "required" => ["path_or_url"],
        ),
    )
end

function _make_compile_tool(config::LLMWiki.WikiConfig)
    return AgentFramework.FunctionTool(
        name="wiki_compile",
        description="Run the wiki compilation pipeline: extract concepts, generate pages, resolve links, and regenerate the index.",
        func=function()
            try
                result = LLMWiki.compile!(config)
                return "Compilation complete: $(result.compiled) compiled, $(result.skipped) skipped, $(result.deleted) deleted"
            catch e
                return "Compilation failed: $(sprint(showerror, e))"
            end
        end,
        parameters=Dict{String,Any}(
            "type" => "object",
            "properties" => Dict{String,Any}(),
        ),
    )
end

function _make_query_tool(config::LLMWiki.WikiConfig)
    return AgentFramework.FunctionTool(
        name="wiki_query",
        description="Answer a question using the wiki knowledge base. Uses a two-step RAG pipeline: page selection then answer synthesis.",
        func=function(question::String)
            try
                return LLMWiki.query_wiki(config, question)
            catch e
                return "Query failed: $(sprint(showerror, e))"
            end
        end,
        parameters=Dict{String,Any}(
            "type" => "object",
            "properties" => Dict{String,Any}(
                "question" => Dict{String,Any}(
                    "type" => "string",
                    "description" => "The question to answer using the wiki",
                ),
            ),
            "required" => ["question"],
        ),
    )
end

function _make_search_tool(config::LLMWiki.WikiConfig)
    return AgentFramework.FunctionTool(
        name="wiki_search",
        description="Search wiki pages by keyword using BM25 ranking. Returns the most relevant pages.",
        func=function(query::String)
            try
                results = LLMWiki.search_wiki(config, query)
                isempty(results) && return "No results found for: $query"

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
        parameters=Dict{String,Any}(
            "type" => "object",
            "properties" => Dict{String,Any}(
                "query" => Dict{String,Any}(
                    "type" => "string",
                    "description" => "Search query keywords",
                ),
            ),
            "required" => ["query"],
        ),
    )
end

function _make_lint_tool(config::LLMWiki.WikiConfig)
    return AgentFramework.FunctionTool(
        name="wiki_lint",
        description="Run structural health checks on the wiki. Reports orphan pages, broken links, stale pages, and other issues.",
        func=function()
            try
                issues = LLMWiki.lint_wiki(config; verbose=true)
                isempty(issues) && return "No issues found — wiki is healthy!"

                buf = IOBuffer()
                println(buf, "Found $(length(issues)) issue(s):\n")
                for issue in issues
                    severity_str = issue.severity == LLMWiki.ERROR_SEVERITY ? "ERROR" :
                                   issue.severity == LLMWiki.WARNING ? "WARN" : "INFO"
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
        parameters=Dict{String,Any}(
            "type" => "object",
            "properties" => Dict{String,Any}(),
        ),
    )
end

function _make_read_tool(config::LLMWiki.WikiConfig)
    return AgentFramework.FunctionTool(
        name="wiki_read",
        description="Read the content of a specific wiki page by its slug (e.g., 'machine-learning').",
        func=function(slug::String)
            for dir in (config.concepts_dir, config.queries_dir)
                page_path = joinpath(config.root, dir, "$slug.md")
                content = LLMWiki.safe_read(page_path)
                if content !== nothing
                    return content
                end
            end

            available = _list_all_slugs(config)
            if !isempty(available)
                best = LLMWiki.fuzzy_match_title(slug, available)
                if best !== nothing
                    return "Page '$slug' not found. Did you mean '$best'?"
                end
            end
            return "Page '$slug' not found."
        end,
        parameters=Dict{String,Any}(
            "type" => "object",
            "properties" => Dict{String,Any}(
                "slug" => Dict{String,Any}(
                    "type" => "string",
                    "description" => "The page slug (URL-safe name) to read",
                ),
            ),
            "required" => ["slug"],
        ),
    )
end

function _make_status_tool(config::LLMWiki.WikiConfig)
    return AgentFramework.FunctionTool(
        name="wiki_status",
        description="Show current wiki statistics: source count, page count, query count, orphans, links, and last compilation time.",
        func=function()
            try
                stats = LLMWiki.wiki_status(config)
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
        parameters=Dict{String,Any}(
            "type" => "object",
            "properties" => Dict{String,Any}(),
        ),
    )
end

function _list_all_slugs(config::LLMWiki.WikiConfig)::Vector{String}
    slugs = String[]
    for dir in (config.concepts_dir, config.queries_dir)
        full_dir = joinpath(config.root, dir)
        isdir(full_dir) || continue
        for f in readdir(full_dir)
            endswith(f, ".md") || continue
            push!(slugs, replace(f, ".md" => ""))
        end
    end
    return slugs
end

end # module LLMWikiAgentFrameworkExt
