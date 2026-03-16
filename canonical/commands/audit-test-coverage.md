Domain: BATS suite in tests/ — read and analyze only, do not execute.

## Output Schema (prefix: COV)
See audit-schema.md for full schema. Use prefix COV, write to ./audit-output/agent7.md.
Format: `### [COV-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Functions, features, or behaviors in recent commits with no BATS coverage
  for happy path and error/edge cases
- New CLI flags not tested
- New config options not tested with valid, invalid, and boundary values
- New code paths unreachable by any existing test
- Tests asserting only exit code without asserting output
- Tautological assertions that can never fail
- Assertions mismatched to claimed behavior
- Expected values stale relative to current implementation
- Hardcoded paths in tests (should use discovered paths)
- Dead or permanently-skipped tests
- Non-RFC-5737 IPs — only 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24,
  2001:db8::/32 permitted
- State modified without teardown
- Order-dependent tests
- Duplicate test cases
- Failure/edge paths undertested relative to happy paths

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "function not tested" findings: search ALL test files (*.bats) for the
   function name. It may be tested indirectly via a higher-level test that
   exercises the code path. Only flag if no test exercises the function at all.
2. For "tautological assertion" findings: read the full test — an assertion
   that looks tautological in isolation may depend on setup/teardown context
   that makes it meaningful.
3. For "hardcoded paths in tests" findings: check if the test is intentionally
   testing a specific path (e.g., verifying install.sh puts files in the right
   place). Tests that validate path behavior NEED literal paths.
4. For "stale expected values" findings: verify the expected value is actually
   wrong by reading the current implementation. Don't assume a value is stale
   just because the implementation file was recently modified.
5. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: COV DONE
Do not return findings in-context.
