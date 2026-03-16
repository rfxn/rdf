#!/usr/bin/env bash
# lib/cmd/state.sh — rdf state subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_state_usage() {
    cat <<'USAGE'
Usage: rdf state [path]

Output deterministic project state as JSON to stdout.
Runs in <1 second with no LLM involvement.

Arguments:
  path    Project directory (default: current directory)

Examples:
  rdf state
  rdf state /root/admin/work/proj/brute-force-detection
  rdf state /root/admin/work/proj/rdf | jq .version
USAGE
}

cmd_state() {
    case "${1:-}" in
        help|--help|-h)
            _state_usage
            return 0
            ;;
    esac

    local project_path="${1:-.}"
    local state_script="${RDF_STATE_DIR}/rdf-state.sh"

    rdf_require_file "$state_script" "rdf-state.sh"

    bash "$state_script" "$project_path"
}
