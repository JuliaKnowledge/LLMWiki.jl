# ──────────────────────────────────────────────────────────────────────────────
# ingest/ingest.jl — Main ingestion dispatcher and utilities
# ──────────────────────────────────────────────────────────────────────────────

# slugify is defined in markdown_utils.jl — no redefinition here.

# ── Sub-modules ──────────────────────────────────────────────────────────────

include("file.jl")
include("web.jl")

# ── Public API ───────────────────────────────────────────────────────────────

"""
    ingest!(config::WikiConfig, path_or_url::String; filename::Union{Nothing,String}=nothing) -> String

Ingest a source into the wiki. Accepts:
- Local file paths (copies to sources/)
- HTTP/HTTPS URLs (fetches and converts to markdown)

Returns the filename of the ingested source in `sources/`.
If `filename` is provided, uses that as the target filename; otherwise derives
one from the path or URL.
"""
function ingest!(config::WikiConfig, path_or_url::String;
                 filename::Union{Nothing,String}=nothing)
    sources_path = joinpath(config.root, config.sources_dir)
    mkpath(sources_path)

    if startswith(path_or_url, "http://") || startswith(path_or_url, "https://")
        return ingest_web!(config, path_or_url; filename=filename)
    else
        return ingest_file!(config, path_or_url; filename=filename)
    end
end

"""
    ingest_batch!(config::WikiConfig, paths::Vector{String}) -> Vector{String}

Ingest multiple sources. Returns a list of ingested filenames.
"""
function ingest_batch!(config::WikiConfig, paths::Vector{String})
    return [ingest!(config, p) for p in paths]
end
