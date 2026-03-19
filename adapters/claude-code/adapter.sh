#!/usr/bin/env bash
# adapters/claude-code/adapter.sh — Claude Code adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh — do not execute directly

# Requires: RDF_HOME, RDF_CANONICAL, RDF_ADAPTERS, jq

_CC_ADAPTER_DIR="${RDF_ADAPTERS}/claude-code"
_CC_OUTPUT_DIR="${_CC_ADAPTER_DIR}/output"
_CC_AGENT_META="${_CC_ADAPTER_DIR}/agent-meta.json"
_CC_COMMAND_META="${_CC_ADAPTER_DIR}/command-meta-v3.json"

# Generate YAML frontmatter block from agent-meta.json entry
# Args: $1 = canonical agent basename (no extension)
# Output: YAML frontmatter to stdout, or empty if agent not in metadata
_cc_agent_frontmatter() {
    local agent="$1"
    local name desc model tools_json disallowed_json

    # Check if agent exists in metadata
    if ! jq -e --arg a "$agent" '.[$a]' "$_CC_AGENT_META" >/dev/null 2>&1; then
        rdf_warn "no metadata for agent: $agent — copying without frontmatter"
        return 1
    fi

    name="$(jq -r --arg a "$agent" '.[$a].name' "$_CC_AGENT_META")"
    desc="$(jq -r --arg a "$agent" '.[$a].description' "$_CC_AGENT_META")"
    model="$(jq -r --arg a "$agent" '.[$a].model' "$_CC_AGENT_META")"
    tools_json="$(jq -c --arg a "$agent" '.[$a].tools // []' "$_CC_AGENT_META")"
    disallowed_json="$(jq -c --arg a "$agent" '.[$a].disallowedTools // []' "$_CC_AGENT_META")"

    echo "---"
    echo "name: ${name}"

    # Multi-line description for readability
    echo "description: >"
    echo "  ${desc}"

    # Tools list
    if [[ "$tools_json" != "[]" ]]; then
        echo "tools:"
        jq -r '.[]' <<< "$tools_json" | while IFS= read -r tool; do
            echo "  - ${tool}"
        done
    fi

    # Disallowed tools list
    if [[ "$disallowed_json" != "[]" ]]; then
        echo "disallowedTools:"
        jq -r '.[]' <<< "$disallowed_json" | while IFS= read -r tool; do
            echo "  - ${tool}"
        done
    fi

    echo "model: ${model}"
    echo "---"
}

# Generate all CC agent files
# Reads canonical/agents/*.md + agent-meta.json -> output/agents/*.md
cc_generate_agents() {
    local src_dir="${RDF_CANONICAL}/agents"
    local dst_dir="${_CC_OUTPUT_DIR}/agents"
    local count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.md; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file" .md)"

        local dst_file="${dst_dir}/${basename_f}.md"

        # Generate frontmatter + canonical body
        if _cc_agent_frontmatter "$basename_f" > "${dst_file}.tmp" 2>/dev/null; then
            echo "" >> "${dst_file}.tmp"
            cat "$src_file" >> "${dst_file}.tmp"
            command mv "${dst_file}.tmp" "$dst_file"
        else
            # No metadata — copy as-is
            command cp "$src_file" "$dst_file"
            command rm -f "${dst_file}.tmp"
        fi
        count=$((count + 1))
    done
    rdf_log "generated ${count} agent files"
}

# Generate all CC command files
# Reads canonical/commands/*.md + command-meta.json -> output/commands/*.md
# Currently: direct copy (commands have no frontmatter in CC)
cc_generate_commands() {
    local src_dir="${RDF_CANONICAL}/commands"
    local dst_dir="${_CC_OUTPUT_DIR}/commands"
    local count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.md; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file")"
        command cp "$src_file" "${dst_dir}/${basename_f}"
        count=$((count + 1))
    done
    rdf_log "generated ${count} command files"
}

# Generate all CC script files
# Direct copy — scripts are already tool-agnostic
cc_generate_scripts() {
    local src_dir="${RDF_CANONICAL}/scripts"
    local dst_dir="${_CC_OUTPUT_DIR}/scripts"
    local count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.sh; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file")"
        # Profile filter
        if ! rdf_profile_includes "scripts" "$basename_f"; then
            rdf_log "  skipped (inactive profile): ${basename_f}"
            continue
        fi
        command cp "$src_file" "${dst_dir}/${basename_f}"
        chmod +x "${dst_dir}/${basename_f}"
        count=$((count + 1))
    done
    rdf_log "generated ${count} script files"
}

# Copy hooks.json to output
cc_generate_hooks() {
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

# Full CC generation pipeline
cc_generate_all() {
    rdf_log "generating Claude Code adapter output..."
    rdf_require_dir "$RDF_CANONICAL" "canonical directory"
    rdf_require_file "$_CC_AGENT_META" "agent-meta.json"
    rdf_require_bin jq

    # Clean output directory
    command rm -rf "$_CC_OUTPUT_DIR"
    command mkdir -p "$_CC_OUTPUT_DIR"

    cc_generate_agents
    cc_generate_commands
    cc_generate_scripts
    cc_generate_hooks
    cc_generate_governance

    local agent_count command_count script_count
    agent_count="$(find "${_CC_OUTPUT_DIR}/agents" -name '*.md' 2>/dev/null | wc -l)"
    command_count="$(find "${_CC_OUTPUT_DIR}/commands" -name '*.md' 2>/dev/null | wc -l)"
    script_count="$(find "${_CC_OUTPUT_DIR}/scripts" -name '*.sh' 2>/dev/null | wc -l)"

    rdf_log "CC generation complete: ${agent_count} agents, ${command_count} commands, ${script_count} scripts"
}
