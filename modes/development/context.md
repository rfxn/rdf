# Development Mode

> Default operational mode. Standard feature development with TDD
> workflow, progressive quality gates, and commit-per-phase protocol.

## Methodology

This is the implicit mode when no mode is specified. It follows the
standard RDF workflow:

1. Plan -> spec -> implementation plan (via /r:plan)
2. Execute phases with TDD cycles (via /r:build)
3. Quality gates per scope classification (via dispatcher)
4. Commit per completed phase

## Planner Behavior

- Brainstorm features, refactors, or bug fixes
- Research best practices for the project's domain
- Challenge assumptions with evidence
- Produce spec + implementation plan with phase descriptions

## Quality Gate Overrides

None — development mode uses the dispatcher's automatic gate selection.
The dispatcher auto-derives scope classification from phase content and
selects appropriate gates. No developer configuration required.

The dispatcher resolves findings internally (engineer fix/refute cycles)
and surfaces only unresolved findings to the developer.

## Reviewer Focus

Standard 4-pass sentinel review:
1. Anti-slop
2. Regression
3. Security
4. Performance

All passes weighted equally.

## Checklist

Before completing a phase:
- [ ] Tests pass (red -> green -> refactor cycle complete)
- [ ] Linter/formatter clean
- [ ] Anti-pattern scan clean
- [ ] Documentation updated if user-facing changes
- [ ] Commit message follows project conventions
