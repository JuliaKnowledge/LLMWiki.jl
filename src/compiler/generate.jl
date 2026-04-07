# ──────────────────────────────────────────────────────────────────────────────
# compiler/generate.jl — LLM page generation & merge pipeline
# ──────────────────────────────────────────────────────────────────────────────

"""
    generate_page(config::WikiConfig, entry::MergedConcept) -> String

Generate (or update) a wiki page for a merged concept using the LLM.
Returns the slug of the generated page.
"""
function generate_page(config::WikiConfig, entry::MergedConcept)
    page_path     = joinpath(config.root, config.concepts_dir, "$(entry.slug).md")
    existing_page = something(safe_read(page_path), "")

    related = load_related_pages(config, entry.slug)

    prompt = page_generation_prompt(
        entry.concept.concept, entry.combined_content, existing_page, related
    )

    body = _chat_completion(
        config,
        prompt,
        "Write the wiki page for \"$(entry.concept.concept)\".";
        temperature=0.4,
        max_tokens=4000,
    )

    # Build page with frontmatter
    now_str = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")

    existing_meta = if !isempty(existing_page)
        first(parse_frontmatter(existing_page))
    else
        nothing
    end

    meta = PageMeta(
        title      = entry.concept.concept,
        summary    = entry.concept.summary,
        sources    = entry.source_files,
        page_type  = CONCEPT,
        created_at = existing_meta !== nothing ? existing_meta.created_at : now_str,
        updated_at = now_str
    )

    full_page = build_page(meta, body)

    if validate_wiki_page(full_page)
        atomic_write(page_path, full_page)
        @info "Generated page" concept=entry.concept.concept slug=entry.slug
    else
        @warn "Invalid page generated, skipping" concept=entry.concept.concept
    end

    return entry.slug
end

# ── Related page loading ─────────────────────────────────────────────────────

"""
    load_related_pages(config::WikiConfig, exclude_slug::String; max_pages::Int=0) -> String

Load existing wiki pages (excluding `exclude_slug`) to provide
cross-referencing context to the LLM.  Returns a single string with pages
separated by `---` dividers.
"""
function load_related_pages(config::WikiConfig, exclude_slug::String; max_pages::Int=0)
    limit = max_pages > 0 ? max_pages : config.max_related_pages
    concepts_path = joinpath(config.root, config.concepts_dir)

    isdir(concepts_path) || return ""

    files = filter(readdir(concepts_path)) do f
        endswith(f, ".md") && f != "$(exclude_slug).md"
    end
    files = first(files, limit)

    contents = String[]
    for f in files
        content = safe_read(joinpath(concepts_path, f))
        content === nothing && continue
        meta, _ = parse_frontmatter(content)
        meta.orphaned && continue
        push!(contents, content)
    end

    return join(contents, "\n\n---\n\n")
end

# ── Extraction merging ───────────────────────────────────────────────────────

"""
    merge_extractions(extractions::Vector{ExtractionResult}, frozen_slugs::Set{String}) -> Vector{MergedConcept}

Merge extraction results so each concept slug maps to **all** contributing
sources.  Concepts whose slug appears in `frozen_slugs` are skipped.
"""
function merge_extractions(extractions::Vector{ExtractionResult}, frozen_slugs::Set{String})
    by_slug = Dict{String, MergedConcept}()

    for result in extractions
        isempty(result.concepts) && continue
        for concept in result.concepts
            slug = slugify(concept.concept)
            slug in frozen_slugs && continue

            if haskey(by_slug, slug)
                existing = by_slug[slug]
                push!(existing.source_files, result.source_file)
                existing.combined_content *= "\n\n--- SOURCE: $(result.source_file) ---\n\n$(result.source_content)"
            else
                by_slug[slug] = MergedConcept(
                    slug             = slug,
                    concept          = concept,
                    source_files     = [result.source_file],
                    combined_content = "--- SOURCE: $(result.source_file) ---\n\n$(result.source_content)"
                )
            end
        end
    end

    return collect(values(by_slug))
end

# ── Page validation ──────────────────────────────────────────────────────────
# validate_wiki_page is defined in markdown_utils.jl — no redefinition here.
