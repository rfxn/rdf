Domain: execute BATS test suite and report results.
Run all targets — do not gate one on another's result.
If parallel execution options are available, use it, run bats tests for
centos 6, 7, rocky9, and ubuntu 24.04

## Output Schema (prefix: TEX)
See audit-schema.md for full schema. Use prefix TEX, write to ./audit-output/agent8.md.
Format: `### [TEX-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim test output
in fenced blocks.

For each target capture: total/pass/fail/skip counts, full output for every
failure (name, file, line, assertion, actual vs expected), infrastructure errors.

For each failure determine: real regression or broken test? If regression,
identify introducing commit. If broken test, what changed? Multiple failures
traceable to single root cause? Flaky vs consistent?

Write to ./audit-output/agent8.md:
  Summary table: target | total | pass | fail | skip | infra errors
  Per-failure: finding schema entry with actual test output as Evidence
  Cross-failure patterns noted in a PATTERNS section at end of file

Evidence must be actual test output verbatim.

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For test failures: distinguish between real regressions (code broke) and
   test infrastructure problems (Docker issues, missing dependencies, network
   timeouts). Infrastructure problems are NOT code findings — report them as
   Info with a clear "INFRA" label, not as Major/Critical.
2. For flaky tests: run the failing test at least twice. If it passes on
   retry, it's flaky — report as Info, not Major.
3. For "multiple failures from single root cause" findings: trace to the root
   and report ONE finding, not N separate findings for N symptoms.
4. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: TEX DONE
Do not return findings in-context.
