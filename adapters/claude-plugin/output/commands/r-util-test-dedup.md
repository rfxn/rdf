Find duplicate, overlapping, tautological, dead, and low-value tests in
the project's test suite. Read-only static analysis — does not modify
any files or execute the test suite.

## Arguments
- `$ARGUMENTS` — optional: specific test file or directory (default: full suite)

## Setup

Read `.rdf/governance/index.md` to identify:
- Test framework (BATS, pytest, jest, etc.)
- Test directory location
- Test conventions from governance/verification.md

## Definitions

**Duplicate** — two test blocks with identical descriptions, or same target
+ same inputs + same assertion with only a cosmetically different name.

**Overlapping** — 3+ tests exercise the same code path with the same input
class. The excess tests can be removed without loss of coverage.

**Tautological / Noop** — assertion that cannot fail given the test setup:
- Only assertion is success-check on a command that succeeds unconditionally
- Test asserts something the test itself just set up
- Expected value constructed identically to the actual

**Dead** — permanently unreachable:
- Unconditional skip with no guard condition
- Skip with "TODO"/"not implemented" and no issue tracker reference
- Tests whose fixtures are never created

**Low-value** — passes without asserting meaningful behavior:
- Single success assertion with no output/state/side-effect assertion
- Asserts only preconditions already verified by every other test
- Exit-code-only assertions on trivial code paths

## Analysis Methodology

### Pass 1 — Inventory
Build a count-per-file and total test count. Note files with unusually
high counts relative to the scope of the feature they cover.

### Pass 2 — Exact duplicates
Find test descriptions appearing 2+ times, even across different files.

### Pass 3 — Dead tests
Find unconditional skip/disable patterns. Read each hit in context.
Conditional skips (guarded by environment checks) are valid — skip them.

### Pass 4 — Tautological candidates
Find tests that run trivial commands or have single success assertions.
Read the full test block to confirm truly single-assertion before flagging.

### Pass 5 — Overlap candidates
From Pass 1, identify functions/features with 5+ dedicated tests. For
each, determine whether all variants test meaningfully distinct input
classes. Flag excess tests using the same input class.

### Pass 6 — Low-value
Look for tests that merely verify setup preconditions already implicit
in the test harness, or exit-code-only assertions on trivial paths.

## Verification Before Reporting

For every candidate finding, before including it in the report:
1. Read the full test block (not just the flagged line)
2. Check whether helper functions contain additional assertions
3. Confirm at least one other test exercises the same behavior before
   flagging OVERLAP
4. Do NOT flag a test that is the only coverage for a distinct behavior
5. When uncertain: classify as NOTE (investigate) rather than PRUNE

## Output

    ## Test Suite Dedup Report — <project>

    Total test count: N

    ### Summary
    | Category            | Candidates | Recommended Action   |
    |---------------------|------------|----------------------|
    | Duplicate           | N          | PRUNE or MERGE       |
    | Tautological / Noop | N          | PRUNE or REWRITE     |
    | Dead (skip)         | N          | PRUNE                |
    | Low-value           | N          | REWRITE or PRUNE     |
    | Overlapping         | N          | PRUNE (keep best)    |
    | **Total**           | **N**      | **safe removals: ~N**|

    ### Findings
    **[file:line] test "description"**
    Category: ...
    Reason: one-sentence explanation
    Action: PRUNE | MERGE with [...] | REWRITE
    Risk: LOW | MEDIUM

    ### Top 10 Safe Prunes
    Highest-confidence, lowest-risk removals in priority order.

## Rules
- Do NOT modify any files
- Do NOT execute the test suite — static analysis only
- Framework-specific: adapt grep patterns to the detected test framework
- When uncertain, classify as NOTE rather than PRUNE
