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

# sk_emit_skills <skills_root> — write <skills_root>/<name>/SKILL.md for every
# skill-meta.json key (excluding _comment). name == dir name (AAIF rule).
sk_emit_skills() {
    local skills_root="$1" name src desc count=0
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "_comment" ]] && continue
        src="${RDF_CANONICAL}/commands/${name}.md"
        if [[ ! -f "$src" ]]; then
            rdf_warn "agent-skills: no canonical command for skill '${name}' — skipped"
            continue
        fi
        desc="$(adp_skill_description "$name" "$src" "$_SK_META")"
        command mkdir -p "${skills_root}/${name}"
        {
            echo "---"
            echo "name: ${name}"
            echo "description: >"
            echo "  ${desc}"
            echo "---"
            echo ""
            command cat "$src"
        } > "${skills_root}/${name}/SKILL.md"
        count=$((count + 1))
    done < <(jq -r 'keys[]' "$_SK_META")
    rdf_log "agent-skills: generated ${count} SKILL.md files"
}

# sk_generate_all — full pipeline with atomic staging swap (codex pattern).
sk_generate_all() {
    rdf_log "generating Agent Skills adapter output..."
    rdf_require_dir "$RDF_CANONICAL" "canonical directory"
    rdf_require_file "$_SK_META" "agent-skills skill-meta.json"
    rdf_require_bin jq

    local _output_final="$_SK_OUTPUT_DIR"
    local _output_new
    _output_new="$(adp_stage_begin "$_output_final")"

    command mkdir -p "${_output_new}/.agents/skills"
    sk_emit_skills "${_output_new}/.agents/skills"

    # SKILL.md bodies link ../reference/*.md — resolve from skills root
    command mkdir -p "${_output_new}/.agents/skills/reference"
    command cp "${RDF_CANONICAL}/reference/"*.md "${_output_new}/.agents/skills/reference/"

    adp_stage_commit "$_output_final" "$_output_new"
    rdf_log "Agent Skills generation complete"
}
