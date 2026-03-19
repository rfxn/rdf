#!/usr/bin/env bash
# lib/cmd/profile.sh — rdf profile subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_PROFILE_REGISTRY="${RDF_HOME}/profiles/registry.json"
_PROFILE_STATE="${RDF_HOME}/.rdf-profiles"

_profile_usage() {
    cat <<'USAGE'
Usage: rdf profile <subcommand> [args]

Manage active domain profiles.

Subcommands:
  list                   Show all available profiles with deps
  install <name> [...]   Activate profiles + resolve dependencies
  remove <name>          Deactivate profile (warns if dependents active)
  status                 Show active profiles + component counts

Examples:
  rdf profile list
  rdf profile install shell
  rdf profile install shell python
  rdf profile remove frontend
  rdf profile status
USAGE
}

# Read active profiles from state file (one per line)
# Returns: newline-separated profile names on stdout
# Core is always implicitly active
_profile_read_active() {
    local profiles="core"
    if [[ -f "$_PROFILE_STATE" ]]; then
        while IFS= read -r line; do
            # Skip blanks and comments
            [[ -z "$line" || "$line" == \#* ]] && continue
            # Avoid duplicating core
            [[ "$line" == "core" ]] && continue
            profiles="${profiles}"$'\n'"${line}"
        done < "$_PROFILE_STATE"
    fi
    echo "$profiles"
}

# Write active profiles to state file
# Args: newline-separated profile names
_profile_write_active() {
    local profiles="$1"
    {
        echo "# RDF active profiles — managed by 'rdf profile'"
        echo "# Do not edit manually — use 'rdf profile install/remove'"
        echo "core"
        echo "$profiles" | while IFS= read -r p; do
            [[ -z "$p" || "$p" == "core" ]] && continue
            echo "$p"
        done
    } > "$_PROFILE_STATE"
}

# Check if a profile exists in registry
_profile_exists() {
    local name="$1"
    jq -e --arg n "$name" '.profiles[$n]' "$_PROFILE_REGISTRY" > /dev/null 2>&1
}

# Check if a profile is currently active
_profile_is_active() {
    local name="$1"
    local active
    active="$(_profile_read_active)"
    echo "$active" | grep -qx "$name"
}

# Get dependency list for a profile
_profile_get_deps() {
    local name="$1"
    jq -r --arg n "$name" '.profiles[$n].requires // [] | .[]' "$_PROFILE_REGISTRY"
}

# Get profiles that depend on a given profile
_profile_get_dependents() {
    local name="$1"
    jq -r --arg n "$name" '.profiles | to_entries[] | select(.value.requires | index($n)) | .key' "$_PROFILE_REGISTRY"
}

# Subcommand: list
_profile_list() {
    rdf_require_file "$_PROFILE_REGISTRY" "profile registry"
    rdf_require_bin jq

    local active
    active="$(_profile_read_active)"

    echo "Available profiles:"
    echo ""

    jq -r '.profiles | to_entries[] | "\(.key)|\(.value.description)|\(.value.requires | join(", "))|\(.value.summary)"' \
        "$_PROFILE_REGISTRY" | while IFS='|' read -r name desc deps summary; do

        local status_marker=" "
        if echo "$active" | grep -qx "$name"; then
            status_marker="*"
        fi

        echo "  [${status_marker}] ${name}"
        echo "      ${desc}"
        if [[ -n "$deps" ]]; then
            echo "      Requires: ${deps}"
        fi
        echo "      Components: ${summary}"
        echo ""
    done

    echo "  [*] = active"
}

# Subcommand: install
_profile_install() {
    [[ $# -eq 0 ]] && rdf_die "usage: rdf profile install <name> [name...]"

    rdf_require_file "$_PROFILE_REGISTRY" "profile registry"
    rdf_require_bin jq

    local active
    active="$(_profile_read_active)"
    local changed=0

    for name in "$@"; do
        # Validate profile exists
        if ! _profile_exists "$name"; then
            rdf_die "unknown profile: ${name} — run 'rdf profile list' to see available"
        fi

        # Skip if already active
        if echo "$active" | grep -qx "$name"; then
            rdf_log "profile already active: ${name}"
            continue
        fi

        # Resolve dependencies first
        local deps
        deps="$(_profile_get_deps "$name")"
        while IFS= read -r dep; do
            [[ -z "$dep" ]] && continue
            if ! echo "$active" | grep -qx "$dep"; then
                rdf_log "installing dependency: ${dep} (required by ${name})"
                active="${active}"$'\n'"${dep}"
                changed=1
            fi
        done <<< "$deps"

        # Activate the profile
        active="${active}"$'\n'"${name}"
        changed=1
        rdf_log "installed profile: ${name}"
    done

    if [[ $changed -eq 1 ]]; then
        _profile_write_active "$active"
        rdf_log "run 'rdf generate claude-code' to apply changes"
    fi
}

# Subcommand: remove
_profile_remove() {
    [[ $# -eq 0 ]] && rdf_die "usage: rdf profile remove <name>"

    local name="$1"
    rdf_require_file "$_PROFILE_REGISTRY" "profile registry"
    rdf_require_bin jq

    # Cannot remove core
    if [[ "$name" == "core" ]]; then
        rdf_die "cannot remove core profile — it is always required"
    fi

    # Check if removable
    local removable
    removable="$(jq -r --arg n "$name" '.profiles[$n].removable // true' "$_PROFILE_REGISTRY")"
    if [[ "$removable" == "false" ]]; then
        rdf_die "profile ${name} is not removable"
    fi

    # Check if active
    if ! _profile_is_active "$name"; then
        rdf_log "profile not active: ${name}"
        return 0
    fi

    # Check for active dependents
    local dependents
    dependents="$(_profile_get_dependents "$name")"
    while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        if _profile_is_active "$dep"; then
            rdf_die "cannot remove ${name} — active profile '${dep}' depends on it. Remove ${dep} first."
        fi
    done <<< "$dependents"

    # Remove from active list
    local active
    active="$(_profile_read_active)"
    active="$(echo "$active" | grep -vx "$name")"
    _profile_write_active "$active"
    rdf_log "removed profile: ${name}"
    rdf_log "run 'rdf generate claude-code' to apply changes"
}

# Subcommand: status
_profile_status() {
    rdf_require_file "$_PROFILE_REGISTRY" "profile registry"
    rdf_require_bin jq

    local active
    active="$(_profile_read_active)"

    echo "Active profiles:"
    echo ""

    local total_gov=0

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        local gov_file="${RDF_HOME}/profiles/${name}/governance-template.md"
        local gov_status="missing"
        if [[ -f "$gov_file" ]]; then
            gov_status="present"
            total_gov=$((total_gov + 1))
        fi

        local desc
        desc="$(jq -r --arg n "$name" '.profiles[$n].description // "no description"' "$_PROFILE_REGISTRY")"
        echo "  ${name}: governance-template ${gov_status}"
        echo "    ${desc}"
    done <<< "$active"

    echo ""
    echo "Governance templates: ${total_gov}"
    echo "Agents: 6 universal (all profiles)"
    echo "Commands: 23 (all profiles)"
}

cmd_profile() {
    case "${1:-}" in
        list)    shift; _profile_list "$@" ;;
        install) shift; _profile_install "$@" ;;
        remove)  shift; _profile_remove "$@" ;;
        status)  shift; _profile_status "$@" ;;
        help|--help|-h) _profile_usage ;;
        "")      rdf_die "missing subcommand — run 'rdf profile help'" ;;
        *)       rdf_die "unknown subcommand: $1 — run 'rdf profile help'" ;;
    esac
}
