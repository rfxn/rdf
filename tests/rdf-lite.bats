#!/usr/bin/env bats
# tests/rdf-lite.bats — RDF 3.4 Phase 7: rdf-lite minimal deploy variant
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# The lite variant is a thin generation mode: rules/core.md is sourced from
# profiles/lite/governance-lite.md (condensed core), hooks.json is not emitted,
# and only the lifecycle command set ships. Default (no --lite) generation must
# stay byte-identical. Hermetic: the adapter is sourced against the real
# RDF_HOME with output redirected to a temp dir (never 'rdf generate', which a
# concurrent phase owns), mirroring tests/rules-deploy.bats. The computed
# lite_boot_tokens<=1000 guard lives in tests/overhead.bats; this file guards
# the generation variant and the lite source budget that drives that figure.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC
LITE_SRC="$RDF_SRC/profiles/lite/governance-lite.md"
FULL_CORE="$RDF_SRC/profiles/core/governance-template.md"

# _generate <output_dir> <lite 0|1> — source the adapter against the real repo
# and run the full CC pipeline into a temp output dir (no 'rdf generate').
_generate() {
    bash -c '
        set -euo pipefail
        rdf_src="$1"; output_dir="$2"; lite="$3"
        RDF_HOME="$rdf_src"
        RDF_LIBDIR="${rdf_src}/lib"
        RDF_VERSION="0.0.0-test"
        export _CC_LITE="$lite"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        rdf_profile_init
        _CC_OUTPUT_DIR="$output_dir"
        source "${rdf_src}/adapters/claude-code/adapter.sh"
        _CC_OUTPUT_DIR="$output_dir"
        cc_generate_all
    ' -- "$RDF_SRC" "$1" "$2" >/dev/null 2>&1
}

setup() {
    TEST_OUT="$(mktemp -d)"
    export _TEST_OUT="$TEST_OUT"
}
teardown() {
    rm -rf "${_TEST_OUT}" "${_TEST_OUT}.new" "${_TEST_OUT}.old" 2>/dev/null || true # ignore cleanup errors
}

@test "lite generation sources condensed core into rules/core.md" {
    _generate "$_TEST_OUT" 1
    [ -f "${_TEST_OUT}/rules/core.md" ]
    # core.md is the condensed lite governance verbatim, not the full template
    run diff -q "${_TEST_OUT}/rules/core.md" "$LITE_SRC"
    [ "$status" -eq 0 ]
    local lite_b full_b
    lite_b="$(wc -c < "${_TEST_OUT}/rules/core.md")"
    full_b="$(wc -c < "$FULL_CORE")"
    [ "$lite_b" -lt "$full_b" ]
    # core stays unscoped even in lite (must survive compaction — spec 4.3)
    run head -1 "${_TEST_OUT}/rules/core.md"
    [ "$output" != "---" ]
}

@test "lite generation does not emit hooks.json" {
    _generate "$_TEST_OUT" 1
    [ ! -f "${_TEST_OUT}/hooks.json" ]
}

@test "lite generation ships only the lifecycle command set" {
    _generate "$_TEST_OUT" 1
    [ -f "${_TEST_OUT}/commands/r-spec.md" ]
    [ -f "${_TEST_OUT}/commands/r-plan.md" ]
    [ -f "${_TEST_OUT}/commands/r-build.md" ]
    [ -f "${_TEST_OUT}/commands/r-ship.md" ]
    [ -f "${_TEST_OUT}/commands/r-start.md" ]
    [ -f "${_TEST_OUT}/commands/r-save.md" ]
    [ ! -f "${_TEST_OUT}/commands/r-audit.md" ]   # utility commands excluded
    [ ! -f "${_TEST_OUT}/commands/r-vpe.md" ]
    local n
    n="$(find "${_TEST_OUT}/commands" -maxdepth 1 -name '*.md' | wc -l)"
    [ "$n" -eq 6 ]
}

@test "default generation leaves rules/core.md byte-identical to full core governance" {
    _generate "$_TEST_OUT" 0
    [ -f "${_TEST_OUT}/rules/core.md" ]
    run diff -q "${_TEST_OUT}/rules/core.md" "$FULL_CORE"
    [ "$status" -eq 0 ]
}

@test "default generation still emits hooks.json and the full command set" {
    _generate "$_TEST_OUT" 0
    [ -f "${_TEST_OUT}/hooks.json" ]
    [ -f "${_TEST_OUT}/commands/r-audit.md" ]
    local n
    n="$(find "${_TEST_OUT}/commands" -maxdepth 1 -name '*.md' | wc -l)"
    [ "$n" -gt 6 ]   # full deploy ships every command, not just lifecycle
}

@test "governance-lite.md is frontmatter-free and within the lite source budget" {
    [ -f "$LITE_SRC" ]
    run head -1 "$LITE_SRC"
    [ "$output" != "---" ]
    local b
    b="$(wc -c < "$LITE_SRC")"
    [ "$b" -le 2800 ]   # ~700 tokens (bytes/4); keeps lite_boot under Goal 8's 1000
}
