#!/usr/bin/env bash
# state/rdf-bus.sh — Concurrent-session coordination primitives (Wave A)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Provides: rdf_session_init, rdf_scoped_filename, rdf_session_short,
#           rdf_parse_phase_scope.
# Sourced by /r-* commands and the pre-commit hook. Idempotent.

# rdf_uuidv7 — emit a UUIDv7 string to stdout
rdf_uuidv7() {
    local ts_ms hex_ts hex_rand variant_byte
    ts_ms=$(($(command date +%s%N) / 1000000))
    printf -v hex_ts '%012x' "$ts_ms"
    hex_rand=$(command od -An -N10 -tx1 /dev/urandom | command tr -d ' \n')
    variant_byte=$(printf '%x' $((0x8 | (0x${hex_rand:3:1} & 0x3))))
    printf '%s-%s-7%s-%s%s-%s\n' \
        "${hex_ts:0:8}" \
        "${hex_ts:8:4}" \
        "${hex_rand:0:3}" \
        "$variant_byte" "${hex_rand:4:3}" \
        "${hex_rand:7:12}"
}

# rdf_session_init — set RDF_SESSION_ID if unset; export
rdf_session_init() {
    if [[ -z "${RDF_SESSION_ID:-}" ]]; then
        RDF_SESSION_ID="$(rdf_uuidv7)"
        export RDF_SESSION_ID
    fi
}

# rdf_scoped_filename path — emit session-suffixed form
rdf_scoped_filename() {
    local path="$1" dir base ext
    rdf_session_init
    dir="$(command dirname "$path")"
    base="$(command basename "$path")"
    if [[ "$base" == *.* ]]; then
        ext=".${base##*.}"
        base="${base%.*}"
    else
        ext=""
    fi
    printf '%s/%s-%s%s\n' "$dir" "$base" "$RDF_SESSION_ID" "$ext"
}

# rdf_session_short — last 12 hex chars of RDF_SESSION_ID
rdf_session_short() {
    rdf_session_init
    printf '%s\n' "${RDF_SESSION_ID##*-}"
}

# rdf_parse_phase_scope plan_path phase_n — emit shell vars to stdout
# Outputs four lines:
#   ALLOWED_REGEX=<pipe-separated path regex>
#   FLEX_REGEX=<pipe-separated Tests-may-touch glob expansion or empty>
#   FLEX_FILE_CEILING=3
#   FLEX_LINE_CEILING=30
# Caller evals to import.
rdf_parse_phase_scope() {
    local plan="$1" n="$2"
    local in_phase=0 files="" flex=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^"### Phase ${n}:" ]]; then
            in_phase=1; continue
        fi
        if [[ "$in_phase" -eq 1 && "$line" =~ ^"### Phase " ]]; then
            break   # next phase reached
        fi
        if [[ "$in_phase" -eq 1 ]]; then
            # Match Files entries: - Create: `path`  /  - Modify: `path`  /  - Delete: `path`
            if [[ "$line" =~ ^-\ (Create|Modify|Delete):\ \`([^\`]+)\` ]]; then
                files="${files:+$files|}${BASH_REMATCH[2]}"
            fi
            # Match Tests-may-touch field: **Tests-may-touch:** path1, path2
            if [[ "$line" =~ ^\*\*Tests-may-touch:\*\*[[:space:]]*(.+)$ ]]; then
                flex="${BASH_REMATCH[1]}"
                flex="${flex// /}"           # strip spaces
                flex="${flex//,/|}"          # commas to pipes
            fi
        fi
    done < "$plan"
    # Escape ALL regex metacharacters except glob *, which we handle next.
    # Order matters: backslash must be first.
    _esc() {
        local s="$1"
        s="${s//\\/\\\\}"
        s="${s//./\\.}"
        s="${s//+/\\+}"
        s="${s//\?/\\?}"
        s="${s//(/\\(}"
        s="${s//)/\\)}"
        s="${s//[/\\[}"
        s="${s//]/\\]}"
        s="${s//\{/\\\{}"
        s="${s//\}/\\\}}"
        s="${s//^/\\^}"
        s="${s//\$/\\\$}"
        # Pipe is meaningful — preserved as alternation when joining
        printf '%s' "$s"
    }
    files="$(_esc "$files")"
    flex="$(_esc "$flex")"
    flex="${flex//\*/[^/]*}"    # glob * → regex [^/]*
    printf 'ALLOWED_REGEX=%s\n' "$files"
    printf 'FLEX_REGEX=%s\n' "$flex"
    printf 'FLEX_FILE_CEILING=3\n'
    printf 'FLEX_LINE_CEILING=30\n'
}
