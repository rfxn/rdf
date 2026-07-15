#!/usr/bin/env bash
# lib/rdf_common.sh — Shared functions for RDF CLI
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly
# shellcheck disable=SC2034  # variables consumed by sourcing scripts

[[ -n "${_RDF_COMMON_LOADED:-}" ]] && return 0 2>/dev/null
_RDF_COMMON_LOADED=1

# Paths — set by rdf_init(); RDF_HOME set by caller before sourcing
RDF_VERSION="${RDF_VERSION:-}"
RDF_LIBDIR="${RDF_LIBDIR:-}"
RDF_CANONICAL="${RDF_CANONICAL:-}"
RDF_ADAPTERS="${RDF_ADAPTERS:-}"
RDF_STATE_DIR="${RDF_STATE_DIR:-}"

rdf_init() {
    # Idempotent — skip if already fully initialized
    [[ -n "${RDF_CANONICAL:-}" ]] && return 0

    # RDF_HOME is set by bin/rdf before sourcing us
    # Validate it exists
    if [[ -z "${RDF_HOME:-}" ]]; then
        echo "rdf: fatal: RDF_HOME not set" >&2
        exit 1
    fi
    if [[ ! -d "$RDF_HOME" ]]; then
        echo "rdf: fatal: RDF_HOME not a directory: ${RDF_HOME}" >&2
        exit 1
    fi

    RDF_LIBDIR="${RDF_HOME}/lib"
    RDF_CANONICAL="${RDF_HOME}/canonical"
    RDF_ADAPTERS="${RDF_HOME}/adapters"
    RDF_STATE_DIR="${RDF_HOME}/state"

    # Read version
    if [[ -f "${RDF_HOME}/VERSION" ]]; then
        RDF_VERSION="$(< "${RDF_HOME}/VERSION")"
        RDF_VERSION="${RDF_VERSION%%[[:space:]]}"
    else
        RDF_VERSION="unknown"
    fi
}

# rdf_canonical_path PATH — print an absolute, symlink-resolved path; always returns 0.
# Tries readlink -f, then realpath, then a cd -P + readlink fallback (non-GNU hosts).
# On failure prints a blank line (empty when captured with "$(...)").
rdf_canonical_path() {
    local _p="${1:-}" _t _d
    # BSD readlink -f / realpath still print to stdout on a nonzero exit, so gate on
    # exit status (and non-empty output) before trusting the captured value.
    if _t="$(command readlink -f "$_p" 2>/dev/null)" && [[ -n "$_t" ]]; then
        printf '%s\n' "$_t"; return 0
    fi
    if command -v realpath >/dev/null 2>&1 \
        && _t="$(command realpath "$_p" 2>/dev/null)" && [[ -n "$_t" ]]; then
        printf '%s\n' "$_t"; return 0
    fi
    if [[ -L "$_p" ]]; then
        _t="$(command readlink "$_p" 2>/dev/null)"
        case "$_t" in
            /*) printf '%s\n' "$_t" ;;
            *)  _d="$(cd -P "$(command dirname "$_p")" 2>/dev/null && pwd)" \
                    && printf '%s/%s\n' "$_d" "$_t" || printf '\n' ;;
        esac
        return 0
    fi
    _d="$(cd -P "$(command dirname "$_p")" 2>/dev/null && pwd)" \
        && printf '%s/%s\n' "$_d" "$(command basename "$_p")" || printf '\n'
    return 0
}

# rdf_hash_stdin — emit hex digest of stdin; portable (sha256sum → shasum -a 256 →
# sha1sum). Returns nonzero if no hashing tool exists. macOS ships shasum, not sha256sum.
rdf_hash_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then command sha256sum | command awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then command shasum -a 256 | command awk '{print $1}'
    elif command -v sha1sum >/dev/null 2>&1; then command sha1sum | command awk '{print $1}'
    else return 1
    fi
}

rdf_die() {
    echo "rdf: error: $*" >&2
    exit 1
}

rdf_warn() {
    echo "rdf: warning: $*" >&2
}

rdf_log() {
    echo "rdf: $*" >&2
}

rdf_require_bin() {
    local bin="$1"
    if ! command -v "$bin" >/dev/null 2>&1; then
        rdf_die "required binary not found: $bin"
    fi
}

rdf_require_file() {
    local file="$1"
    local desc="${2:-file}"
    if [[ ! -f "$file" ]]; then
        rdf_die "$desc not found: $file"
    fi
}

rdf_require_dir() {
    local dir="$1"
    local desc="${2:-directory}"
    if [[ ! -d "$dir" ]]; then
        rdf_die "$desc not found: $dir"
    fi
}

# Profile helpers — used by profile.sh and adapter.sh
RDF_PROFILES_DIR=""
RDF_PROFILES_STATE=""

rdf_profile_init() {
    RDF_PROFILES_DIR="${RDF_HOME}/profiles"
    RDF_PROFILES_STATE="${RDF_HOME}/.rdf-profiles"

    # One-time migration: systems-engineering -> shell (RDF 3.x profile rename)
    if [[ -f "$RDF_PROFILES_STATE" ]]; then
        if grep -q '^systems-engineering$' "$RDF_PROFILES_STATE"; then
            local _mig_tmp
            _mig_tmp="$(mktemp "${RDF_PROFILES_STATE}.XXXXXX")"
            sed 's/^systems-engineering$/shell/' "$RDF_PROFILES_STATE" > "$_mig_tmp" && \
                command mv "$_mig_tmp" "$RDF_PROFILES_STATE"
            rdf_log "migrated profile: systems-engineering -> shell"
        fi
    fi
}

# Get list of active profile names (one per line, core always included)
rdf_get_active_profiles() {
    rdf_profile_init
    echo "core"
    if [[ -f "$RDF_PROFILES_STATE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* || "$line" == "core" ]] && continue
            echo "$line"
        done < "$RDF_PROFILES_STATE"
    fi
}
