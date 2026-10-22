#!/usr/bin/env bash
# lib/cmd/account.sh — rdf account subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

# Registered dirs are never re-derived: the macOS keychain entry is keyed to the exact path string.
_ACCOUNT_HOME="${HOME%/}"
_ACCOUNT_REGISTRY="${_ACCOUNT_HOME}/.rdf/accounts"
_ACCOUNT_PRIMARY_DIR="${_ACCOUNT_HOME}/.claude"
# The primary row stores a marker, not a path: it always launches with CLAUDE_CONFIG_DIR unset.
_ACCOUNT_PRIMARY_MARK="@primary"
_ACCOUNT_NAME_RE='^[a-z0-9][a-z0-9_-]{0,31}$'
# Login, .claude.json, org remote-settings/policy-limits and plugins stay per account.
_ACCOUNT_SHARED=(projects history.jsonl paste-cache file-history tasks todos plans CLAUDE.md
    settings.json keybindings.json skills agents commands rules output-styles scripts governance
    reference)

_account_usage() {
    cat <<'USAGE'
Usage: rdf account <subcommand> [args]

Run Claude Code on several accounts that share projects, memory, history and
config with ~/.claude. Each extra account keeps its own login in
~/.claude-<name>. Launch with 'cs @<name>' after: eval "$(rdf shell init)"

Subcommands:
  add <name> --primary   Name the account already logged in to ~/.claude
  add <name>             Create ~/.claude-<name> linked to ~/.claude's shared state
  list                   Show accounts, logins and shared-link health (* = active)
  link [<name>]          Re-link shared state for one or all accounts
  remove <name>          Unregister an account (its config dir and login are kept)
  dir <name>             Print the account's CLAUDE_CONFIG_DIR (empty for primary)

Examples:
  rdf account add work --primary
  rdf account add personal
  cs @personal           # first launch asks you to log in
USAGE
}

# _account_entries — valid registry rows as name<TAB>dir; tolerates a missing final newline
_account_entries() {
    [[ -f "$_ACCOUNT_REGISTRY" ]] || return 0
    local name dir
    while IFS=$'\t' read -r name dir || [[ -n "$name" ]]; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        case "$dir" in
            *$'\t'*) rdf_warn "skipping malformed row in ${_ACCOUNT_REGISTRY}: ${name}" ;;
            "$_ACCOUNT_PRIMARY_MARK"|/*) printf '%s\t%s\n' "$name" "$dir" ;;
            *) rdf_warn "skipping malformed row in ${_ACCOUNT_REGISTRY}: ${name}" ;;
        esac
    done < "$_ACCOUNT_REGISTRY"
}

# _account_lookup NAME — print NAME's dir (or the primary marker); 1 if unregistered
_account_lookup() {
    local name dir
    while IFS=$'\t' read -r name dir; do
        if [[ "$name" == "$1" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done < <(_account_entries)
    return 1
}

# _account_name_for_dir DIR — print the account registered at DIR (or the marker); 1 if none
_account_name_for_dir() {
    local name dir
    while IFS=$'\t' read -r name dir; do
        if [[ "$dir" == "${1%/}" ]]; then
            printf '%s\n' "$name"
            return 0
        fi
    done < <(_account_entries)
    return 1
}

# _account_unknown NAME — exit 2 (invalid usage); the launchers treat only rc 2 as "not an account"
_account_unknown() {
    local names="" name dir
    while IFS=$'\t' read -r name dir; do
        names="${names:+${names} }${name}"
    done < <(_account_entries)
    echo "rdf: error: unknown account: $1 (registered: ${names:-none})" >&2
    exit 2
}

# _account_display DIR — registry dir as shown to the user
_account_display() {
    case "$1" in
        "$_ACCOUNT_PRIMARY_MARK") printf '~%s\n' "/.claude" ;;
        "$_ACCOUNT_HOME"/*) printf '~%s\n' "${1#"$_ACCOUNT_HOME"}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# _account_link_dir NAME DIR — link each shared entry present in ~/.claude; never replaces a path
_account_link_dir() {
    local name="$1" dir="$2" entry src dst cur linked=0 present=0 kept=0
    if [[ ! -d "$dir" ]]; then
        rdf_warn "${name}: config dir missing: ${dir}"
        return 0
    fi
    for entry in "${_ACCOUNT_SHARED[@]}"; do
        src="${_ACCOUNT_PRIMARY_DIR}/${entry}"
        dst="${dir}/${entry}"
        [[ -e "$src" ]] || continue
        present=$((present + 1))
        if [[ -L "$dst" ]]; then
            cur="$(command readlink "$dst")"
            if [[ "$cur" != "$src" ]]; then
                rdf_warn "${name}: kept ${dst} (links to ${cur}, not ${src})"
                kept=$((kept + 1))
            fi
        elif [[ -e "$dst" ]]; then
            rdf_warn "${name}: kept ${dst} (own copy; merge it into ${src} and remove it to share)"
            kept=$((kept + 1))
        else
            command ln -sn "$src" "$dst"
            linked=$((linked + 1))
        fi
    done
    rdf_log "${name}: $((present - kept))/${present} shared entries linked (${linked} new, ${kept} kept)"
}

# _account_linked_count DIR — "linked/present" for list
_account_linked_count() {
    local dir="$1" entry src ok=0 present=0
    for entry in "${_ACCOUNT_SHARED[@]}"; do
        src="${_ACCOUNT_PRIMARY_DIR}/${entry}"
        [[ -e "$src" ]] || continue
        present=$((present + 1))
        if [[ -L "${dir}/${entry}" && "$(command readlink "${dir}/${entry}")" == "$src" ]]; then
            ok=$((ok + 1))
        fi
    done
    printf '%s/%s\n' "$ok" "$present"
}

# _account_login DIR — "email (org)" from the account's .claude.json, or "not logged in"
_account_login() {
    local conf="${1}/.claude.json" login=""
    [[ "$1" != "$_ACCOUNT_PRIMARY_MARK" ]] || conf="${_ACCOUNT_HOME}/.claude.json"
    if [[ -f "$conf" ]]; then
        login="$(jq -r '.oauthAccount // empty
            | .emailAddress + (if .organizationName then " (" + .organizationName + ")" else "" end)' \
            "$conf" 2>/dev/null)" || login=""  # unreadable config reads as not logged in
    fi
    printf '%s\n' "${login:-not logged in}"
}

_account_add() {
    local name="" primary=0 dir existing arg
    for arg in "$@"; do
        case "$arg" in
            --primary) primary=1 ;;
            -*) rdf_die "unknown option: ${arg} — run 'rdf account help'" ;;
            *)  [[ -z "$name" ]] || rdf_die "unexpected argument: ${arg}"
                name="$arg" ;;
        esac
    done
    [[ -n "$name" ]] || rdf_die "add requires <name> — run 'rdf account help'"
    [[ "$name" =~ $_ACCOUNT_NAME_RE ]] || rdf_die "invalid account name: ${name} (a-z, 0-9, _ and -; 32 max)"
    [[ "$name" != agent-* ]] || rdf_die "invalid account name: ${name} (@agent-* mentions a Claude Code subagent)"
    if _account_lookup "$name" >/dev/null; then
        rdf_die "account already registered: ${name}"
    fi

    if [[ "$primary" -eq 1 ]]; then
        [[ -d "$_ACCOUNT_PRIMARY_DIR" ]] || rdf_die "${_ACCOUNT_PRIMARY_DIR} not found — run claude once and log in first"
        if existing="$(_account_name_for_dir "$_ACCOUNT_PRIMARY_MARK")"; then
            rdf_die "${_ACCOUNT_PRIMARY_DIR} is already registered as: ${existing}"
        fi
        dir="$_ACCOUNT_PRIMARY_MARK"
    else
        dir="${_ACCOUNT_HOME}/.claude-${name}"
        command mkdir -p "$dir"
        command chmod 700 "$dir"
        _account_link_dir "$name" "$dir"
    fi

    command mkdir -p "$(command dirname "$_ACCOUNT_REGISTRY")"
    if [[ ! -s "$_ACCOUNT_REGISTRY" ]]; then
        printf '%s\n' "# RDF Claude Code accounts — managed by 'rdf account'" > "$_ACCOUNT_REGISTRY"
    elif [[ -n "$(command tail -c 1 "$_ACCOUNT_REGISTRY")" ]]; then
        printf '\n' >> "$_ACCOUNT_REGISTRY"
    fi
    printf '%s\t%s\n' "$name" "$dir" >> "$_ACCOUNT_REGISTRY"
    rdf_log "registered ${name}: $(_account_display "$dir")"
    if [[ "$primary" -eq 0 ]]; then
        rdf_log "log in on first launch: c @${name}"
    fi
}

_account_link() {
    local name dir
    if [[ -n "${1:-}" ]]; then
        dir="$(_account_lookup "$1")" || _account_unknown "$1"
        [[ "$dir" != "$_ACCOUNT_PRIMARY_MARK" ]] || rdf_die "$1 is the primary account; nothing to link"
        _account_link_dir "$1" "$dir"
        return 0
    fi
    while IFS=$'\t' read -r name dir; do
        [[ "$dir" == "$_ACCOUNT_PRIMARY_MARK" ]] && continue
        _account_link_dir "$name" "$dir"
    done < <(_account_entries)
}

_account_list() {
    rdf_require_bin jq
    local entries name dir mark shared active_dir
    entries="$(_account_entries)"
    if [[ -z "$entries" ]]; then
        echo "No accounts registered. Start with: rdf account add <name> --primary"
        return 0
    fi
    active_dir="${CLAUDE_CONFIG_DIR:-$_ACCOUNT_PRIMARY_MARK}"
    printf '  %-14s %-24s %-12s %s\n' "ACCOUNT" "DIR" "SHARED" "LOGIN"
    while IFS=$'\t' read -r name dir; do
        mark=" "
        if [[ -n "${RDF_CLAUDE_ACCOUNT:-}" ]]; then
            [[ "$name" != "$RDF_CLAUDE_ACCOUNT" ]] || mark="*"
        elif [[ "$dir" == "${active_dir%/}" ]]; then
            mark="*"
        fi
        if [[ "$dir" == "$_ACCOUNT_PRIMARY_MARK" ]]; then
            shared="primary"
        else
            shared="$(_account_linked_count "$dir")"
        fi
        printf '%s %-14s %-24s %-12s %s\n' "$mark" "$name" "$(_account_display "$dir")" "$shared" "$(_account_login "$dir")"
    done <<< "$entries"
}

_account_remove() {
    local name="${1:-}" dir tmp
    [[ -n "$name" ]] || rdf_die "remove requires <name> — run 'rdf account help'"
    dir="$(_account_lookup "$name")" || _account_unknown "$name"
    tmp="$(command mktemp "${_ACCOUNT_REGISTRY}.XXXXXX")"
    command awk -F'\t' -v n="$name" '$1 != n' "$_ACCOUNT_REGISTRY" > "$tmp"
    command mv "$tmp" "$_ACCOUNT_REGISTRY"
    rdf_log "unregistered ${name}; config dir kept: $(_account_display "$dir")"
}

_account_dir() {
    local dir
    [[ -n "${1:-}" ]] || rdf_die "dir requires <name> — run 'rdf account help'"
    dir="$(_account_lookup "$1")" || _account_unknown "$1"
    if [[ "$dir" == "$_ACCOUNT_PRIMARY_MARK" ]]; then
        printf '\n'
        return 0
    fi
    [[ -d "$dir" ]] || rdf_die "$1: config dir missing: ${dir} — run 'rdf account remove $1' and add it again"
    printf '%s\n' "$dir"
}

cmd_account() {
    case "${1:-}" in
        add)    shift; _account_add "$@" ;;
        list)   shift; _account_list ;;
        link)   shift; _account_link "$@" ;;
        remove) shift; _account_remove "$@" ;;
        dir)    shift; _account_dir "$@" ;;
        help|--help|-h) _account_usage ;;
        "")     rdf_die "missing subcommand — run 'rdf account help'" ;;
        *)      rdf_die "unknown subcommand: $1 — run 'rdf account help'" ;;
    esac
}
