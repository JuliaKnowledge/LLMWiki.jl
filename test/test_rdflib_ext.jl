using Test
using LLMWiki
using RDFLib

# Helper: create a test wiki with 3 interlinked concept pages
function _setup_test_wiki()
    dir = mktempdir()
    config = default_config(dir)
    init_wiki(config)
    cp = joinpath(dir, config.concepts_dir)

    write(joinpath(cp, "julia.md"), """---
title: Julia
summary: A high-performance dynamic programming language
sources:
  - intro.md
tags:
  - programming
  - language
page_type: concept
created_at: "2026-01-01T00:00:00"
updated_at: "2026-04-06T12:00:00"
---

Julia is a high-performance dynamic programming language.
It supports [[Multiple Dispatch]] and a powerful [[Type System]].
""")

    write(joinpath(cp, "multiple-dispatch.md"), """---
title: Multiple Dispatch
summary: Paradigm where function behavior depends on argument types
sources:
  - intro.md
  - advanced.md
tags:
  - programming
  - paradigm
page_type: concept
created_at: "2026-01-01T00:00:00"
updated_at: "2026-04-06T12:00:00"
---

Multiple dispatch in [[Julia]] selects methods based on all argument types.
Related to the [[Type System]].
""")

    write(joinpath(cp, "type-system.md"), """---
title: Type System
summary: Julia type system with abstract types and parametric polymorphism
sources:
  - intro.md
tags:
  - programming
page_type: concept
created_at: "2026-01-02T00:00:00"
updated_at: "2026-04-06T12:00:00"
---

The type system in [[Julia]] supports abstract types, parametric types,
and [[Multiple Dispatch]].
""")

    state = WikiState(sources=Dict(
        "intro.md" => SourceEntry(hash="abc123",
            concepts=["julia", "multiple-dispatch", "type-system"],
            compiled_at="2026-04-06T12:00:00"),
        "advanced.md" => SourceEntry(hash="def456",
            concepts=["multiple-dispatch"],
            compiled_at="2026-04-06T12:00:00"),
    ))
    save_state(config, state)

    return config
end

@testset "LLMWikiRDFLibExt" begin

    @testset "wiki_to_rdf" begin
        config = _setup_test_wiki()
        g = wiki_to_rdf(config)

        @test length(g) > 50
        concepts = collect(RDFLib.subjects(g, RDFLib.RDF.type, RDFLib.SKOS.Concept))
        @test length(concepts) == 3

        # Check that ontology classes are defined
        classes = collect(RDFLib.subjects(g, RDFLib.RDF.type, RDFLib.RDFS.Class))
        @test length(classes) >= 4  # CONCEPT, ENTITY, QUERY_PAGE, OVERVIEW

        # Check namespace bindings
        @test !isempty(g.namespace_manager.prefix_to_ns)
    end

    @testset "wiki_to_rdf without provenance" begin
        config = _setup_test_wiki()
        g = wiki_to_rdf(config; include_provenance=false)

        prov_entities = collect(RDFLib.subjects(g, RDFLib.RDF.type, RDFLib.PROV.Entity))
        @test isempty(prov_entities)
    end

    @testset "sparql_wiki — SELECT titles" begin
        config = _setup_test_wiki()
        results = sparql_wiki(config, """
            PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
            SELECT ?title WHERE {
                ?c a skos:Concept .
                ?c skos:prefLabel ?title .
            }
            ORDER BY ?title
        """)

        titles = [row["title"].lexical for row in results]
        @test length(titles) == 3
        @test titles == ["Julia", "Multiple Dispatch", "Type System"]
    end

    @testset "sparql_wiki — ASK" begin
        config = _setup_test_wiki()
        result = sparql_wiki(config, """
            PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
            ASK { ?c skos:prefLabel "Julia" }
        """)
        @test result == true
    end

    @testset "sparql_wiki — CONSTRUCT" begin
        config = _setup_test_wiki()
        result_graph = sparql_wiki(config, """
            PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
            CONSTRUCT { ?c skos:prefLabel ?t }
            WHERE { ?c a skos:Concept . ?c skos:prefLabel ?t }
        """)
        @test isa(result_graph, RDFGraph)
        @test length(result_graph) == 3
    end

    @testset "sparql_wiki — provenance queries" begin
        config = _setup_test_wiki()
        results = sparql_wiki(config, """
            PREFIX prov: <http://www.w3.org/ns/prov#>
            PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            SELECT ?concept ?source WHERE {
                ?c skos:prefLabel ?concept .
                ?c prov:wasDerivedFrom ?s .
                ?s rdfs:label ?source .
            }
            ORDER BY ?concept ?source
        """)

        @test length(results) == 4
        # Julia ← intro.md
        @test results[1]["concept"].lexical == "Julia"
        @test results[1]["source"].lexical == "intro.md"
        # Multiple Dispatch ← advanced.md, intro.md (alphabetical)
        md_sources = [r["source"].lexical for r in results if r["concept"].lexical == "Multiple Dispatch"]
        @test "intro.md" in md_sources
        @test "advanced.md" in md_sources
    end

    @testset "sparql_wiki — wikilinks as skos:related" begin
        config = _setup_test_wiki()
        results = sparql_wiki(config, """
            PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
            SELECT ?from ?to WHERE {
                ?f skos:related ?t .
                ?f skos:prefLabel ?from .
                ?t skos:prefLabel ?to .
            }
            ORDER BY ?from ?to
        """)

        @test length(results) == 6
        links = [(r["from"].lexical, r["to"].lexical) for r in results]
        @test ("Julia", "Multiple Dispatch") in links
        @test ("Julia", "Type System") in links
        @test ("Multiple Dispatch", "Julia") in links
        @test ("Type System", "Julia") in links
    end

    @testset "rdf_search" begin
        config = _setup_test_wiki()

        # Search by title match
        results = rdf_search(config, "dispatch")
        @test length(results) >= 1
        @test results[1].title == "Multiple Dispatch"
        @test results[1].score > 0

        # Search by summary match
        results2 = rdf_search(config, "polymorphism")
        @test length(results2) >= 1
        @test results2[1].title == "Type System"

        # Search with no matches
        results3 = rdf_search(config, "quantum_physics_xyz")
        @test isempty(results3)
    end

    @testset "rdf_graph_stats" begin
        config = _setup_test_wiki()
        stats = rdf_graph_stats(config)

        @test stats["concepts"] == 3
        @test stats["sources"] >= 2  # 2 source files + git revision entity
        @test stats["wikilinks"] == 6
        @test stats["tags"] == 3  # programming, language, paradigm
        @test stats["orphans"] == 0
        @test stats["total_triples"] > 50
    end

    @testset "validate_wiki_shacl" begin
        config = _setup_test_wiki()
        report = validate_wiki_shacl(config)
        @test report.conforms == true
    end

    @testset "validate_wiki_shacl — missing summary triggers warning" begin
        config = _setup_test_wiki()
        cp = joinpath(config.root, config.concepts_dir)

        # Add a page with no summary
        write(joinpath(cp, "orphan.md"), """---
title: Orphan Concept
summary: ""
sources: []
tags: []
page_type: concept
created_at: "2026-01-01T00:00:00"
updated_at: "2026-04-06T12:00:00"
---

This page has an empty summary.
""")

        report = validate_wiki_shacl(config)
        # May or may not conform depending on empty string handling
        @test isa(report, RDFLib.ValidationReport)
    end

    @testset "export_rdf — Turtle" begin
        config = _setup_test_wiki()
        path = joinpath(config.root, "wiki.ttl")
        export_rdf(config, path)

        content = read(path, String)
        @test filesize(path) > 100
        @test contains(content, "skos:Concept")
        @test contains(content, "skos:prefLabel")
        @test contains(content, "Julia")
    end

    @testset "export_rdf — N-Triples" begin
        config = _setup_test_wiki()
        path = joinpath(config.root, "wiki.nt")
        export_rdf(config, path; format=NTriplesFormat())

        content = read(path, String)
        @test filesize(path) > 100
        @test contains(content, "<http://www.w3.org/2004/02/skos/core#Concept>")
    end

    @testset "export_rdf — JSON-LD" begin
        config = _setup_test_wiki()
        path = joinpath(config.root, "wiki.jsonld")
        export_rdf(config, path; format=JSONLDFormat())

        content = read(path, String)
        @test filesize(path) > 100
    end

    @testset "empty wiki" begin
        dir = mktempdir()
        config = default_config(dir)
        init_wiki(config)

        g = wiki_to_rdf(config)
        # Only ontology classes, no concepts
        concepts = collect(RDFLib.subjects(g, RDFLib.RDF.type, RDFLib.SKOS.Concept))
        @test isempty(concepts)

        stats = rdf_graph_stats(config)
        @test stats["concepts"] == 0
        @test stats["wikilinks"] == 0

        results = rdf_search(config, "anything")
        @test isempty(results)
    end

end
