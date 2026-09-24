#!/usr/bin/env bats
# tests/strip.bats — shared frontmatter-strip + agent-meta preflight unit tests
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: each test sources lib/rdf_common.sh in a throwaway subshell via
# `bash -c`; no RDF_HOME/HOME fixtures needed — both functions under test are
# pure (file args in, stdout/exit code out).
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2088

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

_strip() {  # run rdf_strip_frontmatter against a fixture file
    bash -c 'source "$1/lib/rdf_common.sh"; rdf_strip_frontmatter "$2"' -- "$RDF_SRC" "$1"
}

@test "strip: leading frontmatter block + one blank separator removed" {
    f="$(mktemp)"; printf -- '---\ndescription: x\n---\n\nbody line\n' > "$f"
    run _strip "$f"
    [ "$output" = "body line" ]
    rm -f "$f"
}

@test "strip: frontmatter-less file passes through verbatim" {
    f="$(mktemp)"; printf 'plain body\nsecond line\n' > "$f"
    run _strip "$f"
    [ "${lines[0]}" = "plain body" ]
    [ "${lines[1]}" = "second line" ]
    rm -f "$f"
}

@test "strip: body --- horizontal rules preserved" {
    f="$(mktemp)"; printf -- '---\nx: y\n---\n\nbody\n---\nafter rule\n' > "$f"
    run _strip "$f"
    echo "$output" | grep -q '^---$'
    echo "$output" | grep -q '^after rule$'
    rm -f "$f"
}

@test "strip: unclosed frontmatter yields empty output" {
    f="$(mktemp)"; printf -- '---\nnever closed\n' > "$f"
    run _strip "$f"
    [ -z "$output" ]
    rm -f "$f"
}

@test "require_agent_meta: dies listing every missing agent" {
    d="$(mktemp -d)"; printf '{}\n' > "$d/meta.json"
    touch "$d/alpha.md" "$d/beta.md"
    run bash -c 'source "$1/lib/rdf_common.sh"; rdf_require_agent_meta "$2/meta.json" "$2"' -- "$RDF_SRC" "$d"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q 'alpha, beta'
    rm -rf "$d"
}

@test "require_agent_meta: complete catalog passes silently" {
    d="$(mktemp -d)"; printf '{"alpha":{"name":"a"}}\n' > "$d/meta.json"
    touch "$d/alpha.md"
    run bash -c 'source "$1/lib/rdf_common.sh"; rdf_require_agent_meta "$2/meta.json" "$2"' -- "$RDF_SRC" "$d"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    rm -rf "$d"
}

_require_meta() {  # $1 = meta JSON, $2.. = canonical agent stems to create
    local d; d="$(mktemp -d)"
    printf '%s\n' "$1" > "$d/meta.json"; shift
    local a; for a in "$@"; do touch "$d/${a}.md"; done
    bash -c 'source "$1/lib/rdf_common.sh"; rdf_require_agent_meta "$2/meta.json" "$2"' -- "$RDF_SRC" "$d"
    local rc=$?
    rm -rf "$d"
    return "$rc"
}

@test "require_agent_meta: dies on invalid effort, model, variant key, missing variant effort, and variant collision" {
    run _require_meta '{"a":{"name":"a","effort":"ultra"}}' a
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid agent routing in agent-meta.json: a: effort 'ultra' not in low|medium|high|xhigh|max"* ]]
    run _require_meta '{"a":{"name":"a","model":"gpt-9"}}' a
    [ "$status" -eq 1 ]
    [[ "$output" == *"a: model 'gpt-9' not in opus|sonnet|haiku|fable|inherit"* ]]
    run _require_meta '{"a":{"name":"a","variants":{"9x":{"effort":"low"}}}}' a
    [ "$status" -eq 1 ]
    [[ "$output" == *"a: variant key '9x' must start with a-z"* ]]
    run _require_meta '{"a":{"name":"a","variants":{"lite":{"model":"opus"}}}}' a
    [ "$status" -eq 1 ]
    [[ "$output" == *"a.lite: variant requires effort"* ]]
    run _require_meta '{"a":{"name":"a","variants":{"lite":{"effort":"low"}}},"a-lite":{"name":"x"}}' a a-lite
    [ "$status" -eq 1 ]
    [[ "$output" == *"a: variant lite collides with canonical agent a-lite.md"* ]]
}

@test "require_agent_meta: missing model and effort are valid" {
    run _require_meta '{"a":{"name":"a"},"b":{"name":"b","model":"claude-opus-5-5","effort":"max","variants":{"x":{"effort":"low"}}}}' a b
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "strip: sync.sh defines no local strip implementation" {
    run grep -c '^_strip_frontmatter()' "$RDF_SRC/lib/cmd/sync.sh"
    [ "$output" = "0" ]
}
