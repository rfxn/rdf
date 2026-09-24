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

# ── Test 1: emitter contract — fixture guards the frontmatter transform ──────
#
# Fixture scope is deliberately narrow: the agents/ + plugin-agents/ frontmatter
# blocks. Bodies, scripts/ and reference/ are compared against canonical/ (and
# sidecars re-derived with rdf_hash_stdin), so editing canonical content never
# fails this test — only a change in the emitted frontmatter does.
# The meta is the frozen 3.7.0 catalog (no effort/variants), so this pins the
# emitter mechanics, not live routing values. Regenerate the tar only when the
# agent frontmatter contract changes on purpose (emit from the frozen meta):
#   d="$(mktemp -d)" && bash -c 'RDF_HOME="$PWD"; RDF_LIBDIR="$PWD/lib"; RDF_VERSION=x; source lib/rdf_common.sh; rdf_init; source lib/adapter_common.sh; source adapters/claude-plugin/adapter.sh; m=tests/fixtures/adapter-common/agent-meta-3.7.0.json; adp_emit_agents canonical/agents "$1/agents" "$m" - 0; adp_emit_agents canonical/agents "$1/plugin-agents" "$m" _cpl_rewrite_namespace_text 0' -- "$d" && tar -cf tests/fixtures/adapter-common/agents-expected.tar -C "$d" agents plugin-agents

@test "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture" {
    local expected="${TEST_WORK}/expected"
    local work="${TEST_WORK}/work"
    mkdir -p "$expected" "$work"
    tar -xf "${RDF_SRC}/tests/fixtures/adapter-common/agents-expected.tar" -C "$expected"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; out="$2"; expected="$3"
        RDF_HOME="$rdf_src"; RDF_LIBDIR="${rdf_src}/lib"; RDF_VERSION="0.0.0-test"
        source "${rdf_src}/lib/rdf_common.sh"; rdf_init
        source "${rdf_src}/lib/adapter_common.sh"
        source "${rdf_src}/adapters/claude-plugin/adapter.sh"
        agent_meta="${rdf_src}/tests/fixtures/adapter-common/agent-meta-3.7.0.json"
        adp_emit_agents "${RDF_CANONICAL}/agents" "${out}/agents" "$agent_meta" - 1
        adp_copy_scripts "${RDF_CANONICAL}/scripts" "${out}/scripts"
        adp_copy_reference "${RDF_CANONICAL}/reference" "${out}/reference" 1
        adp_emit_agents "${RDF_CANONICAL}/agents" "${out}/plugin-agents" "$agent_meta" _cpl_rewrite_namespace_text 0

        diff -r "${RDF_CANONICAL}/scripts" "${out}/scripts"
        for f in "${out}"/scripts/*.sh; do
            [[ -x "$f" ]] || { echo "script not executable: $f"; exit 1; }
        done

        for f in "${RDF_CANONICAL}"/reference/*.md; do
            b="$(basename "$f")"
            diff "$f" "${out}/reference/${b}"
            [[ "$(rdf_hash_stdin < "$f")" == "$(cat "${out}/reference/${b}.rdf-hash")" ]] \
                || { echo "reference sidecar mismatch: $b"; exit 1; }
        done

        diff <(ls "${out}/agents" | grep -v "\.rdf-hash$") <(ls "${RDF_CANONICAL}/agents")
        diff <(ls "${out}/plugin-agents") <(ls "${RDF_CANONICAL}/agents")

        for f in "${RDF_CANONICAL}"/agents/*.md; do
            b="$(basename "$f")"
            diff <(sed -n "1,/^---$/p" "${out}/agents/${b}") <(sed -n "1,/^---$/p" "${expected}/agents/${b}")
            diff <(sed -n "1,/^---$/p" "${out}/plugin-agents/${b}") <(sed -n "1,/^---$/p" "${expected}/plugin-agents/${b}")
            diff <(rdf_strip_frontmatter "${out}/agents/${b}") "$f"
            diff <(rdf_strip_frontmatter "${out}/plugin-agents/${b}") <(_cpl_rewrite_namespace_text < "$f")
            [[ "$(rdf_hash_stdin < "$f")" == "$(cat "${out}/agents/${b}.rdf-hash")" ]] \
                || { echo "agent sidecar mismatch: $b"; exit 1; }
            [[ ! -e "${out}/plugin-agents/${b}.rdf-hash" ]] \
                || { echo "unexpected plugin-agent sidecar: $b"; exit 1; }
        done
    ' -- "$RDF_SRC" "$work" "$expected"
    [ "$status" -eq 0 ]
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

# ── Test 2b: effort line + variant emission ──────────────────────────────────

@test "adp_emit_agents emits an effort line and a variant file per declared variant" {
    local src_dir="${TEST_WORK}/src" dst_dir="${TEST_WORK}/dst" meta="${TEST_WORK}/meta.json"
    mkdir -p "$src_dir" "$dst_dir"
    cp "${RDF_SRC}/tests/fixtures/canonical/agents/example.md" "${src_dir}/example.md"
    printf '%s\n' '{"example":{"name":"rdf-example","description":"Base agent.","tools":["Read"],"model":"opus","effort":"xhigh","variants":{"lite":{"effort":"medium","description":"Lite variant."}}}}' > "$meta"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src_dir="$2"; dst_dir="$3"; meta="$4"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        adp_emit_agents "$src_dir" "$dst_dir" "$meta" - 1
    ' -- "$RDF_SRC" "$src_dir" "$dst_dir" "$meta"
    [ "$status" -eq 0 ]
    [[ "$output" == *"generated 2 agent files (1 variants)"* ]]

    grep -q '^effort: xhigh$' "${dst_dir}/example.md"
    grep -q '^name: rdf-example-lite$' "${dst_dir}/example-lite.md"
    grep -q '^  Lite variant\.$' "${dst_dir}/example-lite.md"
    grep -q '^model: opus$' "${dst_dir}/example-lite.md"
    grep -q '^effort: medium$' "${dst_dir}/example-lite.md"
    diff <(sed '1,/^---$/d' "${dst_dir}/example.md" | sed -n '/^---$/,$p') <(sed '1,/^---$/d' "${dst_dir}/example-lite.md" | sed -n '/^---$/,$p')
    [ "$(cat "${dst_dir}/example-lite.md.rdf-hash")" = "$(cat "${dst_dir}/example.md.rdf-hash")" ]
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
        adp_copy_reference "$src" "$dst2" 0 "skills tree"
    ' -- "$RDF_SRC" "$src" "$dst1" "$dst2"
    [ "$status" -eq 0 ]

    [ -f "${dst1}/doc.md" ]
    [ -f "${dst1}/doc.md.rdf-hash" ]
    [ -f "${dst2}/doc.md" ]
    [ ! -f "${dst2}/doc.md.rdf-hash" ]
    # the optional label keeps two copies of the same docs distinguishable
    echo "$output" | grep -qx 'rdf: generated 1 reference docs'
    echo "$output" | grep -qx 'rdf: generated 1 reference docs (skills tree)'
}

# ── Test 6: adp_emit_skills filters body and description; ref_src is a param ──

@test "adp_emit_skills applies the filter to body and description" {
    local src_dir="${TEST_WORK}/src" skills_root="${TEST_WORK}/skills" meta="${TEST_WORK}/meta.json"
    local ref_src="${TEST_WORK}/ref" noref_root="${TEST_WORK}/skills-noref"
    mkdir -p "$src_dir" "$skills_root" "$ref_src"
    printf 'hello world\n\nBody line two.\n' > "${src_dir}/r-hello.md"
    printf '{"r-hello": "hello trigger"}' > "$meta"
    printf 'reference body\n' > "${ref_src}/doc.md"

    # No RDF_HOME / rdf_init: the reference source is a parameter, not a global.
    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src_dir="$2"; skills_root="$3"; meta="$4"; ref_src="$5"; noref_root="$6"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        _test_filter() { sed "s/hello/HELLO/g"; }
        adp_emit_skills "$src_dir" "$skills_root" "$meta" _test_filter 1 adp_names_all "$ref_src"
        adp_emit_skills "$src_dir" "$noref_root" "$meta" _test_filter 1 adp_names_all -
    ' -- "$RDF_SRC" "$src_dir" "$skills_root" "$meta" "$ref_src" "$noref_root"
    [ "$status" -eq 0 ]

    [ -f "${skills_root}/reference/doc.md" ]
    echo "$output" | grep -q 'generated 1 reference docs (skills tree)'   # emit path labels its copy
    [ -f "${noref_root}/r-hello/SKILL.md" ]
    [ ! -e "${noref_root}/reference" ]

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

# ── Test 8: names functions — rc and content ──────────────────────────────────

@test "adp_names_lite, adp_names_from_meta, adp_names_all return rc 0 and the expected names" {
    local src_dir="${TEST_WORK}/src" meta="${TEST_WORK}/meta.json"
    mkdir -p "$src_dir"
    : > "${src_dir}/r-spec.md"
    : > "${src_dir}/r-plan.md"
    : > "${src_dir}/r-util-thing.md"
    printf '{"_comment": "ignored", "r-spec": "t", "r-util-thing": "t"}' > "$meta"

    # Assignment form (not a pipeline) so set -e sees each function's rc.
    run bash -c '
        set -euo pipefail
        rdf_src="$1"; src_dir="$2"; meta="$3"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        all="$(adp_names_all "$src_dir" "$meta")"
        lite="$(adp_names_lite "$src_dir" "$meta")"
        from_meta="$(adp_names_from_meta "$src_dir" "$meta")"
        printf "all:%s\n" "$(printf "%s" "$all" | tr "\n" " ")"
        printf "lite:%s\n" "$(printf "%s" "$lite" | tr "\n" " ")"
        printf "meta:%s\n" "$(printf "%s" "$from_meta" | tr "\n" " ")"
    ' -- "$RDF_SRC" "$src_dir" "$meta"
    [ "$status" -eq 0 ]
    [[ "$output" == *"all:r-plan r-spec r-util-thing"* ]]
    [[ "$output" == *"lite:r-plan r-spec"* ]]
    [[ "$output" == *"meta:r-spec r-util-thing"* ]]
}

# ── Test 9: adp_count ─────────────────────────────────────────────────────────

@test "adp_count returns 0 for an absent dir and N otherwise" {
    local dir="${TEST_WORK}/skills"
    mkdir -p "${dir}/one" "${dir}/two"
    : > "${dir}/one/SKILL.md"
    : > "${dir}/two/SKILL.md"
    : > "${dir}/two/other.md"

    run bash -c '
        set -euo pipefail
        rdf_src="$1"; dir="$2"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        source "${rdf_src}/lib/adapter_common.sh"
        present="$(adp_count "$dir" SKILL.md)"
        absent="$(adp_count "${dir}/absent" SKILL.md)"
        printf "present=%s absent=%s\n" "$((present))" "$((absent))"
    ' -- "$RDF_SRC" "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"present=2"* ]]
    [[ "$output" == *"absent=0"* ]]
}
