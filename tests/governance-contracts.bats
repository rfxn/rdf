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
# shellcheck disable=SC2154

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# _contract <canonical-relpath> <extended-regex> — assert the clause is present.
_contract() {
    local file="${RDF_SRC}/canonical/$1"
    [ -f "$file" ] || { echo "missing canonical file: $1"; return 1; }
    grep -qE "$2" "$file" || { echo "contract absent in $1: /$2/"; return 1; }
}

# ── Engineer: evidence production ─────────────────────────────────────────────

@test "engineer result declares a TDD_EVIDENCE section" {
    _contract agents/engineer.md 'TDD_EVIDENCE'
}

# ── Dispatcher: gates that enforce evidence + regression contracts ────────────

@test "dispatcher parses the Regression-case field from the target phase" {
    _contract agents/dispatcher.md 'Parse .*Regression-case'
}

@test "dispatcher emits NEEDS_CONTEXT when a DONE result lacks EVIDENCE" {
    _contract agents/dispatcher.md 'NEEDS_CONTEXT'
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
    _contract commands/r-review-answer.md 'does not block'
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
