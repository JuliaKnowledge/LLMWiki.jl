using Documenter
using LLMWiki

makedocs(;
    sitename = "LLMWiki.jl",
    modules = [LLMWiki],
    remotes = nothing,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://juliaknowledge.github.io/LLMWiki.jl",
        edit_link = "main",
        repolink = "https://github.com/JuliaKnowledge/LLMWiki.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Guide" => [
            "Getting Started" => "guide/getting-started.md",
            "Configuration" => "guide/configuration.md",
            "Compilation Pipeline" => "guide/compilation.md",
            "Search & Query" => "guide/search-query.md",
            "Extensions" => "guide/extensions.md",
            "Versioning & Provenance" => "guide/versioning.md",
            "Architecture" => "guide/architecture.md",
        ],
        "API Reference" => [
            "Types" => "api/types.md",
            "Operations" => "api/operations.md",
            "Utilities" => "api/utilities.md",
        ],
    ],
    warnonly = [:missing_docs, :cross_references, :docs_block],
)

deploydocs(;
    repo = "github.com/JuliaKnowledge/LLMWiki.jl.git",
    devbranch = "main",
)
