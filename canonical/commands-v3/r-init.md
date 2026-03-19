Governance initialization for any codebase. Scans the project, ingests
existing convention files, detects languages and tooling, and generates
supplementary governance under `.claude/governance/`.

`$ARGUMENTS` is the target path (optional, defaults to `.` for the
current working directory). Can be a subdirectory for monorepo scoping.

---

## Prerequisites

- The governance index schema must exist at `schemas/governance-index.md`
  in the RDF installation (created by Plan 1 Task 2)
- The target path must be a directory (warn if no `.git/` is present)

## Overview

/r:init runs 5 phases in sequence:

1. **Ingest** — scan for existing convention .md files (highest priority)
2. **Codebase scan** — detect languages, frameworks, directory structure
3. **Tooling detection** — CI/CD, containers, linters, git patterns
4. **Generate** — produce supplementary governance files
5. **Validate** — spot-check accuracy, flag low-confidence inferences

Output directory: `.claude/governance/` (relative to target path)

## Phase 1: Ingest Existing Convention Files

Scan the target directory for convention files in priority order.
These files remain authoritative — they are NEVER modified or replaced.

### Priority Cascade

Scan for each file in this order. Higher-priority sources override lower
ones when content overlaps:

```
Priority 1 (curated conventions — highest signal):
  - CLAUDE.md (project root and parent directories)
  - AGENTS.md
  - GEMINI.md

Priority 2 (project state and decisions):
  - MEMORY.md
  - PLAN.md / PLAN*.md

Priority 3 (Cursor conventions):
  - .cursorrules
  - .cursor/rules/*.md

Priority 4 (Copilot conventions):
  - .github/copilot-instructions.md

Priority 5-7 are covered by Phases 2-3 (scan and tooling).
```

### Ingest Procedure

For each file found:

1. Record the file path, line count, and modification date
2. Extract content categories present in the file:
   - **Architecture:** component maps, data flow, system boundaries
   - **Conventions:** coding style, naming, formatting, patterns
   - **Verification:** test commands, lint configs, CI checks
   - **Constraints:** platform targets, version floors, compatibility
   - **Anti-patterns:** known pitfalls, prohibited patterns
3. Build a coverage map: `{category -> [source_file, section_name, line_range]}`
4. DO NOT copy content from these files — only record what they cover
   and where. Governance files will reference them by section name.

### Monorepo Scoping

If `$ARGUMENTS` points to a subdirectory:
- Still check parent directories up to the git root for CLAUDE.md,
  AGENTS.md (these often live at the repo root)
- Scope all other file discovery to the target subdirectory
- Record the scoping in the governance index as `Scope: {subdir}`

### Output of Phase 1

An internal coverage map (not written to disk) that tracks:
- Which files were found and their priority tier
- Which governance categories they cover (full, partial, or none)
- Sections within each file that map to each category
