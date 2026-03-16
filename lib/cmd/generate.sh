#!/usr/bin/env bash
# lib/cmd/generate.sh — rdf generate subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_generate_usage() {
    cat <<'USAGE'
Usage: rdf generate <target>

Build tool-specific output from canonical sources.

Targets:
  claude-code    Generate Claude Code adapter output
  all            Generate all available adapters

The generated output is written to adapters/<target>/output/.
After generation, symlink /root/.claude/{commands,agents,scripts}
to the output directories to activate.

Examples:
  rdf generate claude-code
  rdf generate all
USAGE
}

cmd_generate() {
    case "${1:-}" in
        claude-code)
            # shellcheck disable=SC1091
            source "${RDF_ADAPTERS}/claude-code/adapter.sh"
            cc_generate_all
            ;;
        all)
            # Phase 2: only claude-code available
            # shellcheck disable=SC1091
            source "${RDF_ADAPTERS}/claude-code/adapter.sh"
            cc_generate_all
            # Future: gemini-cli, codex, agents-md adapters
            ;;
        help|--help|-h)
            _generate_usage
            ;;
        "")
            rdf_die "missing target — run 'rdf generate help' for usage"
            ;;
        *)
            rdf_die "unknown target: $1 — run 'rdf generate help' for usage"
            ;;
    esac
}
