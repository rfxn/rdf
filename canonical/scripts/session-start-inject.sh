#!/usr/bin/env bash
# canonical/scripts/session-start-inject.sh — SessionStart command hook.
# Injects the cached RDF lessons ID-index as additionalContext so an agent sees
# which lessons exist and fetches full bodies by ID on demand. READ-ONLY: it
# never regenerates or writes lessons-learned.md / lessons-index.md — the single
# writer is /r-save (index rebuild + ID backfill). Skips source=resume (context
# already present); injects on startup|clear|compact (compact re-inject restores
# lessons dropped by compaction). The <=400B cap bounds per-spawn cost, subagent
# spawns included (the SessionStart source enum has no subagent value).
# Startup must never fail: the EXIT trap forces exit 0.

set -euo pipefail
trap 'exit 0' EXIT   # SessionStart errors must not disrupt startup — force exit 0 on any failure

INDEX="${HOME:-/tmp}/.rdf/lessons-index.md"

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

main() {
    local input source body
    input="$(command cat)"

    source="$(_json_field source "$input")"
    [[ "$source" == "resume" ]] && return 0   # resume already carries context — inject nothing

    [[ -s "$INDEX" ]] || return 0   # no cached index → nothing to inject (never regenerate — /r-save owns writes)

    # jq builds the additionalContext JSON safely (escapes the index body). Without
    # jq, emit nothing rather than hand-roll fragile escaping.
    command -v jq >/dev/null 2>&1 || return 0

    body="$(command head -c 400 "$INDEX")"   # hard cap bounds per-spawn (incl. subagent) cost
    jq -cn --arg c "$body" '{hookSpecificOutput:{additionalContext:$c}}' 2>/dev/null || true  # malformed → inject nothing
}

main "$@"
