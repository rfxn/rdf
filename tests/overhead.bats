#!/usr/bin/env bats
# tests/overhead.bats — RDF 3.4 Phase 6: context-overhead measurement harness
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# state/rdf-overhead.sh isolates RDF's per-session always-loaded token overhead
# into three published figures (default / --rules / lite). It EXCLUDES hooks.json
# bytes (runtime config — never enters model context) and reports scoped language
# rules as dormant (loaded only on a matching-file read). The token figure is a
# bytes/4 estimate (matches state/context-audit.sh). Tests are hermetic: HOME is
# pinned to a temp dir so the live lessons-index never leaks in, and rule/hook
# weights are synthesised into a temp output dir so value assertions are
# deterministic and never depend on a local `rdf generate` (a concurrent phase
# owns generation).
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC
OVERHEAD="$RDF_SRC/state/rdf-overhead.sh"
LESSONS_CAP_TOK=100   # 400-byte injection cap / 4 (session-start-inject.sh)

setup() {
    TEST_TMP="$(mktemp -d)"
    TEST_TMP="$(cd "$TEST_TMP" && pwd -P)"
    export HOME="$TEST_TMP/home"
    mkdir -p "$HOME/.rdf"
}

teardown() {
    command rm -rf "$TEST_TMP" 2>/dev/null || true   # ignore cleanup errors
}

# _nbytes file n char — write exactly n bytes of char into file.
_nbytes() {
    local file="$1" n="$2" ch="$3" i
    : > "$file"
    for ((i = 0; i < n; i++)); do printf '%s' "$ch"; done >> "$file"
}

@test "rdf-overhead emits valid JSON with default/rules/lite figures + excluded block" {
    run bash "$OVERHEAD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null                                   # valid JSON
    echo "$output" | jq -e '.default_boot_tokens != null' >/dev/null
    echo "$output" | jq -e '.rules_boot_tokens != null' >/dev/null
    echo "$output" | jq -e 'has("lite_boot_tokens")' >/dev/null           # present (may be null=pending)
    echo "$output" | jq -e '.breakdown != null' >/dev/null
    echo "$output" | jq -e '.excluded.hooks_json_runtime_config != null' >/dev/null
    echo "$output" | jq -e '.measured_at != null and .commit != null' >/dev/null
}

@test "the --rules figure includes core.md weight; the default figure does not" {
    local out="$TEST_TMP/out"
    mkdir -p "$out/rules"
    _nbytes "$out/rules/core.md" 800 x        # 200 tokens of unscoped core rule
    run bash "$OVERHEAD" "$out"
    [ "$status" -eq 0 ]
    local default rules core
    default="$(echo "$output" | jq -r .default_boot_tokens)"
    rules="$(echo "$output" | jq -r .rules_boot_tokens)"
    core="$(echo "$output" | jq -r .breakdown.core_governance_rule)"
    [ "$core" -eq 200 ]
    [ "$rules" -gt "$default" ]               # opt-in --rules adds core weight
    [ "$rules" -eq $((default + core)) ]      # default carries no rule weight
}

@test "hooks.json bytes are excluded from every boot figure (runtime config)" {
    local out="$TEST_TMP/out2"
    mkdir -p "$out/rules"
    _nbytes "$out/rules/core.md" 400 x        # 100 tokens
    _nbytes "$out/hooks.json"    800 y        # 200 tokens — must NOT enter any boot figure
    run bash "$OVERHEAD" "$out"
    [ "$status" -eq 0 ]
    local excl default rules
    excl="$(echo "$output" | jq -r .excluded.hooks_json_runtime_config)"
    default="$(echo "$output" | jq -r .default_boot_tokens)"
    rules="$(echo "$output" | jq -r .rules_boot_tokens)"
    [ "$excl" -eq 200 ]                       # hooks reported only under excluded
    [ "$default" -eq "$LESSONS_CAP_TOK" ]     # default = lessons index only
    [ "$rules" -eq $((LESSONS_CAP_TOK + 100)) ] # lessons + core, hooks NOT added
}

@test "scoped language rules are counted dormant, not in the default boot figure" {
    local out="$TEST_TMP/out3"
    mkdir -p "$out/rules"
    _nbytes "$out/rules/core.md"   400 x
    _nbytes "$out/rules/python.md" 800 p      # scoped → dormant (200 tokens)
    _nbytes "$out/rules/shell.md"  400 s      # scoped → dormant (100 tokens)
    run bash "$OVERHEAD" "$out"
    [ "$status" -eq 0 ]
    local dormant default
    dormant="$(echo "$output" | jq -r .breakdown.scoped_rules_dormant)"
    default="$(echo "$output" | jq -r .default_boot_tokens)"
    [ "$dormant" -eq 300 ]                    # python + shell, core excluded
    [ "$default" -eq "$LESSONS_CAP_TOK" ]     # dormant rules never in default boot
}

@test "rdf-hash integrity siblings are excluded from rule byte counts" {
    local out="$TEST_TMP/out4"
    mkdir -p "$out/rules"
    _nbytes "$out/rules/core.md"            400 x
    _nbytes "$out/rules/python.md"          400 p   # dormant: 100 tokens
    _nbytes "$out/rules/core.md.rdf-hash"   800 h   # integrity sibling — never model context
    _nbytes "$out/rules/python.md.rdf-hash" 800 h
    run bash "$OVERHEAD" "$out"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .breakdown.core_governance_rule)" -eq 100 ]   # core.md only
    [ "$(echo "$output" | jq -r .breakdown.scoped_rules_dormant)" -eq 100 ]   # python.md only, no hashes
}

@test "absent lessons-index yields the capped default; a smaller live index measures live" {
    run bash "$OVERHEAD"                       # HOME temp, no index → cap
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .default_boot_tokens)" -eq "$LESSONS_CAP_TOK" ]
    _nbytes "$HOME/.rdf/lessons-index.md" 200 z   # 50 tokens, under the 400-byte cap
    run bash "$OVERHEAD"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .default_boot_tokens)" -eq 50 ]
}

@test "lite figure is pending until governance-lite.md is authored (Phase 7)" {
    run bash "$OVERHEAD"
    [ "$status" -eq 0 ]
    local lite
    lite="$(echo "$output" | jq -r .lite_boot_tokens)"
    if [ -f "$RDF_SRC/profiles/lite/governance-lite.md" ]; then
        [ "$lite" != "null" ]
        [ "$lite" -le 1000 ]                  # spec Goal 8 budget
    else
        [ "$lite" = "null" ]                  # pending: source not yet present
    fi
}

@test "published README default figure is within tolerance of measurement (drift guard)" {
    local measured published_k meas_k ok
    measured="$(bash "$OVERHEAD" | jq -r .default_boot_tokens)"   # cap-derived, deterministic
    published_k="$(grep -oE 'default deploy adds ~[0-9]+(\.[0-9])?K' "$RDF_SRC/README.md" \
        | head -1 | grep -oE '[0-9]+(\.[0-9])?')"
    [ -n "$published_k" ]
    meas_k="$(awk "BEGIN{printf \"%.3f\", ${measured}/1000}")"
    ok="$(awk "BEGIN{d=(${meas_k}-${published_k}); d=(d<0?-d:d); print (d <= 0.15*${published_k}+0.2)?1:0}")"
    [ "$ok" -eq 1 ]
}
