#!/usr/bin/env -S julia --project --startup-file=no
# LLMWiki command-line entry point.
#
# Usage:
#   llmwiki <command> [args...]
#
# For convenience install locally with:
#   julia --project -e 'using LLMWiki.CLI; LLMWiki.CLI.command_main()'
# or add this directory to your PATH.

using LLMWiki

LLMWiki.CLI.command_main()
