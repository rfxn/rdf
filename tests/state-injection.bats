#!/usr/bin/env bats
# tests/state-injection.bats — regression guards for state-script code injection
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# C1: context-audit.sh built a `python3 -c` program by interpolating rdf-state.sh
# JSON (which carries git commit messages) into json.loads('''...'''). A commit
# message containing ''' broke out of the Python string → arbitrary code exec when
# /r-context-audit crawled a workspace repo. Fix: feed data via stdin/argv, never
# the program body. These tests lock that closed and guard _json_str's JSON validity.

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    TEST_TMP="$(mktemp -d)"
    TEST_TMP="$(cd "$TEST_TMP" && pwd -P)"
}

teardown() {
    command rm -rf "$TEST_TMP"
}

# _mkrepo dir message — create a git repo whose HEAD commit carries `message`
_mkrepo() {
    local repo="$1" msg="$2"
    command mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    printf 'x\n' > "$repo/f"
    git -C "$repo" add f
    git -C "$repo" commit -q --cleanup=verbatim -F - <<<"$msg"
}

@test "context-audit.sh does not execute code from a hostile commit message (C1 regression)" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    command -v python3 >/dev/null 2>&1 || skip "python3 unavailable — vulnerable path is python-only"

    # context-audit.sh expects the workspace layout <workspace>/rdf/state/rdf-state.sh
    ln -s "$RDF_SRC" "$TEST_TMP/rdf"

    local marker="$TEST_TMP/PWNED"
    _mkrepo "$TEST_TMP/evilrepo" "fix '''+__import__('os').system('touch $marker')+'''"

    # stderr carries harmless absent-file noise in a bare test HOME; keep stdout clean
    # for the JSON assertion. The RCE guard is status 0 + marker absence.
    run bash -c "bash '$RDF_SRC/state/context-audit.sh' '$TEST_TMP' 2>/dev/null"
    [ "$status" -eq 0 ]
    # The injected payload must never have run.
    [ ! -e "$marker" ]
    # Output must still be valid JSON.
    printf '%s' "$output" | python3 -c 'import sys, json; json.load(sys.stdin)'
}

@test "rdf-state.sh returns a payload-bearing commit message as inert JSON data (C1)" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    command -v python3 >/dev/null 2>&1 || skip "python3 unavailable"

    _mkrepo "$TEST_TMP/repo" "msg '''triple''' with \"quotes\" and trailing backslash"

    run bash "$RDF_SRC/state/rdf-state.sh" --full "$TEST_TMP/repo"
    [ "$status" -eq 0 ]
    # Valid JSON, and the payload survives as a string value (not executed).
    printf '%s' "$output" | python3 -c '
import sys, json
d = json.load(sys.stdin)
assert d["recent_commits"], "no commits parsed"
assert "triple" in d["recent_commits"][0]["message"], "message not preserved as data"
'
}

@test "rdf-state.sh escapes control chars into valid JSON (_json_str hardening)" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    command -v python3 >/dev/null 2>&1 || skip "python3 unavailable"

    # Embedded tab in the commit message; raw control chars produce RFC-8259-invalid
    # JSON that breaks strict downstream parsers unless \t/\r escaped.
    _mkrepo "$TEST_TMP/repo" "$(printf 'subject\twith\ttab')"

    run bash "$RDF_SRC/state/rdf-state.sh" --full "$TEST_TMP/repo"
    [ "$status" -eq 0 ]
    # Strict JSON load rejects a raw tab inside a string; passing means it was escaped.
    printf '%s' "$output" | python3 -c 'import sys, json; json.load(sys.stdin)'
}

@test "context-audit.sh counts skills only, tracking legacy commands separately" {
    command -v jq >/dev/null 2>&1 || skip "jq unavailable"
    _mkrepo "$TEST_TMP/proj" "initial"
    local home="$TEST_TMP/home"
    command mkdir -p "$home/.claude/skills/r-a" "$home/.claude/skills/r-b"
    touch "$home/.claude/skills/r-a/SKILL.md" "$home/.claude/skills/r-b/SKILL.md"

    run bash -c 'HOME="$1" bash "$2" "$3"' \
        -- "$home" "$RDF_SRC/state/context-audit.sh" "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    local count legacy
    count="$(printf '%s' "$output" | jq -r '.skills.deployed.count')"
    legacy="$(printf '%s' "$output" | jq -r '.skills.legacy_commands')"
    [ "$count" -eq 2 ]
    [ "$legacy" -eq 0 ]
}

@test "context-audit.sh counts skills deployed as symlinked dirs" {
    command -v jq >/dev/null 2>&1 || skip "jq unavailable"
    _mkrepo "$TEST_TMP/proj" "initial"
    local home="$TEST_TMP/home" out="$TEST_TMP/out/skills"
    command mkdir -p "$out/r-a" "$out/r-b" "$home/.claude/skills"
    touch "$out/r-a/SKILL.md" "$out/r-b/SKILL.md"
    # Production layout: ~/.claude/skills/<n> is a symlink into the adapter output tree
    ln -s "$out/r-a" "$home/.claude/skills/r-a"
    ln -s "$out/r-b" "$home/.claude/skills/r-b"
    ln -s "$TEST_TMP/gone" "$home/.claude/skills/r-dead"

    run bash -c 'HOME="$1" bash "$2" "$3" 2>"$4"' \
        -- "$home" "$RDF_SRC/state/context-audit.sh" "$TEST_TMP/proj" "$TEST_TMP/err"
    [ "$status" -eq 0 ]
    [ ! -s "$TEST_TMP/err" ]                                     # dangling sibling stays silent
    local count bytes
    count="$(printf '%s' "$output" | jq -r '.skills.deployed.count')"
    bytes="$(printf '%s' "$output" | jq -r '.skills.deployed.bytes')"
    [ "$count" -eq 2 ]
    [ "$bytes" -ge 0 ]
}

@test "context-audit.sh counts a lingering legacy commands/ layout separately from skills" {
    command -v jq >/dev/null 2>&1 || skip "jq unavailable"
    _mkrepo "$TEST_TMP/proj" "initial"
    local home="$TEST_TMP/home"
    command mkdir -p "$home/.claude/commands" "$home/.claude/skills/r-a"
    touch "$home/.claude/commands/x.md" "$home/.claude/commands/y.md"
    touch "$home/.claude/skills/r-a/SKILL.md"

    run bash -c 'HOME="$1" bash "$2" "$3"' \
        -- "$home" "$RDF_SRC/state/context-audit.sh" "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    local count legacy
    count="$(printf '%s' "$output" | jq -r '.skills.deployed.count')"
    legacy="$(printf '%s' "$output" | jq -r '.skills.legacy_commands')"
    [ "$count" -eq 1 ]
    [ "$legacy" -eq 2 ]
}

@test "context-audit.sh runs off-workspace: no sibling rdf/, fresh HOME (F4 regression)" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    command -v jq >/dev/null 2>&1 || skip "jq unavailable"

    # Clone-shaped layout: a bare project dir with no <workspace>/rdf/ sibling,
    # and a HOME with none of the ~/.claude or ~/.rdf files the audit measures.
    _mkrepo "$TEST_TMP/clone" "initial"
    command mkdir -p "$TEST_TMP/home"

    run bash -c 'HOME="$1" bash "$2" "$3" 2>"$4"' \
        -- "$TEST_TMP/home" "$RDF_SRC/state/context-audit.sh" "$TEST_TMP/clone" "$TEST_TMP/err"
    [ "$status" -eq 0 ]
    [ ! -s "$TEST_TMP/err" ]
    printf '%s' "$output" | jq -e . >/dev/null
}
