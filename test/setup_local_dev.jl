#!/usr/bin/env julia
# setup_local_dev.jl — develop sibling repos into the LLMWiki test env
#
# `Pkg.test()` for LLMWiki previously relied on `[sources]` entries pointing
# AgentFramework/RDFLib at their GitHub URLs. That pulls remote `main` (not
# the local sibling checkout) and does not cover the transitive unregistered
# `Mem0` dependency at all, so `Pkg.test()` could fail entirely in a fresh
# depot. This script instead `Pkg.develop`s the local sibling checkouts, so:
#
#   * the LLMWikiAgentFrameworkExt, LLMWikiMem0Ext, and LLMWikiRDFLibExt
#     extensions are precompiled and exercised against local code
#   * `Pkg.test()` no longer needs network access to GitHub for these
#
# AzureIdentity.jl is also developed here: both AgentFramework.jl and Mem0.jl
# declare it as a (further unregistered) weakdep, and Pkg's resolver needs it
# to be resolvable when developing AgentFramework/Mem0 together, even though
# LLMWiki itself never loads AzureIdentity directly.
#
# Usage:
#   julia --project=. test/setup_local_dev.jl
#   julia --project=. -e 'using Pkg; Pkg.test()'
#
# Assumes AgentFramework.jl, Mem0.jl, RDFLib.jl, and AzureIdentity.jl are
# sibling directories of LLMWiki.jl in juliaknowledge/.

using Pkg

repo_root = abspath(joinpath(@__DIR__, "..", ".."))

specs = Pkg.PackageSpec[]
for name in ("AgentFramework.jl", "Mem0.jl", "RDFLib.jl", "AzureIdentity.jl")
    p = joinpath(repo_root, name)
    if isdir(p)
        push!(specs, Pkg.PackageSpec(path=p))
        @info "Will develop $name from $p"
    else
        @warn "$name not found at $p; corresponding extension tests will be skipped"
    end
end

if !isempty(specs)
    Pkg.develop(specs)
end

Pkg.resolve()
Pkg.instantiate()
@info "Local dev setup complete. Run: julia --project=. -e 'using Pkg; Pkg.test()'"
