#!/usr/bin/env bats
# tests/adapter.bats — BATS tests for the RDF claude-code adapter round-trip
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# These tests are hermetic: each test gets a fresh temp RDF home and a fresh
# temp output directory. Nothing is written to /root/.claude/ or ~/.rdf/.
#
# Strategy: source the real adapter.sh directly with overridden env vars rather
# than invoking bin/rdf (which hardcodes RDF_HOME from its own dirname). This
# lets the test control RDF_CANONICAL and _CC_OUTPUT_DIR precisely.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091

# Resolve the real RDF project root regardless of CWD
RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

# Helper: run the adapter cc_generate_agents + cc_generate_commands in a
# subprocess with test-controlled env vars.
# Usage: _generate <test_home> <output_dir>
_generate() {
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
        # Source rdf_common.sh — sets RDF_CANONICAL, RDF_ADAPTERS, etc. via rdf_init
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        rdf_profile_init
        # Set adapter vars pointing at the test home
        _CC_ADAPTER_DIR="${RDF_ADAPTERS}/claude-code"
        _CC_OUTPUT_DIR="$output_dir"
        _CC_AGENT_META="${_CC_ADAPTER_DIR}/agent-meta.json"
        _CC_COMMAND_META="${_CC_ADAPTER_DIR}/command-meta-v3.json"
        # Source adapter to get helper functions; adapter.sh sets _CC_OUTPUT_DIR
        # to ${RDF_ADAPTERS}/claude-code/output — override it after sourcing
        source "${rdf_src}/adapters/claude-code/adapter.sh"
        _CC_OUTPUT_DIR="$output_dir"
        rdf_require_dir "$RDF_CANONICAL" "canonical directory"
        rdf_require_file "$_CC_AGENT_META" "agent-meta.json"
        rdf_require_bin jq
        _cc_resolve_hash_cmd
        cc_generate_agents
        cc_generate_commands
    ' -- "$RDF_SRC" "$test_home" "$output_dir"
}

# ── setup / teardown ──────────────────────────────────────────────────────────

setup() {
    TEST_HOME="$(mktemp -d)"
    TEST_OUT="$(mktemp -d)"

    # Directory skeleton
    mkdir -p \
        "${TEST_HOME}/canonical/commands" \
        "${TEST_HOME}/canonical/agents" \
        "${TEST_HOME}/canonical/scripts" \
        "${TEST_HOME}/adapters/claude-code" \
        "${TEST_HOME}/profiles/core" \
        "${TEST_HOME}/state"

    # Fixture canonical files
    cp "${RDF_SRC}/tests/fixtures/canonical/commands/r-example.md" \
        "${TEST_HOME}/canonical/commands/r-example.md"
    cp "${RDF_SRC}/tests/fixtures/canonical/agents/example.md" \
        "${TEST_HOME}/canonical/agents/example.md"

    # Minimal agent-meta.json with the fixture agent
    cat > "${TEST_HOME}/adapters/claude-code/agent-meta.json" <<'META'
{
  "example": {
    "name": "rdf-example",
    "description": "Test fixture agent for adapter BATS tests.",
    "tools": ["Bash", "Read"],
    "disallowedTools": [],
    "model": "sonnet"
  }
}
META

    # Minimal command-meta-v3.json
    echo '{}' > "${TEST_HOME}/adapters/claude-code/command-meta-v3.json"

    # VERSION and empty profile state
    echo "0.0.0-test" > "${TEST_HOME}/VERSION"
    touch "${TEST_HOME}/.rdf-profiles"

    export _TEST_HOME="$TEST_HOME"
    export _TEST_OUT="$TEST_OUT"
}

teardown() {
    rm -rf "${_TEST_HOME}" "${_TEST_OUT}" 2>/dev/null || true # ignore errors on cleanup
}

# ── Test 1: Generator writes expected file tree ───────────────────────────────

@test "generator writes commands/ and agents/ under output dir" {
    _generate "${_TEST_HOME}" "${_TEST_OUT}"

    [ -d "${_TEST_OUT}/commands" ]
    [ -d "${_TEST_OUT}/agents" ]
    [ -f "${_TEST_OUT}/commands/r-example.md" ]
    [ -f "${_TEST_OUT}/agents/example.md" ]
}

# ── Test 2: Canonical body content preserved in deployed output ───────────────

@test "deployed command contains canonical body text" {
    _generate "${_TEST_HOME}" "${_TEST_OUT}"

    grep -q "RDF_TEST_MARKER_r_example" "${_TEST_OUT}/commands/r-example.md"
}

@test "deployed agent contains canonical body text" {
    _generate "${_TEST_HOME}" "${_TEST_OUT}"

    grep -q "RDF_TEST_MARKER_example_agent" "${_TEST_OUT}/agents/example.md"
}

# ── Test 3: .rdf-hash sidecar emitted next to each deployed file ─────────────

@test ".rdf-hash sidecar exists for deployed command" {
    _generate "${_TEST_HOME}" "${_TEST_OUT}"

    local sidecar="${_TEST_OUT}/commands/r-example.md.rdf-hash"
    [ -f "$sidecar" ]
    local hash
    hash="$(cat "$sidecar")"
    [ -n "$hash" ]
}

@test ".rdf-hash sidecar exists for deployed agent" {
    _generate "${_TEST_HOME}" "${_TEST_OUT}"

    local sidecar="${_TEST_OUT}/agents/example.md.rdf-hash"
    [ -f "$sidecar" ]
    local hash
    hash="$(cat "$sidecar")"
    [ -n "$hash" ]
}

# ── Test 4: Running generator twice is idempotent ─────────────────────────────

@test "running generator twice produces identical output and matching sidecar hashes" {
    _generate "${_TEST_HOME}" "${_TEST_OUT}"

    local body1 sidecar1 body2 sidecar2
    body1="$(cat "${_TEST_OUT}/commands/r-example.md")"
    sidecar1="$(cat "${_TEST_OUT}/commands/r-example.md.rdf-hash")"

    _generate "${_TEST_HOME}" "${_TEST_OUT}"

    body2="$(cat "${_TEST_OUT}/commands/r-example.md")"
    sidecar2="$(cat "${_TEST_OUT}/commands/r-example.md.rdf-hash")"

    [ "$body1" = "$body2" ]
    [ "$sidecar1" = "$sidecar2" ]
}

# ── Test 5: Drift detection — corrupted deployed file causes doctor FAIL ──────

@test "corrupting a deployed file causes doctor content-drift FAIL citing the file" {
    # Set up output dir inside TEST_HOME at the expected adapter path so that
    # doctor --scope content-drift can find it via its hardcoded output path logic.
    local adapter_out="${_TEST_HOME}/adapters/claude-code/output"
    mkdir -p "${adapter_out}/commands" "${adapter_out}/agents"
    _generate "${_TEST_HOME}" "${adapter_out}"

    # Verify generation succeeded before corruption
    [ -f "${adapter_out}/commands/r-example.md" ]

    # Corrupt the deployed command by appending noise
    echo "CORRUPTED_CONTENT" >> "${adapter_out}/commands/r-example.md"

    # Run doctor --scope content-drift against the test home.
    # set +e temporarily because `run` captures exit code via BATS machinery
    run "${RDF_SRC}/bin/rdf" doctor --scope content-drift "${_TEST_HOME}"

    # Exit code must be non-zero (FAIL present)
    [ "$status" -ne 0 ]
    # Output must cite the corrupted file
    [[ "$output" == *"r-example.md"* ]]
}

# ── Test 6: /r-verify-claim command file exists in canonical ──────────────────

@test "r-verify-claim command file exists with Invocation section" {
    local cmd_file="${RDF_SRC}/canonical/commands/r-verify-claim.md"
    [ -f "$cmd_file" ]
    # Structural: must have an Invocation section and at least 80 lines
    run grep -c '^## Invocation' "$cmd_file"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run wc -l < "$cmd_file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 80 ]
}

# ── Test 7: Engineer persona declares EVIDENCE block with grammar reference ──

@test "engineer persona declares EVIDENCE block with grammar reference" {
    local file="${RDF_SRC}/canonical/agents/engineer.md"
    run grep -c 'EVIDENCE' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
    run grep -c 'TDD_EVIDENCE' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ── Test 8: Dispatcher Gate 1 references EVIDENCE structural check ───────────

@test "dispatcher Gate 1 references EVIDENCE structural check" {
    local file="${RDF_SRC}/canonical/agents/dispatcher.md"
    run grep -c 'EVIDENCE block' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'Regression-case' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ── Test 9: r-plan template declares Regression-case field ───────────────────

@test "r-plan template declares Regression-case field" {
    local file="${RDF_SRC}/canonical/commands/r-plan.md"
    run grep -c 'Plan Version' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'Regression-case' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

# ── Test 10: r-build schema validation includes Regression-case ──────────────

@test "r-build schema validation includes Regression-case and category set" {
    local file="${RDF_SRC}/canonical/commands/r-build.md"
    run grep -c 'Regression-case' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
    run grep -c 'docs, performance, logging, refactor, security' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -c 'Plan Version' "$file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ── Test 11: agents-md output contains no governance-not-found strings ───────

@test "agents-md output contains no governance-not-found strings" {
    local out_file="${RDF_SRC}/adapters/agents-md/output/AGENTS.md"
    [ -f "$out_file" ]
    run grep -c 'governance file not found' "$out_file"
    # grep -c prints 0 when no matches; success is "0"
    [ "$output" = "0" ]
    run wc -l < "$out_file"
    [ "$status" -eq 0 ]
    [ "$output" -ge 60 ]
}

# ── Test 12: ignore-defaults.md structural check (Goal 4) ─────────────────────

@test "ignore-defaults.md contains at least 6 exclusion entries" {
    local file="${RDF_SRC}/profiles/core/reference/ignore-defaults.md"
    [ -f "$file" ]
    # Count non-comment, non-heading, non-blank exclusion lines in the Default Body
    # Excludes: lines starting with #, lines starting with >, blank lines, lines with 4+ backticks
    run bash -c "grep -vE '^#|^>|^\s*$|^\`\`\`' '$file' | grep -c '/$\|\*' || true"
    [ "$status" -eq 0 ]
    [ "$output" -ge 6 ]
    # Confirm representative defaults are present
    run grep -c 'node_modules/' "$file"
    [ "$output" = "1" ]
    run grep -c '.rdf/work-output/' "$file"
    [ "$output" = "1" ]
}

# ── Test 13: rdf doctor returns zero FAILs after generate ────────────────────

@test "rdf doctor returns zero FAILs after generate" {
    run "${RDF_SRC}/bin/rdf" generate agents-md
    # generate may print informational output; exit code is what matters
    [ "$status" -eq 0 ]
    run bash -c "'${RDF_SRC}/bin/rdf' doctor '${RDF_SRC}' 2>&1 | grep -c '\[FAIL\]' || true"
    # grep -c prints 0 when no [FAIL] markers; || true ensures status 0 when FAIL-free
    # Use [FAIL] pattern (not bare FAIL) to avoid matching the summary line
    # Pass RDF_SRC explicitly so doctor checks the right project dir regardless of CWD
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}
