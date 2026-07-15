#!/usr/bin/env bats
# tests/cmd-migrate-init.bats — coverage for `rdf migrate` and `rdf init`
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Targets the upgrade-path / first-run logic the audit flagged as untested:
# migrate's documented exit codes + real .claude/→.rdf/ move, and init's
# argument validation + dry-run no-write guarantee. Black-box via bin/rdf so
# the real bootstrap/sourcing path is exercised. HOME is pinned to the temp
# dir so nothing touches the developer's ~/.claude.

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RDF="$RDF_SRC/bin/rdf"

setup() {
    TEST_TMP="$(mktemp -d)"
    TEST_TMP="$(cd "$TEST_TMP" && pwd -P)"
    export HOME="$TEST_TMP/home"
    command mkdir -p "$HOME"
}

teardown() {
    command rm -rf "$TEST_TMP"
}

_mkrepo() { command mkdir -p "$1"; git -C "$1" init -q; }

# ---- rdf migrate ----------------------------------------------------------

@test "migrate help exits 0" {
    run bash "$RDF" migrate --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: rdf migrate" ]]
}

@test "migrate on a non-git directory reports and skips (exit 1)" {
    command mkdir -p "$TEST_TMP/plain"
    run bash "$RDF" migrate "$TEST_TMP/plain"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a git repo" ]]
}

@test "migrate on a fresh git project has nothing to do (exit 2)" {
    _mkrepo "$TEST_TMP/fresh"
    run bash "$RDF" migrate "$TEST_TMP/fresh"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "fresh project" ]]
}

@test "migrate on an already-migrated project is idempotent (exit 2)" {
    _mkrepo "$TEST_TMP/done"
    command mkdir -p "$TEST_TMP/done/.rdf/governance"
    run bash "$RDF" migrate "$TEST_TMP/done"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "already migrated" ]]
}

@test "migrate --dry-run leaves the source tree untouched (exit 0)" {
    _mkrepo "$TEST_TMP/dry"
    command mkdir -p "$TEST_TMP/dry/.claude/governance"
    printf '# index\n' > "$TEST_TMP/dry/.claude/governance/index.md"
    run bash "$RDF" migrate --dry-run "$TEST_TMP/dry"
    [ "$status" -eq 0 ]
    [ -d "$TEST_TMP/dry/.claude/governance" ]     # source intact
    [ ! -d "$TEST_TMP/dry/.rdf/governance" ]       # nothing written
}

@test "migrate moves .claude/governance and work-output into .rdf/ (upgrade path)" {
    local repo="$TEST_TMP/live"
    _mkrepo "$repo"
    command mkdir -p "$repo/.claude/governance" "$repo/work-output"
    printf '# index\n' > "$repo/.claude/governance/index.md"
    printf '# constraints\n' > "$repo/.claude/governance/constraints.md"
    printf 'artifact\n' > "$repo/work-output/phase-1.md"
    printf '.claude/\nwork-output/\n' > "$repo/.git/info/exclude"

    run bash "$RDF" migrate "$repo"
    [ "$status" -eq 0 ]
    [ -f "$repo/.rdf/governance/index.md" ]
    [ -f "$repo/.rdf/governance/constraints.md" ]
    [ -f "$repo/.rdf/work-output/phase-1.md" ]
    [ ! -d "$repo/.claude/governance" ]            # old location removed
    grep -qxF '.rdf/' "$repo/.git/info/exclude"    # exclude rewritten
}

@test "migrate detects the conflict state (both governance dirs) with exit 3" {
    local repo="$TEST_TMP/conflict"
    _mkrepo "$repo"
    command mkdir -p "$repo/.claude/governance" "$repo/.rdf/governance"
    printf 'a\n' > "$repo/.claude/governance/index.md"
    printf 'b\n' > "$repo/.rdf/governance/index.md"
    run bash "$RDF" migrate "$repo"
    [ "$status" -eq 3 ]
    [[ "$output" =~ "conflict" ]]
}

# ---- rdf init -------------------------------------------------------------

@test "init help exits 0" {
    run bash "$RDF" init --help
    [ "$status" -eq 0 ]
}

@test "init with no path errors (exit 1)" {
    run bash "$RDF" init
    [ "$status" -eq 1 ]
    [[ "$output" =~ "missing path" ]]
}

@test "init on a nonexistent directory errors (exit 1)" {
    run bash "$RDF" init "$TEST_TMP/does-not-exist"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "directory not found" ]]
}

@test "init --dry-run writes nothing (exit 0)" {
    _mkrepo "$TEST_TMP/idry"
    run bash "$RDF" init --dry-run "$TEST_TMP/idry" </dev/null
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_TMP/idry/.rdf" ]
}
