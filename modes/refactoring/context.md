# Refactoring Mode

> Operational mode for large-scale restructuring, code movement, and
> API changes. Changes how agents approach work -- behavior preservation
> is the primary constraint. No new features, no bug fixes.

## Methodology

Follows a structured refactoring assessment:

1. **Inventory** -- catalog all files, functions, and callers affected
2. **Dependency graph** -- map what calls what, what imports what
3. **Test baseline** -- verify all existing tests pass before changes
4. **Execute** -- move/rename/extract with mechanical precision
5. **Verify** -- run full test suite after every phase, grep for old names

Refactoring types:
- Extract (function, module, package)
- Move (file relocation, directory restructuring)
- Rename (function, variable, file, API endpoint)
- Inline (collapse unnecessary abstraction)
- Decompose (split large functions/files)

## Completeness Verification

Refactoring is only complete when exhaustive evidence confirms no
references to old names, paths, or structures remain.

**Grep-based verification:**
- After every rename/move, grep the ENTIRE repo for the old name --
  not just the files you changed
- Include non-code files: configs, docs, tests, CI, build scripts,
  comments, string literals
- Grep output is the evidence -- include it in phase results
- A phase is not complete until old-name grep returns zero hits

**Caller exhaustiveness:**
- Before moving a symbol, enumerate ALL callers (grep, not memory)
- Cross-reference caller list against updated-caller list after the move
- Any discrepancy is a missed update, not a false positive

**False positive prevention:**
- A passing test suite does not prove completeness -- tests may not
  cover all call sites
- "I updated all the callers I found" is not evidence -- the grep
  output showing zero remaining references is evidence
- Partial renames (updated definition but missed 2 of 5 callers) are
  the most common refactoring defect -- verify counts match

## Planner Behavior

- Build dependency graph before proposing any move
- Every phase must have a regression test step
- No phase may change observable behavior (inputs, outputs, side effects)
- Prefer small phases with high confidence over large ambitious ones
- Search for all callers/importers of every moved/renamed symbol
- Default scope context: changes in this mode typically classify as scope:multi-file or scope:cross-cutting

## Quality Gate Overrides

Refactoring mode elevates regression detection.

| Override | Effect |
|----------|--------|
| Minimum gates | Gates 1 + 2 + 3 (reviewer always runs) |
| Reviewer weighting | Regression pass findings are MUST-FIX |
| Behavior change | ANY observable behavior change is MUST-FIX |
| Evidence requirement | Phase results must include old-name grep output |

## Reviewer Focus

Modified 4-pass sentinel with refactoring emphasis:
1. Anti-slop (standard -- watch for scope creep into "improvements")
2. **Regression** (ELEVATED -- every moved function must have before/after test)
3. Security (standard)
4. Performance (standard -- verify no degradation from restructuring)

Reviewer additionally checks:
- Old-name grep output included in phase results (zero hits required)
- Caller count before move matches updated-caller count after move
- No behavior changes disguised as refactoring

## Checklist

Before completing a refactoring phase:
- [ ] All tests pass before AND after changes
- [ ] No public API changes (same inputs produce same outputs)
- [ ] Grep for old names returns zero hits across entire repo (output included)
- [ ] Caller count before matches updated-caller count after
- [ ] No new dependencies introduced
- [ ] No new features or bug fixes mixed in
- [ ] Callers and importers updated for every move/rename
