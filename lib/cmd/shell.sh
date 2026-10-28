#!/usr/bin/env bash
# lib/cmd/shell.sh — rdf shell subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_shell_usage() {
    cat <<'USAGE'
Usage: rdf shell init

Print the rdf shell function and tab completion for bash or zsh. Add to the end
of ~/.bashrc or ~/.zshrc (a later alias or function named rdf wins):

  eval "$(rdf shell init)"

  rdf use <name>   use account <name> for rdf run, rdf c, rdf x and rdf review
                   in this shell; 'rdf use -' clears it, 'rdf use' alone lists
                   accounts
  completion       rdf subcommands and options, @accounts and account names (zsh:
                   needs compinit)

Every other rdf command passes through to the rdf binary unchanged.
Accounts: rdf account help. Launch options: rdf run help.
USAGE
}

# _shell_init — the rdf path sits in the function body; CC snapshots drop variables and _-prefixed functions
_shell_init() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --sandbox) echo "rdf: shell init --sandbox is gone: c, cs, ch and cuse became rdf c, rdf c --root, rdf c --chrome and rdf use (rdf shell help)" >&2 ;;
            *) rdf_die "unknown option: ${arg} — run 'rdf shell help'" ;;
        esac
    done
    printf '%s\n' 'unalias rdf 2>/dev/null || true  # an absent alias is expected; true keeps set -e shells alive'
    printf 'function rdf {\n    local bin=%q\n' "${RDF_HOME}/bin/rdf"
    cat <<'INIT'
    if [ "${1:-}" != use ]; then
        "$bin" "$@"
        return
    fi
    if [ "$#" -gt 2 ]; then
        echo "rdf: error: usage: rdf use [<name> | -]" >&2
        return 2
    fi
    case "${2:-}" in
        "") "$bin" account list ;;
        -)  unset RDF_ACCOUNT RDF_CLAUDE_ACCOUNT ;;
        *)  "$bin" account dir "$2" >/dev/null && export RDF_ACCOUNT="$2" RDF_CLAUDE_ACCOUNT="$2" ;;
    esac
}
function _rdf_accounts {
    local n d
    [ -f "$HOME/.rdf/accounts" ] || return 0
    while IFS="	" read -r n d || [ -n "$n" ]; do
        case "$n" in ""|"#"*) continue ;; esac
        printf '%s\n' "$n"
    done < "$HOME/.rdf/accounts"
}
function _rdf_lines {
    local w
    COMPREPLY=()
    while IFS= read -r w; do
        [ -n "$w" ] && COMPREPLY+=("$w")
    done < <("$@")
}
function _rdf_reply {
    local w
    COMPREPLY=()
    while IFS= read -r w; do
        case "$w" in "$2"*) [ -n "$w" ] && COMPREPLY+=("$w") ;; esac
    done < <(printf '%s\n' "$1" | command tr ' ' '\n')
}
function _rdf_words {
    local o=0
    if [ -n "${ZSH_VERSION:-}" ]; then [[ -o ksharrays ]] || o=1; fi  # zsh bashcompinit: 1-based COMP_WORDS
    _rdf_cur="${COMP_WORDS[COMP_CWORD+o]:-}"
    [ "$#" -lt 2 ] || _rdf_cur="$2"  # readline's word, which COMPREPLY replaces: @p even though COMP_WORDS splits it at @
    _rdf_prev=""
    [ "$COMP_CWORD" -gt 0 ] && _rdf_prev="${COMP_WORDS[COMP_CWORD-1+o]:-}"
    _rdf_w1="${COMP_WORDS[1+o]:-}"
    _rdf_w2="${COMP_WORDS[2+o]:-}"
}
function _rdf_at {
    case "$_rdf_cur" in
        @*) _rdf_reply "$(_rdf_accounts | command sed 's/^/@/')" "$_rdf_cur"; return 0 ;;
    esac
    return 1
}
function _rdf_complete {
    local words=""
    _rdf_words "$@"
    COMPREPLY=()
    if [ "$COMP_CWORD" -le 1 ]; then
        words="run review use account shell tokens state doctor generate deploy sync init refresh migrate profile github help version"
    else
        case "$_rdf_w1" in
            run|c|x)
                if [ "$_rdf_w1" = run ] && [ "$COMP_CWORD" -eq 2 ]; then words="claude codex help"
                else
                    _rdf_at && return 0
                    words="--yolo --sandbox"
                    case "$_rdf_w1 $_rdf_w2" in "c "*|"run claude") words="--yolo --root --sandbox --chrome --fs" ;; esac
                fi ;;
            review)
                _rdf_at && return 0
                case "$_rdf_prev" in
                    --effort) words="low medium high xhigh" ;;
                    -o|-f) _rdf_lines compgen -f -- "$_rdf_cur"; return 0 ;;
                    -C) _rdf_lines compgen -d -- "$_rdf_cur"; return 0 ;;
                    -m|--model) return 0 ;;
                    *) words="--effort -m -o -C -f --write - --" ;;
                esac ;;
            use)
                [ "$COMP_CWORD" -eq 2 ] && words="$(_rdf_accounts) -" ;;
            account)
                if [ "$COMP_CWORD" -eq 2 ]; then words="add list link remove default primary dir help"
                else
                    case "$_rdf_w2" in
                        link|remove|primary) words="$(_rdf_accounts)" ;;
                        default) words="$(_rdf_accounts) -" ;;
                        dir) words="$(_rdf_accounts) --codex" ;;
                        add) words="--primary" ;;
                    esac
                fi ;;
            shell)
                [ "$COMP_CWORD" -eq 2 ] && words="init help" ;;
            tokens)
                case "$_rdf_prev" in
                    --by) words="day week month session project" ;;
                    --project|--transcripts) _rdf_lines compgen -d -- "$_rdf_cur"; return 0 ;;
                    --days|--since|--session|--top) return 0 ;;
                    *) words="--claude --codex --all --project --transcripts --session --days --since --by --top --json --summary --pricing --no-cache help" ;;
                esac ;;
            generate|deploy)
                words="claude-code claude-plugin codex antigravity agent-skills agents-md gemini-cli all" ;;
        esac
    fi
    _rdf_reply "$words" "$_rdf_cur"
}
if [ -n "${ZSH_VERSION:-}" ] && ! whence complete >/dev/null 2>&1; then
    whence compdef >/dev/null 2>&1 && autoload -U +X bashcompinit 2>/dev/null && bashcompinit  # zsh without compinit: no completion
fi
if type complete >/dev/null 2>&1; then
    complete -F _rdf_complete rdf
fi
INIT
}

cmd_shell() {
    case "${1:-}" in
        init)   shift; _shell_init "$@" ;;
        help|--help|-h) _shell_usage ;;
        "")     rdf_die "missing subcommand — run 'rdf shell help'" ;;
        *)      rdf_die "unknown subcommand: $1 — run 'rdf shell help'" ;;
    esac
}
