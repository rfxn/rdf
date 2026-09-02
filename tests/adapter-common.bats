#!/usr/bin/env bats
# tests/adapter-common.bats — BATS tests for lib/adapter_common.sh (shared adp_* emitters)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: every test works in its own mktemp dir; canonical/ and
# adapters/*/agent-meta.json are read from the real checkout (RDF_SRC) but
# never written to — only the temp output paths receive writes.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

setup() {
    TEST_WORK="$(mktemp -d)"
    export TEST_WORK
}

teardown() {
    rm -rf "${TEST_WORK}" 2>/dev/null || true  # cleanup, ignore errors
}

# ── Test 1: byte-identity against the captured 3.6.5 emitter fixture ─────────

@test "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture" {
    local expected="${TEST_WORK}/expected"
    local work="${TEST_WORK}/work"
    mkdir -p "$expected" "$work"
    tar -xf "${RDF_SRC}/tests/fixtures/adapter-common/agents-expected.tar" -C "$expected"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; out="$2"
        RDF_HOME="$rdf_src"; RDF_LIBDIR="${rdf_src}/lib"; RDF_VERSION="0.0.0-test"
        source "${rdf_src}/lib/rdf_common.sh"; rdf_init
        source "${rdf_src}/lib/adapter_common.sh"
        source "${rdf_src}/adapters/claude-plugin/adapter.sh"
        agent_meta="${RDF_ADAPTERS}/claude-code/agent-meta.json"
        adp_emit_agents "${RDF_CANONICAL}/agents" "${out}/agents" "$agent_meta" - 1
        adp_copy_scripts "${RDF_CANONICAL}/scripts" "${out}/scripts"
        adp_copy_reference "${RDF_CANONICAL}/reference" "${out}/reference" 1
        adp_emit_agents "${RDF_CANONICAL}/agents" "${out}/plugin-agents" "$agent_meta" _cpl_rewrite_namespace_text 0
    ' -- "$RDF_SRC" "$work"
    [ "$status" -eq 0 ]

    diff -rq "${expected}/agents" "${work}/agents"
    diff -rq "${expected}/scripts" "${work}/scripts"
    diff -rq "${expected}/reference" "${work}/reference"
    diff -rq "${expected}/plugin-agents" "${work}/plugin-agents"
}

# ── Test 2: missing-meta branch — plain copy + warn ───────────────────────────

@test "adp_emit_agents plain-copies and warns when meta lacks the agent" {
    local src_dir="${TEST_WORK}/src" dst_dir="${TEST_WORK}/dst" meta="${TEST_WORK}/meta.json"
    mkdir -p "$src_dir" "$dst_dir"
    cp "${RDF_SRC}/tests/fixtures/canonical/agents/example.md" "${src_dir}/example.md"
    echo '{}' > "$meta"

    # adp_agent_frontmatter, called standalone (not through the 2>/dev/null
    # tmp-redirect adp_emit_agents wraps it in), surfaces the warn on stderr.
    run bash -c '
        set -euo pipefail
        rdf_src="$1"; meta="$2"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        adp_agent_frontmatter "$meta" example
    ' -- "$RDF_SRC" "$meta"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no metadata for agent: example"* ]]

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src_dir="$2"; dst_dir="$3"; meta="$4"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        adp_emit_agents "$src_dir" "$dst_dir" "$meta" - 1
    ' -- "$RDF_SRC" "$src_dir" "$dst_dir" "$meta"
    [ "$status" -eq 0 ]

    diff -q "${src_dir}/example.md" "${dst_dir}/example.md"
    [ -f "${dst_dir}/example.md.rdf-hash" ]
}

# ── Test 3: staging swap ──────────────────────────────────────────────────────

@test "adp_stage_commit rotates .old and leaves no staging dirs" {
    local final="${TEST_WORK}/final"
    mkdir -p "$final"
    echo "old-content" > "${final}/marker.txt"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; final="$2"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        staging="$(adp_stage_begin "$final")"
        [[ "$staging" == "${final}.new" ]] || { echo "unexpected staging path: $staging"; exit 1; }
        echo "new-content" > "${staging}/marker.txt"
        adp_stage_commit "$final" "$staging"
    ' -- "$RDF_SRC" "$final"
    [ "$status" -eq 0 ]

    [ -f "${final}/marker.txt" ]
    [ "$(cat "${final}/marker.txt")" = "new-content" ]
    [ ! -e "${final}.old" ]
    [ ! -e "${final}.new" ]
}

# ── Test 4: skill-description fallback chain ──────────────────────────────────

@test "adp_skill_description falls back meta -> first line -> RDF command:" {
    local src="${TEST_WORK}/cmd.md" meta_hit="${TEST_WORK}/meta-hit.json" meta_miss="${TEST_WORK}/meta-miss.json"
    printf '{"cmd": "Meta trigger text"}' > "$meta_hit"
    printf '{}' > "$meta_miss"

    printf '# Heading\n\nFirst real line.\n' > "$src"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src="$2"; meta="$3"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        adp_skill_description cmd "$src" "$meta"
    ' -- "$RDF_SRC" "$src" "$meta_hit"
    [ "$status" -eq 0 ]
    [ "$output" = "Meta trigger text" ]

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src="$2"; meta="$3"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        adp_skill_description cmd "$src" "$meta"
    ' -- "$RDF_SRC" "$src" "$meta_miss"
    [ "$status" -eq 0 ]
    [ "$output" = "First real line." ]

    printf '# Only Heading\n\n' > "$src"
    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src="$2"; meta="$3"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        adp_skill_description cmd "$src" "$meta"
    ' -- "$RDF_SRC" "$src" "$meta_miss"
    [ "$status" -eq 0 ]
    [ "$output" = "RDF command: cmd" ]
}

# ── Test 5: reference sidecar toggle ──────────────────────────────────────────

@test "adp_copy_reference writes sidecars only when asked" {
    local src="${TEST_WORK}/src" dst1="${TEST_WORK}/dst1" dst2="${TEST_WORK}/dst2"
    mkdir -p "$src" "$dst1" "$dst2"
    printf 'reference body\n' > "${src}/doc.md"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src="$2"; dst1="$3"; dst2="$4"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        adp_copy_reference "$src" "$dst1" 1
        adp_copy_reference "$src" "$dst2" 0
    ' -- "$RDF_SRC" "$src" "$dst1" "$dst2"
    [ "$status" -eq 0 ]

    [ -f "${dst1}/doc.md" ]
    [ -f "${dst1}/doc.md.rdf-hash" ]
    [ -f "${dst2}/doc.md" ]
    [ ! -f "${dst2}/doc.md.rdf-hash" ]
}

# ── Test 6: adp_emit_skills filters body and description ─────────────────────

@test "adp_emit_skills applies the filter to body and description" {
    local src_dir="${TEST_WORK}/src" skills_root="${TEST_WORK}/skills" meta="${TEST_WORK}/meta.json"
    mkdir -p "$src_dir" "$skills_root"
    printf 'hello world\n\nBody line two.\n' > "${src_dir}/r-hello.md"
    printf '{"r-hello": "hello trigger"}' > "$meta"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src_dir="$2"; skills_root="$3"; meta="$4"
        RDF_HOME="$rdf_src"; RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"; rdf_init
        source "${rdf_src}/lib/adapter_common.sh"
        _test_filter() { sed "s/hello/HELLO/g"; }
        adp_emit_skills "$src_dir" "$skills_root" "$meta" _test_filter 1 adp_names_all
    ' -- "$RDF_SRC" "$src_dir" "$skills_root" "$meta"
    [ "$status" -eq 0 ]

    local skill="${skills_root}/r-hello/SKILL.md"
    [ -f "$skill" ]
    [ -f "${skill}.rdf-hash" ]
    grep -q '^description: >$' "$skill"
    grep -q '^  HELLO trigger$' "$skill"
    grep -q '^HELLO world$' "$skill"
    # name: is never filtered (skill dir name is canonical) — assert the body
    # line itself was rewritten, not a blanket absence (name: r-hello matches
    # 'hello' as a substring).
    run grep -qx 'hello world' "$skill"
    [ "$status" -ne 0 ]
}

# ── Test 7: staging pattern is centralized in the lib ─────────────────────────

@test "no adapter except gemini defines output_old" {
    run grep -l 'output_old' "${RDF_SRC}/adapters/gemini-cli/adapter.sh"
    [ "$status" -eq 0 ]

    run grep -l 'output_old' \
        "${RDF_SRC}/adapters/claude-code/adapter.sh" \
        "${RDF_SRC}/adapters/claude-plugin/adapter.sh" \
        "${RDF_SRC}/adapters/agent-skills/adapter.sh"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}
