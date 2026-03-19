#!/usr/bin/env bash
# lib/cmd/dispatch.sh — rdf dispatch subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2

# shellcheck disable=SC1090
source "${RDF_LIBDIR}/dispatch.sh"

cmd_dispatch() {
    rdf_warn "rdf dispatch is deprecated in v3 — use the dispatcher agent via /build instead"

    local subcmd="${1:-help}"
    shift 2>/dev/null || true  # shift may fail if no args — safe to ignore

    case "$subcmd" in
        agent)
            # rdf dispatch agent <name> <task-template> <phase> <project-path> [plan-path]
            if [[ $# -lt 4 ]]; then
                rdf_die "usage: rdf dispatch agent <name> <template> <phase> <project-path> [plan-path]"
            fi
            rdf_dispatch_agent "$@"
            ;;
        pipeline)
            # rdf dispatch pipeline <tier> <phase> <project-path> <plan-path> [flags...]
            if [[ $# -lt 4 ]]; then
                rdf_die "usage: rdf dispatch pipeline <tier> <phase> <project-path> <plan-path> [flags...]"
            fi
            rdf_dispatch_pipeline "$@"
            ;;
        status)
            rdf_dispatch_status
            ;;
        help|--help|-h)
            cat <<USAGE
Usage: rdf dispatch <subcommand> [options]

Generate mode-aware agent dispatch instructions.

Subcommands:
  agent     Generate dispatch for a single agent
  pipeline  Generate full pipeline dispatch sequence
  status    Show current dispatch mode and registry stats

Dispatch mode is controlled by RDF_AGENT_TEAMS environment variable:
  false (default) — subagent mode (Agent tool)
  true            — Agent Teams mode (TeammateTool)

Examples:
  rdf dispatch status
  rdf dispatch agent engineer se-implement 3 /path/to/project /path/to/PLAN.md
  rdf dispatch pipeline 2 3 /path/to/project /path/to/PLAN.md
  rdf dispatch pipeline 2 3 /path/to/project /path/to/PLAN.md --no-challenger
  RDF_AGENT_TEAMS=true rdf dispatch pipeline 2 3 /path/to/project /path/to/PLAN.md
USAGE
            ;;
        *)
            rdf_die "unknown dispatch subcommand: $subcmd — run 'rdf dispatch help'"
            ;;
    esac
}
