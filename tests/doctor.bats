#!/usr/bin/env bats
# tests/doctor.bats — BATS tests for rdf doctor check helpers
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: fixture project trees under mktemp; sources doctor.sh check
# helpers directly. Harness pattern mirrors tests/plugin-adapter.bats.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2088

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

# Usage: _run_doc_stats <project_root> — prints _RESULTS rows one per line
_run_doc_stats() {
    local project_root="$1"
    bash -c '
        set -euo pipefail
        rdf_src="$1"
        project_root="$2"
        RDF_HOME="$(mktemp -d)"
        RDF_LIBDIR="${rdf_src}/lib"
        RDF_VERSION="0.0.0-test"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/doctor.sh"
        _reset_results
        _check_doc_stats "$project_root"
        if [ "${#_RESULTS[@]}" -gt 0 ]; then
            printf "%s\n" "${_RESULTS[@]}"
        fi
    ' -- "$RDF_SRC" "$project_root"
}

@test "doc-stats FAILs when a claimed count drifts" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical/commands" "$fix/canonical/agents"
    touch "$fix/canonical/commands/r-a.md" "$fix/canonical/commands/r-util-b.md"
    printf '### Lifecycle Commands (9)\n### Utility Commands (1)\n' > "$fix/WORKFORCE.md"
    run _run_doc_stats "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-stats|FAIL|WORKFORCE.md: lifecycle claims 9, actual 1"* ]]
    [[ "$output" == *"doc-stats|OK|WORKFORCE.md: utility = 1"* ]]
    rm -rf "$fix"
}

@test "doc-stats passes on the live repo (no FAIL rows)" {
    run _run_doc_stats "$RDF_SRC"
    [ "$status" -eq 0 ]
    [[ "$output" != *"|FAIL|"* ]]
    [[ "$output" == *"doc-stats|OK|WORKFORCE.md: lifecycle"* ]]
    [[ "$output" == *"doc-stats|OK|docs/index.md: commands"* ]]
}

@test "doc-stats is a no-op for projects without canonical/" {
    fix="$(mktemp -d)"
    printf '### Lifecycle Commands (9)\n' > "$fix/WORKFORCE.md"
    run _run_doc_stats "$fix"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    rm -rf "$fix"
}

@test "deps check reports jq: OK when present, WARN when masked" {
    run bash -c '
        set -euo pipefail
        rdf_src="$1"
        RDF_HOME="$(mktemp -d)"
        RDF_LIBDIR="${rdf_src}/lib"
        RDF_VERSION="0.0.0-test"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/doctor.sh"
        _reset_results
        _check_deps
        maskbin="$(mktemp -d)"
        for b in bash grep sed; do
            p="$(command -v "$b" 2>/dev/null)" || continue
            ln -s "$p" "$maskbin/$b"
        done
        PATH="$maskbin"
        _check_deps
        printf "%s\n" "${_RESULTS[@]}"
    ' -- "$RDF_SRC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deps|OK|jq present"* ]]
    [[ "$output" == *"deps|WARN|jq not found"* ]]
}
