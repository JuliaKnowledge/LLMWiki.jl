# ──────────────────────────────────────────────────────────────────────────────
# prompts/generate.jl — Wiki page generation prompt templates
# ──────────────────────────────────────────────────────────────────────────────

"""
    page_generation_prompt(concept, source_content, existing_page, related_pages) -> String

Build the system prompt for wiki page generation.

* `concept`        – human-readable concept title.
* `source_content` – combined source material to draw facts from.
* `existing_page`  – current page markdown (empty string for new pages).
* `related_pages`  – concatenated related pages for cross-referencing.
"""
function page_generation_prompt(concept::String, source_content::String,
                                existing_page::String, related_pages::String)
    existing_section = if isempty(existing_page)
        ""
    else
        "\n\nExisting page to update (preserve and extend, don't lose information):\n\n$existing_page"
    end

    related_section = if isempty(related_pages)
        ""
    else
        "\n\nRelated wiki pages for cross-referencing:\n\n$related_pages"
    end

    return """You are a wiki author. Write a clear, well-structured markdown page about "$concept".

Rules:
- Draw facts ONLY from the provided source material. Do not invent information.
- Write in a neutral, informative, encyclopedic tone.
- Use clear headings (##) to structure the content.
- Include a ## Sources section at the end listing the source documents.
- Suggest [[wikilinks]] to related concepts where appropriate (use [[Concept Title]] format).
- Be thorough but concise. Aim for 200-800 words.
- Do NOT include YAML frontmatter — that will be added automatically.
- If updating an existing page, merge new information while preserving existing content.
$existing_section$related_section

--- SOURCE MATERIAL ---

$source_content"""
end
