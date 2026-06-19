#!/usr/bin/env bats
# tests/portability.bats — macOS / portability regression tests for rdf-bus loading
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    TEST_TMP="$(mktemp -d)"
    # mktemp returns a /var/... symlink path; canonicalize to /private/var so it matches the resolved paths the helper returns.
    TEST_TMP="$(cd "$TEST_TMP" && pwd -P)"
}

teardown() {
    command rm -rf "$TEST_TMP"
}

@test "rdf_canonical_path resolves a symlink without readlink -f" {
    # shellcheck disable=SC1091
    source "$RDF_SRC/lib/rdf_common.sh"
    printf 'x\n' > "$TEST_TMP/real.txt"
    ln -s "$TEST_TMP/real.txt" "$TEST_TMP/link.txt"
    result="$(rdf_canonical_path "$TEST_TMP/link.txt")"
    [ "$result" = "$TEST_TMP/real.txt" ]
}

@test "rdf_canonical_path emits a single line on a broken symlink (no double-emit)" {
    # shellcheck disable=SC1091
    source "$RDF_SRC/lib/rdf_common.sh"
    ln -s "$TEST_TMP/does-not-exist" "$TEST_TMP/broken.link"
    result="$(rdf_canonical_path "$TEST_TMP/broken.link")"
    # Must not contain an embedded newline (would mean readlink leaked + fallback printed)
    [[ "$result" != *$'\n'* ]]
}

@test "rdf_canonical_path falls back to realpath when readlink -f unavailable" {
    # shellcheck disable=SC1091
    source "$RDF_SRC/lib/rdf_common.sh"
    command -v realpath >/dev/null 2>&1 || skip "realpath unavailable"
    command mkdir -p "$TEST_TMP/stub"
    printf '#!/bin/sh\nexit 1\n' > "$TEST_TMP/stub/readlink"   # readlink (incl. -f) always fails
    command chmod +x "$TEST_TMP/stub/readlink"
    printf 'x\n' > "$TEST_TMP/real.txt"
    ln -s "$TEST_TMP/real.txt" "$TEST_TMP/link.txt"
    result="$(PATH="$TEST_TMP/stub:$PATH" rdf_canonical_path "$TEST_TMP/link.txt")"
    [ "$result" = "$TEST_TMP/real.txt" ]
}

@test "bin/rdf via absolute symlink resolves RDF_HOME" {
    ln -s "$RDF_SRC/bin/rdf" "$TEST_TMP/rdf-abs"
    run "$TEST_TMP/rdf-abs" --version
    [ "$status" -eq 0 ]
    [ "$output" = "rdf $(cat "$RDF_SRC/VERSION")" ]
}

@test "bin/rdf via relative-target two-hop symlink chain resolves RDF_HOME (EC2+EC3)" {
    # hop2 -> hop1 (relative target) -> real bin/rdf (absolute) : covers EC2 + EC3
    ln -s "$RDF_SRC/bin/rdf" "$TEST_TMP/hop1"
    ( cd "$TEST_TMP" && ln -s hop1 hop2 )
    run "$TEST_TMP/hop2" --version
    [ "$status" -eq 0 ]
    [ "$output" = "rdf $(cat "$RDF_SRC/VERSION")" ]
}

@test "bin/rdf direct (non-symlink) invocation unchanged" {
    run "$RDF_SRC/bin/rdf" --version
    [ "$status" -eq 0 ]
    [ "$output" = "rdf $(cat "$RDF_SRC/VERSION")" ]
}

@test "refresh.sh missing bus emits clear error not raw ENOENT" {
    run bash -c '
        set -euo pipefail
        source "'"$RDF_SRC"'/lib/rdf_common.sh"
        RDF_HOME="'"$RDF_SRC"'"; rdf_init
        RDF_STATE_DIR="/nonexistent-rdf-state"
        source "'"$RDF_SRC"'/lib/cmd/refresh.sh"
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"rdf-bus.sh not found"* ]]
    [[ "$output" != *"No such file or directory"* ]]
}

@test "refresh.sh with bus present sources successfully (normal path)" {
    run bash -c '
        set -euo pipefail
        source "'"$RDF_SRC"'/lib/rdf_common.sh"
        RDF_HOME="'"$RDF_SRC"'"; rdf_init
        source "'"$RDF_SRC"'/lib/cmd/refresh.sh"
        type -t cmd_refresh
    '
    [ "$status" -eq 0 ]
    [ "$output" = "function" ]
}

@test "rotate-work-output.sh missing sibling bus errors clearly" {
    command cp "$RDF_SRC/state/rotate-work-output.sh" "$TEST_TMP/rotate.sh"
    # No rdf-bus.sh beside the copy.
    run bash "$TEST_TMP/rotate.sh" --dry-run "$TEST_TMP"
    [ "$status" -ne 0 ]
    [[ "$output" == *"rdf-bus.sh not found"* ]]
    [[ "$output" != *"No such file or directory"* ]]
}
