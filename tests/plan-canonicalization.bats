#!/usr/bin/env bats
# tests/plan-canonicalization.bats — plan canonicalization resolver lifecycle
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

setup() {
    TEST_TMP="$(mktemp -d)"
    mkdir -p "$TEST_TMP/proj/.rdf" "$TEST_TMP/proj/docs/plans"
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../state/rdf-bus.sh"
    RDF_SESSION_ID="01900000-0000-7000-8000-000000000001"
    export RDF_SESSION_ID
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "rdf_active_plan_path resolves session-scoped pointer" {
    printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/foo.md"
    printf '%s\n' "$TEST_TMP/proj/docs/plans/foo.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
    run rdf_active_plan_path "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/proj/docs/plans/foo.md" ]
}

@test "rdf_active_plan_path falls back to un-suffixed pointer" {
    printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/bar.md"
    printf '%s\n' "$TEST_TMP/proj/docs/plans/bar.md" > "$TEST_TMP/proj/.rdf/active-plan"
    run rdf_active_plan_path "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/proj/docs/plans/bar.md" ]
}

@test "rdf_active_plan_path returns PLAN.md as last resort" {
    printf '%s\n' '# Legacy Plan' > "$TEST_TMP/proj/PLAN.md"
    run rdf_active_plan_path "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/proj/PLAN.md" ]
}

@test "rdf_active_plan_path returns 1 when nothing exists" {
    run rdf_active_plan_path "$TEST_TMP/proj"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "rdf_active_plan_path skips empty pointer and falls through" {
    : > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
    printf '%s\n' '# Legacy' > "$TEST_TMP/proj/PLAN.md"
    run rdf_active_plan_path "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/proj/PLAN.md" ]
}

@test "rdf_active_plan_path skips pointer to nonexistent file" {
    printf '%s\n' "$TEST_TMP/proj/docs/plans/missing.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
    printf '%s\n' '# Legacy' > "$TEST_TMP/proj/PLAN.md"
    run rdf_active_plan_path "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/proj/PLAN.md" ]
}

@test "rdf_active_plan_path strips CRLF from pointer content" {
    printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/baz.md"
    printf '%s\r\n' "$TEST_TMP/proj/docs/plans/baz.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
    run rdf_active_plan_path "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/proj/docs/plans/baz.md" ]
}

@test "rdf_set_active_plan writes session-scoped pointer" {
    printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/qux.md"
    run rdf_set_active_plan "$TEST_TMP/proj/docs/plans/qux.md" "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}" ]
    pointer_content="$(< "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}")"
    [ "$pointer_content" = "$TEST_TMP/proj/docs/plans/qux.md" ]
}

@test "rdf_set_active_plan absolutizes relative paths" {
    printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/rel.md"
    cd "$TEST_TMP/proj"
    run rdf_set_active_plan "docs/plans/rel.md" "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    pointer_content="$(< "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}")"
    [[ "$pointer_content" == /* ]]
}

@test "rdf_set_active_plan rejects nonexistent path" {
    run rdf_set_active_plan "/no/such/file.md" "$TEST_TMP/proj"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "does not exist" ]]
}

@test "rdf_clear_active_plan removes session pointer" {
    printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/clear.md"
    printf '%s\n' "$TEST_TMP/proj/docs/plans/clear.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
    run rdf_clear_active_plan "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}" ]
}

@test "rdf_clear_active_plan is idempotent" {
    run rdf_clear_active_plan "$TEST_TMP/proj"
    [ "$status" -eq 0 ]
}

@test "two RDF_SESSION_IDs maintain independent pointers" {
    printf '%s\n' '# Plan A' > "$TEST_TMP/proj/docs/plans/a.md"
    printf '%s\n' '# Plan B' > "$TEST_TMP/proj/docs/plans/b.md"
    RDF_SESSION_ID="01900000-0000-7000-8000-000000000AAA" \
      rdf_set_active_plan "$TEST_TMP/proj/docs/plans/a.md" "$TEST_TMP/proj"
    RDF_SESSION_ID="01900000-0000-7000-8000-000000000BBB" \
      rdf_set_active_plan "$TEST_TMP/proj/docs/plans/b.md" "$TEST_TMP/proj"
    # Each pointer has independent content
    [ "$(< $TEST_TMP/proj/.rdf/active-plan-01900000-0000-7000-8000-000000000AAA)" = "$TEST_TMP/proj/docs/plans/a.md" ]
    [ "$(< $TEST_TMP/proj/.rdf/active-plan-01900000-0000-7000-8000-000000000BBB)" = "$TEST_TMP/proj/docs/plans/b.md" ]
}

@test "canonical PLAN.md references are scoped to legacy/fallback context" {
    # Guards against new hardcoded PLAN.md read paths being added. Existing
    # references in docs, comments, and legacy-fallback code are counted here;
    # threshold is set above the current baseline to catch regressions.
    local hits
    hits=$(grep -rn '\bPLAN\.md\b' \
        "$RDF_SRC/canonical/" "$RDF_SRC/lib/" "$RDF_SRC/state/" 2>/dev/null | \
        grep -vE 'legacy|fallback|LEGACY|FALLBACK|output-text' | wc -l)
    [ "$hits" -le 20 ]
}

@test ".gitignore includes plan + pointer patterns" {
    local count
    count=$(grep -cE '^PLAN(\*|-\*)?\.md$|^\.rdf/active-plan' "$RDF_SRC/.gitignore")
    [ "$count" -eq 4 ]
}
