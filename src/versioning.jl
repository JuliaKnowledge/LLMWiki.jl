# ──────────────────────────────────────────────────────────────────────────────
# versioning.jl — Git-backed wiki versioning for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Provides atomic, agent-attributed version control for wiki pages.
# Inspired by Persevere's document versioning design:
#   - Auto-init git repo in wiki directory
#   - Atomic commits after compile! cycles (batch all changes)
#   - Per-page history and diffs
#   - Agent-attributed authorship on commits

const DEFAULT_WIKI_GIT_AUTHOR = "LLMWiki Compiler <sdwfrost@users.noreply.github.com>"

# ── Git detection and initialisation ─────────────────────────────────────────

"""
    git_init!(config::WikiConfig)

Initialise a Git repository in the wiki directory if one does not already exist.
Creates an initial commit with any existing files. Safe to call on an
already-initialised repository (no-op).
"""
function git_init!(config::WikiConfig)
    resolve_paths!(config)
    wiki_dir = config.wiki_dir
    isdir(wiki_dir) || mkpath(wiki_dir)

    git_dir = joinpath(wiki_dir, ".git")
    if isdir(git_dir)
        @info "Git repository already initialised" path=wiki_dir
        return nothing
    end

    _git(wiki_dir, ["init", "-q"])

    # Create .gitignore for temporary files
    gitignore_path = joinpath(wiki_dir, ".gitignore")
    if !isfile(gitignore_path)
        write(gitignore_path, "*.tmp\n*.swp\n*~\n.DS_Store\n")
    end

    # Stage everything and make initial commit if there are files
    _git(wiki_dir, ["add", "-A"])
    if _has_staged_changes(wiki_dir)
        _git(wiki_dir, ["commit", "-q", "-m", "Initialise LLMWiki",
             "--author", DEFAULT_WIKI_GIT_AUTHOR])
    end

    @info "Initialised Git versioning" path=wiki_dir
    nothing
end

"""
    _has_git(config::WikiConfig) -> Bool

Check whether the wiki directory has a Git repository.
"""
function _has_git(config::WikiConfig)::Bool
    isdir(joinpath(config.wiki_dir, ".git"))
end

# ── Atomic snapshots ─────────────────────────────────────────────────────────

"""
    git_snapshot!(config::WikiConfig, message::String;
                  author::String=DEFAULT_WIKI_GIT_AUTHOR) -> Union{String, Nothing}

Stage all changes in the wiki directory and create a single atomic commit.
Returns the commit hash, or `nothing` if there were no changes to commit.

This is designed to be called at the end of `compile!` to batch all page
creations, updates, and deletions into one commit — avoiding repository
pollution from intermediate steps.
"""
function git_snapshot!(config::WikiConfig, message::String;
                       author::String=DEFAULT_WIKI_GIT_AUTHOR)
    _has_git(config) || return nothing

    wiki_dir = config.wiki_dir
    _git(wiki_dir, ["add", "-A"])

    if !_has_staged_changes(wiki_dir)
        return nothing
    end

    _git(wiki_dir, ["commit", "-q", "-m", message, "--author", author])
    hash = strip(String(_git_output(wiki_dir, ["rev-parse", "HEAD"])))
    @info "Git snapshot" commit=hash message=message
    return hash
end

# ── History and diffs ────────────────────────────────────────────────────────

"""
    VersionEntry

A single entry in a page's version history.
"""
Base.@kwdef struct VersionEntry
    hash::String
    author::String
    date::String
    message::String
end

"""
    wiki_history(config::WikiConfig, slug::String; limit::Int=20) -> Vector{VersionEntry}

Return the Git commit history for a specific wiki page.
Each entry includes the commit hash, author, date, and message.
Returns an empty vector if Git is not initialised or the page has no history.
"""
function wiki_history(config::WikiConfig, slug::String; limit::Int=20)
    resolve_paths!(config)
    _has_git(config) || return VersionEntry[]

    # Determine the file path relative to the wiki dir
    page_file = _find_page_file(config, slug)
    page_file === nothing && return VersionEntry[]

    rel_path = relpath(page_file, config.wiki_dir)

    entries = VersionEntry[]
    try
        output = String(_git_output(config.wiki_dir, [
            "log", "--format=%H|%an <%ae>|%aI|%s",
            "-n", string(limit), "--", rel_path
        ]))
        for line in split(strip(output), '\n')
            isempty(strip(line)) && continue
            parts = split(line, '|'; limit=4)
            length(parts) >= 4 || continue
            push!(entries, VersionEntry(
                hash    = String(parts[1]),
                author  = String(parts[2]),
                date    = String(parts[3]),
                message = String(parts[4]),
            ))
        end
    catch e
        @warn "Failed to read git history" slug=slug exception=e
    end

    return entries
end

"""
    wiki_diff(config::WikiConfig, slug::String;
              from::Union{String,Nothing}=nothing,
              to::Union{String,Nothing}=nothing) -> String

Return a unified diff for a wiki page between two versions.

- If neither `from` nor `to` is specified, shows uncommitted changes.
- If only `from` is given, diffs from that commit to the working tree.
- If both are given, diffs between those two commits.
- `from` and `to` can be commit hashes, "HEAD", "HEAD~1", etc.

Returns an empty string if Git is not initialised, the page doesn't exist,
or there are no differences.
"""
function wiki_diff(config::WikiConfig, slug::String;
                   from::Union{String,Nothing}=nothing,
                   to::Union{String,Nothing}=nothing)
    resolve_paths!(config)
    _has_git(config) || return ""

    page_file = _find_page_file(config, slug)
    page_file === nothing && return ""

    rel_path = relpath(page_file, config.wiki_dir)

    try
        args = ["diff", "--no-color"]
        if from !== nothing && to !== nothing
            push!(args, "$from..$to")
        elseif from !== nothing
            push!(args, from)
        end
        push!(args, "--")
        push!(args, rel_path)

        return String(_git_output(config.wiki_dir, args))
    catch e
        @warn "Failed to compute diff" slug=slug exception=e
        return ""
    end
end

"""
    wiki_log(config::WikiConfig; limit::Int=20) -> Vector{VersionEntry}

Return the overall Git commit history for the entire wiki.
"""
function wiki_log(config::WikiConfig; limit::Int=20)
    resolve_paths!(config)
    _has_git(config) || return VersionEntry[]

    entries = VersionEntry[]
    try
        output = String(_git_output(config.wiki_dir, [
            "log", "--format=%H|%an <%ae>|%aI|%s", "-n", string(limit)
        ]))
        for line in split(strip(output), '\n')
            isempty(strip(line)) && continue
            parts = split(line, '|'; limit=4)
            length(parts) >= 4 || continue
            push!(entries, VersionEntry(
                hash    = String(parts[1]),
                author  = String(parts[2]),
                date    = String(parts[3]),
                message = String(parts[4]),
            ))
        end
    catch e
        @warn "Failed to read git log" exception=e
    end

    return entries
end

# ── Internal helpers ─────────────────────────────────────────────────────────

"""Find the filesystem path for a page slug (checks concepts/ then queries/)."""
function _find_page_file(config::WikiConfig, slug::String)
    for dir in (config.concepts_dir, config.queries_dir)
        path = joinpath(dir, "$slug.md")
        isfile(path) && return path
    end
    return nothing
end

"""Run a git command in the given directory. Throws on failure."""
function _git(dir::String, args::Vector{String})
    cmd = Cmd(`git $args`; dir=dir)
    run(cmd)
end

"""Run a git command and capture stdout."""
function _git_output(dir::String, args::Vector{String})::Vector{UInt8}
    cmd = Cmd(`git $args`; dir=dir)
    return read(cmd)
end

"""Check if there are staged changes ready to commit."""
function _has_staged_changes(dir::String)::Bool
    try
        cmd = Cmd(`git diff --cached --quiet`; dir=dir)
        success(cmd) && return false  # exit 0 = no changes
        return true
    catch
        return true  # if git diff fails, assume there are changes
    end
end
