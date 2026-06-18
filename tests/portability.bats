#!/usr/bin/env bats
# tests/portability.bats — macOS / portability regression tests for rdf-bus loading
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    TEST_TMP="$(mktemp -d)"
    # Normalize /var -> /private/var on macOS so equality against readlink -f /
    # realpath output holds (both canonicalize macOS's /var and /tmp symlinks).
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

