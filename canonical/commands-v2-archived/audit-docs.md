Domain: README, man pages, inline comments, usage examples, install docs.

## Large file handling (MANDATORY)

Doc files (README, man pages) can exceed 500-900 lines. Follow these rules
to avoid slow, wasteful processing:

- **Do NOT read entire man pages or READMEs in one call.** Use `grep -n`
  to find section markers first (`.SH`/`.SS` for man pages, `^##` for
  README), then read specific sections with offset/limit.
- **Read each file at most once per section.** Extract what you need on
  first read — do not re-read to verify.
- **Read smallest files first** (help/usage functions, conf file, then
  man page, then README) so you have compact reference data before
  tackling the largest files.
- **For cross-surface checks** (e.g., "does man page match README?"),
  extract structured data (flag names, variable names, defaults) into
  your response as compact tables on first read, then compare the tables
  — do not flip back and forth between file reads.

## Output Schema (prefix: DOC)
See audit-schema.md for full schema. Use prefix DOC, write to ./audit-output/agent5.md.
Format: `### [DOC-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Docs describing removed or changed behavior
- CLI flags documented but absent from case statements, or vice versa
- Config options documented but absent from config files, or vice versa
- New features with no documentation
- Removed features still documented
- Example invocations syntactically wrong or using old flag names
- New functions without explanatory comments
- Stale comments mismatching code below them
- Comments describing what rather than why in complex logic
- Contradictions between doc files
- Version or date drift across files
- Install steps referencing changed paths, commands, or dependencies

## Documentation Quality (beyond existence checks)

These checks assess whether documentation is good, not just whether it exists.
Reference: `/root/admin/work/proj/reference/design-system.md` Section 4
(Documentation Formatting Standards).

Check for:
- **Examples accuracy:** Do the documented examples actually work? Are the
  shown commands syntactically valid with plausible output? Do they use
  current flag names, not deprecated ones? Run the command mentally against
  the code to verify the output is realistic.
- **80-column compliance:** Does `help()` output fit 80 columns without
  horizontal scrolling? Check every line of help/usage output — no line
  should exceed 79 characters. Also check man page example blocks and
  README code blocks.
- **Imperative section titles:** Are all section headers in imperative verb
  form? "Configure Firewall Rules" not "Firewall Rule Configuration".
  "Monitor Authentication Logs" not "Authentication Log Monitoring".
  Check README section headers, man page `.SH`/`.SS` titles, and help
  text group headers.
- **README leads with function:** Does the README lead with what the tool
  does in one sentence (first line of the file), not project history,
  backstory, badges, or version numbers? The reader wants to know what
  this tool does immediately.

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "docs describe removed behavior" findings: verify the behavior is
   actually removed — read the code, don't just check git diff. Features may
   be refactored, not removed.
2. For "stale comments" findings: read the code below the comment. If the
   comment is approximately correct (covers the intent even if wording differs
   from implementation), it is NOT stale — discard it.
3. For "missing documentation" findings at Minor/Info level: only report if
   the undocumented feature is user-facing. Internal helper functions without
   doc comments are normal, not findings.
4. For "contradiction between docs" findings: verify both documents are current
   and intended to describe the same thing. Different docs may cover different
   contexts intentionally.
5. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: DOC DONE
Do not return findings in-context.
