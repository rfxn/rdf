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

@test "init renders CONTRIBUTING.md for the detected stack, not shell boilerplate" {
    local py="$TEST_TMP/pyproj"
    _mkrepo "$py"
    printf 'print(1)\n' > "$py/app.py"
    printf 'flask\n' > "$py/requirements.txt"
    git -C "$py" add app.py requirements.txt
    run bash "$RDF" init "$py" --no-memory </dev/null
    [ "$status" -eq 0 ]
    grep -q 'pytest' "$py/CONTRIBUTING.md"
    run grep -e 'shellcheck' -e 'BATS' "$py/CONTRIBUTING.md"
    [ "$status" -ne 0 ]

    local sh="$TEST_TMP/shproj"
    _mkrepo "$sh"
    printf '#!/usr/bin/env bash\necho hi\n' > "$sh/tool.sh"
    git -C "$sh" add tool.sh
    run bash "$RDF" init "$sh" --no-memory </dev/null
    [ "$status" -eq 0 ]
    grep -q 'shellcheck' "$sh/CONTRIBUTING.md"
    grep -q 'make -C tests test' "$sh/CONTRIBUTING.md"

    local bare="$TEST_TMP/bareproj"
    _mkrepo "$bare"
    printf 'notes\n' > "$bare/README.md"
    run bash "$RDF" init "$bare" --no-memory </dev/null
    [ "$status" -eq 0 ]
    grep -q "Follow the conventions in CLAUDE.md" "$bare/CONTRIBUTING.md"
    run grep -e 'shellcheck' -e 'BATS' "$bare/CONTRIBUTING.md"
    [ "$status" -ne 0 ]
}

@test "init detects profiles from untracked sources in a fresh git repo" {
    local proj="$TEST_TMP/untracked"
    _mkrepo "$proj"
    printf 'print(1)\n' > "$proj/app.py"
    printf 'flask\n' > "$proj/requirements.txt"
    # deliberately not `git add` — untracked sources must still be detected
    run bash "$RDF" init "$proj" --no-memory </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" =~ "auto-detected profiles: python" ]]
}

# ---- rdf init --tools -----------------------------------------------------

@test "init --tools unknown exits 1 with the allowed list" {
    _mkrepo "$TEST_TMP/toolsbad"
    run bash "$RDF" init --tools cursor "$TEST_TMP/toolsbad" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unknown --tools value: cursor (allowed: claude-code, agent-skills, agents-md, codex, antigravity)" ]]
}

@test "init --tools '' exits 1 (empty token)" {
    _mkrepo "$TEST_TMP/toolsempty"
    run bash "$RDF" init --tools '' "$TEST_TMP/toolsempty" </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unknown --tools value:" ]]
}

@test "init --tools agent-skills,agents-md writes both artifacts" {
    local proj="$TEST_TMP/toolsboth"
    _mkrepo "$proj"
    printf '# Proj\n' > "$proj/CLAUDE.md"
    run bash "$RDF" init --tools agent-skills,agents-md --no-memory "$proj" </dev/null
    [ "$status" -eq 0 ]
    [ -L "$proj/.agents/skills" ]
    [ -f "$proj/AGENTS.md" ]
}

@test "init --tools codex expands to the composite" {
    local proj="$TEST_TMP/toolscodex"
    _mkrepo "$proj"
    run bash "$RDF" init --tools codex --no-memory "$proj" </dev/null
    [ "$status" -eq 0 ]
    [ -L "$proj/.agents/skills" ]
    [ -f "$proj/AGENTS.md" ]
}

@test "init --tools claude-code is a no-op for extra surfaces" {
    local proj="$TEST_TMP/toolscc"
    _mkrepo "$proj"
    run bash "$RDF" init --tools claude-code --no-memory "$proj" </dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$proj/.agents" ]
    [ ! -e "$proj/AGENTS.md" ]
}

@test "init --dry-run --tools prints would-write lines and writes nothing" {
    local proj="$TEST_TMP/toolsdry"
    _mkrepo "$proj"
    run bash "$RDF" init --dry-run --tools agent-skills,agents-md --no-memory "$proj" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" =~ "would symlink .agents/skills" ]]
    [[ "$output" =~ "would write AGENTS.md" ]]
    [ ! -e "$proj/.agents" ]
    [ ! -e "$proj/AGENTS.md" ]
}

@test "init --tools agents-md on a repo with AGENTS.md skips with a log" {
    local proj="$TEST_TMP/toolsskip"
    _mkrepo "$proj"
    printf 'pre-existing\n' > "$proj/AGENTS.md"
    run bash "$RDF" init --tools agents-md --no-memory "$proj" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" =~ "AGENTS.md already exists" ]]
    grep -q 'pre-existing' "$proj/AGENTS.md"
}
