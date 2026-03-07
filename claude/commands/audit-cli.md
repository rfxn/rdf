Domain: CLI case dispatchers, help/usage text, validation, exit behavior.
Identify all CLI case dispatchers by pattern — do not rely on line numbers.

## Output Schema (prefix: CLI)
See audit-schema.md for full schema. Use prefix CLI, write to ./audit-output/agent4.md.
Format: `### [CLI-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Backend capabilities with no CLI surface
- CLI flags routing to incomplete or stub handlers
- Flags missing short (-x) or long (--example) form — list each with file/context
- --help/-h text inaccurate, missing defaults, or missing value format hints
- Help text describing removed or changed behavior
- Missing argument validation or non-meaningful error messages
- Missing required args producing silent failures instead of useful errors
- Inconsistent exit codes
- Error messages going to stdout instead of stderr
- Frozen entry violations: extract all existing case entries, cross-reference
  against git diff — any modification to an existing entry is critical

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "missing short/long form" findings: verify the project actually uses
   dual-form flags. Some projects intentionally use only one form. Check
   existing conventions before flagging.
2. For "help text inaccurate" findings: read the actual handler code for that
   flag — confirm the help text is wrong, not just differently worded.
3. For "stub handler" findings: read the full function — some handlers
   intentionally delegate to other functions or source additional files.
4. For "missing validation" findings: trace the input path — validation may
   happen in a sourced library function, not inline in the case statement.
5. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: CLI DONE
Do not return findings in-context.
