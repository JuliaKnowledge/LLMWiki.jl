using Test
using LLMWiki

@testset "Markdown Utils" begin
    @testset "slugify" begin
        @test slugify("Knowledge Compilation") == "knowledge-compilation"
        @test slugify("C++ Templates") == "c-templates"
        @test slugify("  Foo  Bar  ") == "foo-bar"
        @test slugify("Hello World!") == "hello-world"
        @test slugify("already-slugified") == "already-slugified"
        @test slugify("UPPER CASE") == "upper-case"
        @test slugify("dots.and,commas") == "dots-and-commas"
        @test slugify("  ") == ""
        @test slugify("single") == "single"
        @test slugify("---hyphens---") == "hyphens"
        @test slugify("café") == "caf"  # non-ASCII stripped
    end

    @testset "find_wikilinks" begin
        @test LLMWiki.find_wikilinks("See [[Machine Learning]] for details.") == ["Machine Learning"]
        @test LLMWiki.find_wikilinks("[[A]] and [[B]] and [[A]]") == ["A", "B"]  # unique
        @test LLMWiki.find_wikilinks("No links here") == String[]
        @test LLMWiki.find_wikilinks("") == String[]
        @test LLMWiki.find_wikilinks("[[First]] then [[Second]]") == ["First", "Second"]
        @test LLMWiki.find_wikilinks("Nested [[ ]] empty") == String[]  # spaces-only is empty after strip
    end

    @testset "add_wikilinks" begin
        body = "Machine Learning is great. Neural Networks are used."
        titles = ["Machine Learning", "Neural Networks"]
        result = LLMWiki.add_wikilinks(body, titles, "Overview")
        @test occursin("[[Machine Learning]]", result)
        @test occursin("[[Neural Networks]]", result)

        # Skips self-references
        result2 = LLMWiki.add_wikilinks("Machine Learning overview", titles, "Machine Learning")
        @test !occursin("[[Machine Learning]]", result2)

        # Skips code blocks
        body3 = "```\nMachine Learning\n```\nMachine Learning outside"
        result3 = LLMWiki.add_wikilinks(body3, titles, "Other")
        @test occursin("[[Machine Learning]]", result3)  # outside code block

        # Skips existing wikilinks
        body4 = "See [[Machine Learning]] already linked. Neural Networks too."
        result4 = LLMWiki.add_wikilinks(body4, titles, "Other")
        @test occursin("[[Neural Networks]]", result4)
        # Should not double-wrap existing links
        @test !occursin("[[[[", result4)
    end

    @testset "fuzzy_match_title" begin
        titles = ["Machine Learning", "Deep Learning", "Neural Networks"]

        # Exact match
        @test LLMWiki.fuzzy_match_title("Machine Learning", titles) == "Machine Learning"

        # Close match
        result = LLMWiki.fuzzy_match_title("machine learning", titles)
        @test result == "Machine Learning"

        # No match
        @test LLMWiki.fuzzy_match_title("quantum computing", titles) === nothing

        # Empty titles
        @test LLMWiki.fuzzy_match_title("anything", String[]) === nothing
    end

    @testset "atomic_write and safe_read" begin
        mktempdir() do dir
            path = joinpath(dir, "subdir", "test.txt")
            LLMWiki.atomic_write(path, "Hello, World!")
            @test isfile(path)
            @test LLMWiki.safe_read(path) == "Hello, World!"

            # Overwrite
            LLMWiki.atomic_write(path, "Updated content")
            @test LLMWiki.safe_read(path) == "Updated content"

            # Non-existent file
            @test LLMWiki.safe_read(joinpath(dir, "nonexistent.txt")) === nothing
        end
    end

    @testset "is_word_boundary" begin
        text = "Hello World test"
        # "World" starts at byte 7, ends at byte 11
        idx_start = findfirst("World", text)
        @test LLMWiki.is_word_boundary(text, first(idx_start), last(idx_start)) == true

        # Not a boundary when embedded in a word
        text2 = "HelloWorld"
        idx2 = findfirst("World", text2)
        @test LLMWiki.is_word_boundary(text2, first(idx2), last(idx2)) == false
    end

    @testset "is_inside_wikilink" begin
        text = "See [[Machine Learning]] for details"
        ml_pos = findfirst("Machine", text)
        @test LLMWiki.is_inside_wikilink(text, first(ml_pos)) == true

        see_pos = findfirst("See", text)
        @test LLMWiki.is_inside_wikilink(text, first(see_pos)) == false
    end

    @testset "_is_inside_code" begin
        text = "Normal text `inline code` more text"
        ic_pos = findfirst("inline", text)
        @test LLMWiki._is_inside_code(text, first(ic_pos)) == true

        normal_pos = findfirst("Normal", text)
        @test LLMWiki._is_inside_code(text, first(normal_pos)) == false
    end
end
