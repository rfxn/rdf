#!/usr/bin/env bash
# PreCompact command hook: snapshot session state before context compaction.
# Reads the PreCompact stdin JSON and writes a compact handoff note to
# ~/.rdf/state/handoff/<session_id>.md for SessionStart(source:compact) to
# re-inject. Compaction must NEVER be blocked or delayed by this hook: the
# EXIT trap forces exit 0 on every path (set -e / set -u / unexpected failure),
# and each fallible step degrades gracefully so a partial snapshot still writes.

set -euo pipefail
trap 'exit 0' EXIT   # PreCompact must never block/delay compaction — force exit 0 on any failure

HANDOFF_DIR="${HOME:-/tmp}/.rdf/state/handoff"

# _json_field field json — extract a top-level string field; jq when present,
# grep/sed fallback otherwise (jq is not guaranteed on the host).
_json_field() {
    local field="$1" json="$2" val=""
    if command -v jq >/dev/null 2>&1; then
        val="$(printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null || true)"  # empty on malformed JSON
    else
        val="$(printf '%s' "$json" | grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | command head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' || true)"  # best-effort field read without jq
    fi
    printf '%s' "$val"
}

# _resolve_active_plan root — echo the active plan path if a .rdf pointer names
# an existing file; cheap read of the pointer written by rdf_set_active_plan
# (no heavy lib sourcing — the PreCompact session id is not RDF_SESSION_ID).
_resolve_active_plan() {
    local root="$1" pointer plan
    for pointer in "$root"/.rdf/active-plan-* "$root"/.rdf/active-plan; do
        [[ -f "$pointer" ]] || continue
        plan=""
        read -r plan < "$pointer" || true   # pointer may lack trailing newline
        if [[ -n "$plan" && -f "$plan" ]]; then
            printf '%s' "$plan"
            return 0
        fi
    done
    return 0
}

main() {
    local input session_id trigger cwd
    input="$(command cat)"

    session_id="$(_json_field session_id "$input")"
    session_id="$(printf '%s' "$session_id" | command tr -cd 'A-Za-z0-9._-')"  # sanitize before use as a filename
    [[ -n "$session_id" ]] || session_id="unknown"
    trigger="$(_json_field trigger "$input")"
    [[ -n "$trigger" ]] || trigger="unknown"
    cwd="$(_json_field cwd "$input")"

    command mkdir -p "$HANDOFF_DIR"
    command find "$HANDOFF_DIR" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true  # prune stale handoffs; ignore races

    local -a lines=()
    lines+=("# RDF handoff snapshot")
    lines+=("- timestamp: $(command date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)")  # blank timestamp tolerated over aborting the snapshot
    lines+=("- trigger: $trigger")
    lines+=("- cwd: ${cwd:-unknown}")

    if [[ -n "$cwd" && -d "$cwd" ]] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local branch head dirty plan wo n f
        branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"  # empty on a commit-less repo; degrade, don't abort
        head="$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)"  # empty on a commit-less repo; degrade, don't abort
        dirty="$(git -C "$cwd" status --porcelain 2>/dev/null | command wc -l | command tr -d ' ' || true)"  # 0 if git errors; degrade, don't abort
        lines+=("- branch: ${branch:-unknown}")
        lines+=("- head: ${head:-unknown}")
        lines+=("- dirty-files: ${dirty:-0}")

        plan="$(_resolve_active_plan "$cwd")"
        [[ -n "$plan" ]] && lines+=("- active-plan: $plan")

        wo="$cwd/.rdf/work-output"
        if [[ -d "$wo" ]]; then
            local -a recent=()
            n=0
            while IFS= read -r f; do
                [[ -f "$wo/$f" ]] || continue
                recent+=("  - $f")
                n=$((n + 1))
                [[ "$n" -ge 3 ]] && break
            done < <(command ls -1t "$wo" 2>/dev/null || true)  # empty listing on error; degrade, don't abort
            if [[ "${#recent[@]}" -gt 0 ]]; then
                lines+=("- recent work-output:")
                lines+=("${recent[@]}")
            fi
        fi
    fi

    printf '%s\n' "${lines[@]}" > "${HANDOFF_DIR}/${session_id}.md"
}

main "$@"
