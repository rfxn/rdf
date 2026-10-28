#!/usr/bin/env bats
# tests/account.bats — rdf account: registry, shared-state links, list, remove, default, primary, dir
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
    unset RDF_CLAUDE_ACCOUNT RDF_ACCOUNT CLAUDE_CONFIG_DIR
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

@test "default stores a registered account; list shows it; - and removing that account clear it" {
    _rdf account add work --primary
    _rdf account add personal
    D="${HOME}/.rdf/accounts.default"
    run _rdf account default nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown account: nope"* ]]
    [ ! -e "$D" ]
    run _rdf account default
    [ "$status" -ne 0 ]
    run _rdf account default personal
    [ "$status" -eq 0 ]
    [ "$(cat "$D")" = "personal" ]
    run _rdf account list
    [ "${lines[3]}" = "default: personal (launches without @name or rdf use)" ]
    run _rdf account default -
    [ "$status" -eq 0 ]
    [ ! -e "$D" ]
    run _rdf account list
    [[ "$output" != *"default:"* ]]

    _rdf account default work
    _rdf account remove personal
    [ "$(cat "$D")" = "work" ]
    run _rdf account remove work
    [[ "$output" == *"default cleared"* ]]
    [ ! -e "$D" ]
}

# _rdfs — rdf with the uname/ps/mv/awk stubs from _swap_fixture first on PATH
_rdfs() { PATH="${HOME}/bin:${PATH}" bash "${RDF_SRC}/bin/rdf" "$@"; }

# _swap_fixture — work (primary) and personal logged in, with plugins; spare not logged in
_swap_fixture() {
    REAL_MV="$(command -v mv)"
    REAL_AWK="$(command -v awk)"
    export REAL_MV REAL_AWK
    mkdir -p "${HOME}/bin" "${HOME}/.claude/plugins"
    printf '#!/bin/sh\necho "${UNAME_S:-Linux}"\n' > "${HOME}/bin/uname"
    printf '#!/bin/sh\n[ ! -f "$HOME/ps.out" ] || cat "$HOME/ps.out"\n' > "${HOME}/bin/ps"
    cat > "${HOME}/bin/mv" <<'STUB'
#!/bin/sh
if [ -n "${MV_FAIL:-}" ]; then
    case "$1" in *"$MV_FAIL") [ -z "${MV_RECREATE:-}" ] || : > "$MV_RECREATE"; exit 1 ;; esac
fi
exec "$REAL_MV" "$@"
STUB
    cat > "${HOME}/bin/awk" <<'STUB'
#!/bin/sh
if [ -n "${AWK_FAIL:-}" ]; then
    case "$*" in *"$AWK_FAIL"*) exit 1 ;; esac
fi
exec "$REAL_AWK" "$@"
STUB
    chmod +x "${HOME}/bin/uname" "${HOME}/bin/ps" "${HOME}/bin/mv" "${HOME}/bin/awk"
    printf '{"oauthAccount":{"emailAddress":"w@example.com","organizationName":"Work Org"}}\n' > "${HOME}/.claude.json"
    printf 'work\n' > "${HOME}/.claude/.credentials.json"
    printf 'work\n' > "${HOME}/.claude/policy-limits.json"
    printf '{"a":[{"installPath":"%s/.claude/plugins/cache/a"}]}\n' "$HOME" > "${HOME}/.claude/plugins/installed_plugins.json"
    printf '{ }\n' > "${HOME}/.claude/plugins/blocklist.json"
    _rdf account add work --primary
    _rdf account add personal
    _rdf account add spare
    P="${HOME}/.claude-personal"
    W="${HOME}/.claude-work"
    mkdir -p "${P}/plugins" "${P}/sessions" "${P}/plans"
    printf '{"oauthAccount":{"emailAddress":"p@example.com"}}\n' > "${P}/.claude.json"
    printf 'personal\n' > "${P}/.credentials.json"
    printf 'mine\n' > "${P}/plans/p.md"
    printf '{"m":{"installLocation":"%s/plugins/marketplaces/m","other":"/x%s/plugins"}}\n' "$P" "$P" \
        > "${P}/plugins/known_marketplaces.json"
    chmod 644 "${P}/plugins/known_marketplaces.json"
}

# _tree — every path under HOME (stubs excluded) with link targets and file checksums
_tree() {
    local p
    find "$HOME" -path "${HOME}/bin" -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
        if [ -L "$p" ]; then
            echo "$p -> $(readlink "$p")"
        elif [ -f "$p" ]; then
            echo "$p $(cksum < "$p")"
        else
            echo "$p"
        fi
    done
}

_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }  # GNU stat, then BSD

@test "primary swaps logins, .claude.json, plugins and org policy; shared state stays in ~/.claude" {
    _swap_fixture
    printf '{}\n' > "${HOME}/.claude/.claude.json"
    run _rdfs account primary personal
    [ "$status" -eq 0 ]
    [[ "$output" == *"primary is now personal; launch work with 'rdf run claude @work'"* ]]
    [[ "$output" == *"left in place: ${HOME}/.claude/.claude.json"* ]]
    [ -f "${HOME}/.claude/.claude.json" ]
    [ "$(cat "${HOME}/.claude/.credentials.json")" = "personal" ]
    [ "$(cat "${W}/.credentials.json")" = "work" ]
    [ "$(cat "${W}/policy-limits.json")" = "work" ]
    [ ! -e "${HOME}/.claude/policy-limits.json" ]
    [ "$(jq -r .oauthAccount.emailAddress "${HOME}/.claude.json")" = "p@example.com" ]
    [ "$(jq -r .oauthAccount.emailAddress "${W}/.claude.json")" = "w@example.com" ]
    [ "$(jq -r .m.installLocation "${HOME}/.claude/plugins/known_marketplaces.json")" = "${HOME}/.claude/plugins/marketplaces/m" ]
    [ "$(jq -r .m.other "${HOME}/.claude/plugins/known_marketplaces.json")" = "/x${P}/plugins" ]
    [ "$(_mode "${HOME}/.claude/plugins/known_marketplaces.json")" = "644" ]
    [ "$(jq -r '.a[0].installPath' "${W}/plugins/installed_plugins.json")" = "${W}/plugins/cache/a" ]
    [ "$(cat "${W}/plugins/blocklist.json")" = "{ }" ]
    [ -d "${HOME}/.claude/sessions" ]
    [ "$(cat "${HOME}/.claude/plans/p.md")" = "mine" ]
    [ -d "${HOME}/.claude/projects" ]
    [ ! -L "${HOME}/.claude/projects" ]
    [ "$(_mode "$W")" = "700" ]
    for e in projects skills settings.json history.jsonl plans; do
        [ "$(readlink "${W}/${e}")" = "${HOME}/.claude/${e}" ]
    done
    [ "$(readlink "${HOME}/.claude-spare/projects")" = "${HOME}/.claude/projects" ]
    [ "$(readlink "${HOME}/.claude-spare/plans")" = "${HOME}/.claude/plans" ]
    [ ! -e "$P" ]
    [ -z "$(_rdf account dir personal)" ]
    [ "$(_rdf account dir work)" = "$W" ]
    run _rdf account list
    [[ "$output" == *"personal       ~/.claude                primary      p@example.com"* ]]
    [[ "$output" == *"work           ~/.claude-work           5/5          w@example.com (Work Org)"* ]]
}

@test "primary --dry-run lists the moves and changes nothing; every refusal changes nothing" {
    _swap_fixture
    before="$(_tree)"
    run _rdfs account primary personal --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"move ~/.claude/.credentials.json -> ~/.claude-work/.credentials.json"* ]]
    [[ "$output" == *"move ~/.claude.json -> ~/.claude-work/.claude.json"* ]]
    [[ "$output" == *"move ~/.claude-personal/.claude.json -> ~/.claude.json"* ]]
    [[ "$output" == *"move ~/.claude-personal/plans -> ~/.claude/plans"* ]]
    [[ "$output" == *"then: registry personal -> primary, work -> ~/.claude-work"* ]]
    [[ "$output" != *"~/.claude/projects"* ]]
    [[ "$output" == *"dry run: nothing changed"* ]]
    [ "$(_tree)" = "$before" ]

    run _rdfs account primary nope
    [ "$status" -eq 2 ]
    run _rdfs account primary
    [ "$status" -eq 1 ]
    [[ "$output" == *"primary requires <name>"* ]]
    run _rdfs account primary personal -x
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: -x"* ]]
    run _rdfs account primary work
    [ "$status" -eq 1 ]
    [[ "$output" == *"work is already the primary account"* ]]
    run _rdfs account primary spare
    [ "$status" -eq 1 ]
    [[ "$output" == *"spare is not logged in"* ]]
    UNAME_S=Darwin run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"not supported on macOS"* ]]

    mkdir "$W"
    run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"${W} already exists"* ]]
    rmdir "$W"

    rm "${P}/skills"
    mkdir "${P}/skills"
    run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"${P}/skills is not a link to ${HOME}/.claude/skills"* ]]
    rmdir "${P}/skills"
    ln -s "${HOME}/.claude/skills" "${P}/skills"

    mkdir "${HOME}/.claude/ide"
    ln -s "${HOME}/.claude/ide" "${P}/ide"
    run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"${P}/ide is a symlink"* ]]
    rm "${P}/ide"
    rmdir "${HOME}/.claude/ide"

    mkdir -p "${HOME}/.claude/sessions"
    printf '{}\n' > "${HOME}/.claude/sessions/$$.json"
    run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"running: pid $$ (${HOME}/.claude/sessions/$$.json)"* ]]
    [[ "$output" == *"quit every Claude Code session"* ]]
    run _rdfs account primary personal --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"running: pid $$"* ]]
    rm -r "${HOME}/.claude/sessions"

    mkdir -p "${P}/daemon"
    printf '{"proto":1,"supervisorPid":%s,"workers":{}}\n' "$$" > "${P}/daemon/roster.json"
    run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"running: pid $$ (${P}/daemon/roster.json)"* ]]
    rm -r "${P}/daemon"

    printf '4242 claude claude --resume\n4243 2.1.309 /opt/x/claude/versions/2.1.309 --bg-spare\n' > "${HOME}/ps.out"
    run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"running: pid 4242 (claude process)"* ]]
    [[ "$output" == *"running: pid 4243 (claude process)"* ]]
    rm "${HOME}/ps.out"
    [ "$(_tree)" = "$before" ]
}

@test "primary undoes every move when a move or the registry write fails" {
    _swap_fixture
    before="$(_tree)"
    MV_FAIL=".claude-personal/.claude.json" run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not move ${P}/.claude.json; every move was undone"* ]]
    [ "$(_tree)" = "$before" ]
    AWK_FAIL=".rdf/accounts" run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not write ${HOME}/.rdf/accounts; every move was undone"* ]]
    [ "$(_tree)" = "$before" ]
}

@test "primary undo never moves onto a path recreated mid-swap" {
    _swap_fixture
    MV_FAIL=".claude-personal/.claude.json" MV_RECREATE="${HOME}/.claude/policy-limits.json" \
        run _rdfs account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not restore ${HOME}/.claude/policy-limits.json: it was recreated; the original is at ${W}/policy-limits.json"* ]]
    [[ "$output" == *"some moves could not be undone"* ]]
    [ "$(cat "${W}/policy-limits.json")" = "work" ]
    [ ! -s "${HOME}/.claude/policy-limits.json" ]
    [ "$(cat "${HOME}/.claude/.credentials.json")" = "work" ]
    [ "$(cat "${P}/.credentials.json")" = "personal" ]
    [ "$(_rdf account dir personal)" = "$P" ]
}

@test "primary with no primary registered refuses" {
    _rdf account add personal
    printf '{}\n' > "${HOME}/.claude-personal/.credentials.json"
    run _rdf account primary personal
    [ "$status" -eq 1 ]
    [[ "$output" == *"no primary account registered"* ]]
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

@test "codex: with ~/.codex present, add creates ~/.codex-<name> (700) linking shared entries and the session dirs it creates in ~/.codex, never auth.json or state; without it, none" {
    run _rdf account add work --primary
    run _rdf account add solo
    [ ! -e "${HOME}/.codex-solo" ]
    mkdir -p "${HOME}/.codex/skills"
    printf 'model = "x"\n' > "${HOME}/.codex/config.toml"
    printf '{}\n' > "${HOME}/.codex/auth.json"
    : > "${HOME}/.codex/state_5.sqlite"
    run _rdf account add personal
    [ "$status" -eq 0 ]
    [[ "$output" == *"personal (codex): 4/4 shared entries linked (4 new, 0 kept)"* ]]
    x="${HOME}/.codex-personal"
    [ "$(stat -c %a "$x" 2>/dev/null || stat -f %Lp "$x")" = "700" ]  # GNU stat, then BSD
    for e in config.toml sessions archived_sessions skills; do
        [ "$(readlink "${x}/${e}")" = "${HOME}/.codex/${e}" ]
    done
    [ ! -e "${x}/auth.json" ]
    [ ! -e "${x}/state_5.sqlite" ]
    [ ! -e "${HOME}/.codex-work" ]
}

@test "codex: link adds missing Codex homes; list shows each account's Codex state; dir --codex prints the home; remove keeps it" {
    run _rdf account add work --primary
    run _rdf account add personal
    mkdir -p "${HOME}/.codex/sessions"
    run _rdf account list
    [[ "$output" == *"CODEX"* ]]
    run _rdf account dir personal --codex
    [ "$output" = "" ]
    run _rdf account link
    [ "$status" -eq 0 ]
    [ -L "${HOME}/.codex-personal/sessions" ]
    [ ! -e "${HOME}/.codex-work" ]
    run _rdf account dir personal --codex
    [ "$output" = "${HOME}/.codex-personal" ]
    run _rdf account dir work --codex
    [ "$output" = "" ]
    run _rdf account dir personal --bogus
    [ "$status" -ne 0 ]
    printf '{}\n' > "${HOME}/.codex-personal/auth.json"
    run _rdf account list
    echo "$output" | grep -qE '^[ *] work .* ~/\.codex$'
    echo "$output" | grep -qE '^  personal .* own, logged in$'
    run _rdf account remove personal
    [[ "$output" == *"Codex home kept: ~/.codex-personal"* ]]
    [ -d "${HOME}/.codex-personal" ]
}
