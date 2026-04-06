# ──────────────────────────────────────────────────────────────────────────────
# search/bm25.jl — BM25 keyword search for LLMWiki.jl
# ──────────────────────────────────────────────────────────────────────────────
#
# Implements Okapi BM25 ranking over wiki page content for fast, lightweight
# keyword search without any external dependencies.

"""
    BM25Index

In-memory BM25 search index over wiki pages.

# Fields
- `docs`: Mapping from slug → full page content.
- `doc_lengths`: Mapping from slug → token count.
- `avg_doc_length`: Average document length across the corpus.
- `term_doc_freq`: Mapping from term → number of documents containing it.
- `total_docs`: Total number of indexed documents.
- `k1`, `b`: BM25 tuning parameters (defaults: k1=1.5, b=0.75).
"""
Base.@kwdef mutable struct BM25Index
    docs::Dict{String,String}       = Dict{String,String}()
    doc_lengths::Dict{String,Int}   = Dict{String,Int}()
    avg_doc_length::Float64         = 0.0
    term_doc_freq::Dict{String,Int} = Dict{String,Int}()
    total_docs::Int                 = 0
    k1::Float64                     = 1.5
    b::Float64                      = 0.75
end

# ── Stopwords ────────────────────────────────────────────────────────────────

const _STOPWORDS = Set([
    "a", "an", "the", "and", "or", "but", "is", "are", "was", "were",
    "be", "been", "being", "have", "has", "had", "do", "does", "did",
    "will", "would", "shall", "should", "may", "might", "must", "can",
    "could", "to", "of", "in", "for", "on", "with", "at", "by", "from",
    "as", "into", "through", "during", "before", "after", "above", "below",
    "between", "out", "off", "over", "under", "again", "further", "then",
    "once", "here", "there", "when", "where", "why", "how", "all", "each",
    "every", "both", "few", "more", "most", "other", "some", "such", "no",
    "not", "only", "own", "same", "so", "than", "too", "very", "just",
    "because", "about", "up", "it", "its", "this", "that", "these", "those",
    "i", "me", "my", "we", "our", "you", "your", "he", "him", "his",
    "she", "her", "they", "them", "their", "what", "which", "who", "whom",
])

# ── Tokenizer ────────────────────────────────────────────────────────────────

"""
    tokenize(text::String) -> Vector{String}

Simple whitespace + punctuation tokenizer with lowercasing and stopword removal.
Strips markdown syntax (headings, links, emphasis markers) before tokenising.
"""
function tokenize(text::String)::Vector{String}
    # Strip markdown formatting
    clean = replace(text, r"```[\s\S]*?```" => " ")  # code blocks
    clean = replace(clean, r"`[^`]*`" => " ")          # inline code
    clean = replace(clean, r"\[\[([^\]]+)\]\]" => s"\1")  # wikilinks → text
    clean = replace(clean, r"\[([^\]]*)\]\([^)]*\)" => s"\1")  # md links → text
    clean = replace(clean, r"[#*_~>|]" => " ")         # formatting chars
    clean = replace(clean, r"---+" => " ")              # horizontal rules

    tokens = String[]
    for m in eachmatch(r"[a-z0-9]+", lowercase(clean))
        word = m.match
        length(word) <= 1 && continue
        word in _STOPWORDS && continue
        push!(tokens, word)
    end
    tokens
end

# ── Index building ───────────────────────────────────────────────────────────

"""
    build_bm25_index(config::WikiConfig) -> BM25Index

Build a BM25 index from all wiki pages (concepts + queries).
Reads each page, strips frontmatter, tokenises the body, and computes
term-document frequencies.
"""
function build_bm25_index(config::WikiConfig)::BM25Index
    index = BM25Index()

    _index_directory!(index, joinpath(config.root, config.concepts_dir))
    _index_directory!(index, joinpath(config.root, config.queries_dir))

    # Compute average document length
    if index.total_docs > 0
        total_length = sum(values(index.doc_lengths))
        index.avg_doc_length = total_length / index.total_docs
    end

    index
end

"""
    _index_directory!(index::BM25Index, dir::String)

Index all `.md` files in a directory into the BM25 index.
"""
function _index_directory!(index::BM25Index, dir::String)
    isdir(dir) || return

    for f in readdir(dir)
        endswith(f, ".md") || continue
        content = safe_read(joinpath(dir, f))
        content === nothing && continue

        slug = replace(f, ".md" => "")
        meta, body = parse_frontmatter(content)
        meta.orphaned && continue

        # Index title + body
        full_text = meta.title * " " * body
        index.docs[slug] = full_text

        tokens = tokenize(full_text)
        index.doc_lengths[slug] = length(tokens)
        index.total_docs += 1

        # Count term-document frequencies (each term counted once per doc)
        seen_terms = Set{String}()
        for token in tokens
            if token ∉ seen_terms
                push!(seen_terms, token)
                index.term_doc_freq[token] = get(index.term_doc_freq, token, 0) + 1
            end
        end
    end
end

# ── BM25 scoring ─────────────────────────────────────────────────────────────

"""
    _bm25_idf(n_docs::Int, doc_freq::Int) -> Float64

Compute the IDF component of BM25:
    IDF(qi) = ln((N - n(qi) + 0.5) / (n(qi) + 0.5) + 1)
where N is total docs and n(qi) is docs containing term qi.
"""
function _bm25_idf(n_docs::Int, doc_freq::Int)::Float64
    log((n_docs - doc_freq + 0.5) / (doc_freq + 0.5) + 1.0)
end

"""
    _bm25_score(index::BM25Index, slug::String, query_tokens::Vector{String}) -> Float64

Compute the BM25 score for a single document against a tokenised query.

    score(D,Q) = Σ IDF(qi) × (f(qi,D) × (k1+1)) / (f(qi,D) + k1×(1 - b + b×|D|/avgdl))
"""
function _bm25_score(index::BM25Index, slug::String, query_tokens::Vector{String})::Float64
    doc_text = get(index.docs, slug, "")
    isempty(doc_text) && return 0.0

    doc_tokens = tokenize(doc_text)
    doc_len = length(doc_tokens)
    doc_len == 0 && return 0.0

    # Build term frequency map for this document
    tf_map = Dict{String,Int}()
    for t in doc_tokens
        tf_map[t] = get(tf_map, t, 0) + 1
    end

    score = 0.0
    for qt in query_tokens
        df = get(index.term_doc_freq, qt, 0)
        df == 0 && continue

        idf = _bm25_idf(index.total_docs, df)
        tf  = get(tf_map, qt, 0)
        tf == 0 && continue

        numerator   = tf * (index.k1 + 1.0)
        denominator = tf + index.k1 * (1.0 - index.b + index.b * doc_len / max(index.avg_doc_length, 1.0))
        score += idf * numerator / denominator
    end

    score
end

# ── Search ───────────────────────────────────────────────────────────────────

"""
    bm25_search(index::BM25Index, query::String; top_k::Int=10) -> Vector{SearchResult}

Search the BM25 index and return ranked results.

Returns at most `top_k` results, each with a slug, title (extracted from
the indexed content), BM25 score, and a snippet from the first matching
sentence.
"""
function bm25_search(index::BM25Index, query::String; top_k::Int=10)::Vector{SearchResult}
    query_tokens = tokenize(query)
    isempty(query_tokens) && return SearchResult[]

    scored = Tuple{String,Float64}[]
    for slug in keys(index.docs)
        s = _bm25_score(index, slug, query_tokens)
        s > 0.0 && push!(scored, (slug, s))
    end

    sort!(scored; by=x -> -x[2])
    n = min(top_k, length(scored))

    results = SearchResult[]
    for i in 1:n
        slug, score = scored[i]
        doc_text = index.docs[slug]

        # Extract title (first line or slug)
        title = _extract_title(doc_text, slug)

        # Generate snippet
        snippet = _generate_snippet(doc_text, query_tokens)

        push!(results, SearchResult(
            slug    = slug,
            title   = title,
            score   = round(score; digits=4),
            snippet = snippet
        ))
    end

    results
end

"""
    _extract_title(text::String, fallback::String) -> String

Extract a title from page content — first heading or the fallback slug.
"""
function _extract_title(text::String, fallback::String)::String
    m = match(r"^#+\s+(.+)$"m, text)
    m !== nothing && return strip(String(m.captures[1]))
    # Try first non-empty line
    for line in split(text, '\n')
        stripped = strip(line)
        !isempty(stripped) && return first(stripped, 80)
    end
    fallback
end

"""
    _generate_snippet(text::String, query_tokens::Vector{String}; max_len::Int=200) -> String

Generate a snippet from the document text that includes query terms.
"""
function _generate_snippet(text::String, query_tokens::Vector{String}; max_len::Int=200)::String
    sentences = split(text, r"[.!?\n]+")
    query_set = Set(query_tokens)

    # Find the sentence with the most query term hits
    best_idx = 0
    best_count = 0
    for (i, sent) in enumerate(sentences)
        tokens = Set(tokenize(String(sent)))
        count = length(intersect(tokens, query_set))
        if count > best_count
            best_count = count
            best_idx = i
        end
    end

    if best_idx == 0
        # Fallback: first non-empty sentence
        for (i, sent) in enumerate(sentences)
            if !isempty(strip(sent))
                best_idx = i
                break
            end
        end
    end

    best_idx == 0 && return ""
    snippet = strip(String(sentences[best_idx]))
    length(snippet) > max_len ? snippet[1:prevind(snippet, max_len)] * "…" : snippet
end
