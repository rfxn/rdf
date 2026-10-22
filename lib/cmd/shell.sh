#!/usr/bin/env bash
# lib/cmd/shell.sh — rdf shell subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_shell_usage() {
    cat <<'USAGE'
Usage: rdf shell init [--sandbox]

Print Claude Code launcher functions for bash or zsh. Add to the end of
~/.bashrc or ~/.zshrc (later aliases or functions with these names win):

  eval "$(rdf shell init)"

Launchers (replace existing aliases of the same names):
  claude, c     claude
  cs            claude --dangerously-skip-permissions
  ch            claude --chrome
  cuse <name>   Use account <name> for launches from this shell; 'cuse -' clears it,
                'cuse' alone lists accounts

Every launcher takes a leading @<name> to pick an account for one run
(cs @personal --resume) and maps --fs to --fork-session. Picking an account
drops inherited credential and provider settings (CLAUDE_CODE_OAUTH_TOKEN,
CLAUDE_CODE_OAUTH_REFRESH_TOKEN, ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN,
ANTHROPIC_PROFILE, ANTHROPIC_BASE_URL, CLAUDE_CODE_USE_BEDROCK,
CLAUDE_CODE_USE_VERTEX, CLAUDE_CODE_USE_FOUNDRY) so that account's login is
used against Anthropic. With no account picked, the launch environment is left
as it is. Accounts: rdf account help

Options:
  --sandbox     cs also sets IS_SANDBOX=1 for its run, which lets it bypass
                permissions as root; use only on a host you treat as a sandbox
USAGE
}

# _shell_init [--sandbox] — config sits in function bodies; CC snapshots drop variables and _-prefixed functions
_shell_init() {
    local cs_mode=bypass
    case "${1:-}" in
        --sandbox) cs_mode=sandbox ;;
        "") ;;
        *) rdf_die "unknown option: $1 — run 'rdf shell help'" ;;
    esac
    printf '%s\n' 'unalias claude c cs ch cuse 2>/dev/null  # absent aliases are expected'
    printf 'function rdf_cli { %q "$@"; }\n' "${RDF_HOME}/bin/rdf"
    printf 'function cs { rdf_launch %s "$@"; }\n' "$cs_mode"
    cat <<'INIT'
function rdf_launch {
    local mode="$1" acct="" dir a rc
    local -a cmd
    shift
    case "${1:-}" in
        @agent-*|@*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) ;;
        @[abcdefghijklmnopqrstuvwxyz0123456789]*)
            rc=0
            if [ -e "${1#@}" ]; then
                rdf_cli account dir "${1#@}" >/dev/null 2>&1 || rc=$?  # rc 2 = unknown account; other errors fail closed
            fi
            if [ "$rc" -ne 2 ]; then
                acct="${1#@}"
                shift
            fi
            ;;
    esac
    [ -n "$acct" ] || acct="${RDF_CLAUDE_ACCOUNT:-}"
    cmd=(env)
    if [ -n "$acct" ]; then
        dir="$(rdf_cli account dir "$acct")" || return
        cmd+=(-u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDE_CODE_OAUTH_REFRESH_TOKEN -u ANTHROPIC_API_KEY
            -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_PROFILE -u CLAUDE_CODE_USE_BEDROCK
            -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_USE_FOUNDRY -u ANTHROPIC_BASE_URL)
        if [ -n "$dir" ]; then
            cmd+=("CLAUDE_CONFIG_DIR=$dir")
        else
            cmd+=(-u CLAUDE_CONFIG_DIR)
        fi
        cmd+=("RDF_CLAUDE_ACCOUNT=$acct")
    fi
    case "$mode" in
        sandbox) cmd+=(IS_SANDBOX=1 claude --dangerously-skip-permissions) ;;
        bypass)  cmd+=(claude --dangerously-skip-permissions) ;;
        chrome)  cmd+=(claude --chrome) ;;
        *)       cmd+=(claude) ;;
    esac
    for a in "$@"; do
        case "$a" in
            --fs) cmd+=(--fork-session) ;;
            *)    cmd+=("$a") ;;
        esac
    done
    command "${cmd[@]}"
}
function claude { rdf_launch plain "$@"; }
function c { rdf_launch plain "$@"; }
function ch { rdf_launch chrome "$@"; }
function cuse {
    case "${1:-}" in
        "") rdf_cli account list ;;
        -)  unset RDF_CLAUDE_ACCOUNT ;;
        *)  rdf_cli account dir "$1" >/dev/null && export RDF_CLAUDE_ACCOUNT="$1" ;;
    esac
}
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
