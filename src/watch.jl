# ──────────────────────────────────────────────────────────────────────────────
# watch.jl — File watcher for LLMWiki.jl auto-recompilation
# ──────────────────────────────────────────────────────────────────────────────

"""
    watch_wiki(config::WikiConfig;
               callback::Union{Nothing,Function}=nothing,
               debounce_seconds::Float64=2.0)

Watch the sources directory for changes and auto-recompile the wiki.

Uses `FileWatching.watch_folder()` to receive filesystem events.  Changes
are debounced so rapid successive edits trigger only one compilation.

If `callback` is provided, it is called after each successful compilation
with the result `NamedTuple` from `compile!`.

Blocks until interrupted (Ctrl-C / `InterruptException`).

# Example
```julia
config = load_config("./my-wiki")
watch_wiki(config) do result
    println("Compiled \$(result.compiled) pages")
end
```
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

    last_compile = 0.0

    try
        while true
            # Block until a filesystem event occurs
            result = watch_folder(sources_path)
            fname = result[1]
            events = result[2]

            # Skip hidden/temp files
            if startswith(basename(fname), ".") || endswith(fname, ".tmp")
                continue
            end

            @info "Change detected" file=fname

            # Debounce: skip if we compiled very recently
            now_time = time()
            if (now_time - last_compile) < debounce_seconds
                @debug "Debounced" elapsed=(now_time - last_compile)
                continue
            end

            # Small delay to let rapid edits settle
            sleep(debounce_seconds)
            last_compile = time()

            # Run compilation
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
        end
    catch e
        if e isa InterruptException
            @info "File watcher stopped"
        else
            rethrow(e)
        end
    end

    nothing
end
