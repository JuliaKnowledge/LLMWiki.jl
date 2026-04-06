# ──────────────────────────────────────────────────────────────────────────────
# prompts/extract.jl — Concept extraction prompt templates
# ──────────────────────────────────────────────────────────────────────────────

"""
    ConceptExtractionResult

Structured output type for LLM concept extraction.
"""
Base.@kwdef struct ConceptExtractionResult
    concepts::Vector{ExtractedConcept} = ExtractedConcept[]
end

"""
    extraction_system_prompt(source_content::String, existing_index::String) -> String

Build the system prompt for concept extraction.  The prompt instructs the LLM
to identify 3–8 distinct, meaningful concepts in the source document and return
them as a JSON array.

When `existing_index` is non-empty the LLM is told to avoid duplicating
concepts already present in the wiki.
"""
function extraction_system_prompt(source_content::String, existing_index::String)
    index_section = if isempty(existing_index)
        "\n\nNo existing wiki pages yet."
    else
        "\n\nHere is the existing wiki index — avoid duplicating concepts already covered:\n\n$existing_index"
    end

    return """You are a knowledge extraction engine. Analyze the following source document and identify 3-8 distinct, meaningful concepts worth documenting as wiki pages.

Each concept should be a standalone topic that someone might look up. Focus on key ideas, techniques, patterns, entities, or named concepts — not trivial details.

For each concept, provide:
- concept: A clear, human-readable title (e.g. "Knowledge Compilation", "Transformer Architecture")
- summary: A one-line description (under 120 characters)
- is_new: true if this concept is not already in the wiki index, false if it updates an existing one

Return your response as JSON with a "concepts" array.$index_section

--- SOURCE DOCUMENT ---

$source_content"""
end
