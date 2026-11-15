#!/usr/bin/env bats
# tests/peers.bats: rdf peers, the read-only view of live Claude Code sessions on every account
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: HOME is a mktemp dir per test; live pids are sleeps started in setup;
# RDF_PEERS_SOCKDIRS always points at a temp dir, never at /run/user or /tmp.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2030,SC2031

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

S1=11111111-1111-4111-8111-111111111111
S2=22222222-2222-4222-8222-222222222222
S3=33333333-3333-4333-8333-333333333333

_rdf() { bash "${RDF_SRC}/bin/rdf" "$@"; }
_out() { bash "${RDF_SRC}/bin/rdf" "$@" 2>/dev/null; }  # stdout only: footer hints go to stderr
_err() { { bash "${RDF_SRC}/bin/rdf" "$@" >/dev/null; } 2>&1; }  # stderr only

setup() {
    HOME="$(mktemp -d)"
    export HOME
    unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID RDF_ACCOUNT RDF_CLAUDE_ACCOUNT
    export GIT_CEILING_DIRECTORIES="$HOME"
    RDF_PEERS_SOCKDIRS="${HOME}/socks"
    export RDF_PEERS_SOCKDIRS
    mkdir -p "$RDF_PEERS_SOCKDIRS"
    sleep 300 >/dev/null 2>&1 3>&- &
    P1=$!
    sleep 300 >/dev/null 2>&1 3>&- &
    P2=$!
    NOW_MS=$(( $(date +%s) * 1000 ))
}

teardown() {
    kill "$P1" "$P2" 2>/dev/null || true  # already gone
    rm -rf "$HOME" 2>/dev/null || true  # cleanup, ignore errors
}

# _start PID: /proc starttime (field 22) on Linux, else a placeholder
_start() {
    if [ -r "/proc/$1/stat" ]; then
        awk '{ sub(/.*\) /, ""); print $20 }' "/proc/$1/stat"
    else
        echo 1
    fi
}

# _session DIR PID NAME SID CWD STARTED_MS [PROCSTART]: write a registry entry
_session() {
    local ps="${7:-}"
    [ -n "$ps" ] || ps="$(_start "$2")"
    mkdir -p "$1"
    jq -n --argjson pid "$2" --arg name "$3" --arg sid "$4" --arg cwd "$5" --argjson st "$6" --arg ps "$ps" \
        '{pid: $pid, sessionId: $sid, cwd: $cwd, name: $name, status: "busy", kind: "interactive",
          startedAt: $st, updatedAt: $st, procStart: $ps, version: "2.1.322", peerProtocol: 1}' > "$1/$2.json"
}

# _transcript SID TITLE PROMPT MODE BRANCH ACCT ORG: write a fixture transcript under ~/.claude/projects
_transcript() {
    local f="${HOME}/.claude/projects/-fixture/$1.jsonl" reply
    reply="START$(head -c 395 /dev/zero | tr '\0' x)"
    mkdir -p "${f%/*}"
    {
        jq -cn '{type: "ai-title", aiTitle: "an older title"}'
        jq -cn --arg b "$5" '{type: "user", gitBranch: $b, message: {role: "user", content: "go"}}'
        jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Edit", input: {file_path: "/r/1"}}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Write", input: {file_path: "/r/2"}}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "MultiEdit", input: {file_path: "/r/3"}}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "NotebookEdit", input: {notebook_path: "/r/4.ipynb"}}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "text", text: "an earlier reply"}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Read", input: {file_path: "/r/read"}}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Edit", input: {file_path: "/r/5"}}]}}'
        jq -cn --arg b "$5" '{type: "assistant", gitBranch: $b, message: {content: [{type: "tool_use", name: "Write", input: {file_path: "/r/6"}}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Edit", input: {file_path: "/r/5"}}]}}'
        jq -cn --arg r "$reply" '{type: "assistant", message: {content: [{type: "text", text: $r}]}}'
        jq -cn '{type: "assistant", message: {content: [{type: "thinking", thinking: "hmm"}]}}'
        jq -cn --arg t "$2" '{type: "ai-title", aiTitle: $t}'
        jq -cn --arg p "$3" '{type: "last-prompt", lastPrompt: $p}'
        jq -cn --arg m "$4" '{type: "user", permissionMode: $m, message: {role: "user", content: "go"}}'
        jq -cn '{type: "mode", mode: "normal"}'
        jq -cn --arg a "$6" --arg o "$7" '{type: "session-owner", accountUuid: $a, organizationUuid: $o}'
        jq -cn '{type: "user", gitBranch: "", message: {role: "user", content: "later"}}'
    } >> "$f"
}

# _fixture: accounts work (primary) and personal (same accountUuid, other org), personal's
# sessions linked to ~/.claude/sessions; alpha (P1) in a git repo, alpha-two (P2) elsewhere
_fixture() {
    mkdir -p "${HOME}/.rdf" "${HOME}/.claude/sessions" "${HOME}/.claude-personal" "${HOME}/repo/sub" "${HOME}/other"
    git -C "${HOME}/repo" init -q
    printf '%s\t%s\n' work @primary personal "${HOME}/.claude-personal" > "${HOME}/.rdf/accounts"
    ln -s "${HOME}/.claude/sessions" "${HOME}/.claude-personal/sessions"
    printf '{"oauthAccount":{"accountUuid":"u-1","organizationUuid":"org-work"}}\n' > "${HOME}/.claude.json"
    printf '{"oauthAccount":{"accountUuid":"u-1","organizationUuid":"org-personal"}}\n' > "${HOME}/.claude-personal/.claude.json"
    _session "${HOME}/.claude/sessions" "$P1" alpha "$S1" "${HOME}/repo" $(( NOW_MS - 7200000 ))
    _session "${HOME}/.claude/sessions" "$P2" alpha-two "$S2" "${HOME}/other" $(( NOW_MS - 60000 ))
    _transcript "$S1" "Alpha work title" "fix the alpha bug" bypassPermissions feat/x u-1 org-work
    _transcript "$S2" "Second session" "second prompt" default main u-1 org-personal
}

@test "table lists live sessions newest first, omits a dead pid, marks this session with *" {
    _fixture
    ( exit 0 ) &
    dead=$!
    wait "$dead"
    _session "${HOME}/.claude/sessions" "$dead" ghost "$S3" "${HOME}/repo" "$NOW_MS"
    printf 'not json\n' > "${HOME}/.claude/sessions/notapid.json"
    export CLAUDE_CODE_SESSION_ID="$S1"
    export CLAUDE_CONFIG_DIR="${HOME}/.claude-personal"
    run _rdf peers
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [[ "${lines[0]}" == "  NAME"*"ACCOUNT"*"STATE"*"MODE"*"AGE"*"PROJECT"*"BRANCH"*"TITLE" ]]
    [[ "${lines[1]}" == "  alpha-two "*"personal"*"busy"*"default"*"1m"*"other"*"main"*"Second session" ]]
    [[ "${lines[2]}" == "* alpha "*"work"*"busy"*"bypass"*"2h"*"repo"*"feat/x"*"Alpha work title" ]]
    [[ "$output" != *ghost* ]]
    jq -cn --arg t "Second session $(head -c 200 /dev/zero | tr '\0' y)" '{type: "ai-title", aiTitle: $t}' \
        >> "${HOME}/.claude/projects/-fixture/${S2}.jsonl"
    run _rdf peers
    [ "${#lines[1]}" -eq 120 ]
    [[ "${lines[1]}" == *"Second session yyy"*"..." ]]
    for l in "${lines[@]}"; do [ "${#l}" -le 120 ]; done
}

@test "Linux: a live pid whose procStart does not match /proc is omitted" {
    [ -r /proc/self/stat ] || skip "no /proc: liveness is kill -0 only"
    _fixture
    _session "${HOME}/.claude/sessions" "$P2" alpha-two "$S2" "${HOME}/other" "$NOW_MS" 999999999
    run _out peers --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.[].name]' <<< "$output")" = '["alpha"]' ]
}

@test "title, last prompt, mode, branch and account come from the transcript; the account pair tells same-uuid accounts apart" {
    _fixture
    run _out peers --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '.[] | select(.name == "alpha") | [.title, .last_prompt, .mode, .branch, .account]' <<< "$output")" \
        = '["Alpha work title","fix the alpha bug","bypass","feat/x","work"]' ]
    [ "$(jq -c '.[] | select(.name == "alpha-two") | [.title, .last_prompt, .mode, .branch, .account]' <<< "$output")" \
        = '["Second session","second prompt","default","main","personal"]' ]
}

@test "--json is an array with the listed keys; card JSON adds last_reply, recent_files and rdf_progress" {
    _fixture
    mkdir -p "${HOME}/repo/.rdf/work-output"
    : > "${HOME}/repo/.rdf/work-output/phase-1-${S1}.md"
    : > "${HOME}/repo/.rdf/work-output/phase-1-${S2}.md"
    export CLAUDE_CODE_SESSION_ID="$S1"
    run _out peers --json
    [ "$status" -eq 0 ]
    [ "$(jq -c 'map(keys) | unique' <<< "$output")" \
        = '[["account","branch","cwd","last_prompt","mode","name","pid","self","session_id","started_at","status","title"]]' ]
    [ "$(jq -c '[.[] | [.name, .pid, .self, .session_id, .status, .cwd, .started_at]]' <<< "$output")" \
        = "[[\"alpha-two\",${P2},false,\"${S2}\",\"busy\",\"${HOME}/other\",$(( NOW_MS - 60000 ))],[\"alpha\",${P1},true,\"${S1}\",\"busy\",\"${HOME}/repo\",$(( NOW_MS - 7200000 ))]]" ]
    run _out peers alpha --json
    [ "$status" -eq 0 ]
    [ "$(jq -r 'type' <<< "$output")" = "object" ]
    [ "$(jq -c 'keys' <<< "$output")" \
        = '["account","branch","cwd","last_prompt","last_reply","mode","name","pid","rdf_progress","recent_files","self","session_id","started_at","status","title"]' ]
    [ "$(jq -c '.recent_files' <<< "$output")" = '["/r/5","/r/6","/r/4.ipynb","/r/3","/r/2"]' ]
    [ "$(jq -c '.rdf_progress' <<< "$output")" = "[\"${HOME}/repo/.rdf/work-output/phase-1-${S1}.md\"]" ]
    [ "$(jq -r '.last_reply | length' <<< "$output")" = "300" ]
    [[ "$(jq -r '.last_reply' <<< "$output")" == STARTxxx* ]]
}

@test "<name> card: exact match beats prefixes, a unique prefix matches, ambiguous or unknown exits 1 listing candidates" {
    _fixture
    run _rdf peers alpha
    [ "$status" -eq 0 ]
    [[ "$output" == *"pid:"*"${P1}"* ]]
    [[ "$output" == *"cwd:"*"${HOME}/repo"* ]]
    [[ "$output" == *"last prompt:"*"fix the alpha bug"* ]]
    [[ "$output" == *"last reply:"*"STARTxxx"* ]]
    [[ "$output" == *"recent files:"*"/r/5"*"/r/6"* ]]
    [[ "$output" != *"/r/read"* ]]
    [[ "$output" == *"rdf progress: -"* ]]
    [ "${lines[${#lines[@]}-1]}" = 'message it: SendMessage to "alpha"' ]
    run _rdf peers alpha-t
    [ "$status" -eq 0 ]
    [[ "$output" == *"pid:"*"${P2}"* ]]
    [ "${lines[${#lines[@]}-1]}" = 'message it: SendMessage to "alpha-two"' ]
    run _rdf peers al
    [ "$status" -eq 1 ]
    [[ "$output" == *alpha* && "$output" == *alpha-two* ]]
    run _rdf peers zzz
    [ "$status" -eq 1 ]
    [[ "$output" == *zzz* && "$output" == *alpha-two* ]]
}

@test "--here keeps sessions under the git toplevel, else under the current dir" {
    _fixture
    run bash -c 'cd "$HOME/repo/sub" || exit 1; bash "$RDF_SRC/bin/rdf" peers --here --json 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.[].name]' <<< "$output")" = '["alpha"]' ]
    run bash -c 'cd "$HOME/other" || exit 1; bash "$RDF_SRC/bin/rdf" peers --json --here 2>/dev/null'
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.[].name]' <<< "$output")" = '["alpha-two"]' ]
    run bash -c 'cd "$HOME" || exit 1; bash "$RDF_SRC/bin/rdf" peers --json --here 2>/dev/null'
    [ "$(jq -c '[.[].name]' <<< "$output")" = '["alpha-two","alpha"]' ]
}

@test "unlinked-account hint names accounts whose sessions are not shared; only an unshared dir attributes a session without a transcript" {
    _fixture
    rm "${HOME}/.claude/projects/-fixture/${S2}.jsonl"
    run _err peers
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run _out peers --json
    [ "$(jq -c '.[] | select(.name == "alpha-two") | .account' <<< "$output")" = '"?"' ]
    rm "${HOME}/.claude-personal/sessions"
    mkdir "${HOME}/.claude-personal/sessions"
    mv "${HOME}/.claude/sessions/${P2}.json" "${HOME}/.claude-personal/sessions/"
    run _err peers
    [ "$output" = "peer messaging across accounts is off for: personal (run: rdf account link)" ]
    run _out peers --json
    [ "$(jq -c '.[] | select(.name == "alpha-two") | [.account, .title, .mode, .branch]' <<< "$output")" = '["personal","","",""]' ]
    run _err peers --json
    [ -z "$output" ]
}

@test "a sessions dir shared with an unregistered primary or CLAUDE_CONFIG_DIR has no dir owner: account ?" {
    mkdir -p "${HOME}/.rdf" "${HOME}/.claude/sessions" "${HOME}/.claude-personal"
    printf '%s\t%s\n' personal "${HOME}/.claude-personal" > "${HOME}/.rdf/accounts"
    ln -s "${HOME}/.claude/sessions" "${HOME}/.claude-personal/sessions"
    printf '{"oauthAccount":{"accountUuid":"u-1","organizationUuid":"org-work"}}\n' > "${HOME}/.claude.json"
    printf '{"oauthAccount":{"accountUuid":"u-2","organizationUuid":"org-personal"}}\n' > "${HOME}/.claude-personal/.claude.json"
    _session "${HOME}/.claude/sessions" "$P1" primary-login "$S1" "${HOME}/repo" "$NOW_MS"
    _session "${HOME}/.claude/sessions" "$P2" on-personal "$S2" "${HOME}/repo" "$NOW_MS"
    _transcript "$S1" t p normal main u-1 org-work
    _transcript "$S2" t p normal main u-2 org-personal
    run _out peers --json
    [ "$(jq -cS 'map({(.name): .account}) | add' <<< "$output")" = '{"on-personal":"personal","primary-login":"?"}' ]
    rm "${HOME}/.claude/projects/-fixture/${S1}.jsonl" "${HOME}/.claude/projects/-fixture/${S2}.jsonl"
    run _out peers --json
    [ "$(jq -cS 'map({(.name): .account}) | add' <<< "$output")" = '{"on-personal":"?","primary-login":"?"}' ]
    printf '%s\t%s\n' work @primary > "${HOME}/.rdf/accounts"
    run _out peers --json
    [ "$(jq -c '[.[].account] | unique' <<< "$output")" = '["work"]' ]
    export CLAUDE_CONFIG_DIR="${HOME}/.claude-personal"
    run _out peers --json
    [ "$(jq -c '[.[].account] | unique' <<< "$output")" = '["?"]' ]
    printf '%s\t%s\n' work @primary personal "${HOME}/.claude-personal" > "${HOME}/.rdf/accounts"
    rm "${HOME}/.claude-personal/sessions"
    mkdir "${HOME}/.claude-personal/sessions"
    mv "${HOME}/.claude/sessions/${P2}.json" "${HOME}/.claude-personal/sessions/"
    ln -s "${HOME}/.claude-personal" "${HOME}/alias"
    export CLAUDE_CONFIG_DIR="${HOME}/alias/"
    run _out peers --json
    [ "$(jq -cS 'map({(.name): .account}) | add' <<< "$output")" = '{"on-personal":"personal","primary-login":"work"}' ]
}

@test "terminal control characters in session fields never reach the terminal" {
    _fixture
    evil=$'evil\e]0;x\a\nname'
    _session "${HOME}/.claude/sessions" "$P2" "$evil" "$S2" "${HOME}/other"$'\e[2J' $(( NOW_MS - 60000 ))
    f="${HOME}/.claude/projects/-fixture/${S2}.jsonl"
    jq -cn '{type: "ai-title", aiTitle: "ok \u001b]0;PWNED\u0007\u001b[31mred \u009b2J"}' >> "$f"
    jq -cn '{type: "last-prompt", lastPrompt: "p \u001b[2J"}' >> "$f"
    jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Edit", input: {file_path: "/r/\u001b[1m"}}]}}' >> "$f"
    run _rdf peers
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [[ "${lines[1]}" == "  evil ]0;x name "*"ok ]0;PWNED [31mred 2J" ]]
    run _rdf peers evil
    [ "$status" -eq 0 ]
    [[ "$output" == *"cwd:          ${HOME}/other?[2J"* && "$output" == *"/r/?[1m"* ]]
    [ "${lines[${#lines[@]}-1]}" = 'message it: SendMessage to "evil?]0;x??name"' ]
    card="$output"
    run _rdf peers zzz
    [ "$status" -eq 1 ]
    [[ "$output" == *"evil?]0;x??name"* ]]
    for o in "$card" "$output"; do
        [[ "$o" != *$'\e'* && "$o" != *$'\a'* && "$o" != *$'\xc2\x9b'* ]]
    done
    run _out peers --json
    [ "$(jq -r '.[] | select(.session_id == "'"$S2"'") | .name' <<< "$output")" = "$evil" ]
}

@test "table widths count characters and terminal columns, not bytes, under any locale" {
    command -v iconv >/dev/null || skip "iconv not installed"
    _fixture
    _session "${HOME}/.claude/sessions" "$P2" "éééééééééééé" "$S2" "${HOME}/other" $(( NOW_MS - 60000 ))
    jq -cn --arg t "$(printf 'é%.0s' $(seq 150))" '{type: "ai-title", aiTitle: $t}' >> "${HOME}/.claude/projects/-fixture/${S2}.jsonl"
    jq -cn --arg t "$(printf '漢%.0s' $(seq 100))" '{type: "ai-title", aiTitle: $t}' >> "${HOME}/.claude/projects/-fixture/${S1}.jsonl"
    run env LC_ALL=C bash "${RDF_SRC}/bin/rdf" peers
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    state="$(printf '%s' "${lines[0]}" | jq -Rr 'split("STATE")[0] | length')"
    for l in "${lines[@]:1}"; do
        printf '%s' "$l" | iconv -f UTF-8 -t UTF-8 >/dev/null
        [ "$(printf '%s' "$l" | jq -Rr 'split("busy")[0] | length')" -eq "$state" ]
    done
    [[ "${lines[1]}" == "  éééééééééééé "*"..." ]]
    [ "$(printf '%s' "${lines[1]}" | jq -Rr 'length')" -eq 120 ]
    [[ "${lines[2]}" == "  alpha "*"漢漢..." ]]
    cols="$(printf '%s' "${lines[2]}" | jq -Rr '[explode[] | if . == 28450 then 2 else 1 end] | add')"
    [ "$cols" -le 120 ] && [ "$cols" -ge 119 ]
}

@test "a torn first line in the 2 MiB transcript tail does not break parsing" {
    _fixture
    f="${HOME}/.claude/projects/-fixture/${S1}.jsonl"
    {
        printf '{"type":"user","pad":"'
        head -c 2200000 /dev/zero | tr '\0' x
        printf '"}\n'
        cat "$f"
    } > "${f}.new"
    mv "${f}.new" "$f"
    run _out peers alpha --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.title, .last_prompt, .account]' <<< "$output")" = '["Alpha work title","fix the alpha bug","work"]' ]
}

@test "no registry dirs at all: no live Claude Code sessions, exit 0; --json prints []" {
    run _rdf peers
    [ "$status" -eq 0 ]
    [ "$output" = "no live Claude Code sessions" ]
    run _rdf peers --json
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "no transcript and no account registry: registry fields only, account ?" {
    _session "${HOME}/.claude/sessions" "$P1" solo "$S1" "${HOME}/repo" "$NOW_MS"
    run _out peers --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '.[] | [.name, .account, .title, .branch]' <<< "$output")" = '["solo","?","",""]' ]
}

@test "orphan-socket hint counts live sockets of this uid with no registry entry" {
    command -v python3 >/dev/null || skip "python3 not installed"
    _fixture
    ( exit 0 ) &
    dead=$!
    wait "$dead"
    sleep 300 >/dev/null 2>&1 3>&- &
    p3=$!
    for p in "$P1" "$dead" "$p3"; do
        python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "${RDF_PEERS_SOCKDIRS}/${p}.sock"
    done
    run _err peers
    kill "$p3" 2>/dev/null || true  # already gone
    [ "$output" = "1 live Claude Code sockets have no registry entry; Claude Code may have changed its session layout" ]
}

@test "usage: unknown flag or extra argument exits 2; help exits 0; rdf help and completion list peers" {
    run _rdf peers --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"--bogus"* ]]
    run _rdf peers a b
    [ "$status" -eq 2 ]
    run _rdf peers help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--here"* && "$output" == *"--json"* ]]
    run _rdf help
    [[ "$output" == *"  peers "* ]]
    run bash -c 'eval "$(bash "$RDF_SRC/bin/rdf" shell init)"
COMP_WORDS=(rdf pe); COMP_CWORD=1; _rdf_complete; printf "%s|" "${COMPREPLY[@]}"; echo
COMP_WORDS=(rdf peers --); COMP_CWORD=2; _rdf_complete; printf "%s|" "${COMPREPLY[@]}"'
    [ "${lines[0]}" = "peers|" ]
    [ "${lines[1]}" = "--here|--json|" ]
}
