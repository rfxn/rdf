#!/usr/bin/env bash
# lib/dispatch.sh — Mode-aware agent dispatch abstraction
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/dispatch.sh or adapters — do not execute directly

[[ -n "${_RDF_DISPATCH_LOADED:-}" ]] && return 0 2>/dev/null  # idempotent source guard
_RDF_DISPATCH_LOADED=1

# Requires rdf_common.sh to be loaded first
if [[ -z "${_RDF_COMMON_LOADED:-}" ]]; then
    echo "dispatch.sh: fatal: rdf_common.sh must be loaded first" >&2
    exit 1
fi

# --- Configuration ---
RDF_DISPATCH_AGENTS="${RDF_HOME}/lib/dispatch-agents.json"
RDF_DISPATCH_TASKS="${RDF_HOME}/lib/dispatch-tasks.json"

# --- Internal helpers ---

# Substitute {var} placeholders in a string
# Usage: _dispatch_subst "template" "var1=val1" "var2=val2" ...
_dispatch_subst() {
    local template="$1"
    shift
    local kv key val
    for kv in "$@"; do
        key="${kv%%=*}"
        val="${kv#*=}"
        # Use a variable to avoid bash 4.x ${var/pat/repl} brace trap
        template="${template//\{${key}\}/${val}}"
    done
    printf '%s' "$template"
}

# Read a field from the agent registry
# Usage: _dispatch_agent_field <agent-name> <field>
_dispatch_agent_field() {
    local agent="$1"
    local field="$2"
    rdf_require_file "$RDF_DISPATCH_AGENTS" "dispatch agent registry"
    jq -r ".agents[\"${agent}\"].${field} // empty" "$RDF_DISPATCH_AGENTS"
}

# Read a field from a task template
# Usage: _dispatch_task_field <template-name> <field>
_dispatch_task_field() {
    local tmpl="$1"
    local field="$2"
    rdf_require_file "$RDF_DISPATCH_TASKS" "dispatch task templates"
    jq -r ".templates[\"${tmpl}\"].${field} // empty" "$RDF_DISPATCH_TASKS"
}

# Read the pipeline definition for a tier
# Usage: _dispatch_pipeline_stages <pipeline-name>
_dispatch_pipeline_stages() {
    local pipeline="$1"
    rdf_require_file "$RDF_DISPATCH_TASKS" "dispatch task templates"
    jq -r ".pipelines[\"${pipeline}\"].stages[]" "$RDF_DISPATCH_TASKS"
}

# Check if Agent Teams mode is enabled
_dispatch_is_teams_mode() {
    rdf_feature_enabled "RDF_AGENT_TEAMS"
}

# --- Public API ---

# Generate dispatch instructions for a single agent
# Usage: rdf_dispatch_agent <agent-name> <task-template> <phase> <project-path> <plan-path>
# Output: Structured markdown dispatch block to stdout
rdf_dispatch_agent() {
    local agent_name="$1"
    local task_tmpl="$2"
    local phase="$3"
    local project_path="$4"
    local plan_path="${5:-}"

    rdf_require_bin jq

    # Resolve agent properties
    local role model cc_name subagent_type team_agent_type timeout
    role="$(_dispatch_agent_field "$agent_name" "role")"
    model="$(_dispatch_agent_field "$agent_name" "model")"
    cc_name="$(_dispatch_agent_field "$agent_name" "cc_name")"
    subagent_type="$(_dispatch_agent_field "$agent_name" "subagent_type")"
    team_agent_type="$(_dispatch_agent_field "$agent_name" "team_agent_type")"
    timeout="$(_dispatch_agent_field "$agent_name" "timeout_minutes")"

    if [[ -z "$role" ]]; then
        rdf_die "unknown agent: $agent_name (not in dispatch registry)"
    fi

    # Resolve task template properties
    local raw_subject raw_output raw_prompt raw_active
    raw_subject="$(_dispatch_task_field "$task_tmpl" "subject")"
    raw_output="$(_dispatch_task_field "$task_tmpl" "output_file")"
    raw_prompt="$(_dispatch_task_field "$task_tmpl" "prompt_template")"
    raw_active="$(_dispatch_task_field "$task_tmpl" "active_form")"

    # Substitute placeholders
    local subs=("phase=${phase}" "project_path=${project_path}" "plan_path=${plan_path}")
    local subject output_file prompt active_form
    subject="$(_dispatch_subst "$raw_subject" "${subs[@]}")"
    output_file="$(_dispatch_subst "$raw_output" "${subs[@]}")"
    prompt="$(_dispatch_subst "$raw_prompt" "${subs[@]}")"
    active_form="$(_dispatch_subst "$raw_active" "${subs[@]}")"

    # Resolve dependencies
    local deps_json
    deps_json="$(jq -r ".templates[\"${task_tmpl}\"].depends_on // [] | join(\", \")" "$RDF_DISPATCH_TASKS")"

    if _dispatch_is_teams_mode; then
        _dispatch_emit_teams "$agent_name" "$role" "$model" "$cc_name" \
            "$team_agent_type" "$subject" "$prompt" "$output_file" \
            "$active_form" "$deps_json" "$timeout"
    else
        _dispatch_emit_subagent "$agent_name" "$role" "$model" "$cc_name" \
            "$subagent_type" "$prompt" "$output_file" "$timeout"
    fi
}

# Generate subagent mode dispatch block
_dispatch_emit_subagent() {
    local agent_name="$1" role="$2" model="$3" cc_name="$4"
    local subagent_type="$5" prompt="$6" output_file="$7" timeout="$8"

    cat <<DISPATCH_BLOCK

### Dispatch: ${role} (${agent_name})

**Mode:** Subagent
**Tool:** Agent
**Parameters:**
- subagent_type: \`${cc_name}\` (fallback: \`${subagent_type}\` with model \`${model}\`)
- prompt: see below
- timeout: ${timeout} minutes

**Prompt:**
> ${prompt}

**Expected output:** \`${output_file}\`

DISPATCH_BLOCK
}

# Generate Agent Teams mode dispatch block
_dispatch_emit_teams() {
    local agent_name="$1" role="$2" model="$3" cc_name="$4"
    local team_agent_type="$5" subject="$6" prompt="$7" output_file="$8"
    local active_form="$9" deps="${10}" timeout="${11}"

    cat <<DISPATCH_BLOCK

### Dispatch: ${role} (${agent_name})

**Mode:** Agent Teams (teammate)
**Tools:** TaskCreate + Task (teammate spawn)

**TaskCreate parameters:**
\`\`\`json
{
  "subject": "${subject}",
  "description": "${prompt}",
  "activeForm": "${active_form}"
}
\`\`\`

**Task (teammate) parameters:**
\`\`\`json
{
  "team_name": "{team_name}",
  "name": "${agent_name}",
  "subagent_type": "${team_agent_type}",
  "model": "${model}",
  "prompt": "${prompt}",
  "run_in_background": true
}
\`\`\`

**Blocked by:** ${deps:-none}
**Expected output:** \`${output_file}\`
**Timeout:** ${timeout} minutes

DISPATCH_BLOCK
}

# Generate a complete pipeline dispatch sequence
# Usage: rdf_dispatch_pipeline <tier> <phase> <project-path> <plan-path> [flags...]
# Flags: --no-challenger, --no-ux, --no-uat, --no-scope
# Output: Complete pipeline dispatch instructions to stdout
rdf_dispatch_pipeline() {
    local tier="$1"
    local phase="$2"
    local project_path="$3"
    local plan_path="$4"
    shift 4

    # Parse flags
    local no_challenger="" no_ux="" no_uat="" no_scope=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            --no-challenger) no_challenger=1 ;;
            --no-ux)         no_ux=1 ;;
            --no-uat)        no_uat=1 ;;
            --no-scope)      no_scope=1 ;;
        esac
    done

    rdf_require_bin jq

    # Select pipeline based on tier
    local pipeline_name
    if [[ "$tier" -le 1 ]]; then
        pipeline_name="tier-0-1"
    elif [[ -n "$no_challenger" ]]; then
        pipeline_name="tier-2-no-challenger"
    else
        pipeline_name="tier-2-plus"
    fi

    # Header
    local mode_label="Subagent"
    if _dispatch_is_teams_mode; then
        mode_label="Agent Teams"
    fi

    cat <<PIPELINE_HEADER
## Pipeline Dispatch: Phase ${phase} (Tier ${tier})

**Mode:** ${mode_label}
**Project:** ${project_path}
**Plan:** ${plan_path}

PIPELINE_HEADER

    # Agent Teams: emit team setup
    if _dispatch_is_teams_mode; then
        local team_name_tmpl team_desc_tmpl team_name team_desc
        team_name_tmpl="$(jq -r '.team.name_template' "$RDF_DISPATCH_TASKS")"
        team_desc_tmpl="$(jq -r '.team.description_template' "$RDF_DISPATCH_TASKS")"
        local project_basename
        project_basename="$(basename "$project_path")"
        team_name="$(_dispatch_subst "$team_name_tmpl" "project=${project_basename}" "phase=${phase}")"
        team_desc="$(_dispatch_subst "$team_desc_tmpl" "project=${project_basename}" "phase=${phase}")"

        cat <<TEAM_SETUP
### Team Setup

**Tool:** TeamCreate
\`\`\`json
{
  "team_name": "${team_name}",
  "description": "${team_desc}"
}
\`\`\`

---

TEAM_SETUP
    fi

    # Emit each stage
    local stages stage agent_name
    stages="$(_dispatch_pipeline_stages "$pipeline_name")"

    while IFS= read -r stage; do
        [[ -z "$stage" ]] && continue

        # Apply skip flags
        case "$stage" in
            scope-*) [[ -n "$no_scope" ]] && continue ;;
            challenger) [[ -n "$no_challenger" ]] && continue ;;
            ux-review) [[ -n "$no_ux" ]] && continue ;;
            uat) [[ -n "$no_uat" ]] && continue ;;
        esac

        agent_name="$(_dispatch_task_field "$stage" "agent")"
        rdf_dispatch_agent "$agent_name" "$stage" "$phase" "$project_path" "$plan_path"
        echo "---"
    done <<< "$stages"

    # Agent Teams: emit parallel group note
    if _dispatch_is_teams_mode; then
        local parallel_group
        parallel_group="$(jq -r ".pipelines[\"${pipeline_name}\"].parallel_groups // {} | keys[]" "$RDF_DISPATCH_TASKS" 2>/dev/null)" || true  # no parallel groups is fine
        if [[ -n "$parallel_group" ]]; then
            echo ""
            echo "### Parallel Execution Groups"
            echo ""
            local group_name group_stages
            while IFS= read -r group_name; do
                group_stages="$(jq -r ".pipelines[\"${pipeline_name}\"].parallel_groups[\"${group_name}\"] | join(\", \")" "$RDF_DISPATCH_TASKS")"
                echo "- **${group_name}:** ${group_stages}"
            done <<< "$parallel_group"
            echo ""
            echo "In Agent Teams mode, tasks in parallel groups share the same"
            echo "dependency set and execute concurrently via self-claiming."
        fi
    fi

    # Agent Teams: emit teardown
    if _dispatch_is_teams_mode; then
        cat <<TEAM_TEARDOWN

---

### Team Teardown

After all tasks complete and results are collected:

1. Send shutdown_request to all teammates
2. Wait for shutdown_response from each
3. Run TeamDelete to clean up

TEAM_TEARDOWN
    fi
}

# Show dispatch mode status
# Usage: rdf_dispatch_status
rdf_dispatch_status() {
    local mode="subagent"
    if _dispatch_is_teams_mode; then
        mode="agent-teams"
    fi
    local agent_count
    agent_count="$(jq '.agents | length' "$RDF_DISPATCH_AGENTS")"
    local template_count
    template_count="$(jq '.templates | length' "$RDF_DISPATCH_TASKS")"
    local pipeline_count
    pipeline_count="$(jq '.pipelines | length' "$RDF_DISPATCH_TASKS")"

    cat <<STATUS
Dispatch Mode: ${mode}
Feature Flag:  RDF_AGENT_TEAMS=${RDF_AGENT_TEAMS:-false}
Agents:        ${agent_count}
Templates:     ${template_count}
Pipelines:     ${pipeline_count}
STATUS
}
