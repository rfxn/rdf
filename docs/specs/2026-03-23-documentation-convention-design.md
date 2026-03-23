# Documentation Convention — Design Spec

**Date:** 2026-03-23
**Project:** RDF (rfxn Development Framework)
**Scope:** New reference document + templates + doctor checks + workspace brand files

---

## 1. Problem Statement

rfxn maintains 16 projects with inconsistent documentation:

- **Badge inconsistency:** APF uses Version-License-CI order, BFD uses
  CI-Version-License-Shell-Platform (5 badges), Sigforge uses
  License-Bash-Tests. No shared style (`flat-square` vs default).
- **Section divergence:** BFD has 13 numbered sections including
  Troubleshooting; APF has 6; Sigforge uses unnumbered sections. Only
  BFD documents exit codes in README.
- **No visual assets:** Zero consumer projects (APF, BFD, LMD, Sigforge)
  have above-the-fold SVG banners or architecture diagrams. RDF is the
  only project with an `assets/` directory (2 SVGs).
- **Missing companion files:** No project has SECURITY.md or
  CONTRIBUTING.md. GitHub's Security tab is empty across all repos.
- **No enforcement:** `rdf doctor` checks governance artifacts, drift,
  memory, plans, GitHub labels, and sync — but has zero README or
  documentation checks.
- **Cross-project standards unversioned:** 8 reference files (1060 lines)
  in the workspace `reference/` directory are not version-controlled.
  The documentation convention needs a versioned, product-grade home.
- **Product/workspace conflation:** No clear separation between
  conventions RDF ships to any consumer (product) vs rfxn-internal
  operational knowledge (workspace).

The ruleplane-org already demonstrates what good visual assets look like
(24 SVGs including dark/light variants, terminal mockups, color palette
definitions) — but this design language has not been extended to any
consumer project README.

## 2. Goals

1. Define a README template with required sections and ordering rules
   that any RDF consumer can adopt
2. Define a progressive documentation level system (floor → level-2 →
   level-3) with explicit asset and section requirements per level
3. Define SVG asset specifications (dimensions, structure, dark/light
   `<picture>` pattern) that are brand-agnostic
4. Create SECURITY.md and CONTRIBUTING.md templates with placeholder
   variables for `rdf init` to fill
5. Add a `readme` scope to `rdf doctor` that validates README structure
   against the project's declared documentation level
6. Establish the product/workspace boundary: RDF `reference/` ships
   universal conventions; rfxn workspace `reference/` holds org-specific
   content (brand, OS targets, audit config)
7. Publish the convention as `rdf/reference/documentation-standard.md`
   alongside existing `diagrams.md`

## 3. Non-Goals

- **Creating actual SVG assets for rfxn projects** — this spec defines
  what assets are needed and their specifications; asset creation is a
  separate implementation effort per project
- **Migrating workspace `reference/` files into RDF** — the
  product/workspace boundary is defined here, but file migration is
  out of scope (separate plan)
- **Modifying existing project READMEs** — the convention defines the
  target state; README rewrites are per-project implementation work
- **Brand system as an RDF product feature** — the convention is
  brand-agnostic; a "define your brand" system in RDF is future work
- **Enforcing convention on non-RDF projects** — the convention is a
  reference document; enforcement only applies to projects using
  `rdf doctor`

## 4. Architecture

### File Map

| File | Status | Lines (est) | Purpose |
|------|--------|-------------|---------|
| `rdf/reference/documentation-standard.md` | New | ~350 | The convention document — README template, section rules, SVG specs, badge standards, level definitions |
| `rdf/reference/templates/SECURITY.md` | New | ~30 | SECURITY.md template with `{{PROJECT}}` placeholders |
| `rdf/reference/templates/CONTRIBUTING.md` | New | ~40 | CONTRIBUTING.md template with placeholders |
| `rdf/lib/cmd/doctor.sh` | Modified | +120 | New `_check_readme` function + `readme` scope |
| `rdf/lib/cmd/init.sh` | Modified | +30 | Generate SECURITY.md + CONTRIBUTING.md from templates |
| `reference/brand.md` | New (workspace) | ~60 | rfxn brand definition: palette, typography, project identities |

### No-Touch Files

| File | Reason |
|------|--------|
| `rdf/reference/diagrams.md` | Existing RDF visual reference — unchanged |
| `rdf/assets/pipeline.svg` | Existing RDF asset — unchanged |
| `rdf/assets/profiles-modes.svg` | Existing RDF asset — unchanged |
| `rdf/CLAUDE.md` | Convention changes don't affect RDF's own CLAUDE.md |
| `rdf/README.md` | RDF README alignment is a separate task |
| `reference/design-system.md` | Workspace file — migration out of scope |
| `reference/os-compat.md` | Workspace file — stays as workspace content |

### Dependency Tree

```
documentation-standard.md (new, standalone reference)
    |
    +-- templates/SECURITY.md (consumed by rdf init)
    +-- templates/CONTRIBUTING.md (consumed by rdf init)
    |
    +-- lib/cmd/doctor.sh (reads documentation-standard level definitions)
    +-- lib/cmd/init.sh (reads templates/ directory)

reference/brand.md (workspace, not committed to RDF)
    |
    +-- consumed by rfxn project SVG creation (manual)
    +-- referenced by rfxn CLAUDE.md files
```

### Product/Workspace Boundary

| Location | Content | Audience |
|----------|---------|----------|
| `rdf/reference/documentation-standard.md` | README template, section order, SVG specs, badge rules, level system, companion file rules | Any RDF consumer |
| `rdf/reference/templates/` | SECURITY.md, CONTRIBUTING.md with `{{placeholders}}` | Any RDF consumer |
| `reference/brand.md` (workspace) | rfxn palette (#07080a, #4ade80), JetBrains Mono, project glyphs | rfxn team only |
| `reference/design-system.md` (workspace) | CLI output conventions with rfxn-specific examples | rfxn team + agents |

### Size Comparison

| Artifact | Before | After |
|----------|--------|-------|
| `rdf/reference/` files | 1 (diagrams.md, 548 lines) | 4 files (~968 lines total: 548 existing + 420 new) |
| `rdf doctor` scopes | 6 (artifacts, drift, memory, plan, github, sync) | 7 (+readme) |
| `rdf init` generated files | CLAUDE.md, .rdf/, .git/info/exclude | + SECURITY.md, CONTRIBUTING.md |
| workspace `reference/` | 8 files, 1060 lines | 9 files (+brand.md, ~60 lines) |

## 5. File Contents

### 5.1 `rdf/reference/documentation-standard.md`

The core convention document. Structured as a reference that both humans
and AI agents consume.

| Section | Purpose | Lines (est) |
|---------|---------|-------------|
| Header + scope | What this document is, who it's for | 10 |
| Documentation levels | Floor, Level 2, Level 3 definitions with requirements tables | 40 |
| README template | Full section-by-section template with ordering rules | 120 |
| Above-the-fold spec | SVG banner spec, `<picture>` pattern, badge conventions | 50 |
| SVG asset specifications | Dimensions, structure rules, dark/light requirements, font embedding | 40 |
| Badge conventions | Order, style, required/optional per level | 25 |
| Middle section conventions | Numbering, fixed positions (Config=3, Usage=4), domain ordering | 30 |
| Companion files | SECURITY.md and CONTRIBUTING.md requirements | 15 |
| Man page cross-referencing | When to defer to man page, cross-reference format | 15 |
| Enforcement | What `rdf doctor --scope readme` checks per level | 25 |

**Key content decisions (from brainstorm):**

Documentation levels:

| Level | Required Sections | Required Assets | Required Companion Files |
|-------|-------------------|-----------------|--------------------------|
| **Floor** | Hero + badges, Quick Start, Introduction, Installation, Configuration, Usage (with exit codes table), License, Support | Consistent badge row | None |
| **Level 2** | Floor + What's New, Integration, Contents (ToC) | Floor + banner SVG (dark+light via `<picture>`) | SECURITY.md, CONTRIBUTING.md |
| **Level 3** | Level 2 + Troubleshooting | Level 2 + pipeline/architecture diagram SVG, terminal demo SVG or GIF | Level 2 |

README template (section order):

```
# Project Name (Abbreviation)

[badges]                              -- FLOOR

**Bold one-liner** -- key capabilities

> Copyright + License blockquote

---

## What's New in X.Y.Z              -- LEVEL 2
[3-5 bullet highlights]

---

## Contents                          -- LEVEL 2
[ToC with numbered sections]

---

## Quick Start                       -- FLOOR
[4-8 commented commands, ends with verify step]

---

## 1. Introduction                   -- FLOOR
### 1.1 Supported Systems

## 2. Installation                   -- FLOOR
### 2.1 Upgrading
### 2.2 Key Files
### 2.3 Uninstallation

## 3. Configuration                  -- FLOOR (always first middle section)
### 3.N [grouped by domain]

## 4. Usage                          -- FLOOR (always second middle section)
### 4.N Exit Codes (table)

## 5-N. [Domain sections]            -- FLOOR (ordered by user workflow)
[noun-phrase titles, 3 words max]
[each opens with 1-2 sentence scope statement]

## Integration                       -- LEVEL 2
## Troubleshooting                   -- LEVEL 3

## License                           -- FLOOR
## Support                           -- FLOOR
```

Above-the-fold SVG specifications:

| Asset | Dimensions | Required at | Structure |
|-------|------------|-------------|-----------|
| Banner (dark) | 830×140-180px | Level 2 | Dark background, project name (monospace), project icon/glyph, one-line tagline |
| Banner (light) | 830×140-180px | Level 2 | Light background variant of same layout |
| Pipeline/architecture diagram | 830×250-350px | Level 3 | Tool workflow as node-and-arrow flow, dark background |
| Terminal demo | 800×variable | Level 3 | CLI output screenshot (Freeze-style or hand-coded SVG) |

`<picture>` tag pattern (mandatory for banner at Level 2+):
```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg">
    <img alt="Project Name" src="assets/banner-dark.svg" width="830">
  </picture>
</p>
```

SVG technical constraints (GitHub camo proxy):
- No `<script>`, `<iframe>`, `<foreignObject>` (stripped)
- CSS `<style>` blocks allowed: `@keyframes`, `@media`, transitions
- External font imports (`@import url()`) stripped — embed as Base64
  `@font-face` with WOFF2 data URI
- No JavaScript animations — CSS only
- SMIL (`<animate>`) has inconsistent support — avoid
- External resource references blocked — all assets must be self-contained

Badge conventions:

| Position | Badge | Style | Required at |
|----------|-------|-------|-------------|
| 1 | CI/build status | `flat-square` | Floor |
| 2 | Version | `flat-square` | Floor |
| 3 | License | `flat-square` | Floor |
| 4 | Platform or language | `flat-square` | Floor (optional) |
| 5 | Test count | `flat-square` | Level 2 (optional) |

All badges use `flat-square` style. Badge row is centered (`<p align="center">`).
Links: Version → CHANGELOG, License → COPYING/LICENSE file, CI → Actions page.

Middle section conventions:
- All consumer projects use numbered sections: `## N. Title`
- Subsections: `### N.M Title` — no deeper than two levels in README
- Numbers are sequential, no gaps
- `## 3. Configuration` is always the first middle section
- `## 4. Usage` is always the second middle section
- `## 5+` are domain-specific, ordered by user workflow
- Noun-phrase titles, 3 words maximum (exception: disambiguation)
- Each section opens with 1-2 sentences explaining scope and when
  the user needs this section
- Config variable tables: 3 columns (Variable | Default | Purpose)
- Code examples use commented commands
- Cross-reference man page for exhaustive detail: *"See `man tool`(1)
  §SECTION for the complete reference."*

Man page cross-referencing:
- README Usage section includes: "See `man <tool>`(1) for the complete
  option reference."
- Man page DESCRIPTION includes: "See README.md for installation and
  configuration guides."
- Exit codes table appears in BOTH README (Usage section) and man page
  (EXIT STATUS section) — man page is authoritative
- README does NOT duplicate the full option list from man page —
  documents the 5-10 most common options with examples, defers to man
  page for the rest

### 5.2 `rdf/reference/templates/SECURITY.md`

| Field | Value |
|-------|-------|
| Placeholders | `{{PROJECT}}`, `{{ORG}}`, `{{CONTACT_EMAIL}}` |
| Sections | Supported Versions, Reporting a Vulnerability, Response Timeline, Scope |
| Lines | ~30 |

Content:
```markdown
# Security Policy — {{PROJECT}}

## Supported Versions

| Version | Supported |
|---------|-----------|
| latest release | Yes |
| previous minor | Security fixes only |
| older | No |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Email: {{CONTACT_EMAIL}}

Include:
- Description of the vulnerability
- Steps to reproduce
- Affected version(s)
- Impact assessment (if known)

## Response Timeline

- **Acknowledgment**: within 48 hours
- **Initial assessment**: within 5 business days
- **Fix or mitigation**: best-effort, typically within 30 days for
  confirmed vulnerabilities

## Scope

This policy covers the {{PROJECT}} codebase. For vulnerabilities in
dependencies, please report to the upstream maintainer and notify us
if the dependency is bundled.
```

### 5.3 `rdf/reference/templates/CONTRIBUTING.md`

| Field | Value |
|-------|-------|
| Placeholders | `{{PROJECT}}`, `{{ORG}}`, `{{CONTACT_EMAIL}}`, `{{LICENSE}}` |
| Sections | How to Contribute, Development Setup, Code Standards, Pull Requests, Security |
| Lines | ~40 |

Content:
```markdown
# Contributing to {{PROJECT}}

## How to Contribute

- **Bug reports**: Open a GitHub Issue with steps to reproduce
- **Feature requests**: Open a GitHub Issue with use case and rationale
- **Security vulnerabilities**: See [SECURITY.md](SECURITY.md)

## Development Setup

```bash
git clone https://github.com/{{ORG}}/{{PROJECT}}.git
cd {{PROJECT}}
# Project-specific setup instructions
```

## Code Standards

- All shell scripts pass `bash -n` and `shellcheck`
- Tests use the BATS framework: `make -C tests test`
- Commit messages follow project conventions (see CHANGELOG for format)

## Pull Requests

1. Fork the repository
2. Create a feature branch from the current release branch
3. Make your changes with tests
4. Ensure all tests pass: `make -C tests test`
5. Submit a pull request with a clear description

## License

By contributing, you agree that your contributions will be licensed
under the {{LICENSE}}.
```

### 5.4 `rdf/lib/cmd/doctor.sh` — Changes

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_check_readme()` | Does not exist | New function: validates README.md against declared documentation level | +70 lines (new function) |
| `_doctor_one()` | Runs 6 check categories | Runs 7 categories (adds readme) | Lines 463-484 |
| `_doctor_usage()` | Lists 6 scopes | Lists 7 scopes (adds readme) | Line 19 |

`_check_readme()` check inventory:

| Check | Level | Severity at declared level |
|-------|-------|---------------------------|
| README.md exists | Floor | FAIL |
| Badge row present (shields.io pattern) | Floor | FAIL |
| `## Quick Start` section exists | Floor | FAIL |
| `## License` section exists | Floor | FAIL |
| Numbered section format (`## N.`) | Floor | FAIL |
| `## 3. Configuration` present | Floor | FAIL |
| `## 4. Usage` present | Floor | FAIL |
| Exit codes table in Usage section | Floor | FAIL |
| What's New section present | Level 2 | FAIL |
| `## Contents` (ToC) present | Level 2 | FAIL |
| `## Integration` section present | Level 2 | FAIL |
| SECURITY.md exists | Level 2 | FAIL |
| CONTRIBUTING.md exists | Level 2 | FAIL |
| `assets/banner-dark.svg` exists | Level 2 | FAIL |
| `assets/banner-light.svg` exists | Level 2 | FAIL |
| `<picture>` tag in README.md | Level 2 | FAIL |
| `## Troubleshooting` section present | Level 3 | FAIL |
| Pipeline/architecture SVG in `assets/` | Level 3 | FAIL |
| Terminal demo asset in `assets/` | Level 3 | FAIL |

Level declaration: read from `.rdf/docs-level` (a single-line file
containing `floor`, `level-2`, or `level-3`). Default if file absent:
`floor`. This avoids modifying the governance index schema. Created by
`rdf init` based on project type (libraries → `floor`, products →
`level-2`). Manually adjustable.

### 5.5 `rdf/lib/cmd/init.sh` — Changes

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `cmd_init()` | Creates CLAUDE.md, .rdf/, .git/info/exclude | Also creates SECURITY.md + CONTRIBUTING.md from templates if missing | +25 lines |

New logic in `cmd_init()`:
1. After governance file creation, create `.rdf/docs-level` if missing
   (default: `floor` for libraries, `level-2` for products — inferred
   from profile type)
2. Check if SECURITY.md exists
3. If missing, read `${RDF_HOME}/reference/templates/SECURITY.md`,
   substitute `{{PROJECT}}` (from basename), `{{ORG}}` (from git remote
   org), `{{CONTACT_EMAIL}}` (from config or default `proj@rfxn.com`)
   using `sed` with `|` delimiter
4. Write to project root
5. Same for CONTRIBUTING.md with `{{LICENSE}}` = "GNU GPL v2" default
6. Report files created in init output

### 5.6 `reference/brand.md` (workspace, not committed to RDF)

rfxn-specific brand definition consumed by project asset creation.

| Section | Content |
|---------|---------|
| Palette | Dark: #07080a (bg), #161b22 (surface), #ffffff (text). Accent: #4ade80 (green). Muted: #8b949e, #7d8590. Light variants: #f8fafc (bg), #0f172a (text). |
| Typography | Primary: JetBrains Mono. Fallback: ui-monospace, Consolas, monospace. |
| Project identities | APF: parallel vertical lines (firewall gate). BFD: geometric threshold line. LMD: scan beam / magnifying glass. Sigforge: fingerprint/signature mark. |
| SVG template notes | Base64 WOFF2 embedding for JetBrains Mono. Window chrome pattern from ruleplane terminal-mockup.svg. Rounded rectangle nodes for pipeline diagrams. |

## 5b. Examples

### Example: Floor-level README (shared library)

```markdown
# tlog_lib

[![CI](https://github.com/rfxn/tlog_lib/actions/...badge.svg)](...)
[![Version](https://img.shields.io/badge/version-2.0.4-blue.svg?style=flat-square)](CHANGELOG)
[![License: GPL v2](https://img.shields.io/badge/license-GPL_v2-green.svg?style=flat-square)](COPYING.GPL)

**Incremental log reading library for Bash** -- byte-offset cursors,
flock-safe concurrent access, journal-aware log following.

> (C) 2002-2026, R-fx Networks <proj@rfxn.com>
> Licensed under GNU GPL v2

## Quick Start

source tlog_lib.sh
tlog_init "/var/log/syslog" "/tmp/cursor"   # Initialize cursor
tlog_read lines                              # Read new lines since last cursor
echo "Got ${#TLOG_LINES[@]} new lines"       # Process results
tlog_verify                                  # Verify cursor health

## 1. Introduction
...
## 2. Installation
...
## 3. Configuration
### 3.1 Cursor Modes
| Variable | Default | Purpose |
|----------|---------|---------|
| TLOG_MODE | bytes | Cursor tracking mode (bytes or lines) |
...
## 4. Usage
### 4.1 Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error |
...
## License
## Support
```

### Example: Level 3 above-the-fold (flagship project)

```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg">
    <img alt="LMD — Linux Malware Detect" src="assets/banner-dark.svg" width="830">
  </picture>
</p>

<p align="center">
  <em>Multi-engine malware scanner for Linux — MD5, SHA-256, HEX, YARA,
  ClamAV integration, real-time inotify monitoring</em>
</p>

<p align="center">
  <a href="..."><img src="https://img.shields.io/badge/version-2.0.1-blue.svg?style=flat-square"></a>
  <a href="..."><img src="https://img.shields.io/badge/tests-247_passing-brightgreen.svg?style=flat-square"></a>
  <a href="..."><img src="https://img.shields.io/badge/license-GPL_v2-green.svg?style=flat-square"></a>
  <a href="..."><img src="https://img.shields.io/badge/platforms-8_distros-orange.svg?style=flat-square"></a>
</p>

<p align="center">
  <img src="assets/pipeline.svg" alt="LMD Detection Pipeline" width="830">
</p>
```

### Example: `rdf doctor --scope readme` output

```
=== linux-malware-detect ===

  [readme]     [OK]  README.md present (707 lines)
  [readme]     [OK]  badge row detected (3 badges)
  [readme]     [OK]  ## Quick Start present
  [readme]     [OK]  ## License present
  [readme]     [OK]  numbered sections (## 1. through ## 12.)
  [readme]     [OK]  ## 3. Configuration present
  [readme]     [OK]  ## 4. CLI Usage present
  [readme]   [FAIL]  exit codes table not found in Usage section
  [readme]   [FAIL]  What's New section missing (level-2 requirement)
  [readme]   [FAIL]  SECURITY.md missing (level-2 requirement)
  [readme]   [FAIL]  CONTRIBUTING.md missing (level-2 requirement)
  [readme]   [FAIL]  assets/banner-dark.svg missing (level-2 requirement)
  [readme]   [FAIL]  assets/banner-light.svg missing (level-2 requirement)

  Summary: 7 OK, 0 WARN, 6 FAIL
```

### Example: `rdf init` companion file generation

```
$ rdf init /root/admin/work/proj/my-tool --type shell

  [init] Detected project: my-tool (shell)
  [init] Created CLAUDE.md from shell governance template
  [init] Created .rdf/governance/
  [init] Created .rdf/docs-level (floor)
  [init] Created SECURITY.md from template
  [init] Created CONTRIBUTING.md from template
  [init] Updated .git/info/exclude (4 entries)
```

## 6. Conventions

### Template Placeholder Convention

All templates use `{{VARIABLE_NAME}}` double-brace syntax. Variables:

| Placeholder | Source | Default |
|-------------|--------|---------|
| `{{PROJECT}}` | `basename` of project directory | required |
| `{{ORG}}` | GitHub remote org (parsed from `git remote get-url origin`) | `rfxn` |
| `{{CONTACT_EMAIL}}` | RDF config or fallback | `proj@rfxn.com` |
| `{{LICENSE}}` | Detected from LICENSE/COPYING file | `GNU GPL v2` |

### Documentation Level Declaration

Stored in `.rdf/docs-level` as a single-line file:

```
floor
```

Valid values: `floor`, `level-2`, `level-3`. Default if file absent:
`floor`. This avoids modifying the governance index schema — the file
is standalone and read independently by `rdf doctor`.

Set during `rdf init` (inferred from project type: libraries default
to `floor`, products default to `level-2`). Manually adjustable:
`echo "level-2" > .rdf/docs-level`.

### Asset Directory Convention

```
assets/
  banner-dark.svg       # Level 2+ required
  banner-light.svg      # Level 2+ required
  pipeline.svg          # Level 3 required (name varies: pipeline.svg, architecture.svg)
  terminal-demo.svg     # Level 3 required (or .gif/.png)
```

All SVGs stored in project root `assets/` directory, version-controlled.

## 7. Interface Contracts

### `rdf doctor --scope readme`

- Input: project path, reads README.md + `.rdf/docs-level`
  for `docs_level`
- Output: standard `_add_result()` entries (category: `readme`)
- Exit code: 1 if any FAIL at declared level, 0 otherwise
- Checks only fire for the declared level and below
- All checks at the declared level are FAIL severity (not WARN)

### `rdf init` companion file generation

- Input: project path, templates from `${RDF_HOME}/reference/templates/`
- Behavior: creates SECURITY.md and CONTRIBUTING.md if they do not
  exist. Never overwrites existing files.
- Placeholder substitution: `sed` with `|` delimiter to avoid
  conflicts with `/` in values: `sed "s|{{PROJECT}}|${name}|g"`
- Reports created files in init output

### Template files

- Location: `${RDF_HOME}/reference/templates/`
- Format: standard markdown with `{{PLACEHOLDER}}` variables
- Consumed by: `rdf init` (automated) and humans (manual copy)

## 8. Migration Safety

### Upgrade path

- `rdf doctor` gains a new scope (`readme`) — existing scopes unchanged
- `rdf init` gains companion file generation — existing behavior
  unchanged (SECURITY.md/CONTRIBUTING.md only created if missing)
- No existing files are modified by this change
- Projects without `.rdf/docs-level` default to `floor` —
  the least restrictive level. Floor requires only README structure
  checks (no companion files), ensuring no false FAILs on existing
  projects. SECURITY.md and CONTRIBUTING.md are Level 2 requirements

### Backward compatibility

- `rdf doctor` without `--scope readme` includes readme checks in
  the `all` scope (same as other check categories)
- `rdf doctor --scope readme` on a project without governance falls
  back to `floor` level checks
- Templates directory is new — no conflict with existing `reference/`
  content

### Rollback

- Remove `_check_readme()` from doctor.sh, remove `readme` from
  scope list and `_doctor_one()` dispatch
- Remove template generation from init.sh
- Delete `reference/templates/` directory and
  `reference/documentation-standard.md`
- No data migration — purely additive change

## 9. Dead Code and Cleanup

No dead code found. The changes are additive to existing files.

Note: `reference/design-system.md` Section 4 ("Documentation Formatting
Standards") in the workspace has a minimal README structure (5 bullet
points) that is superseded by this convention. The workspace file is
out of scope for this spec, but should be updated to reference
`documentation-standard.md` when the convention is published.

## 10a. Test Strategy

| Goal | Test method | Verification |
|------|-------------|-------------|
| Goal 1 (README template) | Manual review — convention document is prose | Section headings match template in documentation-standard.md |
| Goal 2 (level system) | `rdf doctor --scope readme` on projects at each level | Doctor output matches expected checks per level |
| Goal 3 (SVG specs) | Manual review — spec defines dimensions and constraints | Documentation includes all SVG specifications |
| Goal 4 (templates) | `rdf init` on a fresh directory | SECURITY.md and CONTRIBUTING.md created with correct substitutions |
| Goal 5 (doctor checks) | `rdf doctor --scope readme` on a project with/without README sections | Correct FAIL/OK results per declared level |
| Goal 6 (product/workspace boundary) | File locations after implementation | RDF reference/ has convention + templates; workspace reference/ has brand.md |
| Goal 7 (convention published) | File exists at `rdf/reference/documentation-standard.md` | `ls rdf/reference/documentation-standard.md` |

Shell tests for doctor changes:

```bash
# Verify _check_readme added to doctor
grep -c '_check_readme' rdf/lib/cmd/doctor.sh
# expect: 3 (definition + _doctor_one dispatch + scope case)

# Verify readme scope in usage
grep 'readme' rdf/lib/cmd/doctor.sh | head -3
# expect: matches in usage text, scope case, _doctor_one

# Verify templates exist
ls rdf/reference/templates/SECURITY.md rdf/reference/templates/CONTRIBUTING.md
# expect: both files present

# Verify placeholders in templates
grep -c '{{PROJECT}}' rdf/reference/templates/SECURITY.md
# expect: >=2

# Verify init generates companion files
grep '_generate_companion_files\|SECURITY\|CONTRIBUTING' rdf/lib/cmd/init.sh | head -5
# expect: matches for generation logic
```

## 10b. Verification Commands

```bash
# Goal 1: Convention document exists
ls rdf/reference/documentation-standard.md
# expect: file listed

# Goal 2: Level definitions in convention
grep -c 'Floor\|Level 2\|Level 3' rdf/reference/documentation-standard.md
# expect: >=10

# Goal 3: SVG specs in convention
grep -c '830\|<picture>\|banner-dark\|flat-square' rdf/reference/documentation-standard.md
# expect: >=5

# Goal 4: Templates exist with placeholders
grep '{{PROJECT}}' rdf/reference/templates/SECURITY.md && echo "OK"
# expect: OK
grep '{{PROJECT}}' rdf/reference/templates/CONTRIBUTING.md && echo "OK"
# expect: OK

# Goal 5: Doctor has readme scope
grep 'readme' rdf/lib/cmd/doctor.sh | wc -l
# expect: >=5

# Goal 5b: Doctor readme check function
grep -c '_check_readme' rdf/lib/cmd/doctor.sh
# expect: 3

# Goal 6: Workspace brand file exists
ls reference/brand.md
# expect: file listed

# Goal 7: Convention is in rdf/reference/
ls rdf/reference/documentation-standard.md rdf/reference/templates/
# expect: documentation-standard.md, SECURITY.md, CONTRIBUTING.md
```

## 11. Risks

1. **Convention adoption friction** — projects may resist restructuring
   READMEs to match the template.
   *Mitigation:* Progressive levels mean projects start at Floor (close
   to current state) and grow. `rdf doctor` provides concrete,
   actionable gap analysis.

2. **SVG maintenance burden** — dark/light banner variants double the
   asset count and must be kept in sync.
   *Mitigation:* Convention specifies that banners should be simple
   (project name + icon + tagline) to minimize update frequency. Brand
   changes (palette, font) are infrequent.

3. **Template drift** — SECURITY.md/CONTRIBUTING.md templates may
   diverge from what projects have customized.
   *Mitigation:* `rdf doctor` checks for file existence only, not
   content match. Projects are free to customize after generation.

4. **Doctor scope expansion** — adding `readme` to the default `all`
   scope means existing `rdf doctor` runs will show new FAILs.
   *Mitigation:* Default `docs_level` is `floor` (minimal requirements).
   Floor checks only README structure (sections, badges, numbering) —
   no companion files (SECURITY.md, CONTRIBUTING.md are Level 2).
   Most existing projects with a README will pass Floor checks with
   minor adjustments (exit codes table, numbered sections).

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Project has README.md but no `.rdf/docs-level` | Doctor falls back to `floor` level checks | `_check_readme()` reads `.rdf/docs-level` with `floor` default |
| Project has no README.md at all | Doctor reports single FAIL | `_check_readme()` returns after first FAIL, skips section checks |
| SECURITY.md already exists when `rdf init` runs | Init does not overwrite | `[[ -f SECURITY.md ]]` guard before template write |
| Project uses unnumbered sections (e.g., Sigforge) | Doctor reports FAIL for numbered section format | Correct — project must adopt numbered sections to pass Floor |
| Git remote has no org (e.g., `user/repo`) | `{{ORG}}` placeholder resolves to username | `sed` substitution uses whatever `git remote` parsing returns |
| `docs_level` set to unknown value | Doctor treats as `floor` | Case statement default branch |
| Project has `assets/` with non-SVG files only | Level 2/3 banner checks FAIL | Doctor checks for specific filenames, not directory existence |
| README.md has `## 4. CLI Usage` instead of `## 4. Usage` | Doctor check for Usage section passes | Grep pattern matches `## 4.` prefix, not exact title |

## 12. Open Questions

None — all design decisions resolved in brainstorm phase.
