#!/usr/bin/env bats
# tests/governance-contracts.bats — behavioral-contract eval suite for RDF's own
# agents and commands. Each test asserts a load-bearing behavioral contract still
# exists in the canonical source, so a prompt/wording edit that silently drops one
# (e.g. deletes the dispatcher's NEEDS_CONTEXT gate, or turns /r-review-answer into
# a blocking gate) fails CI instead of shipping.
#
# Scope: the evidence-discipline chain — the framework's core value. Complements
# adapter.bats (generator mechanics) and avoids duplicating its assertions; these
# test behavior contracts, not deployment shape. Deterministic, no LLM required —
# contracts are preserved verbatim into deployment (adapter.bats proves that).
#
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# shellcheck disable=SC2154,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# _contract <canonical-relpath> <extended-regex> — assert the clause is present.
_contract() {
    local file="${RDF_SRC}/canonical/$1"
    [ -f "$file" ] || { echo "missing canonical file: $1"; return 1; }
    grep -qE "$2" "$file" || { echo "contract absent in $1: /$2/"; return 1; }
}

# _no_contract <canonical-relpath> <extended-regex> — negation guard: assert
# the clause is ABSENT (catches an inversion sentence a paraphrase-only edit
# could introduce, e.g. "NEEDS_CONTEXT is no longer required").
_no_contract() {
    local file="${RDF_SRC}/canonical/$1"
    [ -f "$file" ] || { echo "missing canonical file: $1"; return 1; }
    grep -qE "$2" "$file" && { echo "negation violated in $1: /$2/ matched"; return 1; }
    return 0
}

# ── Engineer: evidence production ─────────────────────────────────────────────

@test "engineer result declares a TDD_EVIDENCE section" {
    _contract agents/engineer.md 'TDD_EVIDENCE'
    # negation guard: no sentence says the section is now optional
    _no_contract agents/engineer.md 'TDD_EVIDENCE[^.]*\b(no longer|not required|optional|removed)\b'
}

# ── Dispatcher: gates that enforce evidence + regression contracts ────────────

@test "dispatcher parses the Regression-case field from the target phase" {
    _contract agents/dispatcher.md 'Parse .*Regression-case'
}

@test "dispatcher emits NEEDS_CONTEXT when a DONE result lacks EVIDENCE" {
    _contract agents/dispatcher.md 'NEEDS_CONTEXT'
    # negation guard: no sentence disapplies the gate
    _no_contract agents/dispatcher.md 'NEEDS_CONTEXT[^.]*\b(no longer|is not|never|does not)\b'
}

@test "dispatcher defaults to least machinery (serial over parallel)" {
    _contract agents/dispatcher.md 'least machinery|simplicity-budget'
}

# ── QA: independent re-execution of cited evidence ───────────────────────────

@test "qa re-validates EVIDENCE by re-running cited commands" {
    _contract agents/qa.md 'EVIDENCE re-validation'
}

@test "qa records SKIPPED for docs/focused scope (scope-gated re-validation)" {
    _contract agents/qa.md 'EVIDENCE_CHECK: SKIPPED'
}

# ── Reviewer: two modes + verification of its own claims ─────────────────────

@test "reviewer defines both challenge and sentinel modes" {
    # Anchor to the mode-definition headers, not bare prose mentions, so the
    # contract bites if a mode section is gutted or renamed.
    local f="${RDF_SRC}/canonical/agents/reviewer.md"
    grep -qE '^### Challenge Mode' "$f" && grep -qE '^### Sentinel Mode' "$f"
}

@test "reviewer must /r-verify-claim its MUST-FIX current-state assertions" {
    _contract agents/reviewer.md 'Verification protocol \(MUST-FIX assertions\)'
    _contract agents/reviewer.md '/r-verify-claim'
}

# ── /r-review-answer: structured routing, advisory (de-risked, no gate) ───────

@test "r-review-answer routes findings to FIX / REBUT / DEFER" {
    _contract commands/r-review-answer.md 'FIX, REBUT, or DEFER'
}

@test "r-review-answer is advisory — does not block build/ship/merge" {
    local f="${RDF_SRC}/canonical/commands/r-review-answer.md"
    _contract commands/r-review-answer.md 'does not block'
    # negation guard: no sentence promotes it to a gate (explicit if/return —
    # see the security-floor test above for why bare `! grep` is unsafe)
    if grep -qiE '(now|becomes|is) (a )?(blocking|hard) gate|must pass before|blocks? (/r-build|/r-ship|merge)' "$f"; then
        echo "negation violated: a sentence promotes r-review-answer to a gate"
        return 1
    fi
}

@test "r-review-answer flags unanswered MUST-FIX findings" {
    _contract commands/r-review-answer.md 'unanswered'
}

# ── /r-verify-claim: closed-set classifier with an honest escape hatch ────────

@test "r-verify-claim classifies into 5 closed-set claim classes" {
    _contract commands/r-verify-claim.md '5 closed-set'
}

@test "r-verify-claim emits UNVERIFIABLE for unclassifiable claims" {
    _contract commands/r-verify-claim.md 'UNVERIFIABLE'
}

# ── /r-util-mem-compact: anti-crystallization (dedup auto-merges, contradictions
#    are flagged only — auto NEVER resolves one) ───────────────────────────────

@test "consolidation never auto-resolves a contradiction" {
    _contract commands/r-util-mem-compact.md 'NEVER resolves a contradiction'
}

# ── Adapter: core governance is never paths-scoped (spec §4.3). Relocated from
#    tests/rules-deploy.bats — this is a load-bearing behavioral contract, not a
#    deployment-shape check, so it belongs in the contract suite. The _contract
#    helper only greps canonical/, so assert against the adapter source directly.

@test "adapter never scopes core governance (spec 4.3)" {
    grep -qE '\[\[ "\$profile" == "core" \]\] && return 0' \
        "${RDF_SRC}/adapters/claude-code/adapter.sh"
}

# ── Dispatcher: tier cap over scope→gate mapping (3.5 Scale) ──────────────────

@test "dispatcher caps gates by tier, never upgrades" {
    _contract agents/dispatcher.md 'Tier Cap'
    _contract agents/dispatcher.md 'only removes ceremony'
    _contract agents/dispatcher.md 'regression-only sentinel-lite'
    # negation guard: no sentence says the cap can raise/upgrade gates
    _no_contract agents/dispatcher.md 'tier cap[^.]*\b(can|may|will|does)[^.]*upgrade\b'
}

@test "tier cap never drops the security pass on scope:sensitive" {
    # M1 security floor: a bugfix/quick-plan tier must never let a security patch
    # skip Gate 2 or drop the sentinel Security pass (3.3.0 C1 RCE precedent).
    _contract agents/dispatcher.md 'Security floor'
    _contract agents/dispatcher.md 'sentinel-full'
    _contract agents/dispatcher.md 'scope:sensitive'

    local d="${RDF_SRC}/canonical/agents/dispatcher.md" t="${RDF_SRC}/canonical/reference/tiers.md" f
    # formula is stated verbatim in both restating files (tiers.md, dispatcher.md)
    for f in "$d" "$t"; do grep -qF 'max(security_floor, min(scope_gate, tier_cap))' "$f"; done
    # negation guard: no sentence disapplies the floor. NOTE: intentionally
    # `if grep ...; then return 1; fi` rather than bare `! grep ...` — this
    # check is not the function's last statement, and bash's `set -e` (which
    # bats runs test bodies under) explicitly exempts `!`-negated commands
    # from triggering early exit, so a bare `!` here would silently never
    # fail the test regardless of what it matches.
    if grep -qE 'Security floor[^.]*\b(no longer|not|never|does not)\b[^.]*appl' "$d" "$t"; then
        echo "negation violated: a disclaimer sentence disapplies the security floor"
        return 1
    fi
    # order: the floor paragraph precedes the first tier bullet inside the Tier Cap section
    local cap floor bullet
    cap="$(grep -n '^### Tier Cap' "$d" | head -1 | cut -d: -f1)"
    floor="$(grep -n '^\*\*Security floor' "$d" | head -1 | cut -d: -f1)"
    bullet="$(grep -n '^- `full`' "$d" | head -1 | cut -d: -f1)"
    [ -n "$cap" ] && [ -n "$floor" ] && [ -n "$bullet" ] && [ "$cap" -lt "$floor" ] && [ "$floor" -lt "$bullet" ]
    # the indicator list is one list: reviewer.md (source), tiers.md and dispatcher.md (restatements)
    local want got
    want="$(grep -A3 'filename contains' "${RDF_SRC}/canonical/agents/reviewer.md" | grep -oE '`[a-z]+`' | tr -d '`' | sort -u | paste -sd,)"
    for f in "$d" "$t"; do
        got="$(grep -A3 'filename contains' "$f" | grep -oE '`[a-z]+`' | tr -d '`' | sort -u | paste -sd,)"
        [ "$got" = "$want" ] || { echo "indicator list drift in $f: $got != $want"; return 1; }
    done
}

# ── /r-ship: living-spec fold into docs/specs/CURRENT.md (3.5 Scale) ──────────

@test "r-ship folds CURRENT.md and skips on bugfix" {
    # Short single-line anchors — grep -qE is line-based (no cross-wrap match).
    _contract commands/r-ship.md 'docs/specs/CURRENT.md'
    _contract commands/r-ship.md 'bugfix'
    _contract commands/r-ship.md 'rdf_clear_active_tier'
}

# ── /r-ship: per-minor platform-triage gate (D4, platform-alignment spike) ────

@test "r-ship preflight carries the platform-triage line (1d)" {
    _contract commands/r-ship.md '^### 1d\. Platform Triage'
    _contract commands/r-ship.md 'docs/platform-triage\.md'
    _contract commands/r-ship.md 'skipped — patch release'
    _contract commands/r-ship.md 'platform triage missing for'
}

@test "platform-triage ledger top block names the current MAJOR.MINOR or the next minor" {
    local ledger="${RDF_SRC}/docs/platform-triage.md"
    [ -f "$ledger" ] || { echo "missing ${ledger}"; return 1; }
    local ver major minor next want1 want2 top
    ver="$(command cat "${RDF_SRC}/VERSION")"
    major="${ver%%.*}"
    minor="${ver#*.}"; minor="${minor%%.*}"
    next=$((minor + 1))
    want1="${major}.${minor}"
    want2="${major}.${next}"
    top="$(grep -m1 -E '^## [0-9]+\.[0-9]+ — ' "$ledger" | sed -E 's/^## ([0-9]+\.[0-9]+) — .*/\1/')"
    [ "$top" = "$want1" ] || [ "$top" = "$want2" ]
}

# ── /r-spec: Clarify micro-gate precedes Brainstorm (3.5 Scale) ───────────────

@test "r-spec Clarify precedes Brainstorm" {
    # Order check via line numbers — _contract only proves presence, not sequence.
    local f="${RDF_SRC}/canonical/commands/r-spec.md"
    local clarify brainstorm
    clarify="$(grep -n '^## Phase 1.5: Clarify' "$f" | head -1 | cut -d: -f1)"
    brainstorm="$(grep -n '^## Phase 2: Brainstorm' "$f" | head -1 | cut -d: -f1)"
    [ -n "$clarify" ] && [ -n "$brainstorm" ] && [ "$clarify" -lt "$brainstorm" ]
    # negation guard: no sentence removes the gate or reorders it after
    # Brainstorm (explicit if/return — see the security-floor test above)
    if grep -qE 'Clarify[^.]*\b(removed|eliminated|no longer exists|folded into Brainstorm)\b' "$f"; then
        echo "negation violated: Clarify gate removed or reordered"
        return 1
    fi
}

# ── Canonical stays frontmatter-free (Reach — CC frontmatter is adapter-side) ──

@test "canonical commands carry no YAML frontmatter" {
    local root f
    root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    for f in "${root}"/canonical/commands/*.md; do
        [ "$(head -1 "$f")" != "---" ]
    done
}

@test "canonical stays frontmatter-free per the sync rule (no exception clause)" {
    _contract commands/r-sync.md 'canonical stays frontmatter-free'
    # negation guard: no sentence grants canonical an exception
    _no_contract commands/r-sync.md 'canonical (may|can|will|now) (carry|include|have)[^.]*frontmatter'
}

# ── Dispatcher: mandatory end-of-plan sentinel for 3+ phase plans (3.0.3) ──────

@test "dispatcher runs a mandatory end-of-plan sentinel for 3+ phase plans" {
    _contract agents/dispatcher.md '^### End-of-Plan Sentinel'
    _contract agents/dispatcher.md 'run a mandatory full 3-pass'
    # negation guard: no sentence makes the end-of-plan sentinel optional
    _no_contract agents/dispatcher.md 'End-of-Plan Sentinel[^.]*\b(optional|no longer mandatory|removed|not required)\b'
}

# ── /r-build: consistency micro-gate runs before any phase dispatch (3.5 Scale) ─

@test "r-build runs the consistency micro-gate before dispatch" {
    _contract commands/r-build.md 'Consistency micro-gate'
    _contract commands/r-build.md 'rdf-consistency\.sh check'
    # negation guard: no sentence makes the gate optional or disabled
    _no_contract commands/r-build.md '[Cc]onsistency micro-gate[^.]*\b(optional|skip(ped)?|not required|disabled)\b'
}

# ── Dispatcher: structured status writes to work-output after each phase ──────

@test "dispatcher writes structured status to work-output after each phase" {
    _contract agents/dispatcher.md 'Write structured status to \.rdf/work-output/'
    # negation guard: no sentence retires the status write
    _no_contract agents/dispatcher.md 'status (writes?|files?)[^.]*\b(no longer|optional|not required|removed)\b'
}

# ── Suite coverage: an unlisted .bats file never runs (derfxn.bats shipped dark)

@test "every tests/*.bats file is wired into the Makefile run list" {
    local f base missing=""
    for f in "${RDF_SRC}"/tests/*.bats; do
        base="$(basename "$f")"
        grep -qF "$base" "${RDF_SRC}/tests/Makefile" || missing="${missing} ${base}"
    done
    [ -z "$missing" ] || { echo "not in tests/Makefile:${missing}"; return 1; }
}
