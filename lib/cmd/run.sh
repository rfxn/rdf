#!/usr/bin/env bash
# lib/cmd/run.sh — rdf run / rdf review: launch Claude Code or Codex under an rdf account
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

# shellcheck source=lib/cmd/account.sh
source "${RDF_LIBDIR}/cmd/account.sh"

_run_usage() {
    cat <<'USAGE'
Usage: rdf run <claude|codex> [@account] [-y|--yolo | --root | --sandbox] [tool args...]
       rdf c ...   rdf x ...   (short for rdf run claude, rdf run codex)
       rdf review [@account] [--effort LEVEL] [-m MODEL] [-o FILE] [-C DIR] [--write]
                  [PROMPT... | -f FILE | -]

rdf run launches Claude Code or Codex. Options before the first other argument
are rdf's; the rest go to the tool.
  @account     account for this run; without it, the account set by rdf use
               (RDF_ACCOUNT, or the older RDF_CLAUDE_ACCOUNT), else
               'rdf account default', else the environment as it is.
               Accounts: rdf account help
  -y, --yolo   no permission prompts. claude: --dangerously-skip-permissions
               (Claude Code refuses it as root; see --root). codex:
               --dangerously-bypass-approvals-and-sandbox (also drops its sandbox)
  --root       claude: --yolo plus IS_SANDBOX=1, which tells Claude Code it is
               already sandboxed so it skips permissions as root. It isolates
               nothing; use it only on a host you can afford to lose
  --sandbox    the tool's own OS sandbox, permission checks kept. claude: shell
               commands run sandboxed without prompts (writes: the working dir
               and temp; network: hosts you allow) and cannot ask to leave it;
               file edits in the working dir are auto-accepted; anything else
               asks. Linux needs bubblewrap and socat. codex: --sandbox
               workspace-write --ask-for-approval on-request. Not with --yolo or
               --root, nor with tool flags that would undo it
  --fs         claude: --fork-session (anywhere in the arguments)
  --chrome     claude: passed through; rdf options may follow it

Picking an account for claude sets CLAUDE_CONFIG_DIR (unset for the primary) and
drops inherited credential and provider settings (CLAUDE_CODE_OAUTH_TOKEN,
CLAUDE_CODE_OAUTH_REFRESH_TOKEN, ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN,
ANTHROPIC_PROFILE, ANTHROPIC_BASE_URL, CLAUDE_CODE_USE_BEDROCK,
CLAUDE_CODE_USE_VERTEX, CLAUDE_CODE_USE_FOUNDRY) so that account's login is used.
For codex it sets CODEX_HOME to ~/.codex-<account> when that home exists (rdf
account add/link create it when ~/.codex exists), else unsets it so codex uses
~/.codex, and drops CODEX_API_KEY and CODEX_ACCESS_TOKEN.

rdf review runs 'codex exec' for an account with a read-only sandbox:
  --effort LEVEL   model_reasoning_effort (low, medium, high, xhigh, ...)
  -m MODEL         model (default: the Codex config's)
  -o FILE          write the final message to FILE
  -C DIR           working directory for the run
  --write          workspace-write sandbox instead of read-only
  -f FILE          read the prompt from FILE (via stdin, so no argument-length limit)
  -                read the prompt from stdin
  PROMPT...        the prompt; stdin is closed so codex never waits on it
  --               the rest is the prompt, even if it starts with -

Examples:
  rdf run claude @personal --yolo --resume
  rdf c -y --resume
  rdf x @work
  rdf review --effort high -o /tmp/review.md "Review the diff in HEAD~1..HEAD"
  rdf review -f prompt.md -C ~/src/app > /dev/null &
USAGE
}

_RUN_CLAUDE_SANDBOX='{"sandbox":{"enabled":true,"failIfUnavailable":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":true}}'

# _run_sandbox_guard TOOL ARGS... — refuse tool flags that would undo --sandbox
_run_sandbox_guard() {
    local tool="$1" a
    shift
    for a in "$@"; do
        case "${tool}:${a}" in
            claude:--settings|claude:--settings=*|claude:--permission-mode|claude:--permission-mode=*|\
            claude:--dangerously-skip-permissions|claude:--allow-dangerously-skip-permissions|\
            codex:-s|codex:--sandbox|codex:--sandbox=*|codex:-a|codex:--ask-for-approval|codex:--ask-for-approval=*|\
            codex:--dangerously-bypass-approvals-and-sandbox|codex:--yolo|codex:--full-auto)
                echo "rdf: error: --sandbox sets ${tool}'s permissions itself; drop ${a%%=*} from the arguments" >&2
                exit 2 ;;
        esac
    done
}

# _run_pick ARG — set _RUN_ACCT when ARG is @<registered account>; an unregistered @name that is not a path is an error
_run_pick() {
    local a="$1" name="${1#@}"
    case "$a" in
        @agent-*|@*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;;
        @[abcdefghijklmnopqrstuvwxyz0123456789]*) ;;
        *) return 1 ;;
    esac
    if _account_lookup "$name" >/dev/null; then
        _RUN_ACCT="$name"
        return 0
    fi
    [[ ! -e "$name" ]] || return 1
    _account_unknown "$name"
}

# _run_account — the account when none was picked: rdf use, then the stored default; stale names fail closed
_run_account() {
    [[ -n "$_RUN_ACCT" ]] || _RUN_ACCT="${RDF_ACCOUNT:-${RDF_CLAUDE_ACCOUNT:-}}"
    [[ -n "$_RUN_ACCT" ]] || _RUN_ACCT="$(_account_default_name)"
    [[ -z "$_RUN_ACCT" ]] || _account_lookup "$_RUN_ACCT" >/dev/null || _account_unknown "$_RUN_ACCT"
}

# _run_env TOOL [UNSET...] — fill _RUN_ENV with env(1) arguments for the picked account (none picked: environment as is)
_run_env() {
    local tool="$1" dir home v
    shift
    _RUN_ENV=(env)
    for v in "$@"; do
        _RUN_ENV+=(-u "$v")  # env(1) reads no options after the first NAME=value
    done
    [[ -n "$_RUN_ACCT" ]] || return 0
    if [[ "$tool" == claude ]]; then
        dir="$(_account_dir "$_RUN_ACCT")"
        _RUN_ENV+=(-u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDE_CODE_OAUTH_REFRESH_TOKEN -u ANTHROPIC_API_KEY
            -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_PROFILE -u CLAUDE_CODE_USE_BEDROCK
            -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY -u ANTHROPIC_BASE_URL)
        if [[ -n "$dir" ]]; then
            _RUN_ENV+=("CLAUDE_CONFIG_DIR=${dir}")
        else
            _RUN_ENV+=(-u CLAUDE_CONFIG_DIR)
        fi
        _RUN_ENV+=("RDF_CLAUDE_ACCOUNT=${_RUN_ACCT}")
    else
        home="$(_account_codex_home "$_RUN_ACCT")"
        _RUN_ENV+=(-u CODEX_API_KEY -u CODEX_ACCESS_TOKEN)
        if [[ -n "$home" ]]; then
            _RUN_ENV+=("CODEX_HOME=${home}")
        else
            _RUN_ENV+=(-u CODEX_HOME)
        fi
    fi
    _RUN_ENV+=("RDF_ACCOUNT=${_RUN_ACCT}")
}

# _run_launch TOOL ARGS... — rdf run
_run_launch() {
    local tool="${1:-}" yolo=0 root=0 sandbox=0 a
    local -a pre args
    case "$tool" in
        claude|codex) shift ;;
        help|--help|-h) _run_usage; return 0 ;;
        "") echo "rdf: error: run needs a tool: claude or codex — run 'rdf run help'" >&2; exit 2 ;;
        *)  echo "rdf: error: unknown tool: ${tool} (claude or codex) — run 'rdf run help'" >&2; exit 2 ;;
    esac
    _RUN_ACCT=""
    pre=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            @*)
                if [[ -n "$_RUN_ACCT" ]] || ! _run_pick "$1"; then
                    break
                fi
                shift ;;
            -y|--yolo) yolo=1; shift ;;
            --root)
                [[ "$tool" == claude ]] || { echo "rdf: error: --root is claude only; codex has no root check (--yolo, or --sandbox)" >&2; exit 2; }
                root=1; shift ;;
            --sandbox) sandbox=1; shift ;;
            --chrome)
                [[ "$tool" == claude ]] || break
                pre+=(--chrome); shift ;;
            --fs)
                [[ "$tool" == claude ]] || break
                pre+=(--fork-session); shift ;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    if [[ "$sandbox" -eq 1 ]]; then
        [[ "$yolo" -eq 0 && "$root" -eq 0 ]] || { echo "rdf: error: --sandbox keeps permission checks on; it does not combine with --yolo or --root" >&2; exit 2; }
        _run_sandbox_guard "$tool" "$@"
    fi
    _run_account
    if [[ "$tool" == claude && "$sandbox" -eq 1 ]]; then
        _run_env "$tool" IS_SANDBOX
    else
        _run_env "$tool"
    fi
    args=()
    if [[ "$tool" == claude ]]; then
        if [[ "$root" -eq 1 ]]; then
            _RUN_ENV+=(IS_SANDBOX=1)
            args+=(--dangerously-skip-permissions)
        elif [[ "$yolo" -eq 1 ]]; then
            args+=(--dangerously-skip-permissions)
        elif [[ "$sandbox" -eq 1 ]]; then
            args+=(--settings "$_RUN_CLAUDE_SANDBOX" --permission-mode acceptEdits)
        fi
    elif [[ "$yolo" -eq 1 ]]; then
        args+=(--dangerously-bypass-approvals-and-sandbox)
    elif [[ "$sandbox" -eq 1 ]]; then
        args+=(--sandbox workspace-write --ask-for-approval on-request)
    fi
    args+=(${pre[@]+"${pre[@]}"})
    for a in "$@"; do
        if [[ "$tool" == claude && "$a" == "--fs" ]]; then
            args+=(--fork-session)
        else
            args+=("$a")
        fi
    done
    rdf_require_bin "$tool"
    exec "${_RUN_ENV[@]}" "$tool" ${args[@]+"${args[@]}"}
}

# _run_review ARGS... — rdf review: codex exec, read-only unless --write, stdin closed unless the prompt comes from it
_run_review() {
    local sandbox=read-only file="" stdin=0 prompt=""
    local -a opts
    opts=()
    _RUN_ACCT=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            @*)
                if [[ -n "$_RUN_ACCT" ]] || ! _run_pick "$1"; then
                    break
                fi
                shift ;;
            --effort) [[ $# -ge 2 ]] || rdf_die "--effort needs a level"; opts+=(-c "model_reasoning_effort=$2"); shift 2 ;;
            -m|--model) [[ $# -ge 2 ]] || rdf_die "$1 needs a model"; opts+=(-m "$2"); shift 2 ;;
            -o) [[ $# -ge 2 ]] || rdf_die "-o needs a file"; opts+=(-o "$2"); shift 2 ;;
            -C) [[ $# -ge 2 ]] || rdf_die "-C needs a directory"; [[ -d "$2" ]] || rdf_die "no such directory: $2"
                opts+=(-C "$2"); shift 2 ;;
            -f) [[ $# -ge 2 ]] || rdf_die "-f needs a file"; [[ -r "$2" ]] || rdf_die "cannot read prompt file: $2"
                file="$2"; shift 2 ;;
            --write) sandbox=workspace-write; shift ;;
            -) stdin=1; shift ;;
            help|--help|-h) _run_usage; return 0 ;;
            --) shift; break ;;
            -*) rdf_die "unknown option: $1 — run 'rdf review help' (use -- before a prompt that starts with -)" ;;
            *) break ;;
        esac
    done
    prompt="$*"
    if [[ -n "$file" || "$stdin" -eq 1 ]]; then
        [[ -z "$prompt" ]] || rdf_die "give the prompt once: as text, -f FILE or -"
    elif [[ -z "$prompt" ]]; then
        rdf_die "review needs a prompt: text, -f FILE or - (stdin) — run 'rdf review help'"
    fi
    _run_account
    _run_env codex
    rdf_require_bin codex
    if [[ -n "$file" ]]; then
        exec "${_RUN_ENV[@]}" codex exec -s "$sandbox" ${opts[@]+"${opts[@]}"} - < "$file"
    elif [[ "$stdin" -eq 1 ]]; then
        exec "${_RUN_ENV[@]}" codex exec -s "$sandbox" ${opts[@]+"${opts[@]}"} -
    fi
    exec "${_RUN_ENV[@]}" codex exec -s "$sandbox" ${opts[@]+"${opts[@]}"} -- "$prompt" < /dev/null
}

cmd_run() { _run_launch "$@"; }
cmd_review() { _run_review "$@"; }
