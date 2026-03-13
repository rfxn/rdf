Analyze the project's BATS test suite for duplicate, overlapping, tautological,
dead, and low-value tests. Read CLAUDE.md first to locate the test directory and
suite structure. Read-only — report candidates only, do not modify any files.

## Definitions

**Duplicate** — two @test blocks with identical descriptions, or same `run` target
+ same inputs + same assertion with only a cosmetically different name.

**Overlapping** — 3 or more tests exercise the same code path with the same input
class (e.g., five tests all passing `192.0.2.x` to `validate_ip` when two cover the
class). The excess tests can be removed without loss of coverage.

**Tautological / Noop** — assertion that cannot fail given the test setup:
- Only assertion is `assert_success` on a command that succeeds unconditionally
- `run true` or `run echo "static string"` tests with no project logic involvement
- Expected value constructed identically to the actual (e.g., `assert_output "$(fn)"`
  where the test already called `fn` the same way to produce the expected value)
- Test asserts something the test itself just set up (e.g., write X to a file,
  then assert the file contains X — not testing project behavior)

**Dead** — permanently unreachable:
- Unconditional `skip` with no guard condition
- `skip "TODO"` / `skip "not implemented"` with no issue tracker reference
- Tests whose fixtures are never created and always cause setup failure

**Low-value** — passes without asserting meaningful behavior:
- Single `assert_success` with no output, state, or side-effect assertion
- Asserts only that a binary is executable or a file exists, when those are
  implicit preconditions already verified by every other test
- Exit-code-only assertions on code paths with no meaningful control flow

## Analysis methodology

### Pass 1 — Inventory (grep-based, do NOT read full files yet)
Build a count-per-file and total @test count:
```
grep -rn '^@test' tests/*.bats tests/uat/*.bats 2>/dev/null | wc -l
grep -rc '^@test' tests/*.bats tests/uat/*.bats 2>/dev/null | sort -t: -k2 -rn
```
Note files with unusually high counts relative to the scope of the feature they
cover — these are the first candidates for overlap analysis.

### Pass 2 — Exact duplicates
```
grep -rh '^@test' tests/*.bats tests/uat/*.bats 2>/dev/null | sort | uniq -d
```
Flag any @test description appearing 2+ times, even across different files.

### Pass 3 — Dead tests
```
grep -rn '^\s*skip' tests/*.bats tests/uat/*.bats 2>/dev/null
```
Read each hit in 5-line context. Flag unconditional `skip` lines (no `if`, no
variable guard). Skips conditioned on `[[ -z "$SOME_BINARY" ]]` are valid — skip.

### Pass 4 — Tautological candidates
```
grep -rn 'run true\b\|run echo\b' tests/*.bats 2>/dev/null
```
Then find test blocks that have `assert_success` but no `assert_output` or
`assert_line`. Use this pattern to locate candidates (it over-fires — read
each flagged block to confirm truly single-assertion):
```
grep -n 'assert_success\|assert_output\|assert_line\|assert_equal\|@test' tests/*.bats | \
  awk -F: 'prev ~ /@test/ && /assert_success/ && !seen[prev]++ {print prev} {prev=$0}'
```
For each candidate: read the full @test block (offset/limit to just that block).
Only flag if there are truly no additional assertions anywhere in the block,
including inside helper function calls.

### Pass 5 — Overlap candidates
From Pass 1, identify functions with 5+ dedicated tests. For each such function,
read its test blocks and determine whether all variants test meaningfully distinct
input classes. If multiple tests use the same input class (e.g., three valid IPv4
addresses all expected to pass), flag the excess as overlapping. Prioritize the
top 5 highest-count functions.

### Pass 6 — Low-value
Look for test files in the utility/validation domain (typically lowest-numbered
files: 01-*, 02-*) where the same failure mode is tested at multiple granularities
and the coarser test fully subsumes the finer one. Also check for infrastructure
tests that merely verify setup preconditions already implicit in the test harness.

## Verification before reporting

For every candidate finding, before including it in the report:
1. Read the full @test block (not just the flagged line)
2. Check whether helper functions called by the test contain additional assertions
   (grep the helper for `assert_` to confirm)
3. Confirm at least one other test exercises the same behavior before flagging OVERLAP
4. Do NOT flag a test that is the only coverage for a distinct behavior or error path —
   even if it looks simple, single-path coverage has value
5. For overlap: confirm the surviving test(s) cover the same input class, not just
   an adjacent one
6. When uncertain: classify as NOTE (investigate) rather than PRUNE (safe to remove)

## Output

```
## Test Suite Dedup Report — <project> v<version>

Total @test count: N  (N unit/integration, N UAT)

### Summary

| Category              | Candidates | Recommended Action           |
|-----------------------|------------|------------------------------|
| Duplicate             | N          | PRUNE or MERGE               |
| Tautological / Noop   | N          | PRUNE or REWRITE             |
| Dead (skip)           | N          | PRUNE                        |
| Low-value             | N          | REWRITE or PRUNE             |
| Overlapping           | N          | PRUNE (keep highest-quality) |
| **Total**             | **N**      | **safe removals: ~N**        |

### Findings

For each finding, one entry:

**[tests/NN-file.bats:LINE] @test "description"**
Category: Duplicate | Tautological | Dead | Low-value | Overlapping
Reason: one-sentence explanation of why this test adds no value
Action: PRUNE | MERGE with [tests/NN-file.bats:LINE "@test description"] | REWRITE
Risk: LOW (safe to remove without coverage loss) | MEDIUM (verify coverage first)

### Top 10 Safe Prunes
Highest-confidence, lowest-risk removals in priority order.
List file:line + @test description + one-line rationale for each.
```

Do not modify any files. Do not execute the test suite. Static analysis only.
