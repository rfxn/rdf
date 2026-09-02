#!/usr/bin/env bash
# adapters/agent-skills/adapter.sh — Agent Skills (.agents/skills/) adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh — do not execute directly

# Requires: RDF_CANONICAL, RDF_ADAPTERS, jq

# shellcheck disable=SC1090,SC1091
[[ -n "${_RDF_ADAPTER_COMMON_LOADED:-}" ]] || source "${RDF_LIBDIR}/adapter_common.sh"

_SK_ADAPTER_DIR="${RDF_ADAPTERS}/agent-skills"
_SK_OUTPUT_DIR="${_SK_ADAPTER_DIR}/output"
_SK_META="${_SK_ADAPTER_DIR}/skill-meta.json"

# sk_generate_all — full pipeline with atomic staging swap (codex pattern).
sk_generate_all() {
    rdf_log "generating Agent Skills adapter output..."
    rdf_require_dir "$RDF_CANONICAL" "canonical directory"
    rdf_require_file "$_SK_META" "agent-skills skill-meta.json"
    rdf_require_bin jq

    local _output_final="$_SK_OUTPUT_DIR"
    local _output_new
    _output_new="$(adp_stage_begin "$_output_final")"

    adp_emit_skills "${RDF_CANONICAL}/commands" "${_output_new}/.agents/skills" \
        "$_SK_META" - 0 adp_names_from_meta "${RDF_CANONICAL}/reference"

    adp_stage_commit "$_output_final" "$_output_new"
    rdf_log "Agent Skills generation complete"
}
