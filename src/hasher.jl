# ──────────────────────────────────────────────────────────────────────────────
# hasher.jl — SHA-256 change detection for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────

"""
    hash_file(path::String) -> String

Compute the SHA-256 hex digest of the file at `path`.
"""
function hash_file(path::String)::String
    bytes2hex(open(io -> sha256(io), path, "r"))
end

"""
    detect_changes(config::WikiConfig, state::WikiState) -> Vector{SourceChange}

Walk `config.sources_dir`, compare each file's SHA-256 hash against the
recorded state, and classify every file as `NEW`, `CHANGED`, `UNCHANGED`,
or `DELETED`.

Files whose path previously appeared in `state.sources` but no longer exist
on disk are reported as `DELETED`.
"""
function detect_changes(config::WikiConfig, state::WikiState)::Vector{SourceChange}
    changes = SourceChange[]
    seen = Set{String}()

    if isdir(config.sources_dir)
        for (root, _, files) in walkdir(config.sources_dir)
            for fname in files
                fpath = joinpath(root, fname)
                relpath_str = relpath(fpath, config.sources_dir)
                push!(seen, relpath_str)

                current_hash = hash_file(fpath)

                if !haskey(state.sources, relpath_str)
                    push!(changes, SourceChange(file=relpath_str, status=NEW))
                elseif state.sources[relpath_str].hash != current_hash
                    push!(changes, SourceChange(file=relpath_str, status=CHANGED))
                else
                    push!(changes, SourceChange(file=relpath_str, status=UNCHANGED))
                end
            end
        end
    end

    # Detect deletions — files in state but no longer on disk
    for key in keys(state.sources)
        if key ∉ seen
            push!(changes, SourceChange(file=key, status=DELETED))
        end
    end

    changes
end
