#!/usr/bin/env bash
# adapters/claude-code/adapter.sh — Claude Code adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh — do not execute directly

# Requires: RDF_HOME, RDF_CANONICAL, RDF_ADAPTERS, jq

# shellcheck disable=SC1090,SC1091
[[ -n "${_RDF_ADAPTER_COMMON_LOADED:-}" ]] || source "${RDF_LIBDIR}/adapter_common.sh"

_CC_ADAPTER_DIR="${RDF_ADAPTERS}/claude-code"
_CC_OUTPUT_DIR="${_CC_ADAPTER_DIR}/output"
_CC_AGENT_META="${_CC_ADAPTER_DIR}/agent-meta.json"
_CC_SKILL_META="${RDF_ADAPTERS}/agent-skills/skill-meta.json"   # shared intent-trigger source (Phase 8)
# rdf-lite: 1 = condensed core governance, lifecycle commands only, no hooks.
# Default 0 keeps the full generation path byte-identical (set by generate.sh).
_CC_LITE="${_CC_LITE:-0}"

# Generate all CC agent files
# Reads canonical/agents/*.md + agent-meta.json -> output/agents/*.md
cc_generate_agents() {
    adp_emit_agents "${RDF_CANONICAL}/agents" "${_CC_OUTPUT_DIR}/agents" "$_CC_AGENT_META" - 1
}

# Generate all CC skill files: canonical/commands/*.md + skill-meta.json ->
# output/skills/<name>/SKILL.md. --lite ships only the lifecycle command set.
cc_generate_skills() {
    local names_fn=adp_names_all
    [[ "$_CC_LITE" -eq 1 ]] && names_fn=adp_names_lite
    adp_emit_skills "${RDF_CANONICAL}/commands" "${_CC_OUTPUT_DIR}/skills" \
        "$_CC_SKILL_META" - 1 "$names_fn" "${RDF_CANONICAL}/reference"
}

# Copy hooks.json to output
cc_generate_hooks() {
    if [[ "$_CC_LITE" -eq 1 ]]; then
        rdf_log "lite: skipping hooks.json"
        return 0
    fi
    local src="${_CC_ADAPTER_DIR}/hooks/hooks.json"
    local dst_dir="${_CC_OUTPUT_DIR}"

    if [[ -f "$src" ]]; then
        command cp "$src" "${dst_dir}/hooks.json"
        rdf_log "generated hooks.json"
    else
        rdf_warn "hooks.json not found at ${src}"
    fi
}

# Copy active profile governance docs to output
cc_generate_governance() {
    local dst_dir="${_CC_OUTPUT_DIR}/governance"
    command mkdir -p "$dst_dir"
    local count=0

    local active
    active="$(rdf_get_active_profiles)"

    while IFS= read -r profile; do
        [[ -z "$profile" ]] && continue
        local gov_file="${RDF_HOME}/profiles/${profile}/governance-template.md"
        if [[ -f "$gov_file" ]]; then
            command cp "$gov_file" "${dst_dir}/${profile}-governance.md"
            count=$((count + 1))
        fi
    done <<< "$active"

    rdf_log "generated ${count} governance files"
}

# Build a paths: frontmatter block from a profile's registry detect globs.
# Args: $1 = profile name. Emits nothing for core (never scoped — spec §4.3).
_cc_paths_frontmatter() {
    local profile="$1"
    local registry="${RDF_HOME}/profiles/registry.json"
    [[ "$profile" == "core" ]] && return 0   # core is always-loaded, never scoped (spec §4.3)
    [[ -f "$registry" ]] || return 0
    local globs
    globs="$(jq -r --arg p "$profile" '.profiles[$p].detect[]?' "$registry" 2>/dev/null)"  # missing profile → empty
    [[ -n "$globs" ]] || return 0
    echo "---"
    echo "paths:"
    while IFS= read -r g; do
        [[ -z "$g" ]] && continue
        case "$g" in
            */) printf '  - "**/%s**"\n' "$g" ;;   # directory glob — recurse into it
            *)  printf '  - "**/%s"\n' "$g" ;;      # file/extension/path glob
        esac
    done <<< "$globs"
    echo "---"
}

# Emit output/rules/<profile>.md — core unscoped, language profiles paths-scoped.
cc_generate_rules() {
    local dst_dir="${_CC_OUTPUT_DIR}/rules"
    command mkdir -p "$dst_dir"
    local count=0 active profile gov_file front
    active="$(rdf_get_active_profiles)"
    while IFS= read -r profile; do
        [[ -z "$profile" ]] && continue
        if [[ "$_CC_LITE" -eq 1 && "$profile" == "core" ]]; then
            gov_file="${RDF_HOME}/profiles/lite/governance-lite.md"   # condensed core (rdf-lite)
        else
            gov_file="${RDF_HOME}/profiles/${profile}/governance-template.md"
        fi
        [[ -f "$gov_file" ]] || continue
        front="$(_cc_paths_frontmatter "$profile")"
        {
            [[ -n "$front" ]] && printf '%s\n' "$front"
            command cat "$gov_file"
        } > "${dst_dir}/${profile}.md"
        count=$((count + 1))
    done <<< "$active"
    rdf_log "generated ${count} rule files"
}

# Full CC generation pipeline
cc_generate_all() {
    rdf_log "generating Claude Code adapter output..."
    [[ "$_CC_LITE" -eq 1 ]] && rdf_log "lite mode: condensed core governance, lifecycle commands only, no hooks"
    rdf_require_dir "$RDF_CANONICAL" "canonical directory"
    rdf_require_file "$_CC_AGENT_META" "agent-meta.json"
    rdf_require_bin jq
    rdf_require_agent_meta "$_CC_AGENT_META" "${RDF_CANONICAL}/agents"
    adp_require_hash_tool

    local _output_final="$_CC_OUTPUT_DIR"
    local _output_new
    _output_new="$(adp_stage_begin "$_output_final")"
    _CC_OUTPUT_DIR="$_output_new"

    cc_generate_agents
    cc_generate_skills
    adp_copy_scripts "${RDF_CANONICAL}/scripts" "${_CC_OUTPUT_DIR}/scripts"
    adp_copy_reference "${RDF_CANONICAL}/reference" "${_CC_OUTPUT_DIR}/reference" 1
    cc_generate_hooks
    cc_generate_governance
    cc_generate_rules

    _CC_OUTPUT_DIR="$_output_final"
    adp_stage_commit "$_output_final" "$_output_new"

    local agent_count skill_count script_count rule_count reference_count
    agent_count="$(adp_count "${_CC_OUTPUT_DIR}/agents" '*.md')"
    skill_count="$(adp_count "${_CC_OUTPUT_DIR}/skills" 'SKILL.md')"
    script_count="$(adp_count "${_CC_OUTPUT_DIR}/scripts" '*.sh')"
    rule_count="$(adp_count "${_CC_OUTPUT_DIR}/rules" '*.md')"  # rules/ absent → 0, not an error
    reference_count="$(adp_count "${_CC_OUTPUT_DIR}/reference" '*.md')"  # reference/ absent → 0, not an error

    rdf_log "CC generation complete: ${agent_count} agents, ${skill_count} skills, ${script_count} scripts, ${rule_count} rules, ${reference_count} reference docs"
}
