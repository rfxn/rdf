#!/usr/bin/env bats
# tests/rules-deploy.bats — RDF 3.4 T3: paths-scoped governance rules + opt-in deploy
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: fresh temp RDF home + temp output dir per test. Harness pattern
# mirrors tests/plugin-adapter.bats — cc_generate_rules is exercised by
# sourcing the adapter directly against a temp _CC_OUTPUT_DIR (never via
# 'rdf generate', which would race a concurrent output-dir atomic swap).
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2088

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

# Usage: _generate_rules <test_home> <output_dir>
_generate_rules() {
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
        _CC_OUTPUT_DIR="$output_dir"
        source "${rdf_src}/adapters/claude-code/adapter.sh"
        _CC_OUTPUT_DIR="$output_dir"
        cc_generate_rules
    ' -- "$RDF_SRC" "$test_home" "$output_dir"
}

# Usage: _make_deploy_skeleton <fix_home> — minimal claude-code output tree so
# a real deploy proceeds past the pre-flight (cc output is local-only, absent on
# a CI checkout).
_make_deploy_skeleton() {
    local fix_home="$1"
    local out="${fix_home}/adapters/claude-code/output"
    mkdir -p "${out}/agents" "${out}/commands" "${out}/scripts" \
             "${out}/governance" "${out}/rules"
    touch "${out}/commands/x.md" "${out}/governance/core-governance.md" \
          "${out}/rules/core.md"
}

# Usage: _run_deploy <fix_home> [extra cmd_deploy args...]
_run_deploy() {
    local fix_home="$1"; shift
    bash -c '
        set -euo pipefail
        rdf_src="$1"; fix_home="$2"; shift 2
        HOME="$fix_home"
        RDF_HOME="$fix_home"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/deploy.sh"
        cmd_deploy "$@" claude-code
    ' -- "$RDF_SRC" "$fix_home" "$@"
}

setup() {
    TEST_HOME="$(mktemp -d)"
    TEST_OUT="$(mktemp -d)"
    mkdir -p "${TEST_HOME}/profiles/core" \
             "${TEST_HOME}/profiles/python" \
             "${TEST_HOME}/profiles/shell"
    cp "${RDF_SRC}/profiles/registry.json" "${TEST_HOME}/profiles/registry.json"
    cp "${RDF_SRC}/profiles/core/governance-template.md" \
        "${TEST_HOME}/profiles/core/governance-template.md"
    cp "${RDF_SRC}/profiles/python/governance-template.md" \
        "${TEST_HOME}/profiles/python/governance-template.md"
    cp "${RDF_SRC}/profiles/shell/governance-template.md" \
        "${TEST_HOME}/profiles/shell/governance-template.md"
    printf 'python\nshell\n' > "${TEST_HOME}/.rdf-profiles"
    echo "0.0.0-test" > "${TEST_HOME}/VERSION"
    export _TEST_HOME="$TEST_HOME" _TEST_OUT="$TEST_OUT"
}

teardown() {
    rm -rf "${_TEST_HOME}" "${_TEST_OUT}" 2>/dev/null || true # ignore cleanup errors
}

@test "core rule has no paths frontmatter; python rule has paths from detect globs" {
    _generate_rules "${_TEST_HOME}" "${_TEST_OUT}"
    [ -f "${_TEST_OUT}/rules/core.md" ]
    run head -1 "${_TEST_OUT}/rules/core.md"
    [ "$output" != "---" ]
    [ -f "${_TEST_OUT}/rules/python.md" ]
    run head -1 "${_TEST_OUT}/rules/python.md"
    [ "$output" = "---" ]
    grep -q '"\*\*/\*.py"' "${_TEST_OUT}/rules/python.md"
}

@test "directory detect glob maps to a recursive **/dir/** path" {
    _generate_rules "${_TEST_HOME}" "${_TEST_OUT}"
    # shell profile detects files/ (a directory glob) → **/files/**
    grep -q '"\*\*/files/\*\*"' "${_TEST_OUT}/rules/shell.md"
    # ...and *.sh (an extension glob) → **/*.sh
    grep -q '"\*\*/\*.sh"' "${_TEST_OUT}/rules/shell.md"
}

@test "generate emits one rule per active profile" {
    _generate_rules "${_TEST_HOME}" "${_TEST_OUT}"
    local rules
    rules="$(find "${_TEST_OUT}/rules" -name '*.md' | wc -l)"
    [ "$rules" -eq 3 ]   # core + python + shell (from .rdf-profiles)
}

@test "only-core repo emits rules/core.md and nothing scoped" {
    : > "${_TEST_HOME}/.rdf-profiles"   # deactivate python/shell — core only
    _generate_rules "${_TEST_HOME}" "${_TEST_OUT}"
    [ -f "${_TEST_OUT}/rules/core.md" ]
    [ ! -f "${_TEST_OUT}/rules/python.md" ]
    run head -1 "${_TEST_OUT}/rules/core.md"
    [ "$output" != "---" ]
}

@test "deploy omits rules symlink by default (opt-in)" {
    FIX_HOME="$(mktemp -d)"
    _make_deploy_skeleton "$FIX_HOME"
    run _run_deploy "$FIX_HOME"
    [ "$status" -eq 0 ]
    [ ! -e "${FIX_HOME}/.claude/rules" ]     # rules NOT deployed without --rules
    [ -L "${FIX_HOME}/.claude/governance" ]  # sanity: governance IS deployed
    rm -rf "$FIX_HOME"
}

@test "deploy --rules creates the rules symlink" {
    FIX_HOME="$(mktemp -d)"
    _make_deploy_skeleton "$FIX_HOME"
    run _run_deploy "$FIX_HOME" --rules
    [ "$status" -eq 0 ]
    [ -L "${FIX_HOME}/.claude/rules" ]
    [ "$(readlink "${FIX_HOME}/.claude/rules")" = "${FIX_HOME}/adapters/claude-code/output/rules" ]
    rm -rf "$FIX_HOME"
}
