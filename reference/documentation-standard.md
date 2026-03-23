# Documentation Standard

**Version:** 1.0.0
**Project:** RDF (rfxn Development Framework)
**Scope:** README structure, section ordering, SVG asset specifications,
badge conventions, documentation levels, and companion file requirements
for any project governed by RDF.

This document is a machine-readable and human-readable reference. Both
`rdf doctor --scope readme` and human authors use it as the authoritative
source of truth for documentation requirements.

---

## 1. Documentation Levels

Projects declare a documentation level in `.rdf/docs-level` (a single-line
file containing `floor`, `level-2`, or `level-3`). Default if file absent:
`floor`. Set by `rdf init` based on project type; manually adjustable.

```
echo "level-2" > .rdf/docs-level
```

Valid values: `floor`, `level-2`, `level-3`.

### Level Requirements

| Level | Required Sections | Required Assets | Required Companion Files |
|-------|-------------------|-----------------|--------------------------|
| Floor | Hero + badges, Quick Start, Introduction, Installation, Configuration, Usage (with exit codes table), License, Support | Consistent badge row (`flat-square` style) | None |
| Level 2 | Floor + What's New, Integration, Contents (ToC) | Floor + banner SVG (dark+light via `<picture>`) | SECURITY.md, CONTRIBUTING.md |
| Level 3 | Level 2 + Troubleshooting | Level 2 + pipeline/architecture diagram SVG, terminal demo SVG or GIF | Level 2 companion files |

**Floor** is the minimum standard for all projects with a README. It
requires consistent structure and a badge row but no visual assets or
companion files. Appropriate for shared libraries and internal tools.

**Level 2** adds above-the-fold visual identity (dark/light SVG banners),
a What's New section, a table of contents, an Integration section, and
the companion security and contributing files. Appropriate for consumer-
facing products.

**Level 3** adds Troubleshooting, a pipeline or architecture diagram SVG,
and a terminal demo asset. Appropriate for flagship products where
discoverability and onboarding are strategic priorities.

---

## 2. README Template

The canonical section order for all consumer projects. Sections marked
FLOOR are required at all levels. LEVEL 2 and LEVEL 3 sections are
required only at those levels and above.

```
# Project Name (Abbreviation)

[badges — centered, flat-square style]                    FLOOR

**Bold one-liner** -- key capabilities listed inline

> Copyright + License blockquote

---

## What's New in X.Y.Z                                    LEVEL 2
[3-5 bullet highlights of the release]

---

## Contents                                               LEVEL 2
[ToC with numbered sections linking to anchors]

---

## Quick Start                                            FLOOR
[4-8 commented commands, ends with a verify step]

---

## 1. Introduction                                        FLOOR
### 1.1 Supported Systems

## 2. Installation                                        FLOOR
### 2.1 Upgrading
### 2.2 Key Files
### 2.3 Uninstallation

## 3. Configuration                                       FLOOR (always first middle section)
### 3.N [subsections grouped by domain]

## 4. Usage                                               FLOOR (always second middle section)
### 4.N Exit Codes (table)

## 5-N. [Domain sections]                                 FLOOR
[noun-phrase titles, 3 words maximum]
[each opens with 1-2 sentence scope statement]

## Integration                                            LEVEL 2
## Troubleshooting                                        LEVEL 3

## License                                                FLOOR
## Support                                                FLOOR
```

### Template Notes

- `# Project Name (Abbreviation)` — use the full project name. If the
  project has a well-known abbreviation (e.g., APF, LMD, BFD), include
  it in parentheses in the heading.
- The bold one-liner immediately follows the badge row. It is the
  project's value proposition in one sentence. Key capabilities may be
  listed as a dash-separated inline continuation.
- The copyright blockquote uses `>` syntax. Format:
  `> (C) YYYY, R-fx Networks <proj@rfxn.com> / Licensed under GNU GPL v2`
- `## What's New` and `## Contents` appear before `## Quick Start`. The
  horizontal rules (`---`) visually separate the above-the-fold area from
  the main body.
- Domain sections (`## 5+`) are ordered by user workflow — not
  alphabetically or by implementation order.

---

## 3. Above-the-Fold Specification

At Level 2+, the above-the-fold area (before `## Quick Start`) uses a
`<picture>` element to serve dark and light SVG banner variants based on
the viewer's color scheme preference.

### `<picture>` Pattern

```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg">
    <img alt="Project Name" src="assets/banner-dark.svg" width="830">
  </picture>
</p>
```

The `<img>` fallback uses the dark variant. `width="830"` is set on the
`<img>` element, not as an SVG attribute, to allow GitHub's renderer to
scale correctly on narrow viewports.

The `<picture>` element is placed before the badge row. Full above-the-fold
order at Level 2:

```html
<p align="center">
  <picture>...</picture>
</p>

<p align="center">
  [badges]
</p>

**Bold one-liner**

> Copyright + License
```

---

## 4. SVG Asset Specifications

All SVG assets are stored in the project root `assets/` directory and
version-controlled. Asset filenames are fixed — `rdf doctor` checks for
exact filenames.

### Asset Inventory

| Asset | File | Dimensions | Required at | Structure |
|-------|------|------------|-------------|-----------|
| Banner (dark) | `assets/banner-dark.svg` | 830×140-180px | Level 2 | Dark background, project name (monospace), project icon/glyph, one-line tagline |
| Banner (light) | `assets/banner-light.svg` | 830×140-180px | Level 2 | Light background variant of the same layout |
| Pipeline/architecture | `assets/pipeline.svg` | 830×250-350px | Level 3 | Tool workflow as node-and-arrow flow diagram, dark background |
| Terminal demo | `assets/terminal-demo.svg` | 800×variable | Level 3 | CLI output screenshot (SVG or GIF accepted) |

The pipeline/architecture asset filename may vary (`pipeline.svg`,
`architecture.svg`, `workflow.svg`). `rdf doctor` checks for any SVG file
in `assets/` whose name contains `pipeline`, `architecture`, or `workflow`.

The terminal demo may be `.svg`, `.gif`, or `.png`. `rdf doctor` checks
for any asset in `assets/` whose name contains `terminal` or `demo`.

### SVG Technical Constraints (GitHub camo proxy)

GitHub serves SVGs via its camo image proxy. The proxy enforces these
constraints:

- No `<script>` elements — stripped silently
- No `<iframe>` elements — stripped silently
- No `<foreignObject>` elements — stripped silently
- No JavaScript animations — use CSS `@keyframes` only
- No SMIL (`<animate>`, `<animateTransform>`) — inconsistent browser
  support; avoid entirely
- No external resource references (`url(http://...)`) — all assets must
  be self-contained
- External font imports (`@import url(...)`) are stripped — embed fonts
  as Base64 `@font-face` with WOFF2 data URI

CSS `<style>` blocks are allowed, including `@keyframes`, `@media`
queries, and CSS transitions.

### Font Embedding

JetBrains Mono (rfxn standard) must be embedded as a Base64 WOFF2 data
URI. Pattern:

```xml
<defs>
  <style>
    @font-face {
      font-family: 'JetBrains Mono';
      src: url('data:font/woff2;base64,AAAA...') format('woff2');
      font-weight: 400;
      font-style: normal;
    }
  </style>
</defs>
```

Fallback font stack: `'JetBrains Mono', ui-monospace, Consolas, monospace`.

### SVG Structure Guidelines

Banner SVGs should be simple and maintainable:

- Dark banner: background `#07080a` or `#0d1117`, text `#ffffff`,
  accent `#4ade80`
- Light banner: background `#f8fafc` or `#ffffff`, text `#0f172a`,
  accent `#16a34a` (darkened green for contrast)
- Project name in large monospace font (24-36px)
- One-line tagline in smaller weight (14-16px)
- Project icon/glyph as SVG path (not external image)
- No photographic backgrounds — flat or gradient only
- Rounded rectangles (`rx="4"`) for any box elements

---

## 5. Badge Conventions

### Badge Order and Requirements

| Position | Badge | Style | Required at |
|----------|-------|-------|-------------|
| 1 | CI/build status | `flat-square` | Floor |
| 2 | Version | `flat-square` | Floor |
| 3 | License | `flat-square` | Floor |
| 4 | Platform or language | `flat-square` | Floor (optional) |
| 5 | Test count | `flat-square` | Level 2 (optional) |

All badges use `flat-square` style. This is a hard requirement — not
`flat`, not `for-the-badge`, not default. The style parameter is
`?style=flat-square` on shields.io URLs.

Badge row is centered using `<p align="center">`. Example:

```html
<p align="center">
  <a href="actions/workflows/ci.yml"><img src="https://github.com/rfxn/apf/actions/workflows/ci.yml/badge.svg?style=flat-square" alt="CI"></a>
  <a href="CHANGELOG"><img src="https://img.shields.io/badge/version-2.0.2-blue.svg?style=flat-square" alt="Version"></a>
  <a href="COPYING.GPL"><img src="https://img.shields.io/badge/license-GPL_v2-green.svg?style=flat-square" alt="License"></a>
</p>
```

### Badge Link Targets

| Badge | Links to |
|-------|---------|
| CI/build status | GitHub Actions workflow page |
| Version | `CHANGELOG` file |
| License | `COPYING` or `LICENSE` file |
| Platform/language | Relevant documentation or spec |
| Test count | Test directory or CI results |

---

## 6. Middle Section Conventions

### Numbering Rules

- All sections in the main body use numbered format: `## N. Title`
- Subsections use: `### N.M Title`
- No heading depth beyond `###` in README — do not use `####`
- Numbers are sequential with no gaps
- `## 3. Configuration` is always the first numbered middle section
- `## 4. Usage` is always the second numbered middle section
- `## 5+` are domain-specific, ordered by user workflow (not alphabetical)

The fixed positions for Configuration and Usage ensure that automated
tools and users can predict where these sections are across all projects.

### Title Style

- Noun-phrase titles: "Key Files", "Scan Modes", "Trust Management"
- 3 words maximum (exception: disambiguation requires longer)
- No verb phrases: "How to Configure" is wrong; "Configuration" is right

### Section Body

- Each numbered section opens with 1-2 sentences explaining what the
  section covers and when the user needs it
- Config variable tables use 3 columns: Variable | Default | Purpose
- Code examples use commented commands to explain each step
- Cross-reference the man page for exhaustive option lists:
  *"See `man <tool>`(1) for the complete option reference."*

### Example Section Structure

```markdown
## 3. Configuration

APF reads its main configuration from `/etc/apf/conf.apf`. Settings
are shell variables; edit the file directly and restart APF to apply.

See `man apf`(1) §CONFIGURATION for the complete variable reference.

### 3.1 Network Settings

| Variable | Default | Purpose |
|----------|---------|---------|
| IFACE_IN | eth0 | Inbound interface |
| IFACE_OUT | eth0 | Outbound interface |
| DSHIELD_AL | 1 | Enable DShield block list |
```

---

## 7. Companion Files

### Requirements by Level

| File | Required at | Purpose |
|------|-------------|---------|
| `SECURITY.md` | Level 2 | Security vulnerability reporting policy |
| `CONTRIBUTING.md` | Level 2 | Contribution guidelines and development setup |

Companion files are stored in the project root (alongside `README.md`).
They are version-controlled and committed to the repository.

### Template Generation

`rdf init` generates both files from templates in
`${RDF_HOME}/reference/templates/` if they do not exist. Existing files
are never overwritten. Projects may customize the generated files freely —
`rdf doctor` checks only for file existence, not content.

Template placeholders are substituted using `sed` with `|` delimiter:

| Placeholder | Source | Default |
|-------------|--------|---------|
| `{{PROJECT}}` | `basename` of project directory | (required) |
| `{{ORG}}` | GitHub remote org (from `git remote get-url origin`) | `rfxn` |
| `{{CONTACT_EMAIL}}` | RDF config or fallback | `proj@rfxn.com` |
| `{{LICENSE}}` | Detected from `LICENSE`/`COPYING` file | `GNU GPL v2` |

Templates are in `reference/templates/SECURITY.md` and
`reference/templates/CONTRIBUTING.md`.

---

## 8. Man Page Cross-Referencing

Projects with man pages maintain a bidirectional cross-reference between
README and man page. The README does not duplicate the full option list —
it covers the 5-10 most common options with examples and defers to the
man page for the complete reference.

### Cross-Reference Rules

- **README Usage section** includes: "See `man <tool>`(1) for the complete
  option reference."
- **Man page DESCRIPTION** includes: "See README.md for installation and
  configuration guides."
- **Exit codes table** appears in BOTH README (inside `## 4. Usage`) and
  man page (`EXIT STATUS` section). The man page is authoritative.
- README does NOT duplicate the full synopsis from man page — documents
  the most common invocations only.

### Cross-Reference Format

In README `## 4. Usage`:

```markdown
See `man apf`(1) for the complete option reference.
```

In man page `DESCRIPTION` section:

```
See README.md for installation and configuration.
```

---

## 9. Enforcement

`rdf doctor --scope readme` validates README structure against the
project's declared documentation level. All checks at the declared level
use FAIL severity (not WARN). Checks for levels above the declared level
are skipped silently.

The level is read from `.rdf/docs-level`. Default if absent: `floor`.

### Floor Checks

| Check | Description |
|-------|-------------|
| `readme-exists` | `README.md` is present in the project root |
| `badge-row` | Badge row detected (shields.io pattern in README) |
| `quick-start` | `## Quick Start` section present |
| `license-section` | `## License` section present |
| `numbered-sections` | Numbered section format (`## N.`) detected |
| `config-section` | `## 3. Configuration` (or `## 3.` prefix) present |
| `usage-section` | `## 4. Usage` (or `## 4.` prefix) present |
| `exit-codes-table` | Exit codes table in Usage section |

### Level 2 Checks (in addition to Floor)

| Check | Description |
|-------|-------------|
| `whats-new` | `## What's New` section present |
| `contents-toc` | `## Contents` section present |
| `integration` | `## Integration` section present |
| `security-md` | `SECURITY.md` exists in project root |
| `contributing-md` | `CONTRIBUTING.md` exists in project root |
| `banner-dark-svg` | `assets/banner-dark.svg` exists |
| `banner-light-svg` | `assets/banner-light.svg` exists |
| `picture-tag` | `<picture>` tag present in `README.md` |

### Level 3 Checks (in addition to Level 2)

| Check | Description |
|-------|-------------|
| `troubleshooting` | `## Troubleshooting` section present |
| `pipeline-svg` | Pipeline/architecture SVG exists in `assets/` |
| `terminal-demo` | Terminal demo asset exists in `assets/` |

### Example Output

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

---

## 10. Asset Directory Convention

```
assets/
  banner-dark.svg       # Level 2+ required
  banner-light.svg      # Level 2+ required
  pipeline.svg          # Level 3 required (name may vary)
  terminal-demo.svg     # Level 3 required (SVG, GIF, or PNG accepted)
```

All SVGs are stored in the project root `assets/` directory and
version-controlled. The `assets/` directory is committed — do not add it
to `.gitignore`.

---

## 11. Examples

### Example: Floor-level README (shared library)

```markdown
# tlog_lib

[![CI](https://github.com/rfxn/tlog_lib/actions/.../badge.svg)](...)
[![Version](https://img.shields.io/badge/version-2.0.4-blue.svg?style=flat-square)](CHANGELOG)
[![License: GPL v2](https://img.shields.io/badge/license-GPL_v2-green.svg?style=flat-square)](COPYING.GPL)

**Incremental log reading library for Bash** -- byte-offset cursors,
flock-safe concurrent access, journal-aware log following.

> (C) 2002-2026, R-fx Networks <proj@rfxn.com>
> Licensed under GNU GPL v2

## Quick Start

```bash
source tlog_lib.sh
tlog_init "/var/log/syslog" "/tmp/cursor"   # Initialize cursor
tlog_read lines                              # Read new lines since last cursor
echo "Got ${#TLOG_LINES[@]} new lines"       # Process results
```

## 1. Introduction
...

## 3. Configuration
### 3.1 Cursor Modes

| Variable | Default | Purpose |
|----------|---------|---------|
| TLOG_MODE | bytes | Cursor tracking mode (bytes or lines) |

## 4. Usage
### 4.1 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error |

See `man tlog_lib`(1) for the complete option reference.

## License
## Support
```

### Example: Level 2 above-the-fold (consumer product)

```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/banner-light.svg">
    <img alt="APF — Advanced Policy Firewall" src="assets/banner-dark.svg" width="830">
  </picture>
</p>

<p align="center">
  <a href="CHANGELOG"><img src="https://img.shields.io/badge/version-2.0.2-blue.svg?style=flat-square" alt="Version"></a>
  <a href="COPYING.GPL"><img src="https://img.shields.io/badge/license-GPL_v2-green.svg?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/shell-bash-4EAA25.svg?style=flat-square" alt="Shell">
</p>

**Advanced Policy Firewall for Linux** -- stateful packet inspection,
dynamic block lists, trust management, and event logging.

> (C) 2002-2026, R-fx Networks <proj@rfxn.com>
> Licensed under GNU GPL v2
```

---

## 12. Related Documents

- `reference/diagrams.md` — SVG diagram creation process and tooling
- `reference/templates/SECURITY.md` — security policy template
- `reference/templates/CONTRIBUTING.md` — contribution guidelines template
- `reference/brand.md` (workspace) — rfxn color palette, typography,
  project glyphs (not committed to RDF; workspace-only)
