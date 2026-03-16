Domain: harvest planning and memory artifacts from the local project root only.
Do not read files outside the project root.

Read these files if they exist (skip silently if absent):
  ./CLAUDE.md
  ./PLAN.md
  ./MEMORY.md
  ./memory/*.md
  ./memory/**/*.md

Write to ./audit-output/context.md using ONLY the structured format below.

## Output format — one line per item, type-prefixed

```
OPEN: <description> | <source-file>
COMPLETED: <description> | <source-file>
PARTIAL: <description> | <source-file>
CONTRADICTION: <description> | <file-a> vs <file-b>
DUPLICATE: <description> | <file-a> + <file-b>
```

### Rules for extraction
- Extract ONLY actionable status items: open work, completed work, partial
  progress, contradictions between files, and duplicated descriptions
- Each line MUST be self-contained — no multi-line entries, no paragraphs
- Do NOT include: full file contents, architecture docs, variable references,
  testing instructions, project overviews, config details, or code conventions
- Do NOT reproduce verbatim file contents — summarize each item in one line
- Target: **under 100 lines total**. If items exceed 100, prioritize:
  OPEN and PARTIAL first, then CONTRADICTION, then COMPLETED. Drop DUPLICATE.

## Also write: ./audit-output/false-positives.md

Extract any sections from MEMORY.md, CLAUDE.md, or PLAN.md that describe
known false positives, deferred issues, or intentionally-accepted behaviors.
Write each as a one-line pattern:

```
FILE_PATTERN | DESCRIPTION
```

Example:
```
install.sh lmd.user.* | runtime-generated symlinks, not missing references
internals.conf [ -f "$dig" ] | works correctly, not a validation bug
```

If no known false positives are found, write:
`# No project-specific false positives found`

Write output files and exit. Do not return findings in-context.
