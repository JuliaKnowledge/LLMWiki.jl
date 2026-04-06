# ──────────────────────────────────────────────────────────────────────────────
# prompts/lint.jl — Lint / quality-check prompt templates
# ──────────────────────────────────────────────────────────────────────────────

"""
    ContradictionResult

Structured output for contradiction detection between two wiki pages.
"""
Base.@kwdef struct ContradictionResult
    contradictions::Vector{Dict{String,String}} = Dict{String,String}[]
end

"""
    contradiction_check_prompt(page_a::String, page_b::String) -> String

Build prompt to check for contradictions between two wiki pages.
The LLM returns a JSON object with a `contradictions` array.
"""
function contradiction_check_prompt(page_a::String, page_b::String)
    return """You are a fact-checker. Compare these two wiki pages and identify any contradictions, inconsistencies, or conflicting claims between them.

For each contradiction found, provide:
- claim_a: The claim from Page A
- claim_b: The conflicting claim from Page B
- severity: "minor" (phrasing difference) or "major" (factual conflict)
- suggestion: How to resolve it

Return your response as JSON with a "contradictions" array (empty array if none found).

--- PAGE A ---
$page_a

--- PAGE B ---
$page_b"""
end

"""
    staleness_check_prompt(page_content::String, newer_sources::String) -> String

Build prompt to check if a page contains claims superseded by newer sources.
The LLM returns a JSON object with a `stale_claims` array.
"""
function staleness_check_prompt(page_content::String, newer_sources::String)
    return """You are a knowledge base maintainer. Check if any claims in this wiki page have been superseded or contradicted by newer source material.

For each stale claim, provide:
- claim: The claim in the wiki page
- new_info: What the newer source says instead
- suggestion: How to update the page

Return your response as JSON with a "stale_claims" array (empty if all up to date).

--- WIKI PAGE ---
$page_content

--- NEWER SOURCES ---
$newer_sources"""
end
