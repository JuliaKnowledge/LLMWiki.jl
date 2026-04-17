# ──────────────────────────────────────────────────────────────────────────────
# cli.jl — Comonicon.jl command-line interface for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────

module CLI

using Comonicon: Comonicon, @cast
using ..LLMWiki:
    WikiConfig,
    default_config,
    load_config,
    save_config,
    resolve_paths!,
    init_wiki,
    wiki_status,
    compile!,
    ingest!,
    query_wiki,
    lint_wiki,
    watch_wiki,
    search_wiki,
    ERROR_SEVERITY,
    WARNING,
    INFO

# ── Helpers ──────────────────────────────────────────────────────────────────

"""
Load the wiki config at `root`, falling back to `default_config(root)` when
`root/wiki.toml` is missing. Paths are resolved on the returned config.
"""
function _resolve(root::AbstractString)
    root_abs = abspath(String(root))
    config_path = joinpath(root_abs, "wiki.toml")
    config = isfile(config_path) ? load_config(root_abs) : default_config(root_abs)
    resolve_paths!(config)
    return config
end

function _severity_label(sev)
    sev == ERROR_SEVERITY && return "ERROR"
    sev == WARNING && return "WARN"
    return "INFO"
end

# ── Commands ─────────────────────────────────────────────────────────────────

"""
Initialise a new LLMWiki at `root`. Creates the directory layout
(sources/, concepts/, queries/, .wiki/) and writes `wiki.toml`.

# Args

- `root`: path to the wiki directory (created if missing).

# Flags

- `--versioned`: enable git-backed versioning on creation.
"""
@cast function init(root::String="."; versioned::Bool=false)
    root_abs = abspath(root)
    mkpath(root_abs)
    config = default_config(root_abs)
    config.versioned = versioned
    init_wiki(config)
    println("Initialised LLMWiki at $(root_abs)")
end

"""
Print summary statistics for the wiki: counts of sources, concept pages,
query pages, and detected orphans.

# Args

- `root`: path to the wiki (defaults to ".").
"""
@cast function status(root::String=".")
    config = _resolve(root)
    stats = wiki_status(config)
    println("LLMWiki status ($(config.root))")
    println("  sources:   $(stats.source_count)")
    println("  concepts:  $(stats.page_count)")
    println("  queries:   $(stats.query_count)")
    println("  wikilinks: $(stats.link_count)")
    println("  orphans:   $(stats.orphan_count)")
    if stats.last_compiled !== nothing
        println("  compiled:  $(stats.last_compiled)")
    else
        println("  compiled:  never")
    end
end

"""
Ingest a source (local file path or HTTP/HTTPS URL) into `sources/`.

# Args

- `path_or_url`: file path or URL to ingest.

# Options

- `--root <path>`: wiki root (defaults to ".").
- `--filename <name>`: override the target filename under sources/.
"""
@cast function ingest(path_or_url::String; root::String=".", filename::String="")
    config = _resolve(root)
    fname_arg = isempty(filename) ? nothing : String(filename)
    result = ingest!(config, path_or_url; filename=fname_arg)
    println("Ingested → $(result)")
end

"""
Compile the wiki: extract concepts from changed sources, generate concept
pages, resolve wiki-links, and rebuild the index.

# Args

- `root`: path to the wiki (defaults to ".").

# Flags

- `--force`: recompile every source regardless of change detection.
"""
@cast function compile(root::String="."; force::Bool=false)
    config = _resolve(root)
    result = compile!(config; force=force)
    println("Compiled: $(result.compiled)  Skipped: $(result.skipped)  Deleted: $(result.deleted)")
end

"""
Ask the wiki a question via the two-step RAG pipeline.

# Args

- `question`: the natural-language question.

# Options

- `--root <path>`: wiki root (defaults to ".").

# Flags

- `--save`: persist the answer as a query page under queries/.
"""
@cast function query(question::String; root::String=".", save::Bool=false)
    config = _resolve(root)
    answer = query_wiki(config, question; save=save)
    println(answer)
end

"""
Keyword search (BM25) over the wiki concept pages.

# Args

- `query`: the search string.

# Options

- `--root <path>`: wiki root (defaults to ".").
- `--top-k <N>`: maximum number of results (default: 10).
"""
@cast function search(query::String; root::String=".", top_k::Int=10)
    config = _resolve(root)
    results = search_wiki(config, query; top_k=top_k)
    if isempty(results)
        println("(no results)")
        return
    end
    for r in results
        score = round(r.score; digits=3)
        println("[$(score)] $(r.title)  →  $(r.path)")
    end
end

"""
Lint the wiki for broken wiki-links, missing frontmatter, orphan pages, etc.

# Args

- `root`: path to the wiki (defaults to ".").

# Flags

- `--verbose`: show INFO-level issues in addition to warnings and errors.
- `--strict`: exit with status 1 if any issues are found.
"""
@cast function lint(root::String="."; verbose::Bool=false, strict::Bool=false)
    config = _resolve(root)
    issues = lint_wiki(config; verbose=verbose)
    if isempty(issues)
        println("No lint issues.")
        return
    end
    for issue in issues
        label = _severity_label(issue.severity)
        loc = isempty(issue.path) ? "" : " [$(issue.path)]"
        println("$(label)$(loc): $(issue.message)")
    end
    if strict
        has_err = any(i -> i.severity == ERROR_SEVERITY || i.severity == WARNING, issues)
        has_err && exit(1)
    end
end

"""
Watch the wiki sources directory and auto-recompile on changes.

# Args

- `root`: path to the wiki (defaults to ".").

# Options

- `--debounce <seconds>`: debounce window for filesystem events (default: 2.0).
"""
@cast function watch(root::String="."; debounce::Float64=2.0)
    config = _resolve(root)
    println("Watching $(config.sources_dir) (Ctrl-C to stop)")
    try
        watch_wiki(config; debounce_seconds=debounce) do result
            println("→ compiled: $(result.compiled), skipped: $(result.skipped), deleted: $(result.deleted)")
        end
    catch err
        err isa InterruptException || rethrow(err)
        println("\nWatcher stopped.")
    end
end

"""
LLMWiki — LLM-assisted personal knowledge wiki.

Manage markdown sources, extract concepts via an LLM, and answer questions
grounded in the resulting wiki.
"""
Comonicon.@main

end # module CLI
