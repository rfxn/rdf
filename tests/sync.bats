#!/usr/bin/env bats
# tests/sync.bats — rdf sync agents-path guards + shared-strip convergence
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2088

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

_run_sync() {  # $1 = temp RDF_HOME
    bash -c '
        set -euo pipefail
        RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
        source "$2/lib/rdf_common.sh"; rdf_init
        source "$2/lib/cmd/sync.sh"; cmd_sync
    ' -- "$1" "$RDF_SRC"
}

@test "sync agents: frontmatter-less output syncs verbatim (no truncation)" {
    home="$(mktemp -d)"
    mkdir -p "${home}/canonical/agents" "${home}/adapters/claude-code/output/agents"
    printf 'agent body\nline two\n' > "${home}/canonical/agents/a.md"
    printf 'agent body\nline two\n' > "${home}/adapters/claude-code/output/agents/a.md"
    run _run_sync "$home"
    [ "$status" -eq 0 ]
    [ -s "${home}/canonical/agents/a.md" ]                       # NOT truncated to empty
    grep -q '^agent body$' "${home}/canonical/agents/a.md"
    echo "$output" | grep -q '0 updated'                          # verbatim == unchanged
    rm -rf "$home"
}

@test "sync agents: unclosed frontmatter skipped with warning, canonical untouched" {
    home="$(mktemp -d)"
    mkdir -p "${home}/canonical/agents" "${home}/adapters/claude-code/output/agents"
    printf 'precious canonical\n' > "${home}/canonical/agents/a.md"
    printf -- '---\nnever closed\n' > "${home}/adapters/claude-code/output/agents/a.md"
    run _run_sync "$home"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'unclosed frontmatter'
    grep -q '^precious canonical$' "${home}/canonical/agents/a.md"
    rm -rf "$home"
}

@test "sync agents: frontmatter stripped, body --- rules preserved, edit lands" {
    home="$(mktemp -d)"
    mkdir -p "${home}/canonical/agents" "${home}/adapters/claude-code/output/agents"
    printf 'old body\n' > "${home}/canonical/agents/a.md"
    printf -- '---\nname: a\n---\n\nEDITED body\n---\nrule\n' \
        > "${home}/adapters/claude-code/output/agents/a.md"
    run _run_sync "$home"
    [ "$status" -eq 0 ]
    [ "$(head -1 "${home}/canonical/agents/a.md")" = "EDITED body" ]
    grep -q '^---$' "${home}/canonical/agents/a.md"
    rm -rf "$home"
}
