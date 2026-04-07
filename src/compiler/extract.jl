# ──────────────────────────────────────────────────────────────────────────────
# compiler/extract.jl — LLM concept extraction using AgentFramework
# ──────────────────────────────────────────────────────────────────────────────

"""
    extract_concepts(config::WikiConfig, source_content::String, existing_index::String) -> Vector{ExtractedConcept}

Use the configured LLM provider to extract concepts from a source document via
structured JSON output.
"""
function extract_concepts(config::WikiConfig, source_content::String, existing_index::String)
    prompt = extraction_system_prompt(source_content, existing_index)

    text = _chat_completion(
        config,
        prompt,
        "Extract the key concepts from this source.";
        temperature=0.3,
        max_tokens=2000,
    )
    return _parse_concepts(text)
end

"""
    _parse_concepts(text::String) -> Vector{ExtractedConcept}

Parse LLM response text into `ExtractedConcept` objects.
Handles both raw JSON and markdown-wrapped JSON (````json` blocks),
as well as varied key names (`concept`/`title`, `summary`/`description`).
"""
function _parse_concepts(text::String)
    json_str = _strip_json_fences(text)

    try
        parsed = JSON3.read(json_str)
        concepts = ExtractedConcept[]

        items = if parsed isa AbstractDict && haskey(parsed, :concepts)
            parsed[:concepts]
        elseif parsed isa AbstractVector
            parsed
        else
            return concepts
        end

        for item in items
            concept_name = _get_string(item, (:concept, :title))
            summary      = _get_string(item, (:summary, :description))
            is_new       = _get_bool(item, :is_new, true)

            if !isempty(concept_name) && !isempty(summary)
                push!(concepts, ExtractedConcept(
                    concept = concept_name,
                    summary = summary,
                    is_new  = is_new
                ))
            end
        end
        return concepts
    catch e
        @warn "Failed to parse concept extraction response" exception=(e, catch_backtrace())
        return ExtractedConcept[]
    end
end

"""
    extract_for_source(config::WikiConfig, source_file::String) -> ExtractionResult

Full extraction pipeline for a single source file: read source, read index,
call LLM, return typed result.
"""
function extract_for_source(config::WikiConfig, source_file::String)
    @info "Extracting concepts" source=source_file

    source_path    = joinpath(config.root, config.sources_dir, source_file)
    source_content = read(source_path, String)

    index_path     = joinpath(config.root, config.index_file)
    existing_index = something(safe_read(index_path), "")

    concepts = extract_concepts(config, source_content, existing_index)

    if !isempty(concepts)
        names = join([c.concept for c in concepts], ", ")
        @info "Found concepts" count=length(concepts) names=names
    end

    return ExtractionResult(
        source_file    = source_file,
        source_path    = source_path,
        source_content = source_content,
        concepts       = concepts
    )
end

# ── JSON parsing helpers ─────────────────────────────────────────────────────

"""
    _strip_json_fences(text::String) -> String

Remove markdown code fences (````json … ````) if present, returning the inner
JSON string.
"""
function _strip_json_fences(text::String)
    m = match(r"```(?:json)?\s*\n?(.*?)\n?\s*```"s, text)
    return m !== nothing ? String(m.captures[1]) : strip(text)
end

"""
    _get_string(item, keys::Tuple) -> String

Retrieve the first non-empty string value from `item` for the given
candidate `keys`.  Returns `""` if none found.
"""
function _get_string(item, keys::Tuple)
    for k in keys
        if haskey(item, k)
            v = item[k]
            v !== nothing && return String(v)
        end
    end
    return ""
end

"""
    _get_bool(item, key::Symbol, default::Bool) -> Bool

Retrieve a boolean value from `item`, tolerating string `"true"`/`"false"`.
"""
function _get_bool(item, key::Symbol, default::Bool)
    haskey(item, key) || return default
    v = item[key]
    v isa Bool && return v
    v isa AbstractString && return lowercase(v) == "true"
    return default
end
