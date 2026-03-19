Pre-release verification checklist for the current project. Read CLAUDE.md to
determine project type and version. Execute ALL checks, report results, and
produce a release-readiness summary. Do NOT modify files — report only.

## 1. Version consistency
Run the version grep commands from the project's CLAUDE.md. Flag every mismatch.
Identify the authoritative version source and list all files that differ.

## 2. Copyright year check
Verify all copyright headers carry the current calendar year.
```
grep -rn 'Copyright\|copyright\|(C)' files/ conf.* install.sh docs/ 2>/dev/null
```
Flag every stale year.

## 3. CHANGELOG integrity (includes dedup)
- Read CHANGELOG and CHANGELOG.RELEASE
- Verify CHANGELOG.RELEASE content is a subset of CHANGELOG
- Verify every entry has correct tag ([New]/[Change]/[Fix])
- Cross-reference entries against `git log` — flag entries without commits
  and commits without entries
- Run `/rel-chg-dedup` — full deduplication, overlap collapse, fluff detection,
  and structural validation. Report all findings from that pass here.

## 4. PLAN.md status
- Read PLAN.md — list any open MUST items (blockers)
- List open SHOULD items (non-blocking but notable)
- Verify all COMPLETED phases match actual git history

## 4b. GitHub issue status
- Verify a `type:release` issue exists for this version:
  `gh issue list --label "type:release" --state open --json number,title`
- Verify all `type:phase` issues for this release are closed (status: Done)
- If a parent `type:initiative` exists, verify it is linked in the release issue body
- Report any open phase issues as blockers

## 5. AUDIT.md status (if exists)
- List any unresolved Critical or High findings
- Note open Medium count
- Flag any regressed items

## Large documentation file methodology (checks 6-7)

Doc files (README, man pages) can exceed 500-900 lines. Inefficient patterns
waste context and time. Follow this methodology for ALL doc-related checks.

### Read-once extraction (MANDATORY)

Read each documentation surface exactly ONCE and extract structured data into
your response text before moving to the next surface. Never re-read a file to
answer a question you should have captured on first read.

**Extraction pass** — for each surface, extract in a single read:
1. **CLI flags**: short form, long form, description (one line each)
2. **Config variables**: name, default value, description (one line each)
3. **Section inventory**: section headers with line numbers

Write these as compact tables in your response. All subsequent comparison work
operates on these extracted tables — not by re-reading files.

**Surface read order** (smallest to largest, so smaller extracts are ready
when you reach the large files):
1. `help()` / `usage()` — grep for the function, read just that block
2. `conf.*` — config file, typically 100-300 lines
3. Man page — use `grep -n '\.SH\|\.SS\|\.TP'` to get section offsets,
   then read specific sections with offset/limit as needed
4. README — use `grep -n '^##'` to get section offsets, then read specific
   sections with offset/limit rather than the full file
5. `importconf` — only the migration/preamble logic, not the full file

**For man pages over 400 lines**: do NOT read the entire file. Grep for
section markers first, then read only the OPTIONS and CONFIGURATION sections
(where flags and variables live). Read other sections only if a specific
check requires them.

**For README over 400 lines**: do NOT read the entire file. Grep for `^##`
headers to get the section map, then read only the sections relevant to the
current check (typically Configuration, Usage, Installation, Upgrading).

### Comparison phase

After all surfaces are extracted, compare the extracted tables:
- Diff CLI flag lists (help vs man vs README)
- Diff config variable lists (conf file vs man vs README)
- Check defaults match across surfaces
- Check descriptions agree (not identical — semantically consistent)

Report mismatches from the extracted data. Only re-read a file if you need
to resolve an ambiguity in the extracted data (e.g., a description was
truncated and you need the full context).

## 6. Documentation quality review
Read all user-facing documentation (README, man page, help output, config file
comments, install banner) and evaluate for release-grade quality. This is a
qualitative review — not a sync check (that follows in step 7).

Follow the read-once extraction methodology above. The quality review uses
the section inventory and a single reading pass — do not re-read sections.

### Clarity & usability
- **Jargon without context** — flag technical terms used without explanation
  on first appearance (e.g., "pressure trip" without saying what it means)
- **Wall-of-text sections** — paragraphs over ~6 lines with no structure;
  suggest breaking into bullets, tables, or subsections
- **Missing examples** — config variables or CLI flags described only in
  prose with no concrete example showing usage and expected output
- **Ambiguous defaults** — variables where the documented default is unclear
  or the effect of the default is not explained (e.g., `"0"` — does 0 mean
  off, unlimited, or auto?)
- **Action-gap** — sections that explain *what* a feature is but not *how*
  to use it; the reader should never have to guess the next step

### Completeness
- **New features without a section** — anything added this release that is
  user-facing but has no README or man page coverage
- **Error messages without troubleshooting** — error strings in the code
  that a user could encounter but that are not covered in troubleshooting
  or explained near the relevant config
- **Undocumented exit codes** — if the project defines named exit codes,
  verify they are listed somewhere users can find them
- **Upgrade impact** — behavioral changes this release that affect existing
  users but are not called out in the upgrade section

### Formatting & conventions
- **Consistent variable presentation** — config vars should use the same
  format everywhere (backtick-quoted in prose, table rows with default and
  description)
- **Consistent CLI presentation** — flags use the same long/short form
  ordering and description style across README, man page, and help
- **Man page conventions** — verify `man-pages(7)` section ordering
  (NAME, SYNOPSIS, DESCRIPTION, OPTIONS, FILES, SEE ALSO, etc.)
- **Link rot** — flag any URLs in docs that can be trivially verified as
  dead (known sunset services, moved domains); do not fetch

For each finding, note the file, location, and a short suggested improvement.
Classify severity as WARN (should fix before release) or NOTE (nice-to-have).

## 7. Documentation sync audit
Verify that all user-facing documentation surfaces are consistent with each
other. Per CLAUDE.md, CLI options, config variables, exit codes, and key file
paths must match across all surfaces.

This check operates on the extracted tables from the methodology section
above. If check 6 already ran, reuse its extracts — do NOT re-read files.

Checks:
- **help() vs man page** — every CLI flag in `usage_short()`/`usage()` must
  appear in the man page with matching description; no man-page-only flags
- **help() vs README** — every CLI flag in help must appear in README Usage
  section; descriptions must agree
- **man page vs README** — config variable tables, default values, and
  descriptions must match between the two
- **conf file vs man page** — every user-facing variable in `conf.*` with a
  comment must appear in the man page config section with matching default
- **conf file vs README** — same cross-check against README config tables
- **importconf / .ca.def** — new config variables must have upgrade-path
  handling (preamble defaults or merge logic)

For each mismatch, report the surface pair, variable/flag name, and the
discrepancy. Classify as:
- **MISSING** — present in one surface but absent from another
- **MISMATCH** — present in both but description or default differs
- **STALE** — references a removed/renamed item

## 8. Pre-commit validation
Run `/code-validate` checks (bash -n, shellcheck, anti-pattern greps).

## 9. Test matrix readiness
- Verify all CI targets documented in CLAUDE.md exist as Makefile targets
- Check that .github/workflows/ matrix matches documented targets
- Note last CI run status if accessible via `gh`

## 10. Test suite quality
Run `/test-dedup` and report the summary table only. This check is NON-BLOCKING —
test quality candidates do not prevent release but should be tracked for the next
cycle.

Flag as WARN if: total candidates > 10, or any unconditional `skip` blocks exist.
Flag as PASS otherwise.

## Output
```
# Release Readiness: <Project> v<version>

| Check | Status | Details |
|-------|--------|---------|
| Version consistency | PASS/FAIL | <details> |
| Copyright years | PASS/FAIL | <count> stale |
| CHANGELOG integrity | PASS/FAIL | <issues from rel-chg-dedup> |
| Open blockers | PASS/FAIL | <count> MUST items |
| Audit findings | PASS/WARN | <C>C/<H>H open |
| Doc quality (clarity/usability) | PASS/WARN | <count> WARN, <count> NOTE |
| Doc sync (README/man/help) | PASS/FAIL | <count> mismatches |
| Lint/validation | PASS/FAIL | <count> failures |
| CI matrix | PASS/WARN | <coverage> |
| Test suite quality | PASS/WARN | <count> candidates |

Overall: READY / NOT READY / READY WITH WARNINGS
```

If NOT READY, list specific blocking items.

## Editing methodology (when fixing findings from checks 6-7)

When the user asks you to fix doc sync or quality issues found by this
checklist, follow these rules to avoid slow, repetitive file processing:

### Collect-then-batch (MANDATORY)
1. **Collect ALL changes first** — do not start editing after the first
   finding. Walk through every finding and build a complete change list
   organized by file.
2. **Batch edits per file** — make all changes to README in one pass, then
   all changes to the man page, then conf file, etc. Never alternate
   between files (read A, edit A, read B, edit B, read A again, edit A...).
3. **Targeted reads only** — when editing a specific section, use
   offset/limit to read just that section. Do not re-read the full file
   to find the edit location when you already know the line number or
   section header from the audit pass.

### Anti-patterns to avoid
- **Round-trip per finding**: read file → find spot → edit → re-read to
  verify → next finding → read same file again. Instead: collect all
  spots, make all edits, verify once at the end if needed.
- **Full-file re-reads after edits**: the Edit tool confirms success. Do
  not re-read 900 lines to verify a 2-line change landed correctly.
- **Section-by-section comparison during editing**: the audit pass already
  identified what needs changing. During editing, go directly to the
  target location — do not re-compare surfaces.
- **One edit per tool call**: when multiple edits are needed in the same
  file and they don't overlap, make them all in parallel tool calls.
- **Reading the entire man page**: use grep for `.SH`/`.SS` section
  markers to find offsets, then read only the relevant section.
