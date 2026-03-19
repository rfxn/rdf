Produce publication-ready documentation content for a specified surface of
the current project. Read existing content, apply Design System Reference
standards, ensure cross-surface consistency, and present the result for
user review before applying changes.

## Invocation

```
/doc-author <surface> [project]
```

**surface** is one of:

| Surface | Target File(s) | What It Covers |
|---------|----------------|----------------|
| `man-page` | `docs/*.1`, `man/*.8`, etc. | Full man page or specific sections |
| `readme` | `README.md` | Project README content |
| `help-text` | `help()` / `usage()` in CLI file | CLI help output |
| `config-comments` | `conf.*`, `internals.conf` | Inline config documentation |
| `email-template` | `*.tpl`, alert templates | Email and notification templates |
| `changelog` | `CHANGELOG`, `CHANGELOG.RELEASE` | Release changelog entries |

**project** (optional) overrides project auto-detection from CWD.

## Protocol

### 1. Read existing content

For the specified surface, locate and read the current file:
- `man-page`: find `*.1`, `*.5`, `*.8` files in `docs/` or `man/`
- `readme`: find `README.md` in the project root
- `help-text`: grep for `help()` or `usage()` in the main CLI file
  (APF: `files/apf`, BFD: `files/bfd`, LMD: `files/maldet`)
- `config-comments`: read `conf.*` and `internals.conf` in `files/`
- `email-template`: find `.tpl` files in `files/` or template directories
- `changelog`: read `CHANGELOG` and `CHANGELOG.RELEASE`

If the surface does not yet exist (new project, missing man page), note
the absence and proceed to produce new content from scratch.

### 2. Read Design System Reference

Always read `/root/admin/work/proj/reference/design-system.md` before
writing any content. The design system is the authority on formatting,
conventions, and quality standards. Key sections by surface:

| Surface | Design System Sections to Consult |
|---------|----------------------------------|
| `man-page` | Section 4 (Documentation Formatting: Man Page Structure, Examples) |
| `readme` | Section 4 (README Structure, Examples in Documentation) |
| `help-text` | Section 1 (CLI Output Primitives), Section 4 (help() Function) |
| `config-comments` | Section 4 (Verbosity Balance), Section 2 (Error Message Standards) |
| `email-template` | Section 3 (Email and Notification Design, Multi-Channel Format Mapping) |
| `changelog` | Section 4 (Verbosity Balance) + project's existing changelog format |

### 3. Read adjacent surfaces

Before writing, read related surfaces to ensure terminology consistency.
The goal is to prevent "README says X, man page says Y" drift.

| Writing This Surface | Also Read These |
|---------------------|-----------------|
| `man-page` | `help-text`, `readme`, `config-comments` |
| `readme` | `help-text`, `man-page` |
| `help-text` | `man-page`, `readme` |
| `config-comments` | `man-page`, `readme` |
| `email-template` | `config-comments` (variable names), `readme` (feature descriptions) |
| `changelog` | `readme` (feature descriptions), recent `git log` |

Flag any contradictions found across surfaces. Report them to the user
before producing new content, so the authoritative version can be chosen.

### 4. Identify gaps and improvements

Compare the existing content against Design System Reference standards:

- **Structure**: does the surface follow the prescribed section order?
  (README: description, install, usage, config, examples.
  Man page: NAME, SYNOPSIS, DESCRIPTION, OPTIONS, EXIT STATUS, EXAMPLES, FILES, SEE ALSO.)
- **Completeness**: are all CLI flags, config variables, and exit codes documented?
- **Examples**: does every non-trivial feature have a concrete example with
  plausible output? Are examples copy-pasteable?
- **Formatting**: does help() fit 80 columns? Are section titles imperative verb form?
  Are tables aligned? Are units in headers, not cells?
- **Consistency**: do descriptions, defaults, and terminology match across surfaces?

List each finding with its location (file, line, section) and severity
(MUST-FIX for standards violations, SHOULD-FIX for improvements).

### 5. Produce content

Write the improved or new content following these surface-specific standards:

**man-page:**
- Follow `man-pages(7)` section order
- EXAMPLES section is mandatory with real commands and plausible output
- Group OPTIONS by task, not alphabetically
- Document every non-zero exit code in EXIT STATUS

**readme:**
- One-sentence description as the first line
- Install instructions with copy-pasteable commands
- Three most common invocations in Usage
- Never lead with project history, backstory, or badges

**help-text:**
- Must fit 80 columns (no line exceeds 79 characters)
- Show three most common invocations at top
- Pair short and long flags: `-l, --list`
- Group by task with blank-line separators

**config-comments:**
- Each variable gets: what it controls, why it matters, valid values, default
- Use consistent format across all variables in the file
- Complex variables get a one-line example after the comment

**email-template:**
- Summary at top: verdict and counts in the first three lines
- Action before detail: what to do before the evidence
- Follow multi-channel format mapping from the design system
- Never use "URGENT" or "CRITICAL" for non-critical events

**changelog:**
- Follow the project's existing changelog format and tag convention
- Every entry tagged: `[New]`, `[Change]`, or `[Fix]`
- Entries describe the user-visible effect, not the implementation detail

### 6. Present for review

Show the proposed content as a diff against existing content. For new
content (no existing file), show the full content clearly marked as new.

- Use unified diff format when modifying existing files
- Highlight what changed and why (reference the design system standard)
- Ask the user to confirm before applying any changes
- Do NOT overwrite files without explicit user approval

## Rules

- Always consult `/root/admin/work/proj/reference/design-system.md` before
  writing any content. If the design system file does not exist, warn the
  user and proceed with project CLAUDE.md conventions only.
- Cross-surface consistency is mandatory. Read adjacent surfaces before
  writing. Flag contradictions rather than silently choosing one version.
- Never hallucinate real command output. Use plausible representative
  examples that demonstrate the feature accurately.
- Never use placeholders like `[OPTIONS]` or `<args>` in example output.
  Show concrete flags and arguments.
- Content must be publication-ready. No TODO markers, no draft annotations,
  no "TBD" sections. If information is unavailable, omit the section rather
  than stub it.
- For email templates, follow the multi-channel format mapping from the
  design system. Test that the text-only version carries the same
  information as the HTML version.
- Respect existing content structure. Improve and extend rather than
  rewrite from scratch unless the existing content is fundamentally
  misstructured.
- When producing man page content, verify troff/nroff macro syntax is valid.
  Common macros: `.TH`, `.SH`, `.SS`, `.TP`, `.BR`, `.IP`, `.RS`/`.RE`.
- Follow the project's CLAUDE.md for project-specific conventions
  (version format, copyright headers, shebang style).
