using Test
using LLMWiki

@testset "Lint" begin
    @testset "lint_wiki — detects broken wikilinks" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "page-a.md"), """---
title: "Page A"
page_type: concept
---
# Page A

See [[Nonexistent Page]] for more info. This has enough content to avoid empty page warnings.""")

            issues = lint_wiki(cfg)
            broken = filter(i -> i.category == :broken_link, issues)
            @test length(broken) >= 1
            @test any(i -> occursin("Nonexistent Page", i.message), broken)
        end
    end

    @testset "lint_wiki — detects empty pages" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "empty-page.md"), """---
title: "Empty Page"
page_type: concept
---
Short.""")

            issues = lint_wiki(cfg)
            empty_issues = filter(i -> i.category == :empty_page, issues)
            @test length(empty_issues) >= 1
            @test any(i -> i.page == "empty-page", empty_issues)
        end
    end

    @testset "lint_wiki — detects missing frontmatter via orphan" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # Page without proper sources is orphaned
            write(joinpath(cfg.concepts_dir, "no-links.md"), """---
title: "No Links"
page_type: concept
---
# No Links

This page has sufficient content to pass the empty check but no one links to it at all in any page.""")

            issues = lint_wiki(cfg)
            orphans = filter(i -> i.category == :orphan_page, issues)
            @test length(orphans) >= 1
        end
    end

    @testset "LintIssue fields" begin
        issue = LintIssue(
            severity=WARNING,
            category=:broken_link,
            page="test-page",
            message="Test message",
            suggestion="Test suggestion"
        )
        @test issue.severity == WARNING
        @test issue.category == :broken_link
        @test issue.page == "test-page"
        @test issue.message == "Test message"
        @test issue.suggestion == "Test suggestion"
    end

    @testset "lint_wiki — no issues on healthy wiki" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            # Two pages that link to each other, with enough content
            write(joinpath(cfg.concepts_dir, "page-one.md"), """---
title: "Page One"
page_type: concept
---
# Page One

This page discusses important concepts related to [[Page Two]] and provides substantial content for the wiki that should not trigger any empty page warnings.""")

            write(joinpath(cfg.concepts_dir, "page-two.md"), """---
title: "Page Two"
page_type: concept
---
# Page Two

This page is about different topics and links back to [[Page One]] with enough content to pass validation checks for the linting system.""")

            issues = lint_wiki(cfg)
            # Filter out info-level and no_source (since we haven't tracked sources in state)
            critical = filter(i -> i.category in (:broken_link, :empty_page), issues)
            @test isempty(critical)
        end
    end

    @testset "lint_wiki — frontmatter orphaned marker" begin
        mktempdir() do dir
            cfg = default_config(dir)
            init_wiki(cfg)

            write(joinpath(cfg.concepts_dir, "orphaned-page.md"), """---
title: "Orphaned Page"
orphaned: true
page_type: concept
---
# Orphaned Page

This page is marked as orphaned in its frontmatter metadata and should be detected by the linter.""")

            issues = lint_wiki(cfg)
            fm_orphans = filter(i -> i.category == :frontmatter_orphan, issues)
            @test length(fm_orphans) >= 1
            @test any(i -> i.page == "orphaned-page", fm_orphans)
        end
    end
end
