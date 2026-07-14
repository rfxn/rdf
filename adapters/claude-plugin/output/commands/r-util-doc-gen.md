Generate publication-ready documentation for a specific surface of the
current project. Reads existing content, applies project documentation
standards from governance, ensures cross-surface consistency, and presents
results for user review before applying changes.

## Arguments
- `$ARGUMENTS` — required: `<surface>` (see surface table below)

## Setup

Read `.rdf/governance/index.md` to identify:
- Project name and root directory
- Documentation standards (from governance/conventions.md)
- Design system reference (from governance/reference/ if available)
- Authoritative files that define current state

## Surfaces

| Surface | Target File(s) | What It Covers |
|---------|----------------|----------------|
| `man-page` | `docs/*.1`, `man/*.8`, etc. | Full man page or specific sections |
| `readme` | `README.md` | Project README content |
| `help-text` | CLI help/usage functions | CLI help output |
| `config-comments` | Configuration files | Inline config documentation |
| `email-template` | Alert/notification templates | Email and notification templates |
| `changelog` | `CHANGELOG`, `CHANGELOG.RELEASE` | Release changelog entries |

## Protocol

### 1. Read existing content
Locate and read the current file for the specified surface using governance
index to find project file locations.

### 2. Read documentation standards
Load governance/conventions.md and any design system reference docs from
governance/reference/ to understand project-specific formatting rules.

### 3. Read adjacent surfaces
Before writing, read related surfaces to ensure terminology consistency.
Flag any contradictions found across surfaces.

| Writing This Surface | Also Read These |
|---------------------|-----------------|
| `man-page` | `help-text`, `readme`, `config-comments` |
| `readme` | `help-text`, `man-page` |
| `help-text` | `man-page`, `readme` |
| `config-comments` | `man-page`, `readme` |
| `email-template` | `config-comments`, `readme` |
| `changelog` | `readme`, recent `git log` |

### 4. Identify gaps and improvements
Compare existing content against governance documentation standards:
- Structure: correct section order?
- Completeness: all features documented?
- Examples: concrete, copy-pasteable?
- Formatting: consistent with governance conventions?
- Consistency: matches across surfaces?

### 5. Produce content
Write improved or new content following governance conventions and any
design system reference. Surface-specific standards:

- **man-page**: `man-pages(7)` section order, mandatory EXAMPLES section
- **readme**: one-sentence description first, install instructions, top 3 invocations
- **help-text**: 80-column limit, grouped by task
- **config-comments**: what, why, valid values, default for each variable
- **email-template**: summary at top, action before detail
- **changelog**: project tag convention, user-visible effects not implementation

### 6. Present for review

Show proposed content as a diff against existing content. Require explicit
user approval before applying changes.

Use structured formatting for the review presentation:

```
### Doc Generation — {surface} — {project}

#### Gap Analysis

| Area | Status | Detail |
|------|--------|--------|
| **Structure** | *{pass/needs work}* | {detail} |
| **Completeness** | *{pass/needs work}* | {detail} |
| **Examples** | *{pass/needs work}* | {detail} |
| **Formatting** | *{pass/needs work}* | {detail} |
| **Consistency** | *{pass/needs work}* | {detail} |
```

If cross-surface contradictions were found, use a blockquote callout:

```
> **Cross-Surface Contradictions**
> - `{surface_a}` says X, `{surface_b}` says Y — {recommendation}
```

#### Output templates by surface type

**`man-page`** — show proposed troff source in a fenced code block:
````
```nroff
.TH PROJECT 1 "2026-03-18" "v{version}" "User Commands"
.SH NAME
project \- one-line description
...
```
````

**`readme`** — show proposed markdown in a fenced code block:
````
```markdown
# Project Name

One-sentence description.

## Installation
...
```
````

**`help-text`** — show proposed output in a fenced code block:
````
```
Usage: project [OPTIONS]

Options:
  -h, --help     Show this help and exit
  ...
```
````

**`config-comments`** — show proposed inline comments in a fenced code block:
````
```bash
# VARIABLE_NAME
# What: brief description
# Why: rationale
# Valid: value1, value2, value3
# Default: value1
VARIABLE_NAME="value1"
```
````

**`email-template`** — show proposed template in a fenced code block:
````
```
Subject: {project} alert — {summary}

Action required: {action}

Details:
  ...
```
````

**`changelog`** — show proposed entries in a fenced code block:
````
```
[New] feature description
[Fix] bug fix description
```
````

End with a confirmation gate:

```
- [ ] Apply changes to `{target_file}`
- [ ] Skip — no changes needed
```

## Rules
- Always consult governance documentation standards before writing
- Cross-surface consistency is mandatory — flag contradictions
- Never hallucinate command output — use plausible representative examples
- Content must be publication-ready — no TODOs, no TBDs, no stubs
- Respect existing content structure — improve and extend, don't rewrite
- Do NOT modify files without explicit user approval
