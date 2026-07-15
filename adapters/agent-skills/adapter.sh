#!/usr/bin/env bash
# adapters/agent-skills/adapter.sh — Agent Skills (.agents/skills/) adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh — do not execute directly

# Requires: RDF_CANONICAL, RDF_ADAPTERS, jq

_SK_ADAPTER_DIR="${RDF_ADAPTERS}/agent-skills"
_SK_OUTPUT_DIR="${_SK_ADAPTER_DIR}/output"
_SK_META="${_SK_ADAPTER_DIR}/skill-meta.json"

# _sk_skill_description <basename> <src_file> — echo the trigger from
# skill-meta.json; fall back to the canonical body's first non-heading line.
_sk_skill_description() {
    local name="$1" src="$2" desc
    desc="$(jq -r --arg c "$name" '.[$c] // empty' "$_SK_META" 2>/dev/null)"  # missing/malformed → empty, body fallback
    if [[ -z "$desc" ]]; then
        desc="$(sed -n '/^[^#[:space:]]/{ s/[[:space:]]*$//; p; q; }' "$src")"
        [[ -z "$desc" ]] && desc="RDF command: ${name}"
    fi
    printf '%s' "$desc"
}

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
        desc="$(_sk_skill_description "$name" "$src")"
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
    local _output_new="${_SK_OUTPUT_DIR}.new"
    local _output_old="${_SK_OUTPUT_DIR}.old"

    command rm -rf "$_output_new"
    command mkdir -p "$_output_new/.agents/skills"
    sk_emit_skills "${_output_new}/.agents/skills"

    command rm -rf "$_output_old"
    if [[ -d "$_output_final" ]]; then
        command mv "$_output_final" "$_output_old"
    fi
    command mv "$_output_new" "$_output_final"
    command rm -rf "$_output_old"
    rdf_log "Agent Skills generation complete"
}
