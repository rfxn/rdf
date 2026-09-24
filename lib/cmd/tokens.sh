#!/usr/bin/env bash
# lib/cmd/tokens.sh — rdf tokens subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

# cmd_tokens args — run the rdf-tokens.sh helper (it owns usage text and exit codes)
cmd_tokens() {
    local script="${RDF_STATE_DIR}/rdf-tokens.sh"
    rdf_require_file "$script" "rdf-tokens.sh"
    bash "$script" "$@"
}
