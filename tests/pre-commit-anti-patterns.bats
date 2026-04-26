#!/usr/bin/env bats
# tests/pre-commit-anti-patterns.bats — Tests for pre-commit anti-pattern grep section
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOK="$RDF_SRC/state/git-hooks/pre-commit"
FIXTURES="$RDF_SRC/tests/fixtures/pre-commit-anti-patterns"

# _setup_repo dir — initialise a temp git repo with the hook wired in.
# Creates a rdf/phase-3-test branch and a stub PLAN.md + rdf-bus.sh so the
# existing scope-enforcement block exits cleanly (scope check FIRST).
_setup_repo() {
    local repo="$1"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b "rdf/phase-3-test"

    # Minimal PLAN.md so rdf_parse_phase_scope can find the phase scope.
    # All files are in scope (.*) so scope check never blocks.
    cat > "$repo/PLAN.md" <<'PLANEOF'
### Phase 3: test

**Files:**
- Modify: `.*`

PLANEOF

    # Stub rdf-bus.sh: provide rdf_parse_phase_scope that allows all files.
    mkdir -p "$repo/state"
    cat > "$repo/state/rdf-bus.sh" <<'BUSEOF'
rdf_parse_phase_scope() {
    printf "ALLOWED_REGEX='.*'\n"
    printf "FLEX_REGEX=''\n"
    printf "FLEX_FILE_CEILING=3\n"
    printf "FLEX_LINE_CEILING=30\n"
}
BUSEOF

    # Install the real pre-commit hook.
    mkdir -p "$repo/.git/hooks"
    cp "$HOOK" "$repo/.git/hooks/pre-commit"
    chmod +x "$repo/.git/hooks/pre-commit"

    # Initial commit so HEAD exists.
    git -C "$repo" config user.email "test@test.local"
    git -C "$repo" config user.name "Test"
    git -C "$repo" commit -q --allow-empty -m "init"
}

# _stage_fixture repo fixture_path staged_name — copy fixture into repo and stage it.
_stage_fixture() {
    local repo="$1" fixture="$2" name="$3"
    cp "$fixture" "$repo/$name"
    git -C "$repo" add "$name"
}

setup() {
    TEST_REPO="$(mktemp -d)"
    _setup_repo "$TEST_REPO"
}

teardown() {
    rm -rf "$TEST_REPO"
}

@test "clean fixture passes" {
    _stage_fixture "$TEST_REPO" "$FIXTURES/clean.sh" "clean.sh"
    run git -C "$TEST_REPO" commit -m "clean"
    [ "$status" -eq 0 ]
}

@test "bare-coreutils blocks" {
    # Stage a file that contains a bare sha256sum (no 'command' prefix)
    cat > "$TEST_REPO/bare.sh" <<'EOF'
#!/usr/bin/env bash
sha256sum /etc/hostname
EOF
    git -C "$TEST_REPO" add bare.sh
    run git -C "$TEST_REPO" commit -m "bare-coreutils"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "bare-coreutils-no-prefix" ]]
}

@test "same-line # suppresses" {
    # Same bare sha256sum but with a same-line # comment — must pass
    cat > "$TEST_REPO/suppressed.sh" <<'EOF'
#!/usr/bin/env bash
sha256sum /etc/hostname  # vendored upstream; command prefix not applicable
EOF
    git -C "$TEST_REPO" add suppressed.sh
    run git -C "$TEST_REPO" commit -m "suppressed"
    [ "$status" -eq 0 ]
}

@test "ignore.md anti-pattern-skip opts-out per class" {
    # Stage a file with bare cp (bare-coreutils-no-prefix) but opt-out in ignore.md
    mkdir -p "$TEST_REPO/governance"
    printf '# anti-pattern-skip: bare-coreutils-no-prefix\n' > "$TEST_REPO/governance/ignore.md"
    git -C "$TEST_REPO" add governance/ignore.md

    cat > "$TEST_REPO/optout.sh" <<'EOF'
#!/usr/bin/env bash
cp /src /dst
EOF
    git -C "$TEST_REPO" add optout.sh
    run git -C "$TEST_REPO" commit -m "optout"
    [ "$status" -eq 0 ]
}

@test "scope-check ordering preserved (scope first, anti-pattern second)" {
    # On a non-worktree branch the scope block exits 0 early (line ~44 of hook).
    # The anti-pattern section must NOT run before the scope block.
    # Validate by creating a branch without the rdf/phase-N prefix and confirming
    # that a file with bare coreutils is NOT blocked (hook exits 0 — scope block
    # already returned, anti-pattern section never reached).
    local repo2
    repo2="$(mktemp -d)"
    git -C "$repo2" init -q
    git -C "$repo2" checkout -q -b "feature/not-a-phase-branch"
    git -C "$repo2" config user.email "test@test.local"
    git -C "$repo2" config user.name "Test"
    git -C "$repo2" commit -q --allow-empty -m "init"

    # Install the real hook (no PLAN.md / rdf-bus.sh needed — hook exits early).
    mkdir -p "$repo2/.git/hooks"
    cp "$HOOK" "$repo2/.git/hooks/pre-commit"
    chmod +x "$repo2/.git/hooks/pre-commit"

    # Stage a file with bare coreutils — on a non-phase branch this must NOT block.
    cat > "$repo2/bare2.sh" <<'EOF'
#!/usr/bin/env bash
sha256sum /etc/hostname
EOF
    git -C "$repo2" add bare2.sh
    run git -C "$repo2" commit -m "non-phase-branch"
    rm -rf "$repo2"
    # Hook should exit 0 (scope block exited early; anti-pattern not reached).
    [ "$status" -eq 0 ]
}
