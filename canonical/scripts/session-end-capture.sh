#!/usr/bin/env bash
# canonical/scripts/session-end-capture.sh — SessionEnd command hook.
# Appends a deterministic git-only snapshot to the project session journal
# (.rdf/work-output/session-log.jsonl, read by /r-start via rdf-state.sh) and
# writes a session-end-<id>.json cache for /r-save, so a session that never runs
# /r-save is still recorded. Inline git only (no rdf-state.sh) keeps it inside
# the 5s budget. SessionEnd output is ignored by the platform (notification-only)
# and the EXIT trap forces exit 0 so shutdown is never blocked.
# SessionEnd stdin discriminator is `reason` (clear|logout|prompt_input_exit|
# bypass_permissions_disabled|other), NOT `trigger`/`source`.

set -euo pipefail
trap 'exit 0' EXIT   # SessionEnd must never block/delay shutdown — force exit 0 on any failure

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
    local input session_id reason cwd
    input="$(command cat)"

    session_id="$(_json_field session_id "$input")"
    session_id="$(printf '%s' "$session_id" | command tr -cd 'A-Za-z0-9._-')"  # sanitize before use as a filename (no path traversal)
    reason="$(_json_field reason "$input")"
    [[ -n "$reason" ]] || reason="other"   # SessionEnd reason enum catch-all default
    cwd="$(_json_field cwd "$input")"

    [[ -n "$cwd" ]] && { cd "$cwd" || exit 0; }   # bad cwd: bail cleanly (guarded cd)
    [[ -n "$session_id" ]] || session_id="$(command date +%s)-$$"   # id fallback when stdin omits session_id

    # Not a git repo → nothing to snapshot (clean no-op — the masked degrade path).
    command git rev-parse --git-dir >/dev/null 2>&1 || exit 0

    local branch head dirty ts
    branch="$(command git branch --show-current 2>/dev/null || true)"   # empty on detached HEAD; degrade, don't abort
    head="$(command git rev-parse --short HEAD 2>/dev/null || true)"     # empty on a commit-less repo; degrade, don't abort
    dirty="$(command git status --porcelain 2>/dev/null | command wc -l | command tr -d ' ' || true)"  # 0 if git errors; degrade, don't abort
    ts="$(command date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"    # blank ts tolerated over aborting the capture

    local out_dir=".rdf/work-output"
    command mkdir -p "$out_dir" 2>/dev/null || exit 0   # unwritable tree: give up quietly

    # Minimal JSON escaping (backslash + double-quote) for the stdin-derived
    # fields; control chars stripped first — an embedded newline would split the
    # one-record-per-line JSONL and silently break the session_last reader.
    local b_esc r_esc
    b_esc="$(printf '%s' "$branch" | command tr -d '\000-\037')"
    r_esc="$(printf '%s' "$reason" | command tr -d '\000-\037')"
    b_esc="${b_esc//\\/\\\\}"; b_esc="${b_esc//\"/\\\"}"
    r_esc="${r_esc//\\/\\\\}"; r_esc="${r_esc//\"/\\\"}"
    local line
    line="{\"timestamp\":\"${ts}\",\"head_after\":\"${head}\",\"branch\":\"${b_esc}\",\"dirty_files\":${dirty:-0},\"reason\":\"${r_esc}\",\"source\":\"session-end-hook\",\"insight\":null}"

    # Single O_APPEND write to the journal /r-start reads, plus a cache /r-save consumes.
    printf '%s\n' "$line" >> "${out_dir}/session-log.jsonl"
    printf '%s\n' "$line" >  "${out_dir}/session-end-${session_id}.json"
}

main "$@"
