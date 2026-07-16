#!/usr/bin/env bash
# adapters/claude-plugin/adapter.sh — Claude Code plugin adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh — do not execute directly

# Requires: RDF_HOME, RDF_CANONICAL, RDF_ADAPTERS, RDF_VERSION, jq

_CPL_ADAPTER_DIR="${RDF_ADAPTERS}/claude-plugin"
_CPL_OUTPUT_DIR="${_CPL_ADAPTER_DIR}/output"
_CPL_SKILL_META="${RDF_ADAPTERS}/agent-skills/skill-meta.json"   # shared intent-trigger source (mirrors cc adapter)

# Rewrite /r-NAME cross-references to /rdf:r-NAME in a command body.
# Plugin commands are always namespaced by the loader; unrewritten
# references would point at commands that do not exist in plugin installs.
# Boundary rules: leading context is line start or one of space/tab,
# backtick, (, |, ", ', *; trailing boundary is EOL or any char outside
# [a-z-]. Names are applied longest-first so /r-example-extra rewrites
# before /r-example can partially match. POSIX BRE only (macOS CI).
# Args: $1 = src file, $2 = dst file
_cpl_rewrite_namespace() {
    local src="$1"
    local dst="$2"
    local sed_args=()
    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        sed_args+=(-e "s#^/${name}\$#/rdf:${name}#")
        sed_args+=(-e "s#^/${name}\([^a-z-]\)#/rdf:${name}\1#")
        sed_args+=(-e "s#\([[:space:]\`(|\"'*]\)/${name}\$#\1/rdf:${name}#")
        sed_args+=(-e "s#\([[:space:]\`(|\"'*]\)/${name}\([^a-z-]\)#\1/rdf:${name}\2#g")
    done < <(_cpl_command_names_longest_first)
    sed "${sed_args[@]}" "$src" > "$dst"
}

# Emit canonical command basenames (no .md), longest name first.
_cpl_command_names_longest_first() {
    local f b
    for f in "${RDF_CANONICAL}/commands"/*.md; do
        [[ -f "$f" ]] || continue
        b="$(basename "$f" .md)"
        printf '%d %s\n' "${#b}" "$b"
    done | sort -rn | cut -d' ' -f2-
}

# cpl_generate_command_frontmatter <basename-no-ext> — emit an intent-trigger
# description: frontmatter block, mirroring cc_generate_command_frontmatter.
# Trigger comes from the shared agent-skills skill-meta.json; falls back to the
# canonical body's first non-heading line.
cpl_generate_command_frontmatter() {
    local name="$1" desc
    desc="$(jq -r --arg c "$name" '.[$c] // empty' "$_CPL_SKILL_META" 2>/dev/null || true)"  # missing key/file → empty (falls back to body)
    if [[ -z "$desc" ]]; then
        desc="$(sed -n '/^[^#[:space:]]/{ s/[[:space:]]*$//; p; q; }' "${RDF_CANONICAL}/commands/${name}.md")"
        [[ -z "$desc" ]] && desc="RDF command: ${name}"
    fi
    echo "---"
    echo "description: >"
    echo "  ${desc}"
    echo "---"
}

# Generate plugin command files: canonical/commands/*.md -> output/commands/
# with intent-trigger frontmatter + namespace rewrite of the body. No .rdf-hash
# sidecars — strict plugin validation rejects non-component files in the dir.
cpl_generate_commands() {
    local src_dir="${RDF_CANONICAL}/commands"
    local dst_dir="${_CPL_OUTPUT_DIR}/commands"
    local count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.md; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file")"
        local dst_file="${dst_dir}/${basename_f}"
        _cpl_rewrite_namespace "$src_file" "${dst_file}.body"
        {
            cpl_generate_command_frontmatter "${basename_f%.md}"
            echo ""
            command cat "${dst_file}.body"
        } > "$dst_file"
        command rm -f "${dst_file}.body"
        count=$((count + 1))
    done
    rdf_log "generated ${count} command files (intent-trigger frontmatter, namespace-rewritten)"
}

# Generate plugin agent files with CC YAML frontmatter, no hash sidecars.
# Reuses the cc adapter's agent-meta.json as the single metadata source.
cpl_generate_agents() {
    local src_dir="${RDF_CANONICAL}/agents"
    local dst_dir="${_CPL_OUTPUT_DIR}/agents"
    local meta="${RDF_ADAPTERS}/claude-code/agent-meta.json"
    local count=0

    rdf_require_file "$meta" "agent-meta.json"
    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.md; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file" .md)"
        local dst_file="${dst_dir}/${basename_f}.md"

        # Body gets the same /r-X -> /rdf:r-X rewrite as commands —
        # agent personas reference pipeline commands 14 times today.
        if _cpl_agent_frontmatter "$basename_f" "$meta" > "${dst_file}.tmp" 2>/dev/null; then  # agents without metadata fall through to plain copy
            echo "" >> "${dst_file}.tmp"
            _cpl_rewrite_namespace "$src_file" "${dst_file}.body"
            command cat "${dst_file}.body" >> "${dst_file}.tmp"
            command rm -f "${dst_file}.body"
            command mv "${dst_file}.tmp" "$dst_file"
        else
            _cpl_rewrite_namespace "$src_file" "$dst_file"
            command rm -f "${dst_file}.tmp"
        fi
        count=$((count + 1))
    done
    rdf_log "generated ${count} agent files"
}

# YAML frontmatter from agent-meta.json (cc-compatible schema).
# Args: $1 = agent basename, $2 = agent-meta.json path
_cpl_agent_frontmatter() {
    local agent="$1"
    local meta="$2"
    local name desc model tools_json disallowed_json

    if ! jq -e --arg a "$agent" '.[$a]' "$meta" >/dev/null 2>&1; then  # missing entry = signal caller to plain-copy
        rdf_warn "no metadata for agent: $agent — copying without frontmatter"
        return 1
    fi

    name="$(jq -r --arg a "$agent" '.[$a].name' "$meta")"
    desc="$(jq -r --arg a "$agent" '.[$a].description' "$meta")"
    model="$(jq -r --arg a "$agent" '.[$a].model' "$meta")"
    tools_json="$(jq -c --arg a "$agent" '.[$a].tools // []' "$meta")"
    disallowed_json="$(jq -c --arg a "$agent" '.[$a].disallowedTools // []' "$meta")"

    echo "---"
    echo "name: ${name}"
    echo "description: >"
    echo "  ${desc}"
    if [[ "$tools_json" != "[]" ]]; then
        echo "tools:"
        jq -r '.[]' <<< "$tools_json" | while IFS= read -r tool; do
            echo "  - ${tool}"
        done
    fi
    if [[ "$disallowed_json" != "[]" ]]; then
        echo "disallowedTools:"
        jq -r '.[]' <<< "$disallowed_json" | while IFS= read -r tool; do
            echo "  - ${tool}"
        done
    fi
    echo "model: ${model}"
    echo "---"
}

# Copy canonical scripts (hook targets) — executable, unconditional.
cpl_generate_scripts() {
    local src_dir="${RDF_CANONICAL}/scripts"
    local dst_dir="${_CPL_OUTPUT_DIR}/scripts"
    local count=0

    command mkdir -p "$dst_dir"

    for src_file in "${src_dir}"/*.sh; do
        [[ -f "$src_file" ]] || continue
        local basename_f
        basename_f="$(basename "$src_file")"
        command cp "$src_file" "${dst_dir}/${basename_f}"
        command chmod +x "${dst_dir}/${basename_f}"
        count=$((count + 1))
    done
    rdf_log "generated ${count} script files"
}

# Transform hooks.json: every "command" value under ~/.claude/scripts/
# (ANYWHERE in the document — includes top-level statusLine, a sibling
# of "hooks") -> ${CLAUDE_PLUGIN_ROOT}-relative path. Prompt-type hooks
# pass through untouched. walk/1 is defined inline for jq 1.5 compat
# (builtin only since 1.6; local def harmlessly shadows it on 1.6+).
cpl_generate_hooks() {
    local src="${RDF_ADAPTERS}/claude-code/hooks/hooks.json"
    local dst="${_CPL_OUTPUT_DIR}/hooks.json"
    # shellcheck disable=SC2016  # literal ${CLAUDE_PLUGIN_ROOT} — expanded by the plugin loader, not this shell
    local pfx='"${CLAUDE_PLUGIN_ROOT}"/adapters/claude-plugin/output/scripts'

    rdf_require_file "$src" "hooks.json template"
    jq --arg pfx "$pfx" '
        def walk(f):
            . as $in
            | if type == "object" then
                  reduce keys[] as $key ({}; . + {($key): ($in[$key] | walk(f))}) | f
              elif type == "array" then map(walk(f)) | f
              else f
              end;
        walk(
            if type == "object" and (.command? | type == "string")
               and (.command | startswith("~/.claude/scripts/"))
            then .command = ($pfx + (.command | ltrimstr("~/.claude/scripts")))
            else .
            end
        )
    ' "$src" > "$dst"
    rdf_log "generated hooks.json (plugin-root paths)"
}

# Stamp plugin.json version from VERSION and the agents file array from
# generated output. Plugin users only receive updates when version
# changes; agents must be an explicit .md file array — the strict
# validator rejects directory strings (verified against
# claude plugin validate --strict).
cpl_stamp_plugin_version() {
    local manifest="${RDF_HOME}/.claude-plugin/plugin.json"
    local tmp agents_json
    local agent_files=()
    local f

    rdf_require_file "$manifest" "plugin.json"
    for f in "${_CPL_OUTPUT_DIR}/agents"/*.md; do
        [[ -f "$f" ]] || continue
        agent_files+=("./adapters/claude-plugin/output/agents/$(basename "$f")")
    done
    agents_json="$(printf '%s\n' "${agent_files[@]}" | jq -R . | jq -s .)"

    tmp="$(command mktemp)"
    jq --arg v "$RDF_VERSION" --argjson agents "$agents_json" \
        '.version = $v | .agents = $agents' "$manifest" > "$tmp"
    command mv "$tmp" "$manifest"
    rdf_log "stamped plugin.json version: ${RDF_VERSION} (${#agent_files[@]} agents)"
}

# Full plugin generation pipeline
cpl_generate_all() {
    rdf_log "generating Claude Plugin adapter output..."
    rdf_require_dir "$RDF_CANONICAL" "canonical directory"
    rdf_require_bin jq

    local _output_final="$_CPL_OUTPUT_DIR"
    local _output_new="${_CPL_OUTPUT_DIR}.new"
    local _output_old="${_CPL_OUTPUT_DIR}.old"

    # Build into staging directory, then atomic swap (cc adapter pattern)
    command rm -rf "$_output_new"
    command mkdir -p "$_output_new"
    _CPL_OUTPUT_DIR="$_output_new"

    cpl_generate_commands
    cpl_generate_agents
    cpl_generate_scripts
    cpl_generate_hooks
    cpl_stamp_plugin_version

    _CPL_OUTPUT_DIR="$_output_final"
    command rm -rf "$_output_old"
    if [[ -d "$_output_final" ]]; then
        command mv "$_output_final" "$_output_old"
    fi
    command mv "$_output_new" "$_output_final"
    command rm -rf "$_output_old"

    local command_count agent_count script_count
    command_count="$(find "${_CPL_OUTPUT_DIR}/commands" -name '*.md' 2>/dev/null | wc -l)"  # dir may not exist on partial generation
    agent_count="$(find "${_CPL_OUTPUT_DIR}/agents" -name '*.md' 2>/dev/null | wc -l)"      # dir may not exist on partial generation
    script_count="$(find "${_CPL_OUTPUT_DIR}/scripts" -name '*.sh' 2>/dev/null | wc -l)"    # dir may not exist on partial generation

    rdf_log "plugin generation complete: ${command_count} commands, ${agent_count} agents, ${script_count} scripts"
}
