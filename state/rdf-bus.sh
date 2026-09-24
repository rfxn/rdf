#!/usr/bin/env bash
# state/rdf-bus.sh — Concurrent-session coordination primitives (Wave A)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Provides: rdf_session_init, rdf_scoped_filename, rdf_session_short,
#           rdf_parse_phase_scope, rdf_active_plan_path,
#           rdf_set_active_plan, rdf_clear_active_plan,
#           rdf_set_active_tier, rdf_active_tier, rdf_clear_active_tier,
#           rdf_phase_hook_install, rdf_phase_hook_uninstall.
# Sourced by /r-* commands and the pre-commit hook. Idempotent.

# rdf_uuidv7 — emit a UUIDv7 string to stdout
rdf_uuidv7() {
    local ts_ms hex_ts hex_rand variant_byte _raw
    _raw="${EPOCHREALTIME:+${EPOCHREALTIME//[!0-9]/}}"   # locale-safe: strip . or ,
    if [[ -n "$_raw" && "${#_raw}" -ge 16 ]]; then
        ts_ms=$(( 10#${_raw:0:16} / 1000 ))             # sec+µs → ms (bash 5, 6-dp)
    else
        _raw="$(command date +%s%N 2>/dev/null)"
        if [[ -n "$_raw" && "$_raw" != *[!0-9]* ]]; then
            ts_ms=$(( _raw / 1000000 ))                 # ns → ms (GNU date)
        else
            ts_ms=$(( $(command date +%s) * 1000 + RANDOM % 1000 ))  # date +%s%N not numeric: whole seconds + random sub-ms
        fi
    fi
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

# rdf_session_init — set RDF_SESSION_ID if unset (Claude Code session id, else UUIDv7); export
# Each Bash tool call is a fresh shell, so a minted id would differ per call.
rdf_session_init() {
    if [[ -z "${RDF_SESSION_ID:-}" ]]; then
        case "${CLAUDE_CODE_SESSION_ID:-}" in
            ""|*[!A-Za-z0-9-]*) RDF_SESSION_ID="$(rdf_uuidv7)" ;;
            *) RDF_SESSION_ID="$CLAUDE_CODE_SESSION_ID" ;;
        esac
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

# rdf_active_plan_path [project_root] — resolve active plan path
# Resolution order:
#   1. .rdf/active-plan-${RDF_SESSION_ID}  (session-scoped)
#   2. .rdf/active-plan                    (un-suffixed default)
#   3. PLAN.md                             (legacy fallback)
# Returns 0 with path on stdout if found; 1 with empty stdout otherwise.
rdf_active_plan_path() {
    local root="${1:-$PWD}" pointer plan
    rdf_session_init
    pointer="${root}/.rdf/active-plan-${RDF_SESSION_ID}"
    if [[ -f "$pointer" ]]; then
        plan="$(< "$pointer")"
        plan="${plan%[$'\r\n']}"
        plan="${plan%[$'\r\n']}"
        if [[ -n "$plan" && -f "$plan" ]]; then
            printf '%s\n' "$plan"
            return 0
        fi
    fi
    pointer="${root}/.rdf/active-plan"
    if [[ -f "$pointer" ]]; then
        plan="$(< "$pointer")"
        plan="${plan%[$'\r\n']}"
        plan="${plan%[$'\r\n']}"
        if [[ -n "$plan" && -f "$plan" ]]; then
            printf '%s\n' "$plan"
            return 0
        fi
    fi
    if [[ -f "${root}/PLAN.md" ]]; then  # legacy fallback
        printf '%s\n' "${root}/PLAN.md"   # legacy fallback
        return 0
    fi
    return 1
}

# rdf_set_active_plan <plan_path> [project_root] — write pointer
# plan_path may be relative or absolute; absolutized before write.
rdf_set_active_plan() {
    local plan="${1:?rdf_set_active_plan requires plan path}"
    local root="${2:-$PWD}"
    rdf_session_init
    if [[ "$plan" != /* ]]; then
        plan="$(command pwd)/${plan}"
    fi
    if [[ ! -f "$plan" ]]; then
        printf 'rdf_set_active_plan: plan file does not exist: %s\n' "$plan" >&2
        return 1
    fi
    command mkdir -p "${root}/.rdf"
    printf '%s\n' "$plan" > "${root}/.rdf/active-plan-${RDF_SESSION_ID}"
}

# rdf_clear_active_plan [project_root] — remove session pointer (idempotent)
rdf_clear_active_plan() {
    local root="${1:-$PWD}"
    rdf_session_init
    command rm -f "${root}/.rdf/active-plan-${RDF_SESSION_ID}"
}

# rdf_set_active_tier <tier> [project_root] — write session tier pointer
rdf_set_active_tier() {
    local tier="${1:?rdf_set_active_tier requires a tier}"
    local root="${2:-$PWD}"
    case "$tier" in
        full|quick-plan|bugfix) ;;
        *) printf 'rdf_set_active_tier: invalid tier: %s\n' "$tier" >&2; return 1 ;;
    esac
    rdf_session_init
    command mkdir -p "${root}/.rdf"
    printf '%s\n' "$tier" > "${root}/.rdf/active-tier-${RDF_SESSION_ID}"
}

# rdf_active_tier [project_root] — echo the active tier (default: full)
# Precedence (S3): the resolved plan's **Tier:** marker is AUTHORITATIVE and
# reconciles the pre-plan session pointer; else the session pointer (pre-plan
# carrier, used during /r-spec before a plan exists); else "full".
rdf_active_tier() {
    local root="${1:-$PWD}" pointer tier plan marker
    rdf_session_init
    pointer="${root}/.rdf/active-tier-${RDF_SESSION_ID}"
    plan="$(rdf_active_plan_path "$root")" || plan=""     # 1 = no plan yet
    # 1) Plan marker wins once a plan resolves; overwrite the pointer to match.
    if [[ -n "$plan" && -f "$plan" ]]; then
        marker="$(grep -m1 '^\*\*Tier:\*\*' "$plan" 2>/dev/null | sed -E 's/^\*\*Tier:\*\*[[:space:]]*//')"  # no marker → empty
        marker="${marker%%[[:space:]]*}"                  # first token (marker line may carry prose)
        case "$marker" in
            full|quick-plan|bugfix)
                command mkdir -p "${root}/.rdf" 2>/dev/null || true   # reconcile write is best-effort
                printf '%s\n' "$marker" > "$pointer" 2>/dev/null || true   # pointer follows the authoritative marker
                printf '%s\n' "$marker"; return 0 ;;
        esac
    fi
    # 2) Pre-plan phase: the session pointer is the carrier.
    if [[ -f "$pointer" ]]; then
        tier="$(< "$pointer")"; tier="${tier%[$'\r\n']}"; tier="${tier%[$'\r\n']}"
        case "$tier" in full|quick-plan|bugfix) printf '%s\n' "$tier"; return 0 ;; esac
    fi
    # 3) Default.
    printf 'full\n'; return 0
}

# rdf_clear_active_tier [project_root] — remove the session tier pointer (idempotent)
rdf_clear_active_tier() {
    local root="${1:-$PWD}"
    rdf_session_init
    command rm -f "${root}/.rdf/active-tier-${RDF_SESSION_ID}"
}

# _rdf_git_at_least major minor — rc 0 when the installed git is at least major.minor
_rdf_git_at_least() {
    local want_major="$1" want_minor="$2" v major minor
    v="$(git version 2>/dev/null)" || return 1   # no git on PATH
    v="${v#git version }"
    major="${v%%.*}"
    v="${v#*.}"
    minor="${v%%[!0-9]*}"
    case "$major" in ''|*[!0-9]*) return 1 ;; esac
    case "$minor" in ''|*[!0-9]*) return 1 ;; esac
    [[ "$major" -gt "$want_major" ]] && return 0
    [[ "$major" -eq "$want_major" && "$minor" -ge "$want_minor" ]]
}

# _rdf_realdir dir [base] — physical absolute path of dir; a relative dir resolves against base
_rdf_realdir() {
    local dir="$1" base="${2:-.}"
    [[ "$dir" == /* ]] && base="/"
    (CDPATH='' cd -P -- "$base" >/dev/null && CDPATH='' cd -P -- "$dir" >/dev/null && pwd -P)
}

# _rdf_atomic_write dest mode — write stdin to dest through a same-directory temp file, so a concurrent reader never sees a partial file
_rdf_atomic_write() {
    local dest="$1" mode="$2" tmp
    tmp="$(command mktemp "${dest%/*}/.tmp.XXXXXX")" || return 1
    if command cat > "$tmp" && command chmod "$mode" "$tmp" && command mv -f -- "$tmp" "$dest"; then
        return 0
    fi
    command rm -f -- "$tmp"
    return 1
}

# _rdf_passthrough_script — emit the static hook that runs whatever git would run without RDF's include
_rdf_passthrough_script() {
    command cat <<'PASSTHROUGH'
#!/usr/bin/env bash
# RDF phase-branch passthrough — installed by rdf_phase_hook_install (state/rdf-bus.sh)
set -euo pipefail
name="${RDF_HOOK_NAME:-${0##*/}}"
unset RDF_HOOK_NAME
prior=""
while IFS= read -r -d '' _o && IFS= read -r -d '' _v; do
    case "$_o" in *rdf-hooks.inc) continue ;; esac
    prior="$_v"
done < <(git config -z --type=path --show-origin --get-all core.hooksPath 2>/dev/null)  # unset → rc 1, no output
[[ -n "$prior" ]] || prior="$(git rev-parse --git-common-dir)/hooks"
if [[ -d "$prior" ]] && [[ "$(CDPATH='' cd -P -- "$prior" && pwd -P)" == "$(CDPATH='' cd -P -- "${0%/*}" && pwd -P)" ]]; then
    exit 0
fi
[[ -x "${prior}/${name}" ]] || exit 0
if grep -q 'RDF worktree scope enforcement' "${prior}/${name}" 2>/dev/null; then  # unreadable target: run it anyway
    exit 0
fi
exec "${prior}/${name}" "$@"
PASSTHROUGH
}

# rdf_phase_hook_install [dir [hook_src]] — activate the scope-guard pre-commit on rdf/phase-* branches of dir's repo
# rc 0 installed or refreshed; 1 not a repo, not the main worktree toplevel, or no hook source; 2 git < 2.23
rdf_phase_hook_install() {
    local dir="${1:-$PWD}" src="${2:-}" gc gd common gitdir main hdir prior name f o v
    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then   # probe only; reason printed below
        printf 'rdf_phase_hook_install: not a git repository: %s\n' "$dir" >&2
        return 1
    fi
    if ! _rdf_git_at_least 2 23; then
        printf 'rdf_phase_hook_install: git >= 2.23 required (includeIf onbranch)\n' >&2
        return 2
    fi
    gc="$(git -C "$dir" rev-parse --git-common-dir)" || return 1
    common="$(_rdf_realdir "$gc" "$dir")" || return 1
    gd="$(git -C "$dir" rev-parse --absolute-git-dir)" || return 1
    gitdir="$(_rdf_realdir "$gd")" || return 1
    if [[ "$gitdir" == "$common" ]]; then
        if ! main="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$main" ]]; then   # bare repo or inside .git/modules
            printf 'rdf_phase_hook_install: run from the main worktree toplevel (no worktree at %s)\n' "$dir" >&2
            return 1
        fi
    elif [[ "${common##*/}" == ".git" ]]; then
        main="${common%/*}"
    else
        printf 'rdf_phase_hook_install: run from the main worktree toplevel\n' >&2
        return 1
    fi
    [[ -n "$src" ]] || src="${HOME:-}/.rdf/state/git-hooks/pre-commit"
    [[ -f "$src" ]] || src="${main}/state/git-hooks/pre-commit"
    if [[ ! -f "$src" ]]; then
        printf 'rdf_phase_hook_install: pre-commit hook source not found (checked ~/.rdf/state/git-hooks and %s/state/git-hooks)\n' "$main" >&2
        return 1
    fi
    hdir="${common}/rdf-hooks"
    command mkdir -p "$hdir" || return 1
    _rdf_atomic_write "${hdir}/pre-commit" 755 < "$src" || return 1
    printf '%s\n' "$main" | _rdf_atomic_write "${hdir}/.rdf-main-root" 644 || return 1
    _rdf_passthrough_script | _rdf_atomic_write "${hdir}/.rdf-passthrough" 755 || return 1
    for name in applypatch-msg pre-applypatch post-applypatch pre-merge-commit prepare-commit-msg \
        commit-msg post-commit pre-rebase post-checkout post-merge pre-push post-rewrite pre-auto-gc; do
        _rdf_atomic_write "${hdir}/${name}" 755 < "${hdir}/.rdf-passthrough" || return 1
    done
    prior=""
    while IFS= read -r -d '' o && IFS= read -r -d '' v; do
        case "$o" in *rdf-hooks.inc) continue ;; esac
        prior="$v"
    done < <(git -C "$main" config -z --type=path --show-origin --get-all core.hooksPath 2>/dev/null)   # unset → rc 1, no output
    [[ -n "$prior" ]] || prior="${common}/hooks"
    [[ "$prior" == /* ]] || prior="${main}/${prior}"
    if [[ -d "$prior" && "$(_rdf_realdir "$prior")" != "$hdir" ]]; then
        for f in "$prior"/*; do
            [[ -f "$f" && -x "$f" ]] || continue
            name="${f##*/}"
            case "$name" in pre-commit|*.sample) continue ;; esac
            _rdf_atomic_write "${hdir}/${name}" 755 < "${hdir}/.rdf-passthrough" || return 1
        done
    fi
    git config --file "${common}/rdf-hooks.inc" core.hooksPath "$hdir" || return 1
    if [[ "$(git config --file "${common}/config" --get 'includeIf.onbranch:rdf/phase-**.path' 2>/dev/null)" != "rdf-hooks.inc" ]]; then   # unset → empty
        git config --file "${common}/config" 'includeIf.onbranch:rdf/phase-**.path' rdf-hooks.inc || return 1
    fi
    return 0
}

# rdf_phase_hook_uninstall [dir] — remove the phase-branch include and RDF hook files; repeat calls are no-ops
rdf_phase_hook_uninstall() {
    local dir="${1:-$PWD}" gc common
    if ! gc="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)"; then   # reason printed below
        printf 'rdf_phase_hook_uninstall: not a git repository: %s\n' "$dir" >&2
        return 1
    fi
    common="$(_rdf_realdir "$gc" "$dir")" || return 1
    if git config --file "${common}/config" --get 'includeIf.onbranch:rdf/phase-**.path' >/dev/null 2>&1; then   # absent: nothing to remove
        git config --file "${common}/config" --remove-section 'includeIf.onbranch:rdf/phase-**' || return 1
    fi
    command rm -rf -- "${common}/rdf-hooks" "${common}/rdf-hooks.inc"
}
