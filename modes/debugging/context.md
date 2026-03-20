# Debugging Mode

> Operational mode for systematic bug hunting and incident response.
> Changes how agents approach work -- hypothesis-driven investigation
> with instrumentation before fixes. Never fix without a reproduction.

## Methodology

Follows a structured debugging assessment:

1. **Observe** -- collect symptoms, error messages, logs, stack traces
2. **Hypothesize** -- form 2-3 candidate root causes ranked by likelihood
3. **Instrument** -- add logging, assertions, or test cases to narrow down
4. **Isolate** -- identify the exact code path and input that triggers the bug
5. **Fix** -- address root cause, not symptoms
6. **Verify** -- regression test confirms the fix AND the bug cannot recur

Debugging approaches by symptom:
- Crash/panic: stack trace analysis, input reduction
- Wrong output: input-output tracing, boundary value testing
- Performance degradation: profiling, before/after comparison
- Intermittent failure: race condition analysis, state inspection
- Silent corruption: data integrity checks, assertion injection

## Planner Behavior

- Build hypothesis tree before proposing any fix
- Plan instrumentation steps before fix steps
- Prioritize hypotheses by evidence, not intuition
- Research known bugs in dependencies/frameworks for the symptom pattern
- Phase tags default to `risk:medium, type:feature` (the fix is the feature)

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

## Engineer Behavior

- Reproduce the bug with a failing test BEFORE writing any fix
- Instrument before fixing -- add logging or assertions to confirm hypothesis
- Never fix a bug you cannot reproduce
- When the first fix doesn't work, revisit the hypothesis, don't layer patches

## Checklist

Before completing a debugging phase:
- [ ] Bug reproduced with a failing test
- [ ] Root cause identified with evidence (not just "it works now")
- [ ] Fix addresses root cause, not symptoms
- [ ] Regression test added that would catch recurrence
- [ ] No unrelated changes mixed in
- [ ] Instrumentation (debug logging) removed before commit
