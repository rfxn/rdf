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
    # IDs must be globally unique: same-initial categories and bullets inserted
    # above marked ones would otherwise reuse a taken <initial><ordinal>.
    local existing_ids=" " id_tok
    while IFS= read -r id_tok; do
        existing_ids="${existing_ids}${id_tok} "
    done < <(grep -oE '<!-- id:[A-Za-z]+[0-9]+ -->' "$_LESSONS" 2>/dev/null | sed -E 's/.*id:([A-Za-z]+[0-9]+).*/\1/' || true)  # empty set when no markers yet

    local cat_i="X" ord=0 line tmp
    tmp="$(command mktemp "${_LESSONS}.XXXXXX")"   # same dir as target: mv stays an atomic rename (never cross-fs copy)
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
                while [[ "$existing_ids" == *" ${cat_i}${ord} "* ]]; do ord=$((ord + 1)); done
                printf '%s <!-- id:%s%d -->\n' "$line" "$cat_i" "$ord" >> "$tmp"
                existing_ids="${existing_ids}${cat_i}${ord} "
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

# _tokens text — normalize a bullet to a sorted-unique lowercase letter-only
# token set (one per line), dropping a small stopword set. grep/sed are not
# coreutils, so they stay bare (matches cmd_index); tr/sort get the command prefix.
_tokens() {
    printf '%s' "$1" | command tr '[:upper:]' '[:lower:]' | command tr -cs '[:alpha:]' '\n' \
      | grep -vE '^(the|a|an|to|of|for|and|or|in|on|per|before|at|is|be)$' \
      | command sort -u
}

# _jaccard_pct set-a set-b — integer-percent Jaccard of two sorted-unique token
# lists. comm needs sorted input, which _tokens already guarantees.
_jaccard_pct() {
    local a="$1" b="$2" inter uni
    inter="$(command comm -12 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -c . || true)"  # grep -c exits 1 at 0 matches; printed count is the value (anti-pattern #7)
    uni="$(printf '%s\n%s\n' "$a" "$b" | command sort -u | grep -c . || true)"                   # same grep -c exit-1-at-0 handling
    [ "$uni" -gt 0 ] || { echo 0; return 0; }
    echo "$(( inter * 100 / uni ))"
}

# Polarity flags for order-independent contradiction detection. [^a-z] word
# boundaries are POSIX (no \b — macOS/BSD grep). grep is not a coreutil (bare).
_has_max() { printf '%s' "$1" | grep -qiE '(^|[^a-z])(always|every|full|all|must)([^a-z]|$)'; }
_has_min() { printf '%s' "$1" | grep -qiE '(^|[^a-z])(never|no|not|minimum|only|none)([^a-z]|$)'; }

# Thresholds computed against tests/fixtures/lessons/lessons-sample.md:
#   dup pair = 50% ; contradiction pair = 36% ; all eight negatives = 0%.
_DUP_MIN=50; _CONTRA_MIN=25   # contradiction band is [_CONTRA_MIN, _DUP_MIN)

# cmd_scan — propose dedup (token-Jaccard >= _DUP_MIN) and contradiction
# (opposing polarity, overlap in [_CONTRA_MIN, _DUP_MIN)) candidates as JSON.
# Flags only — never mutates. Builds JSON without jq (jq-optional).
cmd_scan() {
    [ -f "$_LESSONS" ] || { printf '{"duplicates":[],"contradictions":[]}\n'; return 0; }   # no lessons: empty result
    local -a bodies=() ids=()
    local line body id
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^-[[:space:]] ]] || continue
        id="$(printf '%s' "$line" | sed -nE 's/.*<!-- id:([A-Z0-9]+) -->.*/\1/p')"
        body="$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//; s/ *<!-- id:[A-Z0-9]+ -->.*//')"
        bodies+=("$body"); ids+=("${id:-?}")
    done < "$_LESSONS"

    local dups="" contras="" i j pct
    for ((i=0; i<${#bodies[@]}; i++)); do
        for ((j=i+1; j<${#bodies[@]}; j++)); do
            pct="$(_jaccard_pct "$(_tokens "${bodies[$i]}")" "$(_tokens "${bodies[$j]}")")"
            if [ "$pct" -ge "$_DUP_MIN" ]; then
                dups="${dups}{\"a\":\"${ids[$i]}\",\"b\":\"${ids[$j]}\",\"jaccard\":${pct}},"
            elif [ "$pct" -ge "$_CONTRA_MIN" ]; then
                # opposing polarity, order-independent: (i.max & j.min) | (i.min & j.max)
                if { _has_max "${bodies[$i]}" && _has_min "${bodies[$j]}"; } \
                   || { _has_min "${bodies[$i]}" && _has_max "${bodies[$j]}"; }; then
                    contras="${contras}{\"a\":\"${ids[$i]}\",\"b\":\"${ids[$j]}\",\"overlap\":${pct}},"
                fi
            fi
        done
    done
    printf '{"duplicates":[%s],"contradictions":[%s]}\n' "${dups%,}" "${contras%,}"
    return 0
}

case "${1:-}" in
    index) cmd_index ;;
    scan)  cmd_scan ;;
    *) echo "usage: rdf-lessons.sh {index|scan} [lessons-file]" >&2; exit 2 ;;
esac
