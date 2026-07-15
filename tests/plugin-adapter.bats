#!/usr/bin/env bats
# tests/plugin-adapter.bats — BATS tests for the RDF claude-plugin adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: fresh temp RDF home + temp output dir per test. Harness
# pattern mirrors tests/adapter.bats.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2088

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
        cpl_generate_agents
        cpl_generate_scripts
        cpl_generate_hooks
        cpl_stamp_plugin_version
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
    cp "${RDF_SRC}/tests/fixtures/canonical/agents/caller.md" \
        "${TEST_HOME}/canonical/agents/caller.md"

    cat > "${TEST_HOME}/adapters/claude-code/agent-meta.json" <<'META'
{
  "example": {
    "name": "rdf-example",
    "description": "Test fixture agent for adapter BATS tests.",
    "tools": ["Bash", "Read"],
    "disallowedTools": [],
    "model": "sonnet"
  },
  "caller": {
    "name": "rdf-caller",
    "description": "Fixture agent with /r- cross-references.",
    "tools": ["Read"],
    "disallowedTools": [],
    "model": "sonnet"
  }
}
META
    printf '#!/usr/bin/env bash\necho fixture\n' > "${TEST_HOME}/canonical/scripts/fixture.sh"

    cp "${RDF_SRC}/adapters/claude-code/hooks/hooks.json" \
        "${TEST_HOME}/adapters/claude-code/hooks/hooks.json"
    printf '{\n  "name": "rdf",\n  "version": "9.9.9"\n}\n' \
        > "${TEST_HOME}/.claude-plugin/plugin.json"

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

@test "plugin agents carry frontmatter" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    head -1 "${_TEST_OUT}/agents/example.md" | grep -q -- '---'
    grep -q '^name: rdf-example$' "${_TEST_OUT}/agents/example.md"
}

@test "plugin agents rewrite /r-X cross-refs in bodies" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    grep -q 'running /rdf:r-example — this' "${_TEST_OUT}/agents/caller.md"
    grep -q 'canonical/commands/r-example\.md' "${_TEST_OUT}/agents/caller.md"
}

@test "plugin output contains no .rdf-hash sidecars" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    run find "${_TEST_OUT}" -name '*.rdf-hash'
    [ -z "$output" ]
}

@test "plugin scripts are copied executable" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    [ -x "${_TEST_OUT}/scripts/fixture.sh" ]
}

@test "plugin hooks.json uses CLAUDE_PLUGIN_ROOT for all 8 script refs" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    run grep -c 'CLAUDE_PLUGIN_ROOT' "${_TEST_OUT}/hooks.json"
    [ "$output" -eq 8 ]
    run grep '~/.claude' "${_TEST_OUT}/hooks.json"
    [ "$status" -ne 0 ]
}

@test "plugin hooks.json preserves prompt-type hooks untouched" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    # PreCompact now mixes a prompt hook (pass-through) with a command hook
    # (path-rewritten) — compare only the prompt-type hooks, which must be identical.
    diff <(jq -S '[.. | objects | select(.type? == "prompt")]' "${_TEST_HOME}/adapters/claude-code/hooks/hooks.json") \
         <(jq -S '[.. | objects | select(.type? == "prompt")]' "${_TEST_OUT}/hooks.json")
}

@test "generate stamps plugin.json version from VERSION" {
    _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
    run jq -r .version "${_TEST_HOME}/.claude-plugin/plugin.json"
    [ "$output" = "0.0.0-test" ]
}

@test "generate claude-plugin target is wired into cmd_generate" {
    grep -q 'claude-plugin)' "${RDF_SRC}/lib/cmd/generate.sh"
    grep -q 'cpl_generate_all' "${RDF_SRC}/lib/cmd/generate.sh"
    grep -q 'claude-plugin' <(bash "${RDF_SRC}/bin/rdf" generate help)
}

# Helper: run _check_install_mode under a fixture HOME, print raw results.
_run_install_mode_check() {
    local fixture_home="$1"
    HOME="$fixture_home" bash -c '
        set -euo pipefail
        rdf_src="$1"
        RDF_HOME="$rdf_src"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/doctor.sh"
        _reset_results
        _check_install_mode "."
        printf "%s\n" "${_RESULTS[@]}"
    ' -- "$RDF_SRC"
}

@test "doctor warns on dual install mode" {
    FIX_HOME="$(mktemp -d)"
    mkdir -p "${FIX_HOME}/.claude/plugins" "${FIX_HOME}/real-target"
    ln -s "${FIX_HOME}/real-target" "${FIX_HOME}/.claude/commands"
    printf '{"version":1,"plugins":{"rdf@rdf":[{"scope":"user"}]}}\n' \
        > "${FIX_HOME}/.claude/plugins/installed_plugins.json"
    run _run_install_mode_check "$FIX_HOME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"install-mode|WARN|both symlink deploy and plugin install"* ]]
    rm -rf "$FIX_HOME"
}

@test "doctor reports plugin-only install as OK" {
    FIX_HOME="$(mktemp -d)"
    mkdir -p "${FIX_HOME}/.claude/plugins"
    printf '{"version":1,"plugins":{"rdf@rdf":[{"scope":"user"}]}}\n' \
        > "${FIX_HOME}/.claude/plugins/installed_plugins.json"
    run _run_install_mode_check "$FIX_HOME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"install-mode|OK|plugin install (rdf@rdf)"* ]]
    rm -rf "$FIX_HOME"
}

@test "deploy warns when plugin manifest lists rdf@rdf" {
    FIX_HOME="$(mktemp -d)"
    mkdir -p "${FIX_HOME}/.claude/plugins"
    printf '{"version":1,"plugins":{"rdf@rdf":[{"scope":"user"}]}}\n' \
        > "${FIX_HOME}/.claude/plugins/installed_plugins.json"
    # Hermetic RDF_HOME: cc output is NOT tracked (local-only via
    # .git/info/exclude), so a CI checkout has none — the deploy
    # pre-flight would die before reaching the warning. Build a
    # minimal skeleton so dry-run deploy proceeds.
    mkdir -p "${FIX_HOME}/adapters/claude-code/output/agents" \
             "${FIX_HOME}/adapters/claude-code/output/commands" \
             "${FIX_HOME}/adapters/claude-code/output/scripts" \
             "${FIX_HOME}/adapters/claude-code/output/governance" \
             "${FIX_HOME}/canonical" "${FIX_HOME}/state"
    touch "${FIX_HOME}/adapters/claude-code/output/commands/x.md"
    echo "0.0.0-test" > "${FIX_HOME}/VERSION"
    run bash -c '
        set -euo pipefail
        rdf_src="$1"
        fix_home="$2"
        HOME="$fix_home"
        RDF_HOME="$fix_home"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/deploy.sh"
        _deploy_claude_code 1 0
    ' -- "$RDF_SRC" "$FIX_HOME"
    [[ "$output" == *"plugin install detected (rdf@rdf)"* ]]
    rm -rf "$FIX_HOME"
}

@test "repo plugin.json version matches VERSION" {
    run jq -r .version "${RDF_SRC}/.claude-plugin/plugin.json"
    [ "$output" = "$(cat "${RDF_SRC}/VERSION")" ]
}

@test "repo marketplace.json declares plugin rdf with source ./" {
    run jq -r '.plugins[0].name + " " + .plugins[0].source' "${RDF_SRC}/.claude-plugin/marketplace.json"
    [ "$output" = "rdf ./" ]
}

@test "repo plugin.json component paths exist" {
    local p
    for key in commands hooks; do
        p="$(jq -r ".${key}" "${RDF_SRC}/.claude-plugin/plugin.json")"
        [ "${p#./}" != "$p" ]           # must be ./-relative
        [ -e "${RDF_SRC}/${p#./}" ]     # must exist in repo
    done
    # agents is an explicit .md file array (validator rejects dir strings)
    run jq -r '.agents | length' "${RDF_SRC}/.claude-plugin/plugin.json"
    [ "$output" -ge 1 ]
    while IFS= read -r p; do
        [ "${p#./}" != "$p" ]
        [ -e "${RDF_SRC}/${p#./}" ]
    done < <(jq -r '.agents[]' "${RDF_SRC}/.claude-plugin/plugin.json")
}
