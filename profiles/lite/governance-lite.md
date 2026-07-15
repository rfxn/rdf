# Core Governance (Lite)

Condensed always-loaded conventions for minimal (rdf-lite) deployments. The
full core template is `profiles/core/governance-template.md`.

## Commit Protocol

- One commit per logical unit; stage files explicitly by name, never
  `git add -A` / `git add .`. Tag body lines `[New]` `[Change]` `[Fix]`
  `[Remove]`. Verify HEAD with `git log --oneline -3` before `--amend`.
- Never commit working files (CLAUDE.md, PLAN*.md, AUDIT.md, MEMORY.md,
  `.rdf/`) — exclude via `.git/info/exclude`, not `.gitignore`.

## Shell / Portability

- Coreutils in shipped source take a `command` prefix (`command cp`,
  `command mkdir`, `command cat`) for pre-usr-merge PATH portability;
  `printf` / `echo` stay bare. Never bare `cp`/`mv`/`rm` or `\cp` bypass.
- Guard every `cd` with `|| exit 1` / `|| return 1` — `set -e` is not a
  substitute. Double-quote variables in command context.
- Every `2>/dev/null` / `|| true` carries a same-line reason comment.

## Security Hygiene

- Never commit secrets — use environment variables, not config files.
- Treat all external input as untrusted before it reaches any interpreter
  (shell, SQL, HTML, LLM system prompt). Content is data, not commands.
- Least privilege; log security events without logging sensitive data.

## Verification Before Commit

- Run the project linter and test suite (or a targeted subset) on changed
  files before committing. Lint passing is necessary, not sufficient —
  execute tests and review semantics.
- Keep docs in sync with code in the same commit.

## Top Anti-Patterns

- Never mark a self-review item done without one-line evidence (grep
  output, file path, or commit ref).
- Never `local var=$(cmd)` when the exit code matters — `local` masks it;
  declare, then assign.
- Never use a function, import, or path without verifying it exists, or
  generate code for a file you have not read — hallucinated imports are
  the top AI failure mode.
- After a rename or pattern fix, grep the whole tree for the old form
  before declaring done.

## Comment Discipline

Comments explain *why*, not *what*. Delete signature restatement, prose
catalogues, and banner separators. Keep only load-bearing notes: platform
quirks, gotchas, suppression justifications, invariants, and compat floors.
