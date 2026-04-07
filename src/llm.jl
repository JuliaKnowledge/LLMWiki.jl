# ──────────────────────────────────────────────────────────────────────────────
# llm.jl — Lightweight provider clients for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────

const DEFAULT_OPENAI_URL = "https://api.openai.com/v1"
const DEFAULT_AZURE_OPENAI_API_VERSION = "2024-06-01"
const DEFAULT_ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
const DEFAULT_HTTP_TIMEOUT = 120

function _chat_completion(config::WikiConfig, system_prompt::String, user_prompt::String;
                          temperature::Float64=0.3,
                          max_tokens::Int=2000)::String
    request = _build_chat_request(
        config,
        system_prompt,
        user_prompt;
        temperature=temperature,
        max_tokens=max_tokens,
    )

    response = HTTP.post(
        request.url,
        request.headers,
        JSON3.write(request.body);
        readtimeout=DEFAULT_HTTP_TIMEOUT,
        status_exception=false,
    )

    if response.status < 200 || response.status >= 300
        body = String(response.body)
        detail = isempty(strip(body)) ? "status $(response.status)" : first(body, min(length(body), 400))
        error("LLM request failed ($(config.provider)): $detail")
    end

    return request.parser(JSON3.read(String(response.body)))
end

function _build_chat_request(config::WikiConfig, system_prompt::String, user_prompt::String;
                             temperature::Float64,
                             max_tokens::Int)
    if config.provider == :ollama
        base_url = something(config.api_url, "http://localhost:11434")
        url = rstrip(base_url, '/') * "/api/chat"
        body = Dict{String,Any}(
            "model" => config.model,
            "stream" => false,
            "messages" => [
                Dict("role" => "system", "content" => system_prompt),
                Dict("role" => "user", "content" => user_prompt),
            ],
            "options" => Dict(
                "temperature" => temperature,
                "num_predict" => max_tokens,
            ),
        )
        return (
            url=url,
            headers=Pair{String,String}["Content-Type" => "application/json"],
            body=body,
            parser=_parse_ollama_text,
        )
    elseif config.provider == :openai
        api_key = _require_env("OPENAI_API_KEY", "OpenAI API key not set. Set OPENAI_API_KEY.")
        base_url = rstrip(something(config.api_url, DEFAULT_OPENAI_URL), '/')
        url = endswith(base_url, "/chat/completions") ? base_url : base_url * "/chat/completions"
        body = Dict{String,Any}(
            "model" => config.model,
            "messages" => [
                Dict("role" => "system", "content" => system_prompt),
                Dict("role" => "user", "content" => user_prompt),
            ],
            "temperature" => temperature,
            "max_tokens" => max_tokens,
        )
        return (
            url=url,
            headers=Pair{String,String}[
                "Content-Type" => "application/json",
                "Authorization" => "Bearer $api_key",
            ],
            body=body,
            parser=_parse_openai_text,
        )
    elseif config.provider == :azure
        endpoint = something(config.api_url, get(ENV, "AZURE_OPENAI_ENDPOINT", nothing))
        endpoint !== nothing && !isempty(strip(endpoint)) || error(
            "Azure OpenAI endpoint not set. Provide config.api_url or set AZURE_OPENAI_ENDPOINT.",
        )
        api_key = _require_env(
            "AZURE_OPENAI_API_KEY",
            "Azure OpenAI authentication not configured. Set AZURE_OPENAI_API_KEY.",
        )
        api_version = get(ENV, "AZURE_OPENAI_API_VERSION", DEFAULT_AZURE_OPENAI_API_VERSION)
        url = rstrip(endpoint, '/') * "/openai/deployments/$(config.model)/chat/completions?api-version=$(api_version)"
        body = Dict{String,Any}(
            "messages" => [
                Dict("role" => "system", "content" => system_prompt),
                Dict("role" => "user", "content" => user_prompt),
            ],
            "temperature" => temperature,
            "max_tokens" => max_tokens,
        )
        return (
            url=url,
            headers=Pair{String,String}[
                "Content-Type" => "application/json",
                "api-key" => api_key,
            ],
            body=body,
            parser=_parse_openai_text,
        )
    elseif config.provider == :anthropic
        api_key = _require_env("ANTHROPIC_API_KEY", "Anthropic API key not set. Set ANTHROPIC_API_KEY.")
        base_url = rstrip(something(config.api_url, DEFAULT_ANTHROPIC_URL), '/')
        url = endswith(base_url, "/messages") ? base_url : base_url * "/messages"
        body = Dict{String,Any}(
            "model" => config.model,
            "system" => system_prompt,
            "messages" => [
                Dict("role" => "user", "content" => user_prompt),
            ],
            "temperature" => temperature,
            "max_tokens" => max_tokens,
        )
        return (
            url=url,
            headers=Pair{String,String}[
                "Content-Type" => "application/json",
                "x-api-key" => api_key,
                "anthropic-version" => "2023-06-01",
            ],
            body=body,
            parser=_parse_anthropic_text,
        )
    else
        error("Unknown LLM provider: $(config.provider)")
    end
end

function _parse_ollama_text(payload)::String
    message = get(payload, :message, nothing)
    message === nothing && error("Ollama response missing message.")
    content = get(message, :content, nothing)
    content === nothing && error("Ollama response missing message content.")
    return String(content)
end

function _parse_openai_text(payload)::String
    choices = get(payload, :choices, nothing)
    choices isa AbstractVector && !isempty(choices) || error("OpenAI-compatible response missing choices.")
    message = get(choices[1], :message, nothing)
    message === nothing && error("OpenAI-compatible response missing message.")
    content = get(message, :content, nothing)
    return _content_to_text(content, "OpenAI-compatible")
end

function _parse_anthropic_text(payload)::String
    content = get(payload, :content, nothing)
    content isa AbstractVector && !isempty(content) || error("Anthropic response missing content.")

    parts = String[]
    for item in content
        get(item, :type, nothing) == "text" || continue
        text = get(item, :text, nothing)
        text === nothing || push!(parts, String(text))
    end

    isempty(parts) && error("Anthropic response did not contain any text blocks.")
    return join(parts, "\n")
end

function _content_to_text(content, label::String)::String
    content isa AbstractString && return String(content)

    if content isa AbstractVector
        parts = String[]
        for item in content
            text = if item isa AbstractDict || haskey(item, :text)
                get(item, :text, nothing)
            else
                nothing
            end
            text === nothing || push!(parts, String(text))
        end
        isempty(parts) || return join(parts, "\n")
    end

    error("$label response missing textual content.")
end

function _require_env(name::String, message::String)::String
    value = get(ENV, name, "")
    isempty(value) && error(message)
    return value
end
