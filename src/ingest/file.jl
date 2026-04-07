# ──────────────────────────────────────────────────────────────────────────────
# ingest/file.jl — Local file ingestion (copy, .txt→.md, PDF extraction)
# ──────────────────────────────────────────────────────────────────────────────

"""
    ingest_file!(config::WikiConfig, filepath::String; filename::Union{Nothing,String}=nothing) -> String

Copy a local file into `sources/`. Handles:
- `.md` files — copied as-is
- `.txt` files — copied and renamed to `.md`
- `.pdf` files — text extracted via PDFIO.jl, saved as `.md`
- Other text files — copied and renamed to `.md`

Returns the target filename.
"""
function ingest_file!(config::WikiConfig, filepath::String;
                      filename::Union{Nothing,String}=nothing)
    if !isfile(filepath)
        error("Source file not found: $filepath")
    end

    ext = lowercase(splitext(filepath)[2])
    base = something(filename, basename(filepath))

    sources_path = joinpath(config.root, config.sources_dir)

    if ext == ".pdf"
        return ingest_pdf!(sources_path, filepath, base)
    else
        # .md, .txt, or any other text file
        target_name = endswith(base, ".md") ? base : splitext(base)[1] * ".md"
        target = joinpath(sources_path, target_name)
        if realpath(filepath) != (isfile(target) ? realpath(target) : "")
            cp(filepath, target; force=true)
        end
        @info "Ingested file" source=filepath target=target_name
        return target_name
    end
end

"""
    ingest_pdf!(sources_path::String, filepath::String, base::String) -> String

Extract text from a PDF using PDFIO.jl and save as a markdown file with
YAML frontmatter recording the source metadata.
"""
function ingest_pdf!(sources_path::String, filepath::String, base::String)
    target_name = splitext(base)[1] * ".md"
    target = joinpath(sources_path, target_name)

    text = extract_pdf_text(filepath)

    content = _build_ingested_source_markdown(
        text;
        title=splitext(base)[1],
        source_type="pdf",
        source_file=basename(filepath),
    )

    write(target, content)
    @info "Ingested PDF" source=filepath target=target_name chars=length(text)
    return target_name
end

"""
    extract_pdf_text(filepath::String) -> String

Extract all text content from a PDF file using PDFIO.jl.
Iterates over every page and concatenates the extracted text.
Returns an error message string if extraction fails.
"""
function extract_pdf_text(filepath::String)
    buf = IOBuffer()
    doc = nothing
    try
        doc = pdDocOpen(filepath)
        npage = pdDocGetPageCount(doc)
        for i in 1:npage
            page = pdDocGetPage(doc, i)
            if page !== nothing
                pdPageExtractText(buf, page)
                write(buf, "\n\n")
            end
        end
    catch e
        @warn "PDF extraction error" exception=(e, catch_backtrace()) filepath=filepath
        return "Error extracting text from PDF: $(basename(filepath))"
    finally
        doc !== nothing && pdDocClose(doc)
    end
    return String(take!(buf))
end
