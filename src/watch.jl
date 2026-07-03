# ──────────────────────────────────────────────────────────────────────────────
# watch.jl — File watcher for LLMWiki.jl auto-recompilation
# ──────────────────────────────────────────────────────────────────────────────

_is_relevant_watch_event(fname::String) = !(startswith(basename(fname), ".") || endswith(fname, ".tmp"))

function _collect_watch_batch(sources_path::String,
                              debounce_seconds::Float64;
                              watch_fn::Function=watch_folder,
                              time_fn::Function=time,
                              pending::Bool=false,
                              last_event_at::Float64=0.0)
    files = String[]
    latest_event_at = last_event_at

    if !pending
        while true
            fname, events = watch_fn(sources_path)
            getproperty(events, :timedout) && continue
            _is_relevant_watch_event(fname) || continue
            @info "Change detected" file=fname
            push!(files, fname)
            latest_event_at = time_fn()
            break
        end
    end

    while true
        remaining = debounce_seconds - (time_fn() - latest_event_at)
        remaining <= 0 && return (files=files, last_event_at=latest_event_at)

        fname, events = watch_fn(sources_path, remaining)
        if getproperty(events, :timedout)
            return (files=files, last_event_at=latest_event_at)
        end
        _is_relevant_watch_event(fname) || continue

        @info "Change detected" file=fname
        push!(files, fname)
        latest_event_at = time_fn()
    end
end

function _drain_watch_events(sources_path::String;
                             watch_fn::Function=watch_folder,
                             time_fn::Function=time)
    files = String[]
    latest_event_at = 0.0

    while true
        fname, events = watch_fn(sources_path, 0.0)
        if getproperty(events, :timedout)
            return (files=files, last_event_at=latest_event_at)
        end
        _is_relevant_watch_event(fname) || continue

        @info "Change detected during compile" file=fname
        push!(files, fname)
        latest_event_at = time_fn()
    end
end

"""
    watch_wiki(config::WikiConfig;
               callback::Union{Nothing,Function}=nothing,
               debounce_seconds::Float64=2.0)

Watch the sources directory for changes and auto-recompile the wiki.

Uses `FileWatching.watch_folder()` to receive filesystem events. Changes are
debounced from the last observed event (not the last compile start/end), and if
more events arrive during a compile the watcher immediately schedules one more
debounced pass before blocking again.

If `callback` is provided, it is called after each successful compilation with
the result `NamedTuple` from `compile!`.

Blocks until interrupted (Ctrl-C / `InterruptException`).
"""
function watch_wiki(config::WikiConfig;
                    callback::Union{Nothing,Function}=nothing,
                    debounce_seconds::Float64=2.0)
    sources_path = joinpath(config.root, config.sources_dir)
    if !isdir(sources_path)
        error("Sources directory does not exist: $sources_path")
    end

    @info "Watching for changes" sources=sources_path debounce=debounce_seconds
    @info "Press Ctrl-C to stop"

    pending = false
    pending_event_at = 0.0

    try
        while true
            batch = _collect_watch_batch(
                sources_path,
                debounce_seconds;
                pending=pending,
                last_event_at=pending_event_at,
            )

            pending = false
            pending_event_at = 0.0

            try
                result = compile!(config)
                @info "Auto-compile complete" compiled=result.compiled skipped=result.skipped deleted=result.deleted
                if callback !== nothing
                    try
                        callback(result)
                    catch cb_err
                        @warn "Watch callback error" exception=(cb_err, catch_backtrace())
                    end
                end
            catch compile_err
                @error "Auto-compilation failed" exception=(compile_err, catch_backtrace())
            end

            drained = _drain_watch_events(sources_path)
            if !isempty(drained.files)
                pending = true
                pending_event_at = drained.last_event_at
            end
        end
    catch e
        if e isa InterruptException
            @info "File watcher stopped"
        else
            rethrow(e)
        end
    finally
        try
            unwatch_folder(sources_path)
        catch
        end
    end

    nothing
end
