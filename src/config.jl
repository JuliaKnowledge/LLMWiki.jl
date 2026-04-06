# ──────────────────────────────────────────────────────────────────────────────
# config.jl — Configuration management for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────

const CONFIG_FILENAME = "config.yaml"

"""
    default_config(root::String=".") -> WikiConfig

Return a `WikiConfig` with all default values rooted at `root`.
Directory paths are made absolute relative to `root`.
"""
function default_config(root::String=".")
    root = abspath(root)
    WikiConfig(
        root          = root,
        sources_dir   = joinpath(root, "sources"),
        wiki_dir      = joinpath(root, "wiki"),
        concepts_dir  = joinpath(root, "wiki", "concepts"),
        queries_dir   = joinpath(root, "wiki", "queries"),
        index_file    = joinpath(root, "wiki", "index.md"),
        log_file      = joinpath(root, "wiki", "log.md"),
        state_dir     = joinpath(root, ".llmwiki"),
        state_file    = joinpath(root, ".llmwiki", "state.json"),
    )
end

"""
    resolve_paths!(config::WikiConfig) -> WikiConfig

Ensure all directory/file paths in `config` are absolute, resolving them
relative to `config.root`.  Mutates and returns `config`.
"""
function resolve_paths!(config::WikiConfig)
    config.root = abspath(config.root)
    r = config.root
    _abs(p) = isabspath(p) ? p : joinpath(r, p)
    config.sources_dir  = _abs(config.sources_dir)
    config.wiki_dir     = _abs(config.wiki_dir)
    config.concepts_dir = _abs(config.concepts_dir)
    config.queries_dir  = _abs(config.queries_dir)
    config.index_file   = _abs(config.index_file)
    config.log_file     = _abs(config.log_file)
    config.state_dir    = _abs(config.state_dir)
    config.state_file   = _abs(config.state_file)
    config
end

"""
    _config_path(config::WikiConfig) -> String

Full path to the YAML configuration file.
"""
_config_path(config::WikiConfig) = joinpath(config.state_dir, CONFIG_FILENAME)

"""
    load_config(root::String=".") -> WikiConfig

Load wiki configuration from `.llmwiki/config.yaml`.  If the file does not
exist, return `default_config(root)`.
"""
function load_config(root::String=".")
    cfg = default_config(root)
    path = _config_path(cfg)
    isfile(path) || return cfg

    data = YAML.load_file(path)
    data isa Dict || return cfg

    for (key, val) in data
        sym = Symbol(key)
        hasfield(WikiConfig, sym) || continue
        ft = fieldtype(WikiConfig, sym)
        try
            if ft === Symbol
                setfield!(cfg, sym, Symbol(val))
            elseif ft === Int
                setfield!(cfg, sym, Int(val))
            elseif ft === Float64
                setfield!(cfg, sym, Float64(val))
            elseif ft === String
                setfield!(cfg, sym, String(val))
            elseif ft === Union{Nothing,String}
                setfield!(cfg, sym, val === nothing ? nothing : String(val))
            end
        catch
            @warn "Ignoring invalid config key" key val
        end
    end

    # Re-resolve derived paths that depend on root
    cfg.root = abspath(cfg.root)
    cfg
end

"""
    save_config(config::WikiConfig)

Persist the current configuration to `.llmwiki/config.yaml`.
Only non-default values are written so the file stays minimal.
"""
function save_config(config::WikiConfig)
    mkpath(config.state_dir)
    defaults = default_config(config.root)
    data = Dict{String,Any}()

    for fname in fieldnames(WikiConfig)
        cur = getfield(config, fname)
        def = getfield(defaults, fname)
        if cur != def
            data[String(fname)] = cur isa Symbol ? String(cur) : cur
        end
    end

    open(_config_path(config), "w") do io
        YAML.write(io, data)
    end
    nothing
end

"""
    init_wiki(config::WikiConfig)

Create the full directory structure for a new LLMWiki instance:
`sources/`, `wiki/concepts/`, `wiki/queries/`, `.llmwiki/`.
Existing directories are left untouched.
"""
function init_wiki(config::WikiConfig)
    resolve_paths!(config)
    for dir in (
        config.sources_dir,
        config.concepts_dir,
        config.queries_dir,
        config.state_dir,
    )
        mkpath(dir)
    end

    # Seed an empty log file if it doesn't exist
    log_path = config.log_file
    if !isfile(log_path)
        open(log_path, "w") do io
            println(io, "# LLMWiki Operation Log\n")
        end
    end

    save_config(config)

    # Initialise Git versioning if enabled
    if config.versioned
        git_init!(config)
    end

    @info "Initialised LLMWiki" root = config.root
    nothing
end

"""
    wiki_status(config::WikiConfig) -> WikiStats

Compute summary statistics for the wiki by scanning the filesystem.
"""
function wiki_status(config::WikiConfig)
    resolve_paths!(config)
    stats = WikiStats()

    # Count sources
    if isdir(config.sources_dir)
        for (root, _, files) in walkdir(config.sources_dir)
            stats.source_count += length(files)
        end
    end

    # Count concept pages and detect orphans / links
    if isdir(config.concepts_dir)
        for f in readdir(config.concepts_dir; join=true)
            endswith(f, ".md") || continue
            stats.page_count += 1
            content = read(f, String)
            # Count internal wiki-links  [[slug]]
            stats.link_count += length(collect(eachmatch(r"\[\[([^\]]+)\]\]", content)))
            # Detect orphan marker in frontmatter
            if occursin("orphaned: true", content)
                stats.orphan_count += 1
            end
        end
    end

    # Count query pages
    if isdir(config.queries_dir)
        for f in readdir(config.queries_dir; join=true)
            endswith(f, ".md") || continue
            stats.query_count += 1
        end
    end

    # Last compiled timestamp from state
    state = load_state(config)
    latest = nothing
    for (_, entry) in state.sources
        ts = entry.compiled_at
        isempty(ts) && continue
        if latest === nothing || ts > latest
            latest = ts
        end
    end
    stats.last_compiled = latest

    stats
end
