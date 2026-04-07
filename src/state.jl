# ──────────────────────────────────────────────────────────────────────────────
# state.jl — Persistent state management for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Wiki state is stored as JSON in `.llmwiki/state.json`.  All writes go
# through an atomic rename to avoid corruption on crash.

const LOCK_FILENAME = "lock"

"""
    load_state(config::WikiConfig) -> WikiState

    Read the wiki state from `config.state_file`.  Returns an empty `WikiState`
if the file does not exist or cannot be parsed.
"""
function load_state(config::WikiConfig)::WikiState
    resolve_paths!(config)
    if config.state_backend == :sqlite
        hasmethod(load_state_sqlite, Tuple{WikiConfig}) || error(
            "SQLite state backend requires `using LLMWiki, SQLite` before loading state.",
        )
        return load_state_sqlite(config)
    end

    path = config.state_file
    isfile(path) || return WikiState()

    try
        json = read(path, String)
        isempty(strip(json)) && return WikiState()
        return JSON3.read(json, WikiState)
    catch e
        @warn "Failed to load wiki state; starting fresh" path exception = e
        return WikiState()
    end
end

"""
    save_state(config::WikiConfig, state::WikiState)

    Persist `state` to `config.state_file` atomically (write to a temporary
file then rename).
"""
function save_state(config::WikiConfig, state::WikiState)
    resolve_paths!(config)
    if config.state_backend == :sqlite
        hasmethod(save_state_sqlite, Tuple{WikiConfig, WikiState}) || error(
            "SQLite state backend requires `using LLMWiki, SQLite` before saving state.",
        )
        save_state_sqlite(config, state)
        return nothing
    end

    mkpath(dirname(config.state_file))
    tmp = config.state_file * ".tmp"
    try
        open(tmp, "w") do io
            JSON3.pretty(io, state)
        end
        mv(tmp, config.state_file; force=true)
    catch e
        # Clean up partial write
        isfile(tmp) && rm(tmp; force=true)
        rethrow(e)
    end
    nothing
end

"""
    update_source_state!(config::WikiConfig, file::String, entry::SourceEntry)

Convenience helper: load state, update the entry for `file`, and save.
"""
function update_source_state!(config::WikiConfig, file::String, entry::SourceEntry)
    state = load_state(config)
    state.sources[file] = entry
    save_state(config, state)
    nothing
end

# ── File-based locking ───────────────────────────────────────────────────────

"""
    _lock_path(config::WikiConfig) -> String

Full path to the lock file.
"""
_lock_path(config::WikiConfig) = joinpath(config.state_dir, LOCK_FILENAME)

"""
    acquire_lock(config::WikiConfig) -> Bool

Attempt to create a lock file under `.llmwiki/lock`.  Returns `true` if the
lock was acquired, `false` if another process already holds it.

A stale lock (older than 10 minutes) is automatically broken.
"""
function acquire_lock(config::WikiConfig)::Bool
    mkpath(config.state_dir)
    lp = _lock_path(config)

    if isfile(lp)
        age_seconds = time() - mtime(lp)
        if age_seconds > 600  # 10 minutes — treat as stale
            @warn "Breaking stale lock" path = lp age_seconds
            rm(lp; force=true)
        else
            return false
        end
    end

    try
        open(lp, "w") do io
            println(io, getpid())
            println(io, Dates.now())
        end
        return true
    catch
        return false
    end
end

"""
    release_lock(config::WikiConfig)

Remove the lock file.  Safe to call even if no lock is held.
"""
function release_lock(config::WikiConfig)
    lp = _lock_path(config)
    isfile(lp) && rm(lp; force=true)
    nothing
end
