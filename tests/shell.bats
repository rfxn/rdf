#!/usr/bin/env bats
# tests/shell.bats — rdf shell init launchers: account selection, --fs, sandbox scoping
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: HOME is a mktemp dir; a stub `claude` on PATH prints the env and argv it got.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

setup() {
    HOME="$(mktemp -d)"
    export HOME
    unset IS_SANDBOX RDF_CLAUDE_ACCOUNT CLAUDE_CONFIG_DIR
    mkdir -p "${HOME}/.claude/projects" "${HOME}/bin"
    cat > "${HOME}/bin/claude" <<'STUB'
#!/usr/bin/env bash
args=""
for a in "$@"; do args="${args}${a}|"; done
printf 'CFG=%s ACCT=%s SANDBOX=%s ARGS=%s\n' "${CLAUDE_CONFIG_DIR-unset}" \
    "${RDF_CLAUDE_ACCOUNT-unset}" "${IS_SANDBOX-unset}" "$args"
STUB
    chmod +x "${HOME}/bin/claude"
    PATH="${HOME}/bin:${PATH}"
    bash "${RDF_SRC}/bin/rdf" account add work --primary
    bash "${RDF_SRC}/bin/rdf" account add personal
    P="${HOME}/.claude-personal"
}

teardown() { rm -rf "$HOME" 2>/dev/null || true; }  # cleanup, ignore errors

# _sh script [init-args] — run script in bash after eval'ing the launchers
_sh() { bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init $1)"; '"$1" _ "${2:-}"; }

@test "cs @name sets the account dir and maps --fs; IS_SANDBOX only with --sandbox, scoped to the run" {
    run _sh 'cs @personal --fs -c'
    [ "$status" -eq 0 ]
    [ "$output" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=--dangerously-skip-permissions|--fork-session|-c|" ]
    run _sh 'cs; c; echo "parent=${IS_SANDBOX-unset}"' --sandbox
    [ "${lines[0]}" = "CFG=unset ACCT=unset SANDBOX=1 ARGS=--dangerously-skip-permissions|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=" ]
    [ "${lines[2]}" = "parent=unset" ]
    run bash "${RDF_SRC}/bin/rdf" shell init --bogus
    [ "$status" -ne 0 ]
}

@test "picking an account drops inherited credential and provider env vars; no pick keeps them" {
    cat > "${HOME}/bin/claude" <<'STUB'
#!/usr/bin/env bash
env | grep -cE '^(CLAUDE_CODE_OAUTH_|ANTHROPIC_(API_KEY|AUTH_TOKEN|PROFILE|BASE_URL)=|CLAUDE_CODE_USE_)' || true  # count only
STUB
    run _sh 'export CLAUDE_CODE_OAUTH_TOKEN=t CLAUDE_CODE_OAUTH_REFRESH_TOKEN=r ANTHROPIC_API_KEY=k \
        ANTHROPIC_AUTH_TOKEN=a ANTHROPIC_PROFILE=p ANTHROPIC_BASE_URL=u CLAUDE_CODE_USE_BEDROCK=1 \
        CLAUDE_CODE_USE_VERTEX=1 CLAUDE_CODE_USE_FOUNDRY=1; c @personal; c @work; c'
    [ "${lines[0]}" = "0" ]
    [ "${lines[1]}" = "0" ]
    [ "${lines[2]}" = "9" ]
}

@test "no account picked makes no rdf call; a failing rdf never falls back to the default account" {
    mkdir -p "${HOME}/work/personal"
    run _sh 'function rdf_cli { return 127; }; c -p hi; cd "$HOME/work" || exit 1; c @personal; echo "rc=$?"
function rdf_cli { return 1; }; c @personal; echo "rc=$?"'
    [ "${lines[0]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=-p|hi|" ]
    [ "${lines[1]}" = "rc=127" ]
    [ "${lines[2]}" = "rc=1" ]
}

@test "a registered account with a deleted dir fails closed even when a same-named path exists" {
    mkdir -p "${HOME}/work/personal"
    rm -rf "$P"
    run _sh 'cd "$HOME/work" || exit 1; cuse work; cs @personal; echo "rc=$?"'
    [[ "$output" == *"config dir missing"* ]]
    [[ "$output" != *"ARGS="* ]]
    [[ "$output" == *"rc=1"* ]]
}

@test "launchers survive Claude Code's Bash-tool snapshot (functions only, _-prefixed dropped)" {
    bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init --sandbox)"
for f in $(declare -F | cut -d" " -f3 | grep -vE "^_[^_]"); do declare -f "$f"; done' > "${HOME}/fns.sh"
    run env -i HOME="$HOME" PATH="$PATH" RDF_CLAUDE_ACCOUNT=personal bash -c 'source "$HOME/fns.sh"; cs; c @work'
    [ "${lines[0]}" = "CFG=${P} ACCT=personal SANDBOX=1 ARGS=--dangerously-skip-permissions|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=work SANDBOX=unset ARGS=" ]
}

@test "@primary drops an inherited CLAUDE_CONFIG_DIR" {
    run _sh 'CLAUDE_CONFIG_DIR=/elsewhere c @work --resume'
    [ "$output" = "CFG=unset ACCT=work SANDBOX=unset ARGS=--resume|" ]
}

@test "no account picked leaves the environment as it is" {
    run _sh 'CLAUDE_CONFIG_DIR=/elsewhere claude -p hi'
    [ "$output" = "CFG=/elsewhere ACCT=unset SANDBOX=unset ARGS=-p|hi|" ]
}

@test "ch adds --chrome" {
    run _sh 'ch @personal'
    [ "$output" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=--chrome|" ]
}

@test "unknown @name launches nothing and fails" {
    run _sh 'cs @nope; echo "rc=$?"'
    [[ "$output" == *"unknown account: nope"* ]]
    [[ "$output" != *"ARGS="* ]]
    [[ "$output" == *"rc=2"* ]]
}

@test "@ mentions that are not accounts pass through as prompt text" {
    mkdir -p "${HOME}/work/src" "${HOME}/work/personal"
    run _sh 'cd "$HOME/work" || exit 1
c "@src/a.ts explain"; c @README.md; c @Makefile; c @agent-rdf-reviewer; c @src; c @personal'
    [ "${lines[0]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=@src/a.ts explain|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=@README.md|" ]
    [ "${lines[2]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=@Makefile|" ]
    [ "${lines[3]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=@agent-rdf-reviewer|" ]
    [ "${lines[4]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=@src|" ]
    [ "${lines[5]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=" ]
}

@test "cuse is sticky, @name overrides it, cuse - clears it, bad names leave it unchanged" {
    run _sh 'cuse personal; c; c @work; cuse nope; c; cuse -; c'
    [ "${lines[0]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=" ]
    [ "${lines[1]}" = "CFG=unset ACCT=work SANDBOX=unset ARGS=" ]
    [[ "${lines[2]}" == *"unknown account: nope"* ]]
    [ "${lines[3]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=" ]
    [ "${lines[4]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=" ]
}

@test "init replaces existing aliases of the launcher names" {
    run bash -c 'shopt -s expand_aliases
alias cs="echo ALIAS-cs"
alias claude="echo ALIAS-claude"
eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
cs
claude'
    [ "$status" -eq 0 ]
    [[ "$output" != *ALIAS* ]]
    [ "${lines[0]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=--dangerously-skip-permissions|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=unset SANDBOX=unset ARGS=" ]
}

@test "zsh: launchers eval over aliases and select accounts" {
    command -v zsh >/dev/null || skip "zsh not installed"
    run zsh -c 'alias cs="echo ALIAS"
eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
cs @personal --fs
cuse work; CLAUDE_CONFIG_DIR=/elsewhere c "@src/a.ts hi"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "CFG=${P} ACCT=personal SANDBOX=unset ARGS=--dangerously-skip-permissions|--fork-session|" ]
    [ "${lines[1]}" = "CFG=unset ACCT=work SANDBOX=unset ARGS=@src/a.ts hi|" ]
}
