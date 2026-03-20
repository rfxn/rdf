# Documentation Mode

> Operational mode for writing and updating project documentation.
> Changes how agents approach work -- read-then-write discipline,
> accuracy verification against source code, no code changes.

## Methodology

Follows a structured documentation assessment:

1. **Survey** -- identify undocumented or stale-documented public surfaces
2. **Prioritize** -- rank by user impact (README > API docs > internal docs)
3. **Read** -- read every function/endpoint/option before documenting it
4. **Write** -- produce documentation, not code
5. **Verify** -- cross-reference every documented item against source code

Documentation types:
- User-facing: README, getting started, tutorials, CLI help text
- API reference: endpoint docs, function signatures, parameter descriptions
- Architecture: system design docs, data flow diagrams, component maps
- Operations: runbooks, deployment guides, troubleshooting
- Man pages: command-line manual pages (troff/mandoc format)

## Planner Behavior

- Inventory undocumented or stale-documented surfaces before planning
- Prioritize by user impact, not by what's easiest to document
- Plan read-then-write: every doc phase starts with reading source
- Include verification step: documented behavior matches actual behavior
- Default scope context: changes in this mode typically classify as scope:docs

## Quality Gate Overrides

Documentation mode elevates user acceptance testing.

| Override | Effect |
|----------|--------|
| Gate 4 (UAT) | Elevated -- test docs from user perspective |
| Reviewer focus | Accuracy against source code is MUST-FIX |
| Scope | No code changes permitted -- docs only |

## Reviewer Focus

Modified 4-pass sentinel with documentation emphasis:
1. Anti-slop (standard -- no unnecessary verbosity, no filler)
2. **Regression** (ELEVATED -- do existing docs still match after changes?)
3. Security (standard -- docs should not expose internal secrets or paths)
4. Performance (N/A for docs)

Additional documentation-specific checks:
- Every documented function/option verified against source
- Examples actually run (code blocks are tested, not aspirational)
- No hallucinated parameters, options, or return values
- Version references match current project version

## Checklist

Before completing a documentation phase:
- [ ] Every documented function verified against source code
- [ ] Examples tested and produce documented output
- [ ] No stale version references
- [ ] No hallucinated parameters or options
- [ ] Cross-references to other docs are valid
- [ ] No code changes -- docs only
