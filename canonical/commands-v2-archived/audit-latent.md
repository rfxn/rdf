Domain: full codebase — not scoped to recent changes. Hunt for bugs and
correctness issues that predate this release. Read as if seeing it fresh.

## Output Schema (prefix: LAT)
See audit-schema.md for full schema. Use prefix LAT, write to ./audit-output/agent2.md.
Format: `### [LAT-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Conditions that can never be true or false
- Loops that cannot terminate or always terminate immediately
- Return paths that silently succeed on error
- Error handling that discards error and continues
- Functions with multiple exit paths producing inconsistent state
- Any shell anti-pattern (backticks, egrep, which, unquoted vars, etc.)
  anywhere in source regardless of when introduced
- Every TODO/FIXME in the codebase — note file, line, approximate age via
  git log -1 on that file
- Code assuming file/command/output exists without verification
- File path variables set conditionally (e.g., `_html=""` then `if ...; _html=path`)
  but passed unconditionally to functions that redirect/read them — the empty-string
  case causes `< ""` errors at runtime that bash -n and shellcheck cannot detect
- Config-conditional file creation (e.g., generating `.html` only when `format=html`)
  with consumers that don't check file existence — trace every consumer to verify
  it handles the missing case, especially across upgrade paths from prior versions
- Assumed network availability without timeout or fallback
- Via git log: files touched repeatedly across releases (churn signal),
  same class of fix in multiple commits (systemic signal), FIXMEs surviving
  multiple versions

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. Read 20+ lines of surrounding context for every suspected issue — the code
   may handle the condition you think is missing in a way you haven't seen yet
2. For "unquoted variable" findings: check if the variable is inside `[[ ]]`,
   on the RHS of an assignment, used as an array index, or in a context where
   word splitting cannot occur. These are NOT bugs — discard them.
3. For "error handling" findings: trace the caller chain. The caller may check
   `$?` or use `set -e`. A function returning silently is only a bug if its
   callers never check the result AND the failure has runtime consequences.
4. For "dead code" findings: grep the ENTIRE codebase including test files and
   sourced libraries. Functions may be called via variable indirection, `$cmd`,
   or from scripts you haven't read.
5. For shell anti-patterns (backticks, egrep, which): verify the hit is in
   project source, not in vendored/third-party code, comments, or test fixtures.
6. Discard anything that doesn't survive verification. Quality over quantity.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: LAT DONE
Do not return findings in-context.
