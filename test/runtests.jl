using Test
using LLMWiki

@testset "LLMWiki.jl" begin
    include("test_types.jl")
    include("test_frontmatter.jl")
    include("test_markdown_utils.jl")
    include("test_config.jl")
    include("test_state.jl")
    include("test_hasher.jl")
    include("test_ingest.jl")
    include("test_search.jl")
    include("test_extensions.jl")
    include("test_lint.jl")
    include("test_log.jl")
    include("test_versioning.jl")
    include("test_rdflib_ext.jl")
end
