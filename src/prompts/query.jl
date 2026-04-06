# ──────────────────────────────────────────────────────────────────────────────
# prompts/query.jl — Query and answer-generation prompt templates
# ──────────────────────────────────────────────────────────────────────────────

"""
    PageSelectionResult

Structured output type for page selection.
"""
Base.@kwdef struct PageSelectionResult
    pages::Vector{String}    = String[]
    reasoning::String        = ""
end

"""
    page_selection_prompt(question::String, index_content::String) -> String

Build the prompt for selecting relevant wiki pages to answer a question.
The LLM returns a JSON object with `pages` (slugs) and `reasoning`.
"""
function page_selection_prompt(question::String, index_content::String)
    return """You are a knowledge base assistant. Given a question and a wiki index, select the most relevant pages to answer the question.

Return your response as JSON with:
- "pages": array of page slugs (filenames without .md extension) — select up to 8 most relevant
- "reasoning": brief explanation of why these pages were selected

Question: $question

Wiki Index:
$index_content"""
end

"""
    answer_generation_prompt(question::String, pages_content::String) -> String

Build the prompt for generating an answer from wiki pages.
Instructs the LLM to cite pages with `[[Page Title]]` wikilinks.
"""
function answer_generation_prompt(question::String, pages_content::String)
    return """You are a knowledge assistant. Answer the question using ONLY the wiki content provided below.

Rules:
- Cite specific pages using [[Page Title]] wikilinks.
- If the wiki doesn't contain enough information to fully answer, say so clearly.
- Be thorough and well-structured.
- Use markdown formatting for readability.

Question: $question

Relevant wiki pages:
$pages_content"""
end
