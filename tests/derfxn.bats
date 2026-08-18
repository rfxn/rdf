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

@test "no rfxn workspace path in canonical, lib, state, bin" {
    run grep -rn '/root/admin/work/proj' "$RDF_SRC/canonical" "$RDF_SRC/lib" "$RDF_SRC/state" "$RDF_SRC/bin"
    [ "$status" -ne 0 ]
}

@test "subagent-stop falls back to HOME .rdf without hardcoded path" {
    local h; h="$(mktemp -d)"
    cd "$FIX"
    run bash -c 'echo "{\"agent_id\":\"t\"}" | HOME="$1" bash "$2/canonical/scripts/subagent-stop.sh"' -- "$h" "$RDF_SRC"
    [ "$status" -eq 0 ]
    grep -q AGENT_STOP "$h/.rdf/agent-feed.log"
    # middle branch (spec 11b): cwd has .rdf/ but no work-output/ → local log, not HOME
    mkdir "$FIX/.rdf"
    run bash -c 'echo "{\"agent_id\":\"t\"}" | HOME="$1" bash "$2/canonical/scripts/subagent-stop.sh"' -- "$h" "$RDF_SRC"
    [ "$status" -eq 0 ]
    grep -q AGENT_STOP "$FIX/.rdf/agent-feed.log"
    rm -rf "$h"
}

@test "subagent-stop exits 0 when HOME unset" {
    cd "$FIX"
    run bash -c 'echo "{\"agent_id\":\"t\"}" | env -u HOME bash "$1/canonical/scripts/subagent-stop.sh"' -- "$RDF_SRC"
    [ "$status" -eq 0 ]
}
