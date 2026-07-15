#!/usr/bin/env bats
# tests/memory-context.bats — RDF 3.4 memory & context
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Phase 1 covers canonical/scripts/session-end-capture.sh: a SessionEnd command
# hook that appends a deterministic git-only snapshot to the project session
# journal (.rdf/work-output/session-log.jsonl) and writes a session-end-<id>.json
# cache for /r-save. The hook must NEVER exit nonzero (SessionEnd output is
# ignored — shutdown must not be blocked), must degrade without jq, and must be
# a clean no-op outside a git repo. HOME is pinned to a temp dir; stdin is fed
# from a file to keep shell metacharacters out of bats `run` (which evals).

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CAP="$RDF_SRC/canonical/scripts/session-end-capture.sh"
LESSONS="$RDF_SRC/state/rdf-lessons.sh"
INJECT="$RDF_SRC/canonical/scripts/session-start-inject.sh"
LESSONS_FIXTURE="$RDF_SRC/tests/fixtures/lessons/lessons-sample.md"

setup() {
    TEST_TMP="$(mktemp -d)"
    TEST_TMP="$(cd "$TEST_TMP" && pwd -P)"
    export HOME="$TEST_TMP/home"
    mkdir -p "$HOME"
    JSON="$TEST_TMP/in.json"
}

teardown() {
    command rm -rf "$TEST_TMP"
}

_mkrepo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    git -C "$repo" commit -q --allow-empty -m init
}

# _minbin dir — symlink the real binaries the hook needs, deliberately excluding
# jq, so PATH=dir simulates a host without jq. type -P resolves the on-disk
# executable only (ignores shell aliases/functions).
_minbin() {
    local dir="$1" tool src
    mkdir -p "$dir"
    for tool in bash env cat tr date mkdir git wc grep sed head; do
        src="$(type -P "$tool" 2>/dev/null)" || continue   # skip tools absent on this host
        [ -n "$src" ] && ln -sf "$src" "$dir/$tool"
    done
}

# ---- session-end-capture.sh -----------------------------------------------

@test "session-end-capture appends journal entry + writes cache, exits 0" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    local repo="$TEST_TMP/repo"
    _mkrepo "$repo"
    printf '{"session_id":"t","reason":"clear","cwd":"%s"}' "$repo" > "$JSON"

    run bash "$CAP" < "$JSON"
    [ "$status" -eq 0 ]
    # journal APPEND is the load-bearing behavior (Goal 1 — read by /r-start)
    [ -f "$repo/.rdf/work-output/session-log.jsonl" ]
    run tail -1 "$repo/.rdf/work-output/session-log.jsonl"
    [[ "$output" == *'"reason":"clear"'* ]]
    [[ "$output" == *'"insight":null'* ]]
    [[ "$output" == *'"source":"session-end-hook"'* ]]
    # cache for /r-save enrichment
    [ -f "$repo/.rdf/work-output/session-end-t.json" ]
}

@test "session-end-capture is a no-op outside a git repo" {
    local nongit="$TEST_TMP/nongit"
    mkdir -p "$nongit"
    printf '{"session_id":"t2","reason":"logout","cwd":"%s"}' "$nongit" > "$JSON"

    run bash "$CAP" < "$JSON"
    [ "$status" -eq 0 ]
    [ ! -f "$nongit/.rdf/work-output/session-log.jsonl" ]   # no journal write outside a repo
}

@test "session-end-capture falls back without jq and still records (exit 0)" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    local repo="$TEST_TMP/repo-nojq"
    _mkrepo "$repo"
    local minbin="$TEST_TMP/minbin"
    _minbin "$minbin"
    printf '{"session_id":"nojq","reason":"logout","cwd":"%s"}' "$repo" > "$JSON"

    run env PATH="$minbin" HOME="$HOME" bash "$CAP" < "$JSON"
    [ "$status" -eq 0 ]
    [ -f "$repo/.rdf/work-output/session-log.jsonl" ]
    [ -f "$repo/.rdf/work-output/session-end-nojq.json" ]
    run tail -1 "$repo/.rdf/work-output/session-log.jsonl"
    [[ "$output" == *'"reason":"logout"'* ]]   # grep/sed fallback extracted reason
}

@test "session-end-capture sanitizes a path-traversal session_id" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    local repo="$TEST_TMP/repo-trav"
    _mkrepo "$repo"
    printf '{"session_id":"../../evil","reason":"clear","cwd":"%s"}' "$repo" > "$JSON"

    run bash "$CAP" < "$JSON"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/evil.json" ]                       # traversal did not escape work-output
    [ ! -e "$repo/.rdf/evil.json" ]
    [ -f "$repo/.rdf/work-output/session-end-....evil.json" ]   # slashes stripped, dots kept
}

# ---- rdf-lessons.sh index --------------------------------------------------

@test "rdf-lessons index emits <=400 byte ID-index" {
    mkdir -p "$HOME/.rdf"
    cp "$LESSONS_FIXTURE" "$HOME/.rdf/lessons-learned.md"

    run bash "$LESSONS" index "$HOME/.rdf/lessons-learned.md"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.rdf/lessons-index.md" ]
    # hard 400-byte cap bounds the per-session injection cost
    [ "$(wc -c < "$HOME/.rdf/lessons-index.md")" -le 400 ]
    # first Workflow bullet is tagged W1 and survives the cap (appears early)
    grep -q '^\[W1\]' "$HOME/.rdf/lessons-index.md"
}

@test "rdf-lessons index assigns stable IDs across two runs (idempotent)" {
    mkdir -p "$HOME/.rdf"
    cp "$LESSONS_FIXTURE" "$HOME/.rdf/lessons-learned.md"

    bash "$LESSONS" index "$HOME/.rdf/lessons-learned.md"
    first="$(grep -c '<!-- id:' "$HOME/.rdf/lessons-learned.md")"
    bash "$LESSONS" index "$HOME/.rdf/lessons-learned.md"
    second="$(grep -c '<!-- id:' "$HOME/.rdf/lessons-learned.md")"
    [ "$first" -eq 5 ]              # one marker per bullet, no more
    [ "$first" -eq "$second" ]      # re-run does not duplicate markers
}

@test "rdf-lessons index on a missing lessons file writes an empty index" {
    mkdir -p "$HOME/.rdf"
    run bash "$LESSONS" index "$HOME/.rdf/absent-lessons.md"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.rdf/lessons-index.md" ]
    [ ! -s "$HOME/.rdf/lessons-index.md" ]   # empty when there are no lessons
}

# ---- session-start-inject.sh -----------------------------------------------

@test "session-start-inject injects on startup, skips resume, is read-only" {
    command -v jq >/dev/null 2>&1 || skip "jq unavailable"
    mkdir -p "$HOME/.rdf"
    cp "$LESSONS_FIXTURE" "$HOME/.rdf/lessons-learned.md"
    bash "$LESSONS" index "$HOME/.rdf/lessons-learned.md"
    [ -f "$HOME/.rdf/lessons-index.md" ]
    local before after
    before="$(cat "$HOME/.rdf/lessons-index.md")"

    # startup → inject additionalContext JSON
    printf '{"source":"startup"}' > "$JSON"
    run bash "$INJECT" < "$JSON"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
    [[ "$output" == *'[W1]'* ]]

    # resume → emit nothing (context already present)
    printf '{"source":"resume"}' > "$JSON"
    run bash "$INJECT" < "$JSON"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    # compact → re-inject (intended: restores lessons dropped by compaction)
    printf '{"source":"compact"}' > "$JSON"
    run bash "$INJECT" < "$JSON"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null

    # READ-ONLY (F7): the hook never rewrites the index
    after="$(cat "$HOME/.rdf/lessons-index.md")"
    [ "$before" = "$after" ]
}

@test "session-start-inject emits nothing when no index exists" {
    printf '{"source":"startup"}' > "$JSON"
    run bash "$INJECT" < "$JSON"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$HOME/.rdf/lessons-index.md" ]   # read-only: absent index is not created
}

# ---- Phase 3: rdf-state diff_categories + r-save/r-start auto-act -----------

@test "rdf-state --full emits diff_categories object" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    command -v jq >/dev/null 2>&1 || skip "jq unavailable"
    local repo="$TEST_TMP/repo-dc"
    _mkrepo "$repo"
    # deterministic classification is a real measurement — the model no longer
    # classifies changed files in /r-save §1
    run bash -c 'bash "$1/state/rdf-state.sh" --full "$2" | jq -e ".diff_categories | type == \"object\""' \
        -- "$RDF_SRC" "$repo"
    [ "$status" -eq 0 ]
}

@test "rdf-state --full diff_categories counts staged files by path prefix" {
    command -v git >/dev/null 2>&1 || skip "git unavailable"
    command -v jq >/dev/null 2>&1 || skip "jq unavailable"
    local repo="$TEST_TMP/repo-dc2"
    _mkrepo "$repo"
    mkdir -p "$repo/canonical/commands" "$repo/docs/specs" "$repo/lib/cmd"
    touch "$repo/canonical/commands/foo.md" "$repo/docs/specs/bar.md" \
          "$repo/lib/cmd/x.sh" "$repo/README.md"
    git -C "$repo" add -A   # stage so porcelain lists per-file (untracked dirs collapse)
    run bash -c 'bash "$1/state/rdf-state.sh" --full "$2" \
        | jq -e ".diff_categories | .commands==1 and .cli==1 and .specs==1 and .docs==1"' \
        -- "$RDF_SRC" "$repo"
    [ "$status" -eq 0 ]
}

@test "r-save selects session-end cache and skips state re-run" {
    grep -q 'RDF_SESSION_ID' "$RDF_SRC/canonical/commands/r-save.md"
    grep -q 'Cache selection rule' "$RDF_SRC/canonical/commands/r-save.md"
    grep -q 'diff_categories' "$RDF_SRC/canonical/commands/r-save.md"
}

@test "r-save and r-start auto-run mem-compact preview at MEMORY threshold" {
    grep -q 'invoke .*/r-util-mem-compact.* in preview' "$RDF_SRC/canonical/commands/r-save.md"
    grep -q 'previewed compaction saves' "$RDF_SRC/canonical/commands/r-start.md"
}

# ---- Phase 4: rdf-lessons scan (dedup + contradiction heuristic) ------------

@test "rdf-lessons scan flags exactly the 50% duplicate" {
    mkdir -p "$HOME/.rdf"
    cp "$LESSONS_FIXTURE" "$HOME/.rdf/lessons-learned.md"
    bash "$LESSONS" index "$HOME/.rdf/lessons-learned.md"   # tag bullets with stable IDs
    run bash "$LESSONS" scan "$HOME/.rdf/lessons-learned.md"
    [ "$status" -eq 0 ]
    # the two paraphrased worktree bullets compute Jaccard 6/12 = 50% (>= _DUP_MIN)
    echo "$output" | jq -e '.duplicates | length == 1' >/dev/null
    echo "$output" | jq -e '.duplicates[0].jaccard == 50' >/dev/null
}

@test "rdf-lessons scan flags exactly the 36% contradiction" {
    mkdir -p "$HOME/.rdf"
    cp "$LESSONS_FIXTURE" "$HOME/.rdf/lessons-learned.md"
    bash "$LESSONS" index "$HOME/.rdf/lessons-learned.md"
    run bash "$LESSONS" scan "$HOME/.rdf/lessons-learned.md"
    [ "$status" -eq 0 ]
    # the two commit-gating bullets compute 4/11 = 36% overlap + opposing polarity
    echo "$output" | jq -e '.contradictions | length == 1' >/dev/null
    echo "$output" | jq -e '.contradictions[0].overlap == 36' >/dev/null
    # the 50% duplicate is caught by the dup branch first, never the contra branch;
    # the eight 0%-overlap negative pairs enter neither array
}
