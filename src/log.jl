# ──────────────────────────────────────────────────────────────────────────────
# log.jl — Operation log for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Every significant operation (compile, query, lint, …) is recorded in
# `wiki/log.md` as a human-readable audit trail.

"""
    log_operation!(config::WikiConfig, operation::Symbol, details::String)

Append an entry to the wiki operation log at `config.log_file`.

Each entry is formatted as:
```
## [2026-04-06T19:00:00] operation | details
```
"""
function log_operation!(config::WikiConfig, operation::Symbol, details::String)
    mkpath(dirname(config.log_file))
    timestamp = Dates.format(Dates.now(), dateformat"yyyy-mm-ddTHH:MM:SS")
    open(config.log_file, "a") do io
        println(io, "## [$timestamp] $operation | $details")
        println(io)
    end
    nothing
end

"""
    read_log(config::WikiConfig) -> Vector{NamedTuple{(:timestamp,:operation,:details), Tuple{String,String,String}}}

Parse the wiki operation log and return a vector of named tuples.
Lines that do not match the expected format are silently skipped.
"""
function read_log(config::WikiConfig)
    entries = NamedTuple{(:timestamp, :operation, :details), Tuple{String,String,String}}[]
    isfile(config.log_file) || return entries

    pattern = r"^## \[([^\]]+)\]\s+(\S+)\s+\|\s+(.*)$"

    for line in eachline(config.log_file)
        m = match(pattern, line)
        m === nothing && continue
        push!(entries, (
            timestamp = String(m.captures[1]),
            operation = String(m.captures[2]),
            details   = String(m.captures[3]),
        ))
    end

    entries
end
