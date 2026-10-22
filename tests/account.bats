#!/usr/bin/env bats
# tests/account.bats — rdf account: registry, shared-state links, list, remove, dir
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: HOME is a mktemp dir per test.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

_rdf() { bash "${RDF_SRC}/bin/rdf" "$@"; }

setup() {
    HOME="$(mktemp -d)"
    export HOME
    unset RDF_CLAUDE_ACCOUNT
    mkdir -p "${HOME}/.claude/projects" "${HOME}/.claude/skills"
    printf '{}\n' > "${HOME}/.claude/settings.json"
    : > "${HOME}/.claude/history.jsonl"
}

teardown() { rm -rf "$HOME" 2>/dev/null || true; }  # cleanup, ignore errors

@test "add --primary registers ~/.claude; add <name> links only shared entries present" {
    printf '{}\n' > "${HOME}/.claude/.credentials.json"
    printf '{}\n' > "${HOME}/.claude/remote-settings.json"
    run _rdf account add work --primary
    [ "$status" -eq 0 ]
    run _rdf account add personal
    [ "$status" -eq 0 ]
    d="${HOME}/.claude-personal"
    [ "$(stat -c %a "$d" 2>/dev/null || stat -f %Lp "$d")" = "700" ]  # GNU stat, then BSD
    for e in projects skills settings.json history.jsonl; do
        [ -L "${d}/${e}" ]
        [ "$(readlink "${d}/${e}")" = "${HOME}/.claude/${e}" ]
    done
    [ ! -e "${d}/.credentials.json" ]
    [ ! -e "${d}/remote-settings.json" ]
    [ ! -e "${d}/plans" ]
    [ "$(grep -c "$(printf '\t')" "${HOME}/.rdf/accounts")" = "2" ]
}

@test "link keeps an own copy and a foreign symlink, then picks up new ~/.claude entries" {
    mkdir -p "${HOME}/.claude-personal/projects" "${HOME}/elsewhere"
    printf 'mine\n' > "${HOME}/.claude-personal/projects/keep"
    ln -s "${HOME}/elsewhere" "${HOME}/.claude-personal/skills"
    ln -s "${HOME}/gone" "${HOME}/.claude-personal/settings.json"
    run _rdf account add personal
    [ "$status" -eq 0 ]
    [[ "$output" == *"kept ${HOME}/.claude-personal/projects (own copy"* ]]
    [[ "$output" == *"kept ${HOME}/.claude-personal/skills (links to ${HOME}/elsewhere"* ]]
    [[ "$output" == *"kept ${HOME}/.claude-personal/settings.json (links to ${HOME}/gone"* ]]
    [ ! -L "${HOME}/.claude-personal/projects" ]
    [ "$(cat "${HOME}/.claude-personal/projects/keep")" = "mine" ]
    [ "$(readlink "${HOME}/.claude-personal/skills")" = "${HOME}/elsewhere" ]
    [ ! -e "${HOME}/elsewhere/skills" ]
    [ -L "${HOME}/.claude-personal/history.jsonl" ]

    mkdir -p "${HOME}/.claude/plans"
    run _rdf account link personal
    [ "$status" -eq 0 ]
    [[ "$output" == *"personal: 2/5 shared entries linked (1 new, 3 kept)"* ]]
    [ "$(readlink "${HOME}/.claude-personal/plans")" = "${HOME}/.claude/plans" ]
    run _rdf account link
    [ "$status" -eq 0 ]
    [[ "$output" == *"(0 new, 3 kept)"* ]]
    [ ! -e "${HOME}/.claude/projects/projects" ]
}

@test "list marks the active account, reads each login and counts links" {
    printf '{"oauthAccount":{"emailAddress":"w@example.com","organizationName":"Work Org"}}\n' > "${HOME}/.claude.json"
    _rdf account add work --primary
    _rdf account add personal
    printf '{"oauthAccount":{"emailAddress":"p@example.com"}}\n' > "${HOME}/.claude-personal/.claude.json"
    _rdf account add spare
    rm "${HOME}/.claude-spare/skills"
    run _rdf account list
    [ "$status" -eq 0 ]
    [[ "$output" == *"* work           ~/.claude                primary      w@example.com (Work Org)"* ]]
    [[ "$output" == *"  personal       ~/.claude-personal       4/4          p@example.com"* ]]
    [[ "$output" == *"  spare          ~/.claude-spare          3/4          not logged in"* ]]
    RDF_CLAUDE_ACCOUNT=personal run _rdf account list
    [[ "$output" == *"  work "* ]]
    [[ "$output" == *"* personal "* ]]
    CLAUDE_CONFIG_DIR="${HOME}/.claude-spare/" run _rdf account list
    [[ "$output" == *"* spare "* ]]
    [[ "$output" == *"  work "* ]]
    CLAUDE_CONFIG_DIR=/elsewhere run _rdf account list
    [[ "$output" != *"* "* ]]
}

@test "list with no registry prints the setup hint" {
    run _rdf account list
    [ "$status" -eq 0 ]
    [[ "$output" == *"rdf account add <name> --primary"* ]]
}

@test "dir prints empty for primary, the dir otherwise, and fails on unknown names" {
    _rdf account add work --primary
    _rdf account add personal
    run _rdf account dir work
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    run _rdf account dir personal
    [ "$output" = "${HOME}/.claude-personal" ]
    run _rdf account dir nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown account: nope (registered: work personal)"* ]]
}

@test "primary is a registry marker, independent of how HOME is spelled" {
    _rdf account add work --primary
    [ "$(grep -c "^work$(printf '\t')@primary$" "${HOME}/.rdf/accounts")" = "1" ]
    HOME="${HOME}//" run _rdf account dir work
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    HOME="$(dirname "$HOME")/./$(basename "$HOME")" run _rdf account dir work
    [ "$output" = "" ]
}

@test "registry: hand edits without a final newline and malformed rows are handled" {
    mkdir -p "${HOME}/.rdf"
    printf '# hand edited\nbroken\t\nrel\tnot/absolute\nwork\t@primary' > "${HOME}/.rdf/accounts"
    [ -z "$(_rdf account dir work 2>/dev/null)" ]  # stdout only; malformed-row warnings go to stderr
    run _rdf account dir broken
    [ "$status" -ne 0 ]
    [[ "$output" == *"skipping malformed row"* ]]
    [[ "$output" == *"unknown account: broken"* ]]
    run _rdf account add personal
    [ "$status" -eq 0 ]
    [ "$(_rdf account dir personal 2>/dev/null)" = "${HOME}/.claude-personal" ]  # stdout only
    [ -z "$(_rdf account dir work 2>/dev/null)" ]  # stdout only
}

@test "dir fails when an account's config dir was deleted" {
    _rdf account add personal
    rm -rf "${HOME}/.claude-personal"
    run _rdf account dir personal
    [ "$status" -ne 0 ]
    [[ "$output" == *"config dir missing"* ]]
}

@test "add, remove, re-add keeps the config dir and its login" {
    _rdf account add personal
    printf '{}\n' > "${HOME}/.claude-personal/.credentials.json"
    run _rdf account remove personal
    [ "$status" -eq 0 ]
    [[ "$output" == *"config dir kept: ~/.claude-personal"* ]]
    [ -d "${HOME}/.claude-personal" ]
    [ -L "${HOME}/.claude-personal/projects" ]
    [ "$(grep -vc '^#' "${HOME}/.rdf/accounts" || true)" = "0" ]  # grep -c exits 1 on zero
    run _rdf account dir personal
    [ "$status" -ne 0 ]
    run _rdf account add personal
    [ "$status" -eq 0 ]
    [[ "$output" == *"4/4 shared entries linked (0 new, 0 kept)"* ]]
    [ -f "${HOME}/.claude-personal/.credentials.json" ]
}

@test "add rejects bad names, duplicates, a second primary and a missing ~/.claude" {
    for bad in "../x" "A" "a/b" "agent-ci" "$(printf 'a%.0s' {1..33})"; do
        run _rdf account add "$bad"
        [ "$status" -ne 0 ]
        [[ "$output" == *"invalid account name"* ]]
    done
    run _rdf account add
    [ "$status" -ne 0 ]
    run _rdf account add -x
    [[ "$output" == *"unknown option: -x"* ]]
    run _rdf account add a b
    [[ "$output" == *"unexpected argument: b"* ]]
    _rdf account add --primary work
    run _rdf account add other --primary
    [ "$status" -ne 0 ]
    [[ "$output" == *"already registered as: work"* ]]
    run _rdf account add work
    [ "$status" -ne 0 ]
    [[ "$output" == *"account already registered: work"* ]]
    run _rdf account link work
    [ "$status" -ne 0 ]
    [[ "$output" == *"primary account"* ]]
    [ ! -e "${HOME}/.claude-A" ]

    rm -rf "${HOME}/.claude" "${HOME}/.rdf"
    run _rdf account add work --primary
    [ "$status" -ne 0 ]
    [[ "$output" == *"run claude once and log in first"* ]]
}
