#!/usr/bin/env bats
# tests/scale-ceremony.bats — RDF 3.5 scale-adaptive ceremony
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# shellcheck disable=SC2154,SC2164,SC1090,SC1091

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

setup() {
    TEST_PROJ="$(mktemp -d)"
    mkdir -p "${TEST_PROJ}/.rdf"
    export _TEST_PROJ="$TEST_PROJ"
}
teardown() { rm -rf "${_TEST_PROJ}" 2>/dev/null || true; } # cleanup, ignore errors

@test "tier pointer roundtrip + invalid rejected" {
    run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=test-sess;
                 rdf_set_active_tier quick-plan "$1"; rdf_active_tier "$1"' -- "$TEST_PROJ" "$RDF_SRC"
    [ "$status" -eq 0 ]
    [ "$output" = "quick-plan" ]
    run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=test-sess;
                 rdf_set_active_tier bogus "$1"' -- "$TEST_PROJ" "$RDF_SRC"
    [ "$status" -eq 1 ]
}

@test "rdf_active_tier defaults to full" {
    run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=fresh-sess;
                 rdf_active_tier "$1"' -- "$TEST_PROJ" "$RDF_SRC"
    [ "$status" -eq 0 ]
    [ "$output" = "full" ]
}

@test "plan Tier marker overrides the session pointer (S3)" {
    # session pointer says full, but a resolved plan marker says bugfix → bugfix wins
    printf '**Plan Version:** 3.6\n**Tier:** bugfix\n' > "${TEST_PROJ}/p.md"
    printf '%s\n' "${TEST_PROJ}/p.md" > "${TEST_PROJ}/.rdf/active-plan-marktest"
    run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=marktest;
                 rdf_set_active_tier full "$1"; rdf_active_tier "$1"' -- "$TEST_PROJ" "$RDF_SRC"
    [ "$status" -eq 0 ]
    [ "$output" = "bugfix" ]   # marker authoritative; pointer reconciled
}

@test "r-plan preamble template carries Tier marker and condensed paths" {
    grep -q '\*\*Tier:\*\*' "${RDF_SRC}/canonical/commands/r-plan.md"
    grep -q 'quickplan' "${RDF_SRC}/canonical/commands/r-plan.md"
    grep -q 'failing regression test' "${RDF_SRC}/canonical/commands/r-plan.md"
}

@test "consistency check passes consistent plan" {
    run bash "${RDF_SRC}/state/rdf-consistency.sh" check "${RDF_SRC}/tests/fixtures/tiers/consistent-plan.md"
    [ "$status" -eq 0 ]
}
@test "consistency check blocks File-Map/phase mismatch" {
    run bash "${RDF_SRC}/state/rdf-consistency.sh" check "${RDF_SRC}/tests/fixtures/tiers/mismatch-plan.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ghost.sh"* ]]
}
@test "consistency check covers a comma-list Files line (M2 multi-path)" {
    # commalist-plan.md has `- Create: `a.sh`, `b.sh`` and File Map lists both.
    run bash "${RDF_SRC}/state/rdf-consistency.sh" check "${RDF_SRC}/tests/fixtures/tiers/commalist-plan.md"
    [ "$status" -eq 0 ]   # single-capture parse would flag b.sh uncovered → 2
}
@test "consistency check warns on uncovered goal" {
    # consistent structurally but spec Goal 9 unreferenced → exit 1
    run bash "${RDF_SRC}/state/rdf-consistency.sh" check \
        "${RDF_SRC}/tests/fixtures/tiers/consistent-plan.md" \
        "${RDF_SRC}/tests/fixtures/tiers/spec-with-extra-goal.md"
    [ "$status" -eq 1 ]
}
@test "--warn-only downgrades a structural error to a warning" {
    run bash "${RDF_SRC}/state/rdf-consistency.sh" check --warn-only "${RDF_SRC}/tests/fixtures/tiers/mismatch-plan.md"
    [ "$status" -eq 1 ]   # exit 2 → 1 under --warn-only
}

@test "r-spec documents tier flags and clarify skip" {
    grep -q -- '--quick' "${RDF_SRC}/canonical/commands/r-spec.md"
    grep -q -- '--bugfix' "${RDF_SRC}/canonical/commands/r-spec.md"
    grep -q 'rdf_set_active_tier' "${RDF_SRC}/canonical/commands/r-spec.md"
    grep -q 'skipped for .*bugfix' "${RDF_SRC}/canonical/commands/r-spec.md"
}
