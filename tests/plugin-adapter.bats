#!/usr/bin/env bats
# tests/plugin-adapter.bats — BATS tests for the RDF claude-plugin adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: fresh temp RDF home + temp output dir per test. Harness
# pattern mirrors tests/adapter.bats.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

# Usage: _generate_plugin <test_home> <output_dir>
_generate_plugin() {
    local test_home="$1"
    local output_dir="$2"
    bash -c '
        set -euo pipefail
        rdf_src="$1"
        test_home="$2"
        output_dir="$3"
        RDF_HOME="$test_home"
        RDF_LIBDIR="${rdf_src}/lib"
        RDF_VERSION="0.0.0-test"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        rdf_profile_init
        _CPL_ADAPTER_DIR="${RDF_ADAPTERS}/claude-plugin"
        _CPL_OUTPUT_DIR="$output_dir"
        source "${rdf_src}/adapters/claude-plugin/adapter.sh"
        _CPL_OUTPUT_DIR="$output_dir"
        rdf_require_dir "$RDF_CANONICAL" "canonical directory"
        rdf_require_bin jq
        cpl_generate_commands
    ' -- "$RDF_SRC" "$test_home" "$output_dir"
}

setup() {
    TEST_HOME="$(mktemp -d)"
    TEST_OUT="$(mktemp -d)"

    mkdir -p \
        "${TEST_HOME}/canonical/commands" \
        "${TEST_HOME}/canonical/agents" \
        "${TEST_HOME}/canonical/scripts" \
        "${TEST_HOME}/adapters/claude-plugin" \
        "${TEST_HOME}/adapters/claude-code/hooks" \
        "${TEST_HOME}/.claude-plugin" \
        "${TEST_HOME}/profiles/core" \
        "${TEST_HOME}/state"

    cp "${RDF_SRC}/tests/fixtures/canonical/commands/r-example.md" \
        "${TEST_HOME}/canonical/commands/r-example.md"
    cp "${RDF_SRC}/tests/fixtures/canonical/commands/r-example-extra.md" \
        "${TEST_HOME}/canonical/commands/r-example-extra.md"
    cp "${RDF_SRC}/tests/fixtures/canonical/commands/r-caller.md" \
        "${TEST_HOME}/canonical/commands/r-caller.md"
    cp "${RDF_SRC}/tests/fixtures/canonical/agents/example.md" \
        "${TEST_HOME}/canonical/agents/example.md"

    echo "0.0.0-test" > "${TEST_HOME}/VERSION"
    touch "${TEST_HOME}/.rdf-profiles"

    export _TEST_HOME="$TEST_HOME"
    export _TEST_OUT="$TEST_OUT"
}

teardown() {
    rm -rf "${_TEST_HOME}" "${_TEST_OUT}" 2>/dev/null || true # ignore errors on cleanup
}

@test "plugin generator writes commands under output dir" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    [ -d "${_TEST_OUT}/commands" ]
    [ -f "${_TEST_OUT}/commands/r-caller.md" ]
    [ -f "${_TEST_OUT}/commands/r-example.md" ]
    [ -f "${_TEST_OUT}/commands/r-example-extra.md" ]
}

@test "plugin commands rewrite /r-X cross-refs to /rdf:r-X" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    grep -q '`/rdf:r-example`' "${_TEST_OUT}/commands/r-caller.md"
    grep -q '^/rdf:r-example at line start' "${_TEST_OUT}/commands/r-caller.md"
    grep -q '(/rdf:r-example)' "${_TEST_OUT}/commands/r-caller.md"
    grep -q '|/rdf:r-example|' "${_TEST_OUT}/commands/r-caller.md"
}

@test "rewrite does not touch path-like r- strings" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    grep -q 'canonical/commands/r-example\.md' "${_TEST_OUT}/commands/r-caller.md"
    run grep 'canonical/commands/rdf:' "${_TEST_OUT}/commands/r-caller.md"
    [ "$status" -ne 0 ]
}

@test "rewrite handles prefix-colliding command names" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    # longer name rewritten atomically
    grep -q 'run /rdf:r-example-extra for' "${_TEST_OUT}/commands/r-caller.md"
    # no leftover un-namespaced occurrence of the longer name
    run grep ' /r-example-extra' "${_TEST_OUT}/commands/r-caller.md"
    [ "$status" -ne 0 ]
}

@test "generate claude-plugin target is wired into cmd_generate" {
    grep -q 'claude-plugin)' "${RDF_SRC}/lib/cmd/generate.sh"
    grep -q 'cpl_generate_all' "${RDF_SRC}/lib/cmd/generate.sh"
    grep -q 'claude-plugin' <(bash "${RDF_SRC}/bin/rdf" generate help)
}
