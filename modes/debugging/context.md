# Debugging Mode

> Operational mode for systematic bug hunting and incident response.
> Changes how agents approach work -- hypothesis-driven investigation
> with instrumentation before fixes. Never fix without a reproduction.

## Methodology

Follows a structured debugging assessment:

1. **Observe** -- collect symptoms, error messages, logs, stack traces
2. **Hypothesize** -- form 2-3 candidate root causes ranked by evidence weight
3. **Instrument** -- add logging, assertions, or test cases to narrow down
4. **Discriminate** -- run targeted checks that distinguish between hypotheses
5. **Isolate** -- identify the exact code path and input that triggers the bug
6. **Fix** -- address root cause, not symptoms
7. **Verify** -- regression test confirms the fix AND the bug cannot recur

Debugging approaches by symptom:
- Crash/panic: stack trace analysis, input reduction
- Wrong output: input-output tracing, boundary value testing
- Performance degradation: profiling, before/after comparison
- Intermittent failure: race condition analysis, state inspection
- Silent corruption: data integrity checks, assertion injection

## Evidence Discipline

Hypotheses must be ranked by evidence weight, not intuition or
familiarity. A hypothesis backed by a stack trace outranks one backed
by "this looks suspicious."

**Evidence hierarchy:**

| Evidence type | Weight | Example |
|---------------|--------|---------|
| Reproduction | Strongest | Failing test that triggers the bug on demand |
| Stack trace / core dump | Strong | Points to exact crash location |
| Log correlation | Moderate | Timestamp match between error and state change |
| Code reading | Weak | "This path looks like it could fail" |
| Intuition | Not evidence | Must be converted to testable prediction |

**Discrimination protocol:**
- Before committing to a hypothesis, design a check that would
  DISPROVE it -- if you cannot disprove it, investigate it
- When two hypotheses remain, find an observable that differs
  between them and instrument for it
- Never layer fix attempts -- if the first fix doesn't work, the
  hypothesis was wrong; go back to Observe

**False positive prevention:**
- "It works now" is not root-cause evidence -- explain the mechanism
- Correlation is not causation -- a recent change near the bug site
  does not prove it caused the bug without a causal chain
- Symptom disappearance after a change may be coincidence --
  the regression test must trigger the original symptom reliably

## Planner Behavior

- Build hypothesis tree before proposing any fix
- Plan instrumentation steps before fix steps
- Prioritize hypotheses by evidence, not intuition
- Research known bugs in dependencies/frameworks for the symptom pattern
- Default scope context: changes in this mode typically classify as scope:focused or scope:multi-file

## Quality Gate Overrides

None -- development gates apply. Reviewer checks root-cause quality.

| Override | Effect |
|----------|--------|
| Reviewer focus | Root-cause analysis quality is elevated |
| Regression | Bug reproduction test must exist before fix is accepted |

## Reviewer Focus

Modified 4-pass sentinel with debugging emphasis:
1. Anti-slop (standard -- no drive-by fixes to unrelated code)
2. **Regression** (ELEVATED -- does the fix include a test that reproduces the original bug?)
3. Security (standard -- bugs are often security-adjacent)
4. Performance (standard)

Reviewer additionally checks:
- Root cause identified with causal mechanism, not just "it works after this change"
- Hypothesis ranking documented with evidence, not just assertion
- No layered patches -- single root-cause fix

## Engineer Behavior

- Reproduce the bug with a failing test BEFORE writing any fix
- Instrument before fixing -- add logging or assertions to confirm hypothesis
- Never fix a bug you cannot reproduce
- When the first fix doesn't work, revisit the hypothesis, don't layer patches
- Rank hypotheses by evidence weight -- strongest evidence investigated first

## Checklist

Before completing a debugging phase:
- [ ] Bug reproduced with a failing test
- [ ] Hypotheses ranked by evidence weight (documented, not just claimed)
- [ ] Root cause identified with causal mechanism (not just "it works now")
- [ ] Fix addresses root cause, not symptoms
- [ ] Regression test added that would catch recurrence
- [ ] No unrelated changes mixed in
- [ ] Instrumentation (debug logging) removed before commit
