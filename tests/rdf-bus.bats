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
