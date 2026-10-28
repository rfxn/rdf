#!/usr/bin/env bats
# tests/run.bats — rdf run (and rdf c / rdf x) and rdf review: account selection, --yolo/--root/--sandbox, Codex homes, codex exec plumbing
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: HOME is a mktemp dir; stub `claude` and `codex` on PATH print the env and argv they got.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

_rdf() { bash "${RDF_SRC}/bin/rdf" "$@"; }

setup() {
    exec </dev/null  # the codex stub reads stdin; a regression that reaches it must fail, not hang
    HOME="$(mktemp -d)"
    export HOME
    unset IS_SANDBOX RDF_CLAUDE_ACCOUNT RDF_ACCOUNT CLAUDE_CONFIG_DIR CODEX_HOME
    mkdir -p "${HOME}/.claude/projects" "${HOME}/.codex/sessions" "${HOME}/bin"
    printf 'model = "x"\n' > "${HOME}/.codex/config.toml"
    cat > "${HOME}/bin/claude" <<'STUB'
#!/usr/bin/env bash
args=""
for a in "$@"; do args="${args}${a}|"; done
printf 'claude CFG=%s ACCT=%s RA=%s SANDBOX=%s ARGS=%s\n' "${CLAUDE_CONFIG_DIR-unset}" \
    "${RDF_CLAUDE_ACCOUNT-unset}" "${RDF_ACCOUNT-unset}" "${IS_SANDBOX-unset}" "$args"
STUB
    cat > "${HOME}/bin/codex" <<'STUB'
#!/usr/bin/env bash
args=""
for a in "$@"; do args="${args}${a}|"; done
in="$(cat)"
printf 'codex HOME=%s RA=%s ARGS=%s STDIN=%s\n' "${CODEX_HOME-unset}" "${RDF_ACCOUNT-unset}" "$args" "$in"
STUB
    chmod +x "${HOME}/bin/claude" "${HOME}/bin/codex"
    PATH="${HOME}/bin:${PATH}"
    _rdf account add work --primary
    _rdf account add personal
    P="${HOME}/.claude-personal"
    X="${HOME}/.codex-personal"
}

teardown() { rm -rf "$HOME" 2>/dev/null || true; }  # cleanup, ignore errors

@test "run claude: @account, --yolo, --root, --fs and --chrome; rdf options may follow --chrome; tool args pass untouched" {
    run _rdf run claude @personal --yolo --fs -c
    [ "$output" = "claude CFG=${P} ACCT=personal RA=personal SANDBOX=unset ARGS=--dangerously-skip-permissions|--fork-session|-c|" ]
    run _rdf run claude --root
    [ "$output" = "claude CFG=unset ACCT=unset RA=unset SANDBOX=1 ARGS=--dangerously-skip-permissions|" ]
    run _rdf run claude --chrome @work --yolo -p "a b"
    [ "$output" = "claude CFG=unset ACCT=work RA=work SANDBOX=unset ARGS=--dangerously-skip-permissions|--chrome|-p|a b|" ]
    run _rdf run claude -p --yolo
    [ "$output" = "claude CFG=unset ACCT=unset RA=unset SANDBOX=unset ARGS=-p|--yolo|" ]
    run _rdf run claude -- --yolo
    [ "$output" = "claude CFG=unset ACCT=unset RA=unset SANDBOX=unset ARGS=--yolo|" ]
    run _rdf run claude --fs --root -c
    [ "$output" = "claude CFG=unset ACCT=unset RA=unset SANDBOX=1 ARGS=--dangerously-skip-permissions|--fork-session|-c|" ]
    run _rdf c --resume --fs
    [ "$output" = "claude CFG=unset ACCT=unset RA=unset SANDBOX=unset ARGS=--resume|--fork-session|" ]
    run _rdf x --fs -y
    [ "$output" = "codex HOME=unset RA=unset ARGS=--fs|-y| STDIN=" ]
}

@test "rdf c and rdf x are rdf run claude and rdf run codex; -y is --yolo until the first tool argument" {
    run _rdf c @personal -y --fs -c
    [ "$output" = "claude CFG=${P} ACCT=personal RA=personal SANDBOX=unset ARGS=--dangerously-skip-permissions|--fork-session|-c|" ]
    run _rdf c -p -y
    [ "$output" = "claude CFG=unset ACCT=unset RA=unset SANDBOX=unset ARGS=-p|-y|" ]
    run _rdf x @personal -y exec hi
    [ "$output" = "codex HOME=${X} RA=personal ARGS=--dangerously-bypass-approvals-and-sandbox|exec|hi| STDIN=" ]
}

@test "picking an account drops inherited credential and provider env vars, CLAUDE_CONFIG_DIR and Codex auth overrides; no pick keeps them" {
    cat > "${HOME}/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(env | grep -cE '^(CLAUDE_CODE_OAUTH_|ANTHROPIC_(API_KEY|AUTH_TOKEN|PROFILE|BASE_URL)=|CLAUDE_CODE_USE_)')" "${CLAUDE_CONFIG_DIR-unset}"
STUB
    export CLAUDE_CODE_OAUTH_TOKEN=t CLAUDE_CODE_OAUTH_REFRESH_TOKEN=r ANTHROPIC_API_KEY=k \
        ANTHROPIC_AUTH_TOKEN=a ANTHROPIC_PROFILE=p ANTHROPIC_BASE_URL=u CLAUDE_CODE_USE_BEDROCK=1 \
        CLAUDE_CODE_USE_VERTEX=1 CLAUDE_CODE_USE_FOUNDRY=1 CLAUDE_CONFIG_DIR=/elsewhere
    run _rdf c @personal
    [ "$output" = "0 ${P}" ]
    run _rdf c @work
    [ "$output" = "0 unset" ]
    run _rdf c
    [ "$output" = "9 /elsewhere" ]
    cat > "${HOME}/bin/codex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${CODEX_API_KEY-unset} ${CODEX_ACCESS_TOKEN-unset}"
STUB
    export CODEX_API_KEY=k CODEX_ACCESS_TOKEN=t
    run _rdf x @personal
    [ "$output" = "unset unset" ]
    run _rdf review @work hi
    [ "$output" = "unset unset" ]
    run _rdf x
    [ "$output" = "k t" ]
}

@test "@mentions that are not accounts pass through; a registered account with a deleted dir fails closed even when a same-named path exists" {
    mkdir -p "${HOME}/w/src" "${HOME}/w/personal"
    cd "${HOME}/w"
    for m in "@src/a.ts explain" @README.md @Makefile @agent-rdf-reviewer @src; do
        run _rdf c "$m"
        [ "$output" = "claude CFG=unset ACCT=unset RA=unset SANDBOX=unset ARGS=${m}|" ]
    done
    run _rdf c @personal
    [ "$output" = "claude CFG=${P} ACCT=personal RA=personal SANDBOX=unset ARGS=" ]
    rm -rf "$P"
    run _rdf c @personal
    [ "$status" -ne 0 ]
    [[ "$output" == *"config dir missing"* ]]
    [[ "$output" != *"ARGS="* ]]
}

@test "run codex: an account's own home becomes CODEX_HOME, the primary and a home-less account unset it; --yolo bypasses; --root is refused" {
    run bash -c 'CODEX_HOME=/elsewhere bash "$RDF_SRC/bin/rdf" run codex @personal --yolo exec hi < /dev/null'
    [ "$output" = "codex HOME=${X} RA=personal ARGS=--dangerously-bypass-approvals-and-sandbox|exec|hi| STDIN=" ]
    run bash -c 'CODEX_HOME=/elsewhere bash "$RDF_SRC/bin/rdf" run codex @work < /dev/null'
    [ "$output" = "codex HOME=unset RA=work ARGS= STDIN=" ]
    rm -rf "$X"
    run bash -c 'CODEX_HOME=/elsewhere bash "$RDF_SRC/bin/rdf" run codex @personal < /dev/null'
    [ "$output" = "codex HOME=unset RA=personal ARGS= STDIN=" ]
    run bash -c 'CODEX_HOME=/elsewhere bash "$RDF_SRC/bin/rdf" run codex < /dev/null'
    [ "$output" = "codex HOME=/elsewhere RA=unset ARGS= STDIN=" ]
    run _rdf run codex --root
    [ "$status" -eq 2 ]
    [[ "$output" == *"--root is claude only"* ]]
}

@test "--sandbox is each tool's own sandbox with permission checks kept, drops an inherited IS_SANDBOX, and refuses --yolo, --root and flags that undo it" {
    run env IS_SANDBOX=1 bash "${RDF_SRC}/bin/rdf" c @personal --sandbox -c
    [ "$status" -eq 0 ]
    j='{"sandbox":{"enabled":true,"failIfUnavailable":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":true}}'
    [ "$output" = "claude CFG=${P} ACCT=personal RA=personal SANDBOX=unset ARGS=--settings|${j}|--permission-mode|acceptEdits|-c|" ]
    settings="${output#*ARGS=--settings|}"
    printf '%s' "${settings%%|*}" | jq -e '.sandbox.enabled and .sandbox.failIfUnavailable and .sandbox.allowUnsandboxedCommands == false'
    run bash -c 'bash "$RDF_SRC/bin/rdf" x --sandbox < /dev/null'
    [ "$output" = "codex HOME=unset RA=unset ARGS=--sandbox|workspace-write|--ask-for-approval|on-request| STDIN=" ]
    for bad in "c --sandbox -y" "c --root --sandbox" "c --sandbox --settings {}" "c --sandbox -p --permission-mode=bypassPermissions" \
        "c --sandbox --dangerously-skip-permissions" "x --sandbox exec -s danger-full-access hi" "x --sandbox -a never" "x --sandbox --yolo"; do
        # shellcheck disable=SC2086  # each case is a command line, split on purpose
        run _rdf $bad
        [ "$status" -eq 2 ]
        [[ "$output" != *"ARGS="* ]]
    done
}

@test "account precedence: @name, then RDF_ACCOUNT, then RDF_CLAUDE_ACCOUNT, then the stored default; stale names fail closed" {
    _rdf account default personal
    run _rdf run claude
    [ "$output" = "claude CFG=${P} ACCT=personal RA=personal SANDBOX=unset ARGS=" ]
    run env RDF_CLAUDE_ACCOUNT=work bash "${RDF_SRC}/bin/rdf" run claude
    [ "$output" = "claude CFG=unset ACCT=work RA=work SANDBOX=unset ARGS=" ]
    run env RDF_ACCOUNT=personal RDF_CLAUDE_ACCOUNT=work bash "${RDF_SRC}/bin/rdf" run claude
    [ "$output" = "claude CFG=${P} ACCT=personal RA=personal SANDBOX=unset ARGS=" ]
    run env RDF_ACCOUNT=personal bash "${RDF_SRC}/bin/rdf" run claude @work
    [ "$output" = "claude CFG=unset ACCT=work RA=work SANDBOX=unset ARGS=" ]
    run env RDF_ACCOUNT=gone bash "${RDF_SRC}/bin/rdf" run codex
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown account: gone"* ]]
    [[ "$output" != *"codex HOME"* ]]
    printf 'gone\n' > "${HOME}/.rdf/accounts.default"
    run _rdf run claude
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown account: gone"* ]]
    [[ "$output" != *"ARGS="* ]]
}

@test "unknown @name exits 2 and launches nothing; an @mention that is not an account passes through to codex too" {
    run _rdf run codex @nope
    [ "$status" -eq 2 ]
    [[ "$output" != *"codex HOME"* ]]
    mkdir -p "${HOME}/w/notes"
    run bash -c 'cd "$HOME/w" || exit 1; bash "$RDF_SRC/bin/rdf" run codex @notes < /dev/null'
    [ "$output" = "codex HOME=unset RA=unset ARGS=@notes| STDIN=" ]
}

@test "review: read-only codex exec with stdin closed for a text prompt; --effort, -m, -o, -C and --write map to codex flags" {
    mkdir -p "${HOME}/repo"
    run bash -c 'echo LEAK | bash "$RDF_SRC/bin/rdf" review @personal --effort high -m gpt-x -o out.md -C "$HOME/repo" check the diff'
    [ "$status" -eq 0 ]
    [ "$output" = "codex HOME=${X} RA=personal ARGS=exec|-s|read-only|-c|model_reasoning_effort=high|-m|gpt-x|-o|out.md|-C|${HOME}/repo|--|check the diff| STDIN=" ]
    run bash -c 'bash "$RDF_SRC/bin/rdf" review --write -- -starts-with-dash < /dev/null'
    [ "$output" = "codex HOME=unset RA=unset ARGS=exec|-s|workspace-write|--|-starts-with-dash| STDIN=" ]
    run bash -c 'bash "$RDF_SRC/bin/rdf" review resume < /dev/null'
    [ "$output" = "codex HOME=unset RA=unset ARGS=exec|-s|read-only|--|resume| STDIN=" ]
}

@test "review: -f FILE and - feed the prompt on stdin; one prompt only; no prompt, a bad option or a missing dir fails" {
    printf 'long prompt\n' > "${HOME}/p.md"
    run bash -c 'bash "$RDF_SRC/bin/rdf" review -f "$HOME/p.md"'
    [ "$output" = "codex HOME=unset RA=unset ARGS=exec|-s|read-only|-| STDIN=long prompt" ]
    run bash -c 'echo piped | bash "$RDF_SRC/bin/rdf" review -'
    [ "$output" = "codex HOME=unset RA=unset ARGS=exec|-s|read-only|-| STDIN=piped" ]
    run _rdf review -f "${HOME}/p.md" also text
    [ "$status" -ne 0 ]
    [[ "$output" == *"give the prompt once"* ]]
    run bash -c 'bash "$RDF_SRC/bin/rdf" review < /dev/null'
    [ "$status" -ne 0 ]
    [[ "$output" == *"review needs a prompt"* ]]
    run _rdf review --bogus x
    [ "$status" -ne 0 ]
    run _rdf review -C "${HOME}/missing" x
    [ "$status" -ne 0 ]
    [[ "$output" != *"codex HOME"* ]]
}

@test "run needs a known tool; help prints usage; a missing tool binary is reported" {
    run _rdf run
    [ "$status" -eq 2 ]
    run _rdf run vim
    [ "$status" -eq 2 ]
    run _rdf run help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: rdf run <claude|codex>"* ]]
    rm "${HOME}/bin/codex"
    run env PATH="${HOME}/bin:$(dirname "$(command -v jq)"):/usr/bin:/bin" bash "${RDF_SRC}/bin/rdf" run codex
    [ "$status" -ne 0 ]
    [[ "$output" == *"required binary not found: codex"* ]]
}
