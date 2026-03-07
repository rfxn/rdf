Domain: version string and copyright consistency.

## Output Schema (prefix: VER)
See audit-schema.md for full schema. Use prefix VER, write to ./audit-output/agent12.md.
Format: `### [VER-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Execute:
  grep -rn 'VERSION=' files/ conf.* install.sh 2>/dev/null
  grep -rn 'version' docs/ README* *.md 2>/dev/null
  grep -rn 'Version:' *.spec man/* 2>/dev/null
  grep -rn 'Copyright\|copyright' files/ conf.* install.sh docs/ 2>/dev/null

All version references must match — flag every mismatch, identify authoritative.

All copyright headers must carry:
  R-fx Networks <proj@rfxn.com>, Ryan MacDonald <ryan@rfxn.com>, GPL v2,
  (C) 2002-YYYY with YYYY = current year

Flag every deviation and every stale year.

Include grep output verbatim as Evidence.

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "version mismatch" findings: identify the AUTHORITATIVE version source
   (usually the main script's VERSION= line) and verify all other references
   against it. Files that have their own independent version (e.g., shared
   libraries with TLOG_LIB_VERSION) are NOT mismatches.
2. For "stale copyright year" findings: check if the file was actually
   modified this year. Files untouched since last year do not necessarily need
   a copyright bump — only files being modified in the current release.
3. For "missing copyright fields" findings: verify the file type warrants a
   copyright header. Data files, test fixtures, and generated files typically
   don't need one.
4. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: VER DONE
Do not return findings in-context.
