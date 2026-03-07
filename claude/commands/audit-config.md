Domain: config files, parsers, defaults, and config loading order.

## Output Schema (prefix: CFG)
See audit-schema.md for full schema. Use prefix CFG, write to ./audit-output/agent6.md.
Format: `### [CFG-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Keys defined but never read in any sourced file
- Keys read in code but missing from default config
- New APF vars missing ${VAR:-default} in .ca.def
- New LMD renames missing compat.conf mappings — verify all deprecated
  variable mappings are current
- BFD var names or defaults that were changed (must be preserved)
- Config keys without inline comments, or with vague/wrong/stale comments
  (every key needs: type, valid values, default, effect)
- Invalid input not producing error or safe fallback
- Defaults unsafe for production hosting
- Load order disrupted: internals.conf → conf.* → compat.conf → OS override
  → CLI
- Inconsistent naming conventions, value formats, or comment style

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "key defined but never read" findings: grep ALL sourced files in the
   project (main script, all files in files/, internals.conf, all library
   files). Variables may be read via `${!var}` indirection, `eval`, or in
   sourced chains. Also check if the variable is used by an external consumer
   (e.g., APF vars read by BFD, LMD vars read by monitoring scripts).
2. For "key read but missing from config" findings: check if the variable has
   a `${VAR:-default}` fallback. If it does, a missing config entry is
   intentional (the default is the config). Only flag if no fallback exists
   AND the variable is required.
3. For "missing compat mapping" findings: verify the variable was actually
   renamed in this release by checking git diff. Variables that have always
   had the same name don't need compat mappings.
4. For "unsafe default" findings: consider the project's deployment context.
   These are server-side security tools run as root — some defaults that look
   "unsafe" in general contexts are correct for this use case.
5. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: CFG DONE
Do not return findings in-context.
