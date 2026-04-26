#!/usr/bin/env bats
# tests/rdf-bus.bats — Unit tests for state/rdf-bus.sh
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    unset RDF_SESSION_ID
    # shellcheck disable=SC1091
    source "$RDF_SRC/state/rdf-bus.sh"
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    command rm -rf "$TEST_TMP"
}

@test "rdf_session_init generates valid UUIDv7" {
    rdf_session_init
    [[ "$RDF_SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

@test "rdf_session_init preserves pre-set RDF_SESSION_ID" {
    RDF_SESSION_ID="01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
    export RDF_SESSION_ID
    rdf_session_init
    [ "$RDF_SESSION_ID" = "01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105" ]
}

@test "rdf_scoped_filename appends session ID before extension" {
    RDF_SESSION_ID="01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
    export RDF_SESSION_ID
    result="$(rdf_scoped_filename ".rdf/work-output/vpe-progress.md")"
    [ "$result" = ".rdf/work-output/vpe-progress-01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105.md" ]
}

@test "rdf_session_short returns last 12 chars" {
    RDF_SESSION_ID="01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
    export RDF_SESSION_ID
    [ "$(rdf_session_short)" = "a4b3f9c2e105" ]
}

@test "rdf_parse_phase_scope extracts Files paths from fixture PLAN" {
    printf '%s\n' \
        '### Phase 5: Example' \
        '- Create: `state/foo.sh`' \
        '- Modify: `canonical/agents/qa.md`' \
        '' \
        '### Phase 6: Other' \
        > "$TEST_TMP/PLAN.md"
    output="$(rdf_parse_phase_scope "$TEST_TMP/PLAN.md" 5)"
    [[ "$output" == *"ALLOWED_REGEX=state/foo\\.sh|canonical/agents/qa\\.md"* ]]
}

@test "rdf_parse_phase_scope extracts Tests-may-touch when present" {
    printf '%s\n' \
        '### Phase 7: Example' \
        '- Modify: `canonical/x.md`' \
        '**Tests-may-touch:** tests/fixtures/*.json, tests/helpers/*.bash' \
        '' \
        '### Phase 8: Other' \
        > "$TEST_TMP/PLAN.md"
    output="$(rdf_parse_phase_scope "$TEST_TMP/PLAN.md" 7)"
    [[ "$output" == *"FLEX_REGEX=tests/fixtures/[^/]*\\.json|tests/helpers/[^/]*\\.bash"* ]]
    [[ "$output" == *"FLEX_FILE_CEILING=3"* ]]
    [[ "$output" == *"FLEX_LINE_CEILING=30"* ]]
}

# Helper: run pre-commit hook in a fixture git repo with mocked PLAN.md
_setup_fixture_repo() {
    local repo="$1" phase_n="$2"
    command mkdir -p "$repo/state"
    git -C "$repo" init -q
    git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "root"
    git -C "$repo" checkout -q -b "rdf/phase-${phase_n}-01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
    # Commit infrastructure files before installing hook (hook enforces scope
    # and would reject PLAN.md/rdf-bus.sh if they were staged without a phase entry).
    command cp "$RDF_SRC/state/rdf-bus.sh" "$repo/state/"
    printf '%s\n' '### Phase 0: Init' > "$repo/PLAN.md"
    git -C "$repo" add state/rdf-bus.sh PLAN.md
    git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "infra"
    # Install hook after infrastructure is committed.
    command cp "$RDF_SRC/state/git-hooks/pre-commit" "$repo/.git/hooks/"
    command chmod +x "$repo/.git/hooks/pre-commit"
}

@test "pre-commit hook rejects out-of-scope commit" {
    _setup_fixture_repo "$TEST_TMP/repo" 1
    # Write PLAN.md to filesystem (hook reads it) but do NOT stage it.
    printf '%s\n' '### Phase 1: Test' '- Modify: `state/foo.sh`' > "$TEST_TMP/repo/PLAN.md"
    command mkdir -p "$TEST_TMP/repo/state"
    echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
    echo "echo bad" > "$TEST_TMP/repo/state/bad.sh"
    git -C "$TEST_TMP/repo" add state/foo.sh state/bad.sh
    run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SCOPE VIOLATION"* ]]
}

@test "pre-commit hook accepts in-scope commit" {
    _setup_fixture_repo "$TEST_TMP/repo" 1
    # Write PLAN.md to filesystem (hook reads it) but do NOT stage it.
    printf '%s\n' '### Phase 1: Test' '- Modify: `state/foo.sh`' > "$TEST_TMP/repo/PLAN.md"
    command mkdir -p "$TEST_TMP/repo/state"
    echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
    git -C "$TEST_TMP/repo" add state/foo.sh
    run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
    [ "$status" -eq 0 ]
}

@test "pre-commit hook accepts flex-zone commit under ceilings" {
    _setup_fixture_repo "$TEST_TMP/repo" 1
    # Write PLAN.md to filesystem (hook reads it) but do NOT stage it.
    printf '%s\n' \
        '### Phase 1: Test' \
        '- Modify: `state/foo.sh`' \
        '**Tests-may-touch:** tests/fixtures/*.json' \
        > "$TEST_TMP/repo/PLAN.md"
    command mkdir -p "$TEST_TMP/repo/state" "$TEST_TMP/repo/tests/fixtures"
    echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
    echo '{"a":1}' > "$TEST_TMP/repo/tests/fixtures/x.json"
    git -C "$TEST_TMP/repo" add state/foo.sh tests/fixtures/x.json
    run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
    [ "$status" -eq 0 ]
}

@test "pre-commit hook rejects flex-zone commit over file ceiling" {
    _setup_fixture_repo "$TEST_TMP/repo" 1
    # Write PLAN.md to filesystem (hook reads it) but do NOT stage it.
    printf '%s\n' \
        '### Phase 1: Test' \
        '- Modify: `state/foo.sh`' \
        '**Tests-may-touch:** tests/fixtures/*.json' \
        > "$TEST_TMP/repo/PLAN.md"
    command mkdir -p "$TEST_TMP/repo/state" "$TEST_TMP/repo/tests/fixtures"
    echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
    for i in 1 2 3 4; do echo "{\"$i\":$i}" > "$TEST_TMP/repo/tests/fixtures/x$i.json"; done
    git -C "$TEST_TMP/repo" add state/foo.sh tests/fixtures/
    run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"flex zone"* ]] || [[ "$output" == *"ceiling"* ]]
}

@test "rdf_parse_phase_scope escapes regex metacharacters in paths" {
    printf '%s\n' \
        '### Phase 9: Localization' \
        '- Modify: `docs/i18n/[en]/index.md`' \
        '- Create: `lib/util(plus).sh`' \
        '- Create: `lib/v1+util.sh`' \
        '- Create: `lib/util?.sh`' \
        '' \
        '### Phase 10: Other' \
        > "$TEST_TMP/PLAN.md"
    output="$(rdf_parse_phase_scope "$TEST_TMP/PLAN.md" 9)"
    # Verify [en] escaped, () escaped, +/? escaped — not parsed as regex char class/group/quantifier
    [[ "$output" == *"docs/i18n/\\[en\\]/index\\.md"* ]]
    [[ "$output" == *"lib/util\\(plus\\)\\.sh"* ]]
    [[ "$output" == *"lib/v1\\+util\\.sh"* ]]
    [[ "$output" == *"lib/util\\?\\.sh"* ]]
}
