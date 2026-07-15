#!/usr/bin/env bash
# state/rdf-lessons.sh — lessons-learned index + consolidation scan.
# `index` assigns stable [<Cat><ordinal>] IDs to lessons bullets (persisted as
# <!-- id:W1 --> markers) and writes a size-capped ~/.rdf/lessons-index.md that
# the SessionStart hook injects. `scan` proposes dedup/contradiction candidates
# for /r-util-mem-compact (never mutates). index is the SINGLE writer of
# lessons-learned.md / lessons-index.md (called only by /r-save, flock-guarded);
# the SessionStart hook is read-only.
# Usage: rdf-lessons.sh index [lessons-file]   -> writes <dir>/lessons-index.md
#        rdf-lessons.sh scan  [lessons-file]   -> JSON candidates to stdout
set -euo pipefail

_LESSONS="${2:-${HOME}/.rdf/lessons-learned.md}"
_INDEX="$(command dirname "$_LESSONS")/lessons-index.md"
_MAX_LINES=12          # cap injected entries
_MAX_BYTES=400         # hard size cap for the index body

# _cat_initial heading — uppercase first letter of a "## <Category>" heading.
_cat_initial() {
    printf '%s' "${1:0:1}" | command tr '[:lower:]' '[:upper:]'
}

# cmd_index — backfill missing <!-- id --> markers in place (idempotent), then
# emit a compact size-capped index (most-recent _MAX_LINES entries).
cmd_index() {
    [ -f "$_LESSONS" ] || { : > "$_INDEX"; return 0; }   # no lessons: empty index

    # Single-writer lock (F7): /r-save and /r-util-mem-compact both mutate via
    # cmd_index — serialize with flock when present; degrade to a direct write.
    if command -v flock >/dev/null 2>&1; then
        exec 9>"${_LESSONS}.lock" || true   # lock fd; proceed unlocked if it cannot open
        flock 9 2>/dev/null || true         # best-effort; never block the index rebuild
    fi

    # Pass 1: ensure every bullet carries an id marker (idempotent re-runs).
    local cat_i="X" ord=0 line tmp
    tmp="$(command mktemp)"
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^##[[:space:]] ]]; then
            cat_i="$(_cat_initial "${line#\#\# }")"; ord=0
            printf '%s\n' "$line" >> "$tmp"; continue
        fi
        if [[ "$line" =~ ^-[[:space:]] ]]; then
            ord=$((ord + 1))
            if [[ "$line" == *"<!-- id:"* ]]; then
                printf '%s\n' "$line" >> "$tmp"
            else
                printf '%s <!-- id:%s%d -->\n' "$line" "$cat_i" "$ord" >> "$tmp"
            fi
            continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$_LESSONS"
    command mv "$tmp" "$_LESSONS"

    # Pass 2: build the index body to a temp, size-cap via head from a file (not
    # a live pipe — avoids SIGPIPE aborting the producer under set -o pipefail).
    # Per-field sed extraction (F3): BSD sed (macOS CI) emits a literal 't' for a
    # \t replacement, so IDs and bodies are pulled with separate POSIX sed -E.
    local body_tmp count=0 bline id body clause
    body_tmp="$(command mktemp)"
    printf '%s\n' "RDF lessons available (fetch full text by ID from ~/.rdf/lessons-learned.md):" > "$body_tmp"
    while IFS= read -r bline; do
        [ "$count" -ge "$_MAX_LINES" ] && break
        id="$(printf '%s' "$bline" | sed -nE 's/.*<!-- id:([A-Z0-9]+) -->.*/\1/p')"
        body="$(printf '%s' "$bline" | sed -E 's/^-[[:space:]]+//; s/ *<!-- id:[A-Z0-9]+ -->.*//')"
        clause="${body%%.*}"; clause="${clause%%;*}"
        printf '[%s] %s\n' "$id" "${clause:0:70}" >> "$body_tmp"
        count=$((count + 1))
    done < <(grep -E '^-[[:space:]].*<!-- id:' "$_LESSONS" 2>/dev/null || true)  # grep rc1 (no tagged bullets yet) is not an error

    command head -c "$_MAX_BYTES" "$body_tmp" > "$_INDEX"
    command rm -f "$body_tmp"
    return 0
}

# cmd_scan — emit dedup/contradiction candidates as JSON. The real Jaccard +
# polarity heuristic lands with the consolidation pass; this reports none so the
# scan subcommand is callable now.
cmd_scan() {
    printf '{"duplicates":[],"contradictions":[]}\n'
    return 0
}

case "${1:-}" in
    index) cmd_index ;;
    scan)  cmd_scan ;;
    *) echo "usage: rdf-lessons.sh {index|scan} [lessons-file]" >&2; exit 2 ;;
esac
