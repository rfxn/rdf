Domain: recent changes only. Begin with `git log` and `git diff` to scope.

## Output Schema (prefix: REG)
See audit-schema.md for full schema. Use prefix REG, write to ./audit-output/agent1.md.
Format: `### [REG-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Renamed/removed/moved functions still referenced elsewhere
- Sourced-file load order disrupted: internals.conf → conf.* → compat.conf
  → OS override → CLI
- Main CLI case dispatcher modified for existing entries (identify by pattern,
  not line number — any modification to a frozen entry is critical)
- Shared utility behavior changed across call sites
- TODO/FIXME introduced in recent commits
- Stubbed or no-op implementations
- Config options added but never read
- New config vars missing ${VAR:-default} or compat mappings
- Commit message intent not matching actual diff
- Logic inversions, wrong regex, bad defaults, off-by-one conditions
- Dead functions/variables, sourced files referencing removed helpers

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. Read the actual code context (20+ surrounding lines) — not just the diff hunk
2. For "function removed/renamed" findings: grep the ENTIRE codebase for all
   references. If zero callers remain, it's not a regression — discard it.
3. For "config never read" findings: grep all sourced files (internals.conf,
   the main script, all library files) — config may be read via variable
   indirection or sourced-file chains you haven't examined
4. For TODO/FIXME: check if it's newly introduced in THIS diff or pre-existing.
   Pre-existing TODOs are latent-agent territory, not regression findings.
5. Discard anything that doesn't survive verification. Fewer real findings
   beat more padded findings.

Also check changelog accuracy:
- Every entry in current release section of CHANGELOG and CHANGELOG.RELEASE
  must correspond to an actual diff change
- Tag correctness: [New]/[Change]/[Fix]
- Diff changes with no changelog entry

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: REG DONE
Do not return findings in-context.
