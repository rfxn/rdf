# Core Governance Template

> Seed template for /r:init. Merged with codebase scan results during
> governance generation. Not copied verbatim -- scan data overrides
> where conflicts exist.

## Commit Protocol

- One commit per logical unit -- never batch unrelated changes
- Stage files explicitly by name -- never `git add -A` or `git add .`
- Tag body lines: `[New]` `[Change]` `[Fix]` `[Remove]`
- Never commit working files (CLAUDE.md, PLAN*.md, AUDIT.md, MEMORY.md,
  .claude/) -- exclude via .git/info/exclude, not .gitignore
- Amend safety: verify HEAD with `git log --oneline -3` before --amend

## Verification Checks

- Run project linter(s) on all changed files before commit
- Run project test suite (or targeted subset) before commit
- Scan for common anti-patterns (see anti-patterns section)
- Validate that documentation stays in sync with code changes

## Artifact Taxonomy

Working artifacts never committed:
- `CLAUDE.md` -- project governance (generated or curated)
- `PLAN*.md` -- session-local implementation plans
- `AUDIT.md` -- audit pipeline output
- `MEMORY.md` -- auto-memory persistence
- `.claude/` -- tool-specific configuration
- `work-output/` -- agent status files (ephemeral)

## Session Safety

- Agent output filenames use integer phase numbers, not labels
- Verify expected file paths exist before reading
- Write structured status to work-output/ after each phase
