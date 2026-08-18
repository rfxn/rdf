#!/usr/bin/env bats
# tests/derfxn.bats — de-rfxn regression suite (spec 2026-08-18)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: every fixture under mktemp -d; no shared-directory scans.
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

# _rdf_call <fn-and-args...> — run an init.sh function against the checkout
_rdf_call() {
    bash -c '
        rdf_src="$1"; shift
        RDF_HOME="$rdf_src"; RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/init.sh"
        "$@"
    ' -- "$RDF_SRC" "$@"
}

setup() { FIX="$(mktemp -d)"; export FIX; }
teardown() { rm -rf "$FIX" 2>/dev/null || true; }  # cleanup, ignore errors

@test "rfxn-workspace profile is opt-in: not auto-detected, valid via --type" {
    touch "$FIX/x.sh"
    run _rdf_call _detect_profiles "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" != *rfxn-workspace* ]]
    run _rdf_call cmd_init "$FIX" --type shell,rfxn-workspace --no-memory
    [ "$status" -eq 0 ]
    grep -q 'Cross-Project Coordination' "$FIX/CLAUDE.md"
    # spec 11b: rfxn-workspace ALONE (no language profile) is also valid
    local alone; alone="$(mktemp -d)"
    run _rdf_call cmd_init "$alone" --type rfxn-workspace --no-memory
    [ "$status" -eq 0 ]
    grep -q 'Cross-Project Coordination' "$alone/CLAUDE.md"
    rm -rf "$alone"
}

@test "init on plain repo copies no cross-project.md" {
    touch "$FIX/x.sh"
    run _rdf_call cmd_init "$FIX" --type shell --no-memory
    [ "$status" -eq 0 ]
    [ ! -f "$FIX/.rdf/governance/reference/cross-project.md" ]
}
