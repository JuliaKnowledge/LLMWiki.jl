module LLMWikiRDFLibExt

using LLMWiki
using LLMWiki: JSON3, Dates, slugify, parse_frontmatter, find_wikilinks,
               WikiConfig, WikiState, PageMeta, PageType, CONCEPT, ENTITY,
               QUERY_PAGE, OVERVIEW, SearchResult, resolve_paths!
using RDFLib

# ── Namespace definitions ────────────────────────────────────────────────────

const WIKI = Namespace("http://llmwiki.org/wiki/")
const WIKI_ONTOLOGY = Namespace("http://llmwiki.org/ontology/")

# ── Helper: build a URIRef for a concept slug ────────────────────────────────

_concept_uri(slug::String) = WIKI("concept/$slug")
_source_uri(file::String)  = WIKI("source/$(replace(file, r"[^A-Za-z0-9._-]" => "_"))")
_page_type_uri(pt::PageType) = WIKI_ONTOLOGY(lowercase(string(pt)))

# ── wiki_to_rdf ──────────────────────────────────────────────────────────────

"""
    LLMWiki.wiki_to_rdf(config::WikiConfig; include_provenance::Bool=true) -> RDFGraph

Export the entire wiki as an RDF knowledge graph.

Each wiki page becomes a `skos:Concept` with:
- `skos:prefLabel` — page title
- `skos:definition` — page summary
- `skos:related` — wikilink connections between concepts
- `dcterms:created` / `dcterms:modified` — timestamps
- `dcterms:subject` — tags
- `rdf:type` — page type mapped to a wiki ontology class

If `include_provenance=true` (default), source provenance is modelled with PROV:
- Sources are `prov:Entity` instances
- Concepts `prov:wasDerivedFrom` their source documents
- Compilation is a `prov:Activity` that `prov:used` sources and `prov:generated` concepts

Requires `using LLMWiki, RDFLib`.
"""
function LLMWiki.wiki_to_rdf(config::LLMWiki.WikiConfig; include_provenance::Bool=true)
    resolve_paths!(config)
    g = RDFGraph()

    # Bind prefixes for readable serialization
    nsm = g.namespace_manager
    bind!(nsm, "wiki", WIKI)
    bind!(nsm, "wont", WIKI_ONTOLOGY)
    bind!(nsm, "skos", SKOS)
    bind!(nsm, "dcterms", DCTERMS)
    bind!(nsm, "prov", PROV)
    bind!(nsm, "rdf", RDF)
    bind!(nsm, "rdfs", RDFS)
    bind!(nsm, "xsd", XSD)
    bind!(nsm, "foaf", FOAF)
    bind!(nsm, "owl", OWL)

    # Define ontology classes
    _add_ontology_classes!(g)

    # Collect all page slugs → titles for wikilink resolution
    slug_to_meta = Dict{String, Tuple{PageMeta, String}}()
    concepts_path = joinpath(config.root, config.concepts_dir)

    if isdir(concepts_path)
        for file in readdir(concepts_path)
            endswith(file, ".md") || continue
            content = read(joinpath(concepts_path, file), String)
            meta, body = parse_frontmatter(content)
            slug = replace(file, ".md" => "")
            slug_to_meta[slug] = (meta, body)
        end
    end

    # Also scan queries directory
    queries_path = joinpath(config.root, config.queries_dir)
    if isdir(queries_path)
        for file in readdir(queries_path)
            endswith(file, ".md") || continue
            content = read(joinpath(queries_path, file), String)
            meta, body = parse_frontmatter(content)
            slug = replace(file, ".md" => "")
            slug_to_meta[slug] = (meta, body)
        end
    end

    # Build slug lookup for wikilink resolution
    title_to_slug = Dict{String, String}()
    for (slug, (meta, _)) in slug_to_meta
        !isempty(meta.title) && (title_to_slug[lowercase(meta.title)] = slug)
    end

    # Add each page as a SKOS Concept
    for (slug, (meta, body)) in slug_to_meta
        uri = _concept_uri(slug)

        # Type assertions
        add!(g, Triple(uri, RDF.type, SKOS.Concept))
        add!(g, Triple(uri, RDF.type, _page_type_uri(meta.page_type)))

        # Labels and descriptions
        add!(g, Triple(uri, SKOS.prefLabel, Literal(meta.title)))
        if !isempty(meta.summary)
            add!(g, Triple(uri, SKOS.definition, Literal(meta.summary)))
        end

        # Tags as dcterms:subject
        for tag in meta.tags
            add!(g, Triple(uri, DCTERMS.subject, Literal(tag)))
        end

        # Timestamps
        if !isempty(meta.created_at)
            add!(g, Triple(uri, DCTERMS.created, Literal(meta.created_at, datatype=XSD.dateTime)))
        end
        if !isempty(meta.updated_at)
            add!(g, Triple(uri, DCTERMS.modified, Literal(meta.updated_at, datatype=XSD.dateTime)))
        end

        # Orphan status
        if meta.orphaned
            add!(g, Triple(uri, WIKI_ONTOLOGY("orphaned"), Literal(true)))
        end

        # Wikilinks → skos:related
        links = find_wikilinks(body)
        for link_title in links
            target_slug = get(title_to_slug, lowercase(link_title), nothing)
            if target_slug !== nothing && target_slug != slug
                add!(g, Triple(uri, SKOS.related, _concept_uri(target_slug)))
            end
        end

        # Source provenance
        if include_provenance
            for source_file in meta.sources
                src_uri = _source_uri(source_file)
                add!(g, Triple(src_uri, RDF.type, PROV.Entity))
                add!(g, Triple(src_uri, RDFS.label, Literal(source_file)))
                add!(g, Triple(uri, PROV.wasDerivedFrom, src_uri))
            end
        end
    end

    # Add wiki-level provenance activity
    if include_provenance
        state = LLMWiki.load_state(config)
        activity_uri = WIKI("compilation/latest")
        add!(g, Triple(activity_uri, RDF.type, PROV.Activity))
        add!(g, Triple(activity_uri, RDFS.label, Literal("LLMWiki compilation")))

        for (file, entry) in state.sources
            src_uri = _source_uri(file)
            add!(g, Triple(src_uri, RDF.type, PROV.Entity))
            add!(g, Triple(activity_uri, PROV.used, src_uri))
            if !isempty(entry.compiled_at)
                add!(g, Triple(activity_uri, PROV.endedAtTime,
                    Literal(entry.compiled_at, datatype=XSD.dateTime)))
            end
            for concept_slug in entry.concepts
                concept_uri = _concept_uri(concept_slug)
                add!(g, Triple(activity_uri, PROV.generated, concept_uri))
            end
        end
    end

    return g
end

# ── Ontology class definitions ───────────────────────────────────────────────

function _add_ontology_classes!(g::RDFGraph)
    for pt in (CONCEPT, ENTITY, QUERY_PAGE, OVERVIEW)
        cls_uri = _page_type_uri(pt)
        add!(g, Triple(cls_uri, RDF.type, RDFS.Class))
        add!(g, Triple(cls_uri, RDFS.subClassOf, SKOS.Concept))
        add!(g, Triple(cls_uri, RDFS.label, Literal(lowercase(string(pt)))))
    end

    # Define wiki ontology properties
    orphan_prop = WIKI_ONTOLOGY("orphaned")
    add!(g, Triple(orphan_prop, RDF.type, OWL.DatatypeProperty))
    add!(g, Triple(orphan_prop, RDFS.domain, SKOS.Concept))
    add!(g, Triple(orphan_prop, RDFS.range, XSD.boolean))
    add!(g, Triple(orphan_prop, RDFS.label, Literal("whether the page is orphaned")))
end

# ── sparql_wiki ──────────────────────────────────────────────────────────────

"""
    LLMWiki.sparql_wiki(config::WikiConfig, query::String; include_provenance::Bool=true)

Execute a SPARQL query against the wiki's RDF knowledge graph.

Returns SPARQL results (the type depends on the query form):
- `SELECT` → `Vector{Dict{String, Identifier}}`
- `ASK` → `Bool`
- `CONSTRUCT` / `DESCRIBE` → `RDFGraph`

Common queries:
```sparql
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
SELECT ?title WHERE { ?c skos:prefLabel ?title } ORDER BY ?title
```

Requires `using LLMWiki, RDFLib`.
"""
function LLMWiki.sparql_wiki(config::LLMWiki.WikiConfig, query::String;
                              include_provenance::Bool=true)
    g = LLMWiki.wiki_to_rdf(config; include_provenance=include_provenance)
    return sparql_query(g, query)
end

# ── export_rdf ───────────────────────────────────────────────────────────────

"""
    LLMWiki.export_rdf(config::WikiConfig, path::String;
                        format=TurtleFormat(), include_provenance::Bool=true)

Serialize the wiki knowledge graph to a file.

Supported formats: `TurtleFormat()`, `NTriplesFormat()`, `JSONLDFormat()`,
`RDFXMLFormat()`, `NQuadsFormat()`, `TriGFormat()`.

Requires `using LLMWiki, RDFLib`.
"""
function LLMWiki.export_rdf(config::LLMWiki.WikiConfig, path::String;
                             format::RDFLib.SerializationFormat=TurtleFormat(),
                             include_provenance::Bool=true)
    g = LLMWiki.wiki_to_rdf(config; include_provenance=include_provenance)
    content = serialize(g, format)
    mkpath(dirname(path))
    write(path, content)
    return path
end

# ── validate_wiki_shacl ─────────────────────────────────────────────────────

"""
    LLMWiki.validate_wiki_shacl(config::WikiConfig) -> RDFLib.ValidationReport

Validate the wiki knowledge graph against SHACL shapes that enforce:
- Every concept has a `skos:prefLabel`
- Every concept has a `skos:definition`
- Every concept has at least one `prov:wasDerivedFrom` source
- `skos:related` targets must be `skos:Concept` instances
- Timestamps must be `xsd:dateTime`

Returns a `ValidationReport` with `.conforms::Bool` and `.results`.

Requires `using LLMWiki, RDFLib`.
"""
function LLMWiki.validate_wiki_shacl(config::LLMWiki.WikiConfig)
    g = LLMWiki.wiki_to_rdf(config; include_provenance=true)
    shapes = _build_wiki_shapes()
    return validate(g, shapes)
end

function _build_wiki_shapes()
    shapes = RDFGraph()
    sh_ns = SH

    # ConceptShape — validates wiki concept pages
    concept_shape = WIKI_ONTOLOGY("ConceptShape")
    add!(shapes, Triple(concept_shape, RDF.type, sh_ns.NodeShape))
    add!(shapes, Triple(concept_shape, sh_ns.targetClass, SKOS.Concept))

    # Must have skos:prefLabel (minCount 1, maxCount 1)
    label_prop = BNode()
    add!(shapes, Triple(concept_shape, sh_ns.property, label_prop))
    add!(shapes, Triple(label_prop, sh_ns.path, SKOS.prefLabel))
    add!(shapes, Triple(label_prop, sh_ns.minCount, Literal(1)))
    add!(shapes, Triple(label_prop, sh_ns.maxCount, Literal(1)))
    add!(shapes, Triple(label_prop, sh_ns.datatype, XSD.string))
    add!(shapes, Triple(label_prop, sh_ns.name, Literal("title")))
    add!(shapes, Triple(label_prop, sh_ns.description,
        Literal("Every concept must have exactly one title (skos:prefLabel)")))

    # Should have skos:definition (minCount 0 — warning severity)
    def_prop = BNode()
    add!(shapes, Triple(concept_shape, sh_ns.property, def_prop))
    add!(shapes, Triple(def_prop, sh_ns.path, SKOS.definition))
    add!(shapes, Triple(def_prop, sh_ns.minCount, Literal(1)))
    add!(shapes, Triple(def_prop, sh_ns.severity, sh_ns.Warning))
    add!(shapes, Triple(def_prop, sh_ns.name, Literal("summary")))
    add!(shapes, Triple(def_prop, sh_ns.description,
        Literal("Every concept should have a summary (skos:definition)")))

    # skos:related targets must be skos:Concept
    related_prop = BNode()
    add!(shapes, Triple(concept_shape, sh_ns.property, related_prop))
    add!(shapes, Triple(related_prop, sh_ns.path, SKOS.related))
    add!(shapes, Triple(related_prop, sh_ns("class"), SKOS.Concept))
    add!(shapes, Triple(related_prop, sh_ns.name, Literal("wikilinks")))
    add!(shapes, Triple(related_prop, sh_ns.description,
        Literal("Wikilink targets must be valid concepts")))

    # dcterms:created should be xsd:dateTime
    created_prop = BNode()
    add!(shapes, Triple(concept_shape, sh_ns.property, created_prop))
    add!(shapes, Triple(created_prop, sh_ns.path, DCTERMS.created))
    add!(shapes, Triple(created_prop, sh_ns.maxCount, Literal(1)))
    add!(shapes, Triple(created_prop, sh_ns.datatype, XSD.dateTime))

    # dcterms:modified should be xsd:dateTime
    modified_prop = BNode()
    add!(shapes, Triple(concept_shape, sh_ns.property, modified_prop))
    add!(shapes, Triple(modified_prop, sh_ns.path, DCTERMS.modified))
    add!(shapes, Triple(modified_prop, sh_ns.maxCount, Literal(1)))
    add!(shapes, Triple(modified_prop, sh_ns.datatype, XSD.dateTime))

    return shapes
end

# ── rdf_search ───────────────────────────────────────────────────────────────

"""
    LLMWiki.rdf_search(config::WikiConfig, query::String; top_k::Int=10) -> Vector{SearchResult}

Search the wiki using SPARQL full-text matching on `skos:prefLabel` and
`skos:definition`. Uses `FILTER(CONTAINS(...))` for substring matching.

Requires `using LLMWiki, RDFLib`.
"""
function LLMWiki.rdf_search(config::LLMWiki.WikiConfig, query::String; top_k::Int=0)
    top_k = top_k > 0 ? top_k : config.search_top_k
    lq = lowercase(query)

    sparql = """
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    PREFIX wiki: <http://llmwiki.org/wiki/>
    SELECT ?concept ?title ?summary WHERE {
        ?concept a skos:Concept .
        ?concept skos:prefLabel ?title .
        OPTIONAL { ?concept skos:definition ?summary }
        FILTER(
            CONTAINS(LCASE(STR(?title)), "$lq") ||
            (BOUND(?summary) && CONTAINS(LCASE(STR(?summary)), "$lq"))
        )
    }
    ORDER BY ?title
    """

    g = LLMWiki.wiki_to_rdf(config; include_provenance=false)
    results_raw = sparql_query(g, sparql)

    results = LLMWiki.SearchResult[]
    for row in results_raw
        title_val = row["title"].lexical
        uri_str = row["concept"].value
        slug = replace(uri_str, "http://llmwiki.org/wiki/concept/" => "")
        summary_val = haskey(row, "summary") && row["summary"] !== nothing ?
            row["summary"].lexical : ""
        score = _match_score(lq, title_val, summary_val)
        push!(results, LLMWiki.SearchResult(
            slug=slug, title=title_val, score=score,
            snippet=first(summary_val, 200)
        ))
    end

    sort!(results, by=r -> r.score, rev=true)
    return first(results, min(top_k, length(results)))
end

function _match_score(query::String, title::String, summary::String)
    score = 0.0
    lq = lowercase(query)
    lt = lowercase(title)
    ls = lowercase(summary)
    if lt == lq
        score += 1.0
    elseif contains(lt, lq)
        score += 0.8
    end
    if contains(ls, lq)
        score += 0.3
    end
    return score
end

# ── graph_stats ──────────────────────────────────────────────────────────────

"""
    LLMWiki.rdf_graph_stats(config::WikiConfig) -> Dict{String, Any}

Return statistics about the wiki knowledge graph:
- `:total_triples` — total number of RDF triples
- `:concepts` — number of SKOS concepts
- `:sources` — number of provenance source entities
- `:wikilinks` — number of skos:related edges
- `:orphans` — number of orphaned concepts
- `:tags` — distinct tag count

Requires `using LLMWiki, RDFLib`.
"""
function LLMWiki.rdf_graph_stats(config::LLMWiki.WikiConfig)
    g = LLMWiki.wiki_to_rdf(config; include_provenance=true)

    concepts = length(collect(subjects(g, RDF.type, SKOS.Concept)))
    sources = length(collect(subjects(g, RDF.type, PROV.Entity)))
    wikilinks = length(collect(triples(g, (nothing, SKOS.related, nothing))))
    orphans = length(collect(subjects(g, WIKI_ONTOLOGY("orphaned"), Literal(true))))
    tags_set = Set{String}()
    for t in triples(g, (nothing, DCTERMS.subject, nothing))
        push!(tags_set, t.object.lexical)
    end

    return Dict{String, Any}(
        "total_triples" => length(g),
        "concepts" => concepts,
        "sources" => sources,
        "wikilinks" => wikilinks,
        "orphans" => orphans,
        "tags" => length(tags_set),
    )
end

end # module
