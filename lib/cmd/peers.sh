#!/usr/bin/env bash
# lib/cmd/peers.sh: rdf peers subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf; do not execute directly

# shellcheck disable=SC1090,SC1091
source "${RDF_LIBDIR}/cmd/account.sh"

_PEERS_SID_RE='^[A-Za-z0-9_-]+$'
_PEERS_TAIL_BYTES=2097152
_PEERS_ENTRIES=""
_PEERS_ACCTS="[]"
_PEERS_CDIRS=()
_PEERS_SDIRS=()
_PEERS_SOWNER=()
_PEERS_PDIRS=()
_PEERS_ALLPIDS=" "
_PEERS_SEEN=" "
_PEERS_OBJS=""

# One session object from transcript lines on stdin; owner "-" marks a registry dir shared by several config dirs.
# shellcheck disable=SC2016
_PEERS_JQ='def str: if type == "string" then . else "" end;
[inputs | fromjson? // empty | objects] as $recs
| def lastof($t): ([$recs[] | select(.type == $t)] | last) // {};
  lastof("session-owner") as $own
| ([$accts[] | select(.a != "" and .a == ($own.accountUuid | str) and .o == ($own.organizationUuid | str)) | .name]
    | first) as $owner
| [$recs[] | select(.type == "assistant") | .message.content? | arrays | .[] | objects] as $blocks
| {
    name: ($reg.name | str),
    account: ($owner // (if $dirowner != "" and $dirowner != "-" then $dirowner else "?" end)),
    pid: $pid,
    session_id: ($reg.sessionId | str),
    status: ($reg.status | str),
    mode: ([$recs[] | .permissionMode | strings] | last // ""),
    started_at: ($reg.startedAt | if type == "number" then . else null end),
    cwd: ($reg.cwd | str),
    branch: ([$recs[] | .gitBranch | strings | select(. != "")] | last // ""),
    title: (lastof("ai-title").aiTitle | str),
    last_prompt: (lastof("last-prompt").lastPrompt | str),
    self: ($self != "" and ($reg.sessionId | str) == $self),
    last_reply: ([$blocks[] | select(.type == "text") | .text | str | select(. != "")] | last // "" | .[0:300]),
    recent_files: ([$blocks[]
        | select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit" or .name == "NotebookEdit"))
        | (.input.file_path? // .input.notebook_path?) | strings]
        | reverse | reduce .[] as $f ([]; if any(.[]; . == $f) then . else . + [$f] end) | .[0:5])
  }'

# Display helpers; wide is the East Asian Wide/Fullwidth and emoji blocks, two terminal columns each.
# shellcheck disable=SC2016
_PEERS_FMT_JQ='def age: if type == "number" then ((now - . / 1000) | floor | if . < 0 then 0 else . end
        | if . < 60 then "\(.)s" elif . < 3600 then "\(. / 60 | floor)m"
          elif . < 86400 then "\(. / 3600 | floor)h" else "\(. / 86400 | floor)d" end)
    else "" end;
def flat: tostring | gsub("[\\s\u0000-\u001f\u007f-\u009f]+"; " ") | sub("^ "; "") | sub(" $"; "");
def safe: tostring | gsub("[\u0000-\u001f\u007f-\u009f]"; "?");
def project: (split("/") | map(select(. != "")) | last) // "";
def wide: . as $c | any([4352, 4447], [11904, 42191], [44032, 55203], [63744, 64255], [65040, 65049],
    [65072, 65135], [65280, 65376], [65504, 65510], [127744, 128591], [128640, 128767], [129280, 129791],
    [131072, 262141]; $c >= .[0] and $c <= .[1]);
def cw: if wide then 2 else 1 end;
def cols: [explode[] | cw] | add // 0;
def cut($n): reduce explode[] as $c ({w: 0, s: [], full: false};
    if .full then . else ($c | cw) as $k | if .w + $k > $n then .full = true else .w += $k | .s += [$c] end end)
    | .s | implode;
def pad($n): . + (($n - cols) as $k | if $k > 0 then " " * $k else "" end);'

_PEERS_LIST_KEYS='{name, account, pid, session_id, status, mode, started_at, cwd, branch, title, last_prompt, self}'

_peers_usage() {
    cat <<'USAGE'
Usage: rdf peers [<name>] [--here] [--json]

Show the live Claude Code sessions on this machine, on every rdf account, and
what each one is working on. Read-only: it reads Claude Code's session registry
and transcripts and writes nothing.

  <name>   Card for one session (exact name, else a unique prefix): pid, cwd,
           last prompt and reply, recent files, RDF progress files
  --here   Only sessions in this repo (git toplevel, else the current dir)
  --json   JSON array (one object with <name>)

Columns: NAME (* = this session) ACCOUNT STATE MODE AGE PROJECT BRANCH TITLE.
From a Claude Code session, message one with SendMessage to its name.

Exit codes: 0 ok, 1 no live session matches <name>, 2 usage error
USAGE
}

# _peers_usage_error MSG: exit 2 (invalid usage)
_peers_usage_error() {
    echo "rdf: error: $1 (run 'rdf peers help')" >&2
    exit 2
}

# _peers_phys DIR: physical path of an existing directory; 1 when absent
_peers_phys() { ( cd -P "$1" 2>/dev/null && pwd ); }  # missing or unreadable dir: the caller skips it

# _peers_add_cfg NAME DIR: record config DIR (NAME empty: unregistered) and its sessions and projects dirs once per physical path
_peers_add_cfg() {
    local name="$1" dir="$2" phys i=0
    phys="$(_peers_phys "$dir")" || return 0
    while (( i < ${#_PEERS_CDIRS[@]} )); do
        [[ "${_PEERS_CDIRS[i]}" != "$phys" ]] || return 0
        i=$((i + 1))
    done
    _PEERS_CDIRS+=("$phys")
    i=0
    if phys="$(_peers_phys "${dir}/sessions")"; then
        while (( i < ${#_PEERS_SDIRS[@]} )); do
            [[ "${_PEERS_SDIRS[i]}" == "$phys" ]] && break
            i=$((i + 1))
        done
        if (( i == ${#_PEERS_SDIRS[@]} )); then
            _PEERS_SDIRS+=("$phys")
            _PEERS_SOWNER+=("$name")
        elif [[ "${_PEERS_SOWNER[i]}" != "$name" ]]; then
            _PEERS_SOWNER[i]="-"
        fi
    fi
    if phys="$(_peers_phys "${dir}/projects")"; then
        i=0
        while (( i < ${#_PEERS_PDIRS[@]} )); do
            [[ "${_PEERS_PDIRS[i]}" == "$phys" ]] && return 0
            i=$((i + 1))
        done
        _PEERS_PDIRS+=("$phys")
    fi
}

# _peers_accounts_json: [{name, a, o}] from each registered account's .claude.json oauthAccount
_peers_accounts_json() {
    local name dir conf one lines=""
    while IFS=$'\t' read -r name dir; do
        [[ -n "$name" ]] || continue
        conf="${dir}/.claude.json"
        [[ "$dir" != "$_ACCOUNT_PRIMARY_MARK" ]] || conf="${_ACCOUNT_HOME}/.claude.json"
        [[ -f "$conf" ]] || continue
        one="$(jq -c --arg n "$name" \
            '{name: $n, a: (.oauthAccount.accountUuid // ""), o: (.oauthAccount.organizationUuid // "")}' \
            "$conf" 2>/dev/null)" || continue  # unreadable .claude.json: this account is never matched
        lines="${lines}${one}"$'\n'
    done <<< "$_PEERS_ENTRIES"
    printf '%s' "$lines" | jq -sc '.'
}

# _peers_scan: registry and projects dirs of ~/.claude, every registered account and $CLAUDE_CONFIG_DIR
_peers_scan() {
    local name dir primary=""
    _PEERS_ENTRIES="$(_account_entries)"
    while IFS=$'\t' read -r name dir; do
        [[ "$dir" != "$_ACCOUNT_PRIMARY_MARK" ]] || primary="$name"
    done <<< "$_PEERS_ENTRIES"
    _peers_add_cfg "$primary" "$_ACCOUNT_PRIMARY_DIR"
    while IFS=$'\t' read -r name dir; do
        [[ -n "$name" && "$dir" != "$_ACCOUNT_PRIMARY_MARK" ]] || continue
        _peers_add_cfg "$name" "$dir"
    done <<< "$_PEERS_ENTRIES"
    # Added last: a registered dir under any spelling is already recorded and skipped.
    [[ -z "${CLAUDE_CONFIG_DIR:-}" ]] || _peers_add_cfg "" "$CLAUDE_CONFIG_DIR"
    _PEERS_ACCTS="$(_peers_accounts_json)"
}

# _peers_starttime PID: field 22 of /proc/PID/stat, empty without /proc
_peers_starttime() {
    local stat f
    [[ -r "/proc/$1/stat" ]] || return 0
    read -r stat 2>/dev/null < "/proc/$1/stat" || return 0  # exited since kill -0: the caller keeps kill -0's answer
    read -r -a f <<< "${stat##*\)}"
    printf '%s\n' "${f[19]:-}"
}

# _peers_under PATH TOP: 0 when PATH (physical when it exists) is TOP or below it
_peers_under() {
    local p
    [[ "$2" != / ]] || return 0
    p="$(_peers_phys "$1")" || p="${1%/}"
    [[ "$p" == "$2" || "$p" == "$2"/* ]]
}

# _peers_here_root: physical git toplevel of the current dir, else the current dir
_peers_here_root() {
    local top
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""  # outside a work tree, or no git: use the current dir
    [[ -n "$top" ]] || top="$PWD"
    _peers_phys "$top" || printf '%s\n' "$top"
}

# _peers_transcript SID: first projects/*/SID.jsonl across the scanned projects dirs
_peers_transcript() {
    local i=0 f
    [[ "$1" =~ $_PEERS_SID_RE ]] || return 0
    while (( i < ${#_PEERS_PDIRS[@]} )); do
        for f in "${_PEERS_PDIRS[i]}"/*/"$1".jsonl; do
            if [[ -f "$f" ]]; then
                printf '%s\n' "$f"
                return 0
            fi
        done
        i=$((i + 1))
    done
}

# _peers_tail FILE: last 2 MiB of FILE; nothing when FILE is empty or unreadable
_peers_tail() {
    [[ -n "$1" ]] || return 0
    _account_try command tail -c "$_PEERS_TAIL_BYTES" "$1" 2>/dev/null || true  # transcript gone or unreadable: fields stay empty
}

# _peers_mode_fill OBJ FILE: OBJ with mode set to the last top-level permissionMode anywhere in FILE, one streaming pass
_peers_mode_fill() {
    # shellcheck disable=SC2016
    local q='(input | fromjson) as $o | ([inputs | fromjson? | objects | .permissionMode | strings] | last) as $m
        | $o | if $m == null then . else .mode = $m end'
    { printf '%s\n' "$1"; _account_try command grep -aE '"permissionMode"[[:space:]]*:' "$2" 2>/dev/null || true; } | jq -cnR "$q"  # no match, or file gone or unreadable: OBJ unchanged
}

# _peers_collect TOP: append one JSON object per live session to _PEERS_OBJS (TOP non-empty: --here filter)
_peers_collect() {
    local top="$1" i=0 owner file pid probe sid pstart cwd reg start tx obj filled
    while (( i < ${#_PEERS_SDIRS[@]} )); do
        owner="${_PEERS_SOWNER[i]}"
        for file in "${_PEERS_SDIRS[i]}"/*.json; do
            [[ -f "$file" ]] || continue
            pid="${file##*/}"
            pid="${pid%.json}"
            case "$pid" in ''|*[!0-9]*) continue ;; esac
            _PEERS_ALLPIDS="${_PEERS_ALLPIDS}${pid} "
            [[ "$_PEERS_SEEN" != *" ${pid} "* ]] || continue
            kill -0 "$pid" 2>/dev/null || continue  # dead or foreign pid: a stale entry
            # shellcheck disable=SC2016
            probe="$(jq -r 'select(type == "object")
                | [(.sessionId // "" | tostring), (.procStart // "" | tostring), (.cwd // "" | tostring), tojson]
                | join("\u001f")' "$file" 2>/dev/null)" || continue  # torn or unparsable entry: skipped
            [[ -n "$probe" ]] || continue
            IFS=$'\x1f' read -r sid pstart cwd reg <<< "$probe"
            start="$(_peers_starttime "$pid")"
            [[ -z "$start" || -z "$pstart" || "$start" == "$pstart" ]] || continue
            if [[ -n "$top" ]] && ! _peers_under "$cwd" "$top"; then continue; fi
            tx="$(_peers_transcript "$sid")"
            obj="$(_peers_tail "$tx" | jq -cnR --argjson reg "$reg" --argjson pid "$pid" \
                --argjson accts "$_PEERS_ACCTS" --arg dirowner "$owner" \
                --arg self "${CLAUDE_CODE_SESSION_ID:-}" "$_PEERS_JQ" 2>/dev/null)" || continue  # entry that is not an object: skipped
            [[ -n "$obj" ]] || continue
            # Claude Code writes permissionMode on few records; compact output spells "mode":"" only for that field.
            if [[ -n "$tx" && "$obj" == *'"mode":""'* ]] && filled="$(_peers_mode_fill "$obj" "$tx")"; then
                obj="$filled"
            fi
            _PEERS_SEEN="${_PEERS_SEEN}${pid} "
            _PEERS_OBJS="${_PEERS_OBJS}${obj}"$'\n'
        done
        i=$((i + 1))
    done
}

# _peers_sock_dirs: cc-socks dirs to check for orphan sockets, one physical path per line
_peers_sock_dirs() {
    local list uid d phys seen=" "
    if [[ -n "${RDF_PEERS_SOCKDIRS+x}" ]]; then
        list="$RDF_PEERS_SOCKDIRS"
    else
        uid="$(command id -u)"
        list="/run/user/${uid}/cc-socks:/tmp/cc-socks:/tmp/cc-socks-${uid}:/private/tmp/cc-socks:/private/tmp/cc-socks-${uid}"
    fi
    while [[ -n "$list" ]]; do
        d="${list%%:*}"
        if [[ "$list" == *:* ]]; then list="${list#*:}"; else list=""; fi
        [[ -n "$d" ]] || continue
        phys="$(_peers_phys "$d")" || continue
        [[ "$seen" != *" ${phys} "* ]] || continue
        seen="${seen}${phys} "
        printf '%s\n' "$phys"
    done
}

# _peers_orphans: count of live sockets owned by this uid whose pid has no registry entry
_peers_orphans() {
    local n=0 d s pid
    while IFS= read -r d; do
        for s in "$d"/*.sock; do
            [[ -S "$s" && -O "$s" ]] || continue
            pid="${s##*/}"
            pid="${pid%.sock}"
            case "$pid" in ''|*[!0-9]*) continue ;; esac
            [[ "$_PEERS_ALLPIDS" != *" ${pid} "* ]] || continue
            kill -0 "$pid" 2>/dev/null || continue  # socket file left by an exited session
            n=$((n + 1))
        done
    done < <(_peers_sock_dirs)
    printf '%s\n' "$n"
}

# _peers_footer: at most two stderr hints, unshared registries and orphan sockets
_peers_footer() {
    local name dir off="" n
    while IFS=$'\t' read -r name dir; do
        [[ -n "$name" && "$dir" != "$_ACCOUNT_PRIMARY_MARK" && -d "$dir" ]] || continue
        if [[ -L "${dir}/sessions" && "$(command readlink "${dir}/sessions")" == "${_ACCOUNT_PRIMARY_DIR}/sessions" ]]; then
            continue
        fi
        off="${off:+${off}, }${name}"
    done <<< "$_PEERS_ENTRIES"
    [[ -z "$off" ]] || echo "peer messaging across accounts is off for: ${off} (run: rdf account link)" >&2
    n="$(_peers_orphans)"
    [[ "$n" -eq 0 ]] || echo "${n} live Claude Code sockets have no registry entry; Claude Code may have changed its session layout" >&2
}

# _peers_table ROWS: one line per session, title cut to keep lines within 120 terminal columns
_peers_table() {
    printf '%s\n' "$1" | jq -r "${_PEERS_FMT_JQ}"'
        [[" ", "NAME", "ACCOUNT", "STATE", "MODE", "AGE", "PROJECT", "BRANCH", "TITLE"]]
          + [.[] | [(if .self then "*" else " " end)]
              + ([.name, .account, .status, .mode, (.started_at | age), (.cwd | project), .branch, .title] | map(flat))]
        | . as $rows
        | [20, 14, 5, 11, 4, 18, 20] as $cap
        | [range(1; 8) as $i | [$rows[][$i] | cols] | max | if . > $cap[$i - 1] then $cap[$i - 1] else . end] as $w
        | ([120 - 2 - ($w | map(. + 1) | add), 10] | max) as $tw
        | $rows[]
        | .[0] + " " + ([range(1; 8) as $i | .[$i] | cut($w[$i - 1]) | pad($w[$i - 1])] | join(" ")) + " "
          + (.[8] | if cols > $tw then cut($tw - 3) + "..." else . end)
        | sub(" +$"; "")'
}

# _peers_card WANT ROWS JSON: the card for the one session named WANT (exact, else unique prefix)
_peers_card() {
    local want="$1" rows="$2" json="$3" hits count names sid cwd f prog="" obj
    # shellcheck disable=SC2016
    hits="$(printf '%s\n' "$rows" | jq -c --arg n "$want" \
        'map(select(.name == $n)) as $ex | if ($ex | length) > 0 then $ex else map(select(.name | startswith($n))) end')"
    count="$(printf '%s\n' "$hits" | jq 'length')"
    if [[ "$count" -ne 1 ]]; then
        if [[ "$count" -eq 0 ]]; then
            names="$(printf '%s\n' "$rows" | jq -r "${_PEERS_FMT_JQ}"'map(.name | safe) | join(", ")')"
            rdf_die "no live session matches: ${want} (live: ${names:-none})"
        fi
        names="$(printf '%s\n' "$hits" | jq -r "${_PEERS_FMT_JQ}"'map(.name | safe) | join(", ")')"
        rdf_die "${want} matches ${count} sessions: ${names}"
    fi
    obj="$(printf '%s\n' "$hits" | jq -c '.[0]')"
    sid="$(printf '%s\n' "$obj" | jq -r '.session_id')"
    cwd="$(printf '%s\n' "$obj" | jq -r '.cwd')"
    if [[ "$sid" =~ $_PEERS_SID_RE && -n "$cwd" ]]; then
        for f in "$cwd"/.rdf/work-output/*-"$sid".md; do
            if [[ -f "$f" ]]; then prog="${prog}${f}"$'\n'; fi
        done
    fi
    # Bound first: jq evaluates the right side of + before the left, so [inputs] would take the object line.
    # shellcheck disable=SC2016
    obj="$({ printf '%s\n' "$obj"; printf '%s' "$prog"; } \
        | jq -cnR '(input | fromjson) as $o | $o + {rdf_progress: [inputs | select(. != "")]}')"
    if [[ "$json" -eq 1 ]]; then
        printf '%s\n' "$obj" | jq "${_PEERS_LIST_KEYS} + {last_reply, recent_files, rdf_progress}"
        return 0
    fi
    printf '%s\n' "$obj" | jq -r "${_PEERS_FMT_JQ}"'
        "name:         \(.name | safe)\(if .self then " (this session)" else "" end)",
        "account:      \(.account | safe)",
        "pid:          \(.pid)",
        "session:      \(.session_id | safe)",
        "state:        \(.status | safe)",
        "mode:         \(.mode | safe)",
        "started:      \(if .started_at then (.started_at | age) + " ago" else "" end)",
        "cwd:          \(.cwd | safe)",
        "branch:       \(.branch | safe)",
        "title:        \(.title | flat)",
        "last prompt:  \(.last_prompt | flat)",
        "last reply:   \(.last_reply | flat)",
        (if (.recent_files | length) == 0 then "recent files: -" else "recent files:", (.recent_files[] | "  " + safe) end),
        (if (.rdf_progress | length) == 0 then "rdf progress: -" else "rdf progress:", (.rdf_progress[] | "  " + safe) end),
        "message it: SendMessage to \"\(.name | safe)\""'
}

# cmd_peers args: list live Claude Code sessions on every account; read-only
cmd_peers() {
    local name="" here=0 json=0 arg top="" rows
    for arg in "$@"; do
        case "$arg" in
            --here) here=1 ;;
            --json) json=1 ;;
            help|--help|-h) _peers_usage; return 0 ;;
            -*) _peers_usage_error "unknown option: ${arg}" ;;
            *)  [[ -z "$name" ]] || _peers_usage_error "unexpected argument: ${arg}"
                name="$arg" ;;
        esac
    done
    rdf_require_bin jq
    _peers_scan
    [[ "$here" -eq 0 ]] || top="$(_peers_here_root)"
    _peers_collect "$top"
    rows="$(printf '%s' "$_PEERS_OBJS" \
        | jq -sc 'map(.mode |= if . == "bypassPermissions" then "bypass" else . end) | sort_by(-(.started_at // 0))')"
    if [[ -n "$name" ]]; then
        _peers_card "$name" "$rows" "$json"
        return 0
    fi
    if [[ "$json" -eq 1 ]]; then
        printf '%s\n' "$rows" | jq "[.[] | ${_PEERS_LIST_KEYS}]"
        return 0
    fi
    if [[ "$rows" == "[]" ]]; then
        echo "no live Claude Code sessions"
    else
        _peers_table "$rows"
    fi
    _peers_footer
}
