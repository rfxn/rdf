#!/usr/bin/env bats
# tests/bootstrap.bats — Unit tests for canonical/scripts/state-bootstrap.sh
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

_make_plugin_root() {   # $1 = dir; returns script path in $BOOT
    mkdir -p "$1/state/git-hooks" "$1/adapters/claude-plugin/output/scripts"
    printf '#!/usr/bin/env bash\necho helper\n' > "$1/state/rdf-bus.sh"
    printf '#!/usr/bin/env bash\necho hook\n' > "$1/state/git-hooks/pre-commit"
    printf '9.9.9-test\n' > "$1/VERSION"
    cp "$RDF_SRC/canonical/scripts/state-bootstrap.sh" \
       "$1/adapters/claude-plugin/output/scripts/state-bootstrap.sh"
    BOOT="$1/adapters/claude-plugin/output/scripts/state-bootstrap.sh"
}

@test "bootstrap copies helpers + stamps version from plugin-root layout" {
    root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
    run env HOME="$home" bash "$BOOT"
    [ "$status" -eq 0 ]; [ -z "$output" ]                      # silent success
    [ -x "${home}/.rdf/state/rdf-bus.sh" ]
    [ -x "${home}/.rdf/state/git-hooks/pre-commit" ]
    [ "$(cat "${home}/.rdf/state/.rdf-version")" = "9.9.9-test" ]
    [ "$(cat "${home}/.rdf/state/.rdf-source")" = "$root" ]
    rm -rf "$root" "$home"
}

@test "bootstrap no-ops when stamp is current" {
    root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
    env HOME="$home" bash "$BOOT"
    printf 'sentinel\n' > "${home}/.rdf/state/rdf-bus.sh"     # local mutation
    run env HOME="$home" bash "$BOOT"                          # stamp matches → no copy
    [ "$status" -eq 0 ]
    grep -q '^sentinel$' "${home}/.rdf/state/rdf-bus.sh"
    rm -rf "$root" "$home"
}

@test "bootstrap no-ops when helpers are checkout symlinks" {
    root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
    mkdir -p "${home}/.rdf/state"
    ln -s "$root/state/rdf-bus.sh" "${home}/.rdf/state/rdf-bus.sh"
    run env HOME="$home" bash "$BOOT"
    [ "$status" -eq 0 ]
    [ -L "${home}/.rdf/state/rdf-bus.sh" ]                     # untouched
    [ ! -f "${home}/.rdf/state/.rdf-version" ]                 # no stamp written
    rm -rf "$root" "$home"
}

@test "bootstrap exits 0 without VERSION at root and copies nothing" {
    root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
    rm -f "$root/VERSION"
    run env HOME="$home" bash "$BOOT"
    [ "$status" -eq 0 ]
    [ ! -e "${home}/.rdf/state/rdf-bus.sh" ]
    rm -rf "$root" "$home"
}

@test "bootstrap exits 0 on unwritable HOME" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "mode bits ignored as root"
    fi
    root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
    chmod 555 "$home"
    run env HOME="$home" bash "$BOOT"
    [ "$status" -eq 0 ]
    chmod 755 "$home"; rm -rf "$root" "$home"
}
