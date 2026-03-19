Generate publication-ready documentation for a specific surface of the
current project. Reads existing content, applies project documentation
standards from governance, ensures cross-surface consistency, and presents
results for user review before applying changes.

## Arguments
- `$ARGUMENTS` — required: `<surface>` (see surface table below)

## Setup

Read `.claude/governance/index.md` to identify:
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

## Rules
- Always consult governance documentation standards before writing
- Cross-surface consistency is mandatory — flag contradictions
- Never hallucinate command output — use plausible representative examples
- Content must be publication-ready — no TODOs, no TBDs, no stubs
- Respect existing content structure — improve and extend, don't rewrite
- Do NOT modify files without explicit user approval
