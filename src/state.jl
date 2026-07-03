# ──────────────────────────────────────────────────────────────────────────────
# state.jl — Persistent state management for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Wiki state is stored as JSON in `.llmwiki/state.json`. All writes go
# through an atomic rename to avoid corruption on crash.

const LOCK_FILENAME = "lock"
const LOCK_OWNER_FILENAME = "owner.json"
const LOCK_STALE_SECONDS = 3600.0
const LOCK_HEARTBEAT_SECONDS = 30.0
const ACTIVE_LOCK_TOKENS = Dict{String,String}()
const ACTIVE_LOCK_TIMERS = Dict{String,Timer}()
const LOCK_STATE_GUARD = ReentrantLock()

"""
    load_state(config::WikiConfig) -> WikiState

Read the wiki state from `config.state_file`. Returns an empty `WikiState`
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
        @warn "Failed to load wiki state; starting fresh" path exception=e
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

Full path to the lock directory.
"""
_lock_path(config::WikiConfig) = joinpath(config.state_dir, LOCK_FILENAME)

_lock_owner_path(lock_path::String) = joinpath(lock_path, LOCK_OWNER_FILENAME)

function _write_lock_metadata(lock_path::String, token::String)
    payload = Dict(
        "token" => token,
        "pid" => getpid(),
        "heartbeat_at" => Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS"),
    )
    open(_lock_owner_path(lock_path), "w") do io
        write(io, JSON3.write(payload))
    end
    nothing
end

function _read_lock_metadata(lock_path::String)::Dict{String,Any}
    owner_path = _lock_owner_path(lock_path)
    isfile(owner_path) || return Dict{String,Any}()

    try
        data = JSON3.read(read(owner_path, String))
        data isa AbstractDict || return Dict{String,Any}()
        Dict{String,Any}(string(k) => v for (k, v) in pairs(data))
    catch
        Dict{String,Any}()
    end
end

function _lock_age_seconds(lock_path::String; now_time::Float64=time())::Float64
    mtimes = Float64[]
    isdir(lock_path) && push!(mtimes, mtime(lock_path))
    owner_path = _lock_owner_path(lock_path)
    isfile(owner_path) && push!(mtimes, mtime(owner_path))
    isempty(mtimes) && return Inf
    now_time - maximum(mtimes)
end

_lock_is_stale(lock_path::String; now_time::Float64=time()) = _lock_age_seconds(lock_path; now_time=now_time) > LOCK_STALE_SECONDS

function _remember_active_lock!(lock_path::String, token::String)
    lock(LOCK_STATE_GUARD)
    try
        ACTIVE_LOCK_TOKENS[lock_path] = token
    finally
        unlock(LOCK_STATE_GUARD)
    end
    nothing
end

function _active_lock_token(lock_path::String)
    lock(LOCK_STATE_GUARD)
    try
        get(ACTIVE_LOCK_TOKENS, lock_path, nothing)
    finally
        unlock(LOCK_STATE_GUARD)
    end
end

function _forget_active_lock!(lock_path::String)
    timer = nothing
    lock(LOCK_STATE_GUARD)
    try
        timer = pop!(ACTIVE_LOCK_TIMERS, lock_path, nothing)
        pop!(ACTIVE_LOCK_TOKENS, lock_path, nothing)
    finally
        unlock(LOCK_STATE_GUARD)
    end

    timer isa Timer && close(timer)
    nothing
end

function _start_lock_heartbeat!(lock_path::String, token::String)
    timer = Timer(LOCK_HEARTBEAT_SECONDS; interval=LOCK_HEARTBEAT_SECONDS) do _
        _active_lock_token(lock_path) == token || return
        isdir(lock_path) || return
        metadata = _read_lock_metadata(lock_path)
        get(metadata, "token", nothing) == token || return
        try
            _write_lock_metadata(lock_path, token)
        catch
        end
    end

    lock(LOCK_STATE_GUARD)
    try
        ACTIVE_LOCK_TIMERS[lock_path] = timer
    finally
        unlock(LOCK_STATE_GUARD)
    end
    nothing
end

function _break_stale_lock!(lock_path::String)
    _forget_active_lock!(lock_path)
    if isdir(lock_path)
        rm(lock_path; recursive=true, force=true)
    elseif isfile(lock_path)
        rm(lock_path; force=true)
    end
    nothing
end

"""
    acquire_lock(config::WikiConfig) -> Bool

Attempt to create a lock directory under `.llmwiki/lock`. Returns `true` if
the lock was acquired, `false` if another process already holds it.

The lock is created atomically with `mkdir`, stores an owner token and PID in
`owner.json`, and refreshes that file periodically so long compiles do not look
stale. A stale lock (older than `LOCK_STALE_SECONDS`) is automatically broken.
"""
function acquire_lock(config::WikiConfig)::Bool
    mkpath(config.state_dir)
    lock_path = _lock_path(config)
    token = string(getpid(), "-", uuid4())

    for _ in 1:2
        try
            mkdir(lock_path)
            try
                _write_lock_metadata(lock_path, token)
            catch
                rm(lock_path; recursive=true, force=true)
                rethrow()
            end
            _remember_active_lock!(lock_path, token)
            _start_lock_heartbeat!(lock_path, token)
            return true
        catch
            if !isdir(lock_path)
                return false
            end

            age_seconds = _lock_age_seconds(lock_path)
            if _lock_is_stale(lock_path)
                @warn "Breaking stale lock" path=lock_path age_seconds
                _break_stale_lock!(lock_path)
                continue
            end

            return false
        end
    end

    false
end

"""
    release_lock(config::WikiConfig)

Remove the lock directory if this process still owns it. Safe to call even if
no lock is held.
"""
function release_lock(config::WikiConfig)
    lock_path = _lock_path(config)
    token = _active_lock_token(lock_path)
    token === nothing && return nothing

    try
        metadata = _read_lock_metadata(lock_path)
        owner_token = get(metadata, "token", nothing)
        owner_pid = try
            Int(get(metadata, "pid", -1))
        catch
            -1
        end

        if owner_token != token || owner_pid != getpid()
            @warn "Skipping lock release because ownership changed" path=lock_path owner_pid owner_token
            return nothing
        end

        isdir(lock_path) && rm(lock_path; recursive=true, force=true)
    finally
        _forget_active_lock!(lock_path)
    end

    nothing
end
