#!/usr/bin/env bats
# tests/hooks-handoff.bats — compaction handoff square (PreCompact snapshot +
# SessionStart re-injection)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Covers canonical/scripts/precompact-snapshot.sh and session-start-context.sh.
# Both hooks must NEVER exit nonzero (compaction/startup must not be blocked) and
# must degrade gracefully without jq. HOME is pinned to a temp dir so the snapshot
# store (~/.rdf/state/handoff/) never touches the developer's real home. stdin is
# fed from a file to keep shell metacharacters out of bats `run` (which evals).

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PRE="$RDF_SRC/canonical/scripts/precompact-snapshot.sh"
SS="$RDF_SRC/canonical/scripts/session-start-context.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
    TEST_TMP="$(cd "$TEST_TMP" && pwd -P)"
    export HOME="$TEST_TMP/home"
    mkdir -p "$HOME"
    HANDOFF="$HOME/.rdf/state/handoff"
    JSON="$TEST_TMP/in.json"
}

teardown() {
    command rm -rf "$TEST_TMP"
}

_mkrepo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    printf 'x\n' > "$repo/f"
    git -C "$repo" add f
    git -C "$repo" commit -qm init
}

# _minbin dir — populate dir with symlinks to the real binaries the hooks need,
# deliberately excluding jq, so PATH=dir simulates a host without jq. type -P
# resolves the on-disk executable only (ignores shell aliases/functions).
_minbin() {
    local dir="$1" tool src
    mkdir -p "$dir"
    for tool in bash env cat tr date mkdir mv find head ls wc grep sed git rm sort; do
        src="$(type -P "$tool" 2>/dev/null)" || continue
        [ -n "$src" ] && ln -sf "$src" "$dir/$tool"
    done
}

# ---- precompact-snapshot.sh -----------------------------------------------

@test "precompact writes a snapshot with core fields (git repo cwd)" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    local repo="$TEST_TMP/repo"
    _mkrepo "$repo"
    printf 'dirty\n' > "$repo/untracked"   # force a nonzero dirty count
    printf '{"session_id":"sid-A","cwd":"%s","trigger":"auto"}' "$repo" > "$JSON"

    run bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
    [ -f "$HANDOFF/sid-A.md" ]
    run cat "$HANDOFF/sid-A.md"
    [[ "$output" =~ "trigger: auto" ]]
    [[ "$output" == *"cwd: $repo"* ]]
    [[ "$output" =~ "branch: " ]]
    [[ "$output" =~ "head: " ]]
    [[ "$output" =~ "dirty-files: 1" ]]
    [[ "$output" =~ "timestamp: "[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "precompact records the active plan and recent work-output" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    local repo="$TEST_TMP/repo2"
    _mkrepo "$repo"
    mkdir -p "$repo/.rdf/work-output"
    printf '# plan\n' > "$repo/.rdf/theplan.md"
    printf '%s\n' "$repo/.rdf/theplan.md" > "$repo/.rdf/active-plan"
    printf 'a\n' > "$repo/.rdf/work-output/phase-1-result.md"
    printf '{"session_id":"sid-B","cwd":"%s","trigger":"manual"}' "$repo" > "$JSON"

    run bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
    run cat "$HANDOFF/sid-B.md"
    [[ "$output" == *"active-plan: $repo/.rdf/theplan.md"* ]]
    [[ "$output" =~ "recent work-output:" ]]
    [[ "$output" == *"phase-1-result.md"* ]]
}

@test "precompact snapshot stays within the 40-line ceiling" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    local repo="$TEST_TMP/repo3"
    _mkrepo "$repo"
    mkdir -p "$repo/.rdf/work-output"
    local i
    for i in 1 2 3 4 5 6 7 8; do printf 'x\n' > "$repo/.rdf/work-output/w-$i.md"; done
    printf '{"session_id":"sid-C","cwd":"%s","trigger":"auto"}' "$repo" > "$JSON"

    run bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
    run wc -l < "$HANDOFF/sid-C.md"
    [ "$output" -le 40 ]
    # newest-3 cap: exactly three work-output entries listed
    run grep -c '^  - ' "$HANDOFF/sid-C.md"
    [ "$output" -eq 3 ]
}

@test "precompact exits 0 on garbage stdin" {
    printf 'this is not json }{ ][' > "$JSON"
    run bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
}

@test "precompact exits 0 on empty stdin" {
    : > "$JSON"
    run bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
}

@test "precompact sanitizes a path-traversal session_id (no escape from handoff dir)" {
    printf '{"session_id":"../../etc/evil","cwd":"/nonexistent","trigger":"auto"}' > "$JSON"
    run bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/home/.rdf/state/etc/evil.md" ]   # traversal did not escape
    [ ! -e "$HOME/etc/evil.md" ]
}

@test "precompact prunes handoff files older than 7 days" {
    mkdir -p "$HANDOFF"
    printf 'old\n' > "$HANDOFF/stale.md"
    # fixed past timestamp: portable across GNU and BSD touch (-d '10 days ago' is GNU-only)
    touch -t 202001010000 "$HANDOFF/stale.md"
    printf '{"session_id":"sid-fresh","cwd":"/nonexistent","trigger":"auto"}' > "$JSON"
    run bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
    [ ! -e "$HANDOFF/stale.md" ]        # pruned
    [ -f "$HANDOFF/sid-fresh.md" ]      # fresh write survived
}

# ---- session-start-context.sh ---------------------------------------------

@test "session-start injects the snapshot and renames it to .consumed" {
    mkdir -p "$HANDOFF"
    printf '# RDF handoff snapshot\n- trigger: auto\n' > "$HANDOFF/sid-D.md"
    printf '{"session_id":"sid-D","source":"compact"}' > "$JSON"

    run bash "$SS" < "$JSON"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "RDF post-compaction handoff:" ]]
    [[ "$output" =~ "trigger: auto" ]]
    [ ! -e "$HANDOFF/sid-D.md" ]
    [ -f "$HANDOFF/sid-D.md.consumed" ]
}

@test "session-start emits nothing when no snapshot exists" {
    printf '{"session_id":"sid-absent","source":"compact"}' > "$JSON"
    run bash "$SS" < "$JSON"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-start is idempotent — a rerun after consume emits nothing" {
    mkdir -p "$HANDOFF"
    printf '# RDF handoff snapshot\n' > "$HANDOFF/sid-E.md"
    printf '{"session_id":"sid-E","source":"compact"}' > "$JSON"
    run bash "$SS" < "$JSON"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # second invocation: snapshot already consumed
    run bash "$SS" < "$JSON"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "session-start exits 0 on garbage stdin" {
    printf 'not json' > "$JSON"
    run bash "$SS" < "$JSON"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---- jq-absent fallback ----------------------------------------------------

@test "precompact fallback parses fields without jq (exit 0)" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    local minbin="$TEST_TMP/minbin"
    _minbin "$minbin"
    printf '{"session_id":"sid-noJQ","cwd":"/nonexistent","trigger":"manual"}' > "$JSON"

    run env PATH="$minbin" HOME="$HOME" bash "$PRE" < "$JSON"
    [ "$status" -eq 0 ]
    [ -f "$HANDOFF/sid-noJQ.md" ]
    run cat "$HANDOFF/sid-noJQ.md"
    [[ "$output" =~ "trigger: manual" ]]   # grep/sed fallback extracted the field
}

@test "session-start fallback injects without jq when snapshot present (exit 0)" {
    local minbin="$TEST_TMP/minbin"
    _minbin "$minbin"
    mkdir -p "$HANDOFF"
    printf '# RDF handoff snapshot\n- trigger: manual\n' > "$HANDOFF/sid-noJQ2.md"
    printf '{"session_id":"sid-noJQ2","source":"compact"}' > "$JSON"

    run env PATH="$minbin" HOME="$HOME" bash "$SS" < "$JSON"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "RDF post-compaction handoff:" ]]
    [ -f "$HANDOFF/sid-noJQ2.md.consumed" ]
}

@test "session-start fallback emits empty output without jq when no snapshot (exit 0)" {
    local minbin="$TEST_TMP/minbin"
    _minbin "$minbin"
    printf '{"session_id":"sid-none","source":"compact"}' > "$JSON"
    run env PATH="$minbin" HOME="$HOME" bash "$SS" < "$JSON"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
