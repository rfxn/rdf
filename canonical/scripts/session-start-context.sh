#!/usr/bin/env bash
# SessionStart(source:compact) command hook: re-inject the pre-compaction
# handoff snapshot. If ~/.rdf/state/handoff/<session_id>.md exists, its content
# is printed to stdout (which Claude Code injects as context) and the file is
# renamed to .consumed so a later SessionStart does not re-inject it. Absent
# snapshot prints nothing. Startup must never fail: the EXIT trap forces exit 0.

set -euo pipefail
trap 'exit 0' EXIT   # SessionStart errors must not disrupt startup — force exit 0 on any failure

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

main() {
    local input session_id snapshot
    input="$(command cat)"

    session_id="$(_json_field session_id "$input")"
    session_id="$(printf '%s' "$session_id" | command tr -cd 'A-Za-z0-9._-')"  # sanitize before use as a filename
    [[ -n "$session_id" ]] || return 0

    snapshot="${HANDOFF_DIR}/${session_id}.md"
    [[ -f "$snapshot" ]] || return 0

    printf 'RDF post-compaction handoff:\n'
    command cat "$snapshot" 2>/dev/null || true   # already checked -f; tolerate a concurrent prune
    command mv "$snapshot" "${snapshot}.consumed" 2>/dev/null || true   # idempotence — don't re-inject on a later event
}

main "$@"
