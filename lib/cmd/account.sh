#!/usr/bin/env bash
# lib/cmd/account.sh — rdf account subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

# Registered dirs are never re-derived: the macOS keychain entry is keyed to the exact path string.
_ACCOUNT_HOME="${HOME%/}"
_ACCOUNT_REGISTRY="${_ACCOUNT_HOME}/.rdf/accounts"
# rdf_launch (lib/cmd/shell.sh) reads this path directly so a launch costs no rdf call.
_ACCOUNT_DEFAULT="${_ACCOUNT_REGISTRY}.default"
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
  default <name>|-       Account launchers use without @name or cuse; '-' clears it
  primary <name> [--dry-run]
                         Move <name>'s login into ~/.claude and the current primary's
                         login to ~/.claude-<old>; quit every Claude Code session first
  dir <name>             Print the account's CLAUDE_CONFIG_DIR (empty for primary)

Examples:
  rdf account add work --primary
  rdf account add personal
  cs @personal           # first launch asks you to log in
  rdf account default personal
  rdf account primary personal --dry-run
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
    local entries name dir mark shared active_dir default
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
    default="$(_account_default_name)"
    [[ -z "$default" ]] || printf 'default: %s (launches without @name or cuse)\n' "$default"
}

_account_remove() {
    local name="${1:-}" dir tmp
    [[ -n "$name" ]] || rdf_die "remove requires <name> — run 'rdf account help'"
    dir="$(_account_lookup "$name")" || _account_unknown "$name"
    tmp="$(command mktemp "${_ACCOUNT_REGISTRY}.XXXXXX")"
    command awk -F'\t' -v n="$name" '$1 != n' "$_ACCOUNT_REGISTRY" > "$tmp"
    command mv "$tmp" "$_ACCOUNT_REGISTRY"
    rdf_log "unregistered ${name}; config dir kept: $(_account_display "$dir")"
    [[ "$(_account_default_name)" != "$name" ]] || _account_default_clear
}

_account_default_name() {
    [[ -f "$_ACCOUNT_DEFAULT" ]] || return 0
    command head -n 1 "$_ACCOUNT_DEFAULT"
}

_account_default_clear() {
    command rm -f "$_ACCOUNT_DEFAULT"
    rdf_log "default cleared; launches without @name or cuse leave the environment as it is"
}

_account_default() {
    local name="${1:-}"
    [[ -n "$name" ]] || rdf_die "default requires <name>, or - to clear — run 'rdf account help'"
    if [[ "$name" == "-" ]]; then
        _account_default_clear
        return 0
    fi
    _account_lookup "$name" >/dev/null || _account_unknown "$name"
    printf '%s\n' "$name" > "$_ACCOUNT_DEFAULT"
    rdf_log "default: ${name} (launches without @name or cuse)"
}

_account_is_shared() {
    local entry
    for entry in "${_ACCOUNT_SHARED[@]}"; do
        [[ "$entry" != "$1" ]] || return 0
    done
    return 1
}

# _account_dir_entries DIR — every entry name in DIR, dotfiles included
_account_dir_entries() {
    local path
    for path in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        if [[ -e "$path" || -L "$path" ]]; then
            printf '%s\n' "${path##*/}"
        fi
    done
}

_ACCOUNT_PLAN=()
_ACCOUNT_MOVED=()

# _account_try CMD... — subshell: under set -e, bash 3.2 exits on a failing 'command' even inside || or if
_account_try() { ( "$@" ); }

# _account_live_records DIR... — "pid source" from session files and daemon rosters
_account_live_records() {
    local dir file pid
    for dir in "$@"; do
        for file in "$dir"/sessions/*.json; do
            [[ -f "$file" ]] || continue
            pid="${file##*/}"
            printf '%s %s\n' "${pid%.json}" "$file"
        done
        file="${dir}/daemon/roster.json"
        [[ -f "$file" ]] || continue
        # shellcheck disable=SC2016
        _account_try command jq -r --arg f "$file" '.. | objects | to_entries[]
            | select(.key == "pid" or .key == "supervisorPid") | .value | numbers | "\(.) \($f)"' \
            "$file" 2>/dev/null || true  # unreadable roster: the process scan still applies
    done
}

# _account_live DIR... — "pid N (source)" per running Claude Code process that may rewrite files being moved
_account_live() {
    local pid source comm argv0 exe
    {
        while read -r pid source; do
            case "$pid" in ''|*[!0-9]*) continue ;; esac
            if kill -0 "$pid" 2>/dev/null; then  # dead or foreign pid: stale record
                printf 'pid %s (%s)\n' "$pid" "$source"
            fi
        done < <(_account_live_records "$@")
        # Spawns via the binary's real path get the version as comm, e.g. claude/versions/2.1.309
        while read -r pid comm argv0 _; do
            exe="$(command readlink "/proc/${pid}/exe" 2>/dev/null)" || exe=""  # no /proc entry: comm and argv0 still apply
            if [[ "$comm" == claude || "${argv0##*/}" == claude || "$argv0" == */claude/versions/* \
                || "${exe##*/}" == claude || "$exe" == */claude/versions/* ]]; then
                printf 'pid %s (claude process)\n' "$pid"
            fi
        done < <(command ps -U "$(command id -u)" -o pid= -o comm= -o args= 2>/dev/null)  # no ps: the records above still apply
    } | command awk '!seen[$2]++'
}

# _account_plan_add SRC DST — queue a move; a moved symlink would dangle or loop, so refuse it
_account_plan_add() {
    [[ ! -L "$1" ]] || rdf_die "$1 is a symlink; replace it with what it points to, or move it by hand, then retry"
    _ACCOUNT_PLAN+=("$1" "$2")
}

# _account_mv SRC DST — rename, recorded for _account_unmove; never replaces DST
_account_mv() {
    if [[ -e "$2" || -L "$2" ]]; then
        rdf_warn "not replacing $2"
        return 1
    fi
    _account_try command mv "$1" "$2" || return 1
    _ACCOUNT_MOVED+=("$1" "$2")
}

# _account_unmove — reverse recorded renames, newest first; 1 if any could not be restored
_account_unmove() {
    local i=$(( ${#_ACCOUNT_MOVED[@]} - 2 )) rc=0
    while (( i >= 0 )); do
        if [[ -e "${_ACCOUNT_MOVED[i]}" || -L "${_ACCOUNT_MOVED[i]}" ]]; then
            rdf_warn "could not restore ${_ACCOUNT_MOVED[i]}: it was recreated; the original is at ${_ACCOUNT_MOVED[i+1]}"
            rc=1
        elif ! _account_try command mv "${_ACCOUNT_MOVED[i+1]}" "${_ACCOUNT_MOVED[i]}"; then
            rdf_warn "could not restore ${_ACCOUNT_MOVED[i]} from ${_ACCOUNT_MOVED[i+1]}"
            rc=1
        fi
        i=$(( i - 2 ))
    done
    _ACCOUNT_MOVED=()
    return "$rc"
}

# _account_swap_abort NEWDIR MSG — undo the swap so far and exit 1
_account_swap_abort() {
    if _account_unmove; then
        _account_try command rmdir "$1" || rdf_warn "kept $1"
        rdf_die "$2; every move was undone"
    fi
    rdf_die "$2; some moves could not be undone (see warnings), and the registry is unchanged"
}

# jq 1.5 has no walk; rewrite string values that start with $from
# shellcheck disable=SC2016
_ACCOUNT_REHOME_JQ='def rehome: if type == "object" then map_values(rehome)
    elif type == "array" then map(rehome)
    elif type == "string" and startswith($from) then $to + .[($from | length):]
    else . end;
rehome'

# _account_rehome_plugins DIR FROM TO — plugin metadata stores absolute config-dir paths
_account_rehome_plugins() {
    local file tmp
    for file in "$1"/plugins/*.json; do
        [[ -f "$file" ]] || continue
        _account_try command grep -qF "$2/" "$file" || continue
        tmp="$(command mktemp "${file}.XXXXXX")" || continue
        # writing through the existing file keeps its mode and owner
        if _account_try command jq --arg from "$2/" --arg to "$3/" "$_ACCOUNT_REHOME_JQ" "$file" > "$tmp" \
            && _account_try command cat "$tmp" > "$file"; then
            command rm -f "$tmp"
            continue
        fi
        command rm -f "$tmp"
        rdf_warn "could not rewrite paths in ${file}; reinstall its plugins if they fail to load"
    done
}

_account_primary() {
    local name="" dry=0 arg target old new_dir entry link live tmp i
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry=1 ;;
            -*) rdf_die "unknown option: ${arg} — run 'rdf account help'" ;;
            *)  [[ -z "$name" ]] || rdf_die "unexpected argument: ${arg}"
                name="$arg" ;;
        esac
    done
    [[ -n "$name" ]] || rdf_die "primary requires <name> — run 'rdf account help'"
    target="$(_account_lookup "$name")" || _account_unknown "$name"
    [[ "$target" != "$_ACCOUNT_PRIMARY_MARK" ]] || rdf_die "${name} is already the primary account"
    old="$(_account_name_for_dir "$_ACCOUNT_PRIMARY_MARK")" \
        || rdf_die "no primary account registered — run 'rdf account add <name> --primary'"
    [[ "$old" =~ $_ACCOUNT_NAME_RE ]] || rdf_die "invalid account name in ${_ACCOUNT_REGISTRY}: ${old}"
    [[ "${target%/}" != "$_ACCOUNT_PRIMARY_DIR" ]] || rdf_die "${name} is registered at ${_ACCOUNT_PRIMARY_DIR}; fix ${_ACCOUNT_REGISTRY} first"
    [[ "$(command uname -s)" != Darwin ]] \
        || rdf_die "not supported on macOS: each login is a keychain entry keyed to its config dir path"
    rdf_require_bin jq
    [[ -d "$target" ]] || rdf_die "${name}: config dir missing: ${target}"
    [[ -f "${target}/.credentials.json" ]] \
        || rdf_die "${name} is not logged in (no ${target}/.credentials.json) — log in with 'c @${name}' first"
    [[ -d "$_ACCOUNT_PRIMARY_DIR" ]] || rdf_die "${_ACCOUNT_PRIMARY_DIR} not found"
    new_dir="${_ACCOUNT_HOME}/.claude-${old}"
    [[ ! -e "$new_dir" && ! -L "$new_dir" ]] || rdf_die "${new_dir} already exists — move it aside first"

    _ACCOUNT_PLAN=()
    while IFS= read -r entry; do
        [[ "$entry" != .claude.json ]] || continue
        _account_is_shared "$entry" || _account_plan_add "${_ACCOUNT_PRIMARY_DIR}/${entry}" "${new_dir}/${entry}"
    done < <(_account_dir_entries "$_ACCOUNT_PRIMARY_DIR")
    if [[ -e "${_ACCOUNT_HOME}/.claude.json" || -L "${_ACCOUNT_HOME}/.claude.json" ]]; then
        _account_plan_add "${_ACCOUNT_HOME}/.claude.json" "${new_dir}/.claude.json"
    fi
    while IFS= read -r entry; do
        [[ "$entry" != .claude.json ]] || continue
        if _account_is_shared "$entry"; then
            link=""
            [[ ! -L "${target}/${entry}" ]] || link="$(command readlink "${target}/${entry}")"
            [[ "$link" != "${_ACCOUNT_PRIMARY_DIR}/${entry}" ]] || continue
            if [[ -e "${_ACCOUNT_PRIMARY_DIR}/${entry}" || -L "${_ACCOUNT_PRIMARY_DIR}/${entry}" ]]; then
                rdf_die "${target}/${entry} is not a link to ${_ACCOUNT_PRIMARY_DIR}/${entry} — merge it in and remove it first"
            fi
        fi
        _account_plan_add "${target}/${entry}" "${_ACCOUNT_PRIMARY_DIR}/${entry}"
    done < <(_account_dir_entries "$target")
    if [[ -e "${target}/.claude.json" || -L "${target}/.claude.json" ]]; then
        _account_plan_add "${target}/.claude.json" "${_ACCOUNT_HOME}/.claude.json"
    fi
    if [[ -e "${_ACCOUNT_PRIMARY_DIR}/.claude.json" ]]; then
        rdf_warn "left in place: ${_ACCOUNT_PRIMARY_DIR}/.claude.json (Claude Code reads ~/.claude.json; delete it if it holds ${old}'s login)"
    fi

    live="$(_account_live "$_ACCOUNT_PRIMARY_DIR" "$target")"
    if [[ -n "$live" ]]; then
        while IFS= read -r entry; do
            rdf_warn "running: ${entry}"
        done <<< "$live"
        [[ "$dry" -eq 1 ]] || rdf_die "quit every Claude Code session and its daemon first; they rewrite these files while they run"
    fi

    rdf_log "primary ${name}: $(_account_display "$target") -> ~/.claude; ${old}: ~/.claude -> $(_account_display "$new_dir")"
    if [[ "$dry" -eq 1 ]]; then
        i=0
        while (( i < ${#_ACCOUNT_PLAN[@]} )); do
            rdf_log "  move $(_account_display "${_ACCOUNT_PLAN[i]}") -> $(_account_display "${_ACCOUNT_PLAN[i+1]}")"
            i=$(( i + 2 ))
        done
        rdf_log "  then: registry ${name} -> primary, ${old} -> $(_account_display "$new_dir"); rewrite config-dir paths in both accounts' plugins/*.json; link shared entries into every account"
        rdf_log "dry run: nothing changed"
        return 0
    fi

    _ACCOUNT_MOVED=()
    _account_try command mkdir "$new_dir" || rdf_die "could not create ${new_dir}"
    _account_try command chmod 700 "$new_dir" || _account_swap_abort "$new_dir" "could not chmod ${new_dir}"
    i=0
    while (( i < ${#_ACCOUNT_PLAN[@]} )); do
        _account_mv "${_ACCOUNT_PLAN[i]}" "${_ACCOUNT_PLAN[i+1]}" \
            || _account_swap_abort "$new_dir" "could not move ${_ACCOUNT_PLAN[i]}"
        i=$(( i + 2 ))
    done
    tmp="$(command mktemp "${_ACCOUNT_REGISTRY}.XXXXXX")" \
        || _account_swap_abort "$new_dir" "could not write ${_ACCOUNT_REGISTRY}"
    # shellcheck disable=SC2016
    if ! _account_try command awk -F'\t' -v OFS='\t' -v t="$name" -v o="$old" -v d="$new_dir" \
            -v m="$_ACCOUNT_PRIMARY_MARK" '$1 == t { $2 = m } $1 == o { $2 = d } { print }' \
            "$_ACCOUNT_REGISTRY" > "$tmp" \
        || ! _account_try command mv "$tmp" "$_ACCOUNT_REGISTRY"; then
        command rm -f "$tmp"
        _account_swap_abort "$new_dir" "could not write ${_ACCOUNT_REGISTRY}"
    fi

    _account_rehome_plugins "$_ACCOUNT_PRIMARY_DIR" "$target" "$_ACCOUNT_PRIMARY_DIR"
    _account_rehome_plugins "$new_dir" "$_ACCOUNT_PRIMARY_DIR" "$new_dir"
    for entry in "${_ACCOUNT_SHARED[@]}"; do
        link="${target}/${entry}"
        if [[ -L "$link" && "$(command readlink "$link")" == "${_ACCOUNT_PRIMARY_DIR}/${entry}" ]]; then
            _account_try command rm -f "$link" || rdf_warn "could not remove ${link}"
        fi
    done
    _account_try command rmdir "$target" 2>/dev/null || rdf_warn "kept ${target}: not empty after the swap"  # rmdir's own error adds nothing
    _account_try _account_link || rdf_warn "linking stopped early; run 'rdf account link' to finish"
    rdf_log "primary is now ${name}; launch ${old} with 'c @${old}'"
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
        default) shift; _account_default "$@" ;;
        primary) shift; _account_primary "$@" ;;
        dir)    shift; _account_dir "$@" ;;
        help|--help|-h) _account_usage ;;
        "")     rdf_die "missing subcommand — run 'rdf account help'" ;;
        *)      rdf_die "unknown subcommand: $1 — run 'rdf account help'" ;;
    esac
}
