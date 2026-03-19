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

# Feature flags — environment-based
rdf_feature_enabled() {
    local flag="$1"
    local val
    val="${!flag:-false}"
    [[ "$val" == "true" || "$val" == "1" ]]
}

# Read a JSON value using jq — dies if jq not available
rdf_json_get() {
    local file="$1"
    local query="$2"
    rdf_require_bin jq
    rdf_require_file "$file" "JSON file"
    jq -r "$query" "$file"
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

# Check if a component belongs to any active profile
# Args: $1=component type (agents|commands|scripts), $2=component name
# Returns: 0 if included, 1 if excluded
# v3: all component types are universal — profile.json filtering removed.
#     Agents, commands, and scripts are always included.
rdf_profile_includes() {
    return 0
}
