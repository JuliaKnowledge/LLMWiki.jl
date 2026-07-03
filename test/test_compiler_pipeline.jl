using Test
using UUIDs
using JSON3
using LLMWiki

const LLMWIKI_TEST_CHAT_HANDLER = Ref{Any}(nothing)

@eval LLMWiki begin
    function _chat_completion(config::WikiConfig, system_prompt::String, user_prompt::String;
                              temperature::Float64=0.3,
                              max_tokens::Int=2000)::String
        handler = Main.LLMWIKI_TEST_CHAT_HANDLER[]
        handler === nothing && error("No test chat handler configured.")
        handler(config, system_prompt, user_prompt; temperature=temperature, max_tokens=max_tokens)
    end
end

function with_test_wiki(f::Function, label::String)
    root = joinpath(@__DIR__, "sandbox", "$(label)-$(uuid4())")
    mkpath(root)
    config = default_config(root)
    config.versioned = false
    init_wiki(config)

    try
        f(root, config)
    finally
        isdir(root) && rm(root; recursive=true, force=true)
    end
end

function write_source(config::WikiConfig, file::String, content::String)
    path = joinpath(config.sources_dir, file)
    mkpath(dirname(path))
    write(path, content)
    path
end

read_page(config::WikiConfig, slug::String) = read(joinpath(config.concepts_dir, "$slug.md"), String)

function mock_source(specs::Vector{Tuple{String,String}}; marker::String, invalid::Bool=false)
    lines = ["MARKER: $marker"]
    invalid && push!(lines, "INVALID_PAGE")
    append!(lines, ["CONCEPT: $title|$summary" for (title, summary) in specs])
    join(lines, "\n")
end

function _extract_source_document(system_prompt::String)
    m = match(r"--- SOURCE DOCUMENT ---\n\n(.*)"s, system_prompt)
    m === nothing && error("Test extraction prompt missing source document.")
    String(m.captures[1])
end

function _extract_source_material(system_prompt::String)
    m = match(r"--- SOURCE MATERIAL ---\n\n(.*)"s, system_prompt)
    m === nothing && error("Test generation prompt missing source material.")
    String(m.captures[1])
end

function _concept_title(system_prompt::String)
    m = match(r"Write a clear, well-structured markdown page about \"([^\"]+)\"", system_prompt)
    m === nothing && error("Test generation prompt missing concept title.")
    String(m.captures[1])
end

function _parse_mock_concepts(source_content::String)
    concepts = Dict{String,Any}[]
    for raw_line in split(source_content, '\n')
        line = strip(raw_line)
        startswith(line, "CONCEPT:") || continue
        spec = strip(line[length("CONCEPT:")+1:end])
        parts = split(spec, "|"; limit=2)
        title = strip(parts[1])
        summary = length(parts) == 2 ? strip(parts[2]) : "Summary for $title"
        push!(concepts, Dict("concept" => title, "summary" => summary, "is_new" => true))
    end
    concepts
end

function compiler_mock_chat(::WikiConfig, system_prompt::String, user_prompt::String; temperature::Float64, max_tokens::Int)
    if user_prompt == "Extract the key concepts from this source."
        source_content = _extract_source_document(system_prompt)
        return JSON3.write(Dict("concepts" => _parse_mock_concepts(source_content)))
    end

    source_material = strip(_extract_source_material(system_prompt))
    concept = _concept_title(system_prompt)
    occursin("INVALID_PAGE", source_material) && return "   "
    "## $concept\n\n$source_material\n\n## Sources\n- auto\n"
end

function make_watch_fn(events)
    index = Ref(1)
    function watch_fn(path::String, timeout_s::Real=-1)
        index[] > length(events) && error("No scripted watch event left for timeout=$timeout_s at $path")
        event = events[index[]]
        index[] += 1
        event
    end
    watch_fn
end

function make_time_fn(values::Vector{Float64})
    index = Ref(1)
    function time_fn()
        index[] > length(values) && return values[end]
        value = values[index[]]
        index[] += 1
        value
    end
    time_fn
end

@testset "Compiler / deps / resolver / watch regressions" begin
    LLMWIKI_TEST_CHAT_HANDLER[] = compiler_mock_chat

    @testset "shared-source deletion regenerates surviving owner" begin
        with_test_wiki("shared-delete") do _, config
            write_source(config, "a.md", mock_source([("Alpha", "Shared alpha")]; marker="A"))
            write_source(config, "b.md", mock_source([("Alpha", "Shared alpha")]; marker="B"))

            first_result = compile!(config)
            @test first_result.compiled == 1

            rm(joinpath(config.sources_dir, "a.md"))
            second_result = compile!(config)

            @test second_result.compiled == 1
            @test second_result.deleted == 1

            meta, body = parse_frontmatter(read_page(config, "alpha"))
            @test Set(meta.sources) == Set(["b.md"])
            @test !meta.orphaned
            @test !occursin("MARKER: A", body)
            @test occursin("MARKER: B", body)
            @test !haskey(load_state(config).sources, "a.md")
        end
    end

    @testset "removed concepts regenerate surviving owners and add renamed pages" begin
        with_test_wiki("removed-concepts") do _, config
            write_source(config, "a.md", mock_source(
                [("Alpha", "Alpha summary"), ("Beta", "Beta summary")];
                marker="A1",
            ))
            write_source(config, "b.md", mock_source([("Beta", "Beta summary")]; marker="B"))

            @test compile!(config).compiled == 2

            write_source(config, "a.md", mock_source(
                [("Alpha", "Alpha summary"), ("Gamma", "Gamma summary")];
                marker="A2",
            ))
            result = compile!(config)

            @test result.compiled == 3
            beta_meta, beta_body = parse_frontmatter(read_page(config, "beta"))
            @test Set(beta_meta.sources) == Set(["b.md"])
            @test !occursin("MARKER: A1", beta_body)
            @test !occursin("MARKER: A2", beta_body)
            @test occursin("MARKER: B", beta_body)

            gamma_meta, gamma_body = parse_frontmatter(read_page(config, "gamma"))
            @test Set(gamma_meta.sources) == Set(["a.md"])
            @test occursin("MARKER: A2", gamma_body)

            state = load_state(config)
            @test Set(state.sources["a.md"].concepts) == Set(["alpha", "gamma"])
        end
    end

    @testset "dependency propagation reaches fixed point" begin
        with_test_wiki("fixed-point") do _, config
            write_source(config, "a.md", mock_source([("Alpha", "Alpha summary")]; marker="A1"))
            write_source(config, "b.md", mock_source(
                [("Alpha", "Alpha summary"), ("Bridge", "Bridge summary")];
                marker="B1",
            ))
            write_source(config, "c.md", mock_source([("Bridge", "Bridge summary")]; marker="C1"))

            @test compile!(config).compiled == 2

            write_source(config, "a.md", mock_source([("Alpha", "Alpha summary")]; marker="A2"))
            result = compile!(config)

            @test result.compiled == 2
            bridge_meta, bridge_body = parse_frontmatter(read_page(config, "bridge"))
            @test Set(bridge_meta.sources) == Set(["b.md", "c.md"])
            @test occursin("MARKER: B1", bridge_body)
            @test occursin("MARKER: C1", bridge_body)
        end
    end

    @testset "invalid generation does not advance source state" begin
        with_test_wiki("invalid-generation") do _, config
            write_source(config, "bad.md", mock_source([("Invalid", "Broken page")]; marker="BAD", invalid=true))

            first_result = compile!(config)
            @test first_result.compiled == 0
            @test !haskey(load_state(config).sources, "bad.md")
            @test !isfile(joinpath(config.concepts_dir, "invalid.md"))

            second_result = compile!(config)
            @test second_result.compiled == 0
            @test !haskey(load_state(config).sources, "bad.md")

            write_source(config, "bad.md", mock_source([("Invalid", "Broken page")]; marker="GOOD"))
            third_result = compile!(config)
            @test third_result.compiled == 1
            @test haskey(load_state(config).sources, "bad.md")
        end
    end

    @testset "resolver detects ambiguous titles and rewrites renamed wikilinks" begin
        with_test_wiki("resolver") do _, config
            LLMWiki.atomic_write(
                joinpath(config.concepts_dir, "a.md"),
                LLMWiki.build_page(PageMeta(title="Shared Title", sources=["a.md"]), "Body A"),
            )
            LLMWiki.atomic_write(
                joinpath(config.concepts_dir, "b.md"),
                LLMWiki.build_page(PageMeta(title="Shared Title", sources=["b.md"]), "Body B"),
            )

            title_index = LLMWiki._build_title_index(config)
            @test sort(title_index["shared title"]) == ["a", "b"]
            @test_throws ArgumentError LLMWiki.resolve_links!(config, ["a"], String[])
        end

        with_test_wiki("resolver-rename") do _, config
            LLMWiki.atomic_write(
                joinpath(config.concepts_dir, "new-title.md"),
                LLMWiki.build_page(PageMeta(title="New Title", sources=["new.md"]), "## New\n\nBody"),
            )
            LLMWiki.atomic_write(
                joinpath(config.concepts_dir, "other.md"),
                LLMWiki.build_page(PageMeta(title="Other", sources=["other.md"]), "See [[Old Title]] in context."),
            )

            modified = LLMWiki.resolve_links!(
                config,
                ["other"],
                ["new-title"];
                renamed_titles=Dict("Old Title" => "New Title"),
            )

            @test modified == 1
            _, body = parse_frontmatter(read_page(config, "other"))
            @test occursin("[[New Title]]", body)
            @test !occursin("[[Old Title]]", body)
        end
    end

    @testset "lock ownership is verified before release" begin
        with_test_wiki("lock-ownership") do _, config
            @test LLMWiki.acquire_lock(config)
            lock_path = LLMWiki._lock_path(config)
            owner_path = LLMWiki._lock_owner_path(lock_path)
            write(owner_path, JSON3.write(Dict("token" => "foreign", "pid" => getpid(), "heartbeat_at" => "now")))

            LLMWiki.release_lock(config)
            @test isdir(lock_path)

            rm(lock_path; recursive=true, force=true)
            LLMWiki._forget_active_lock!(lock_path)
        end
    end

    @testset "stale lock helper honors heartbeat age" begin
        with_test_wiki("lock-stale") do _, config
            lock_path = LLMWiki._lock_path(config)
            mkdir(lock_path)
            LLMWiki._write_lock_metadata(lock_path, "token")
            owner_path = LLMWiki._lock_owner_path(lock_path)
            owner_mtime = mtime(owner_path)

            @test !LLMWiki._lock_is_stale(lock_path; now_time=owner_mtime + (LLMWiki.LOCK_STALE_SECONDS / 2))
            @test LLMWiki._lock_is_stale(lock_path; now_time=owner_mtime + LLMWiki.LOCK_STALE_SECONDS + 1)
        end
    end

    @testset "watch helpers debounce from last event and drain queued changes" begin
        batch = LLMWiki._collect_watch_batch(
            "unused",
            1.0;
            watch_fn=make_watch_fn([
                ("one.md", (renamed=false, changed=true, timedout=false)),
                ("two.md", (renamed=false, changed=true, timedout=false)),
            ]),
            time_fn=make_time_fn([100.0, 100.2, 101.3, 102.4]),
        )
        @test batch.files == ["one.md", "two.md"]
        @test batch.last_event_at == 101.3

        drained = LLMWiki._drain_watch_events(
            "unused";
            watch_fn=make_watch_fn([
                (".hidden", (renamed=false, changed=true, timedout=false)),
                ("note.tmp", (renamed=false, changed=true, timedout=false)),
                ("real.md", (renamed=false, changed=true, timedout=false)),
                ("", (renamed=false, changed=false, timedout=true)),
            ]),
            time_fn=make_time_fn([200.0]),
        )
        @test drained.files == ["real.md"]
        @test drained.last_event_at == 200.0
    end
end
