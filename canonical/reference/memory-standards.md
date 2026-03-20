# MEMORY.md Standards

Extracted from parent CLAUDE.md for on-demand reference.

---

## Required Sections

Each project's MEMORY.md (under `.rdf/memory/`) must maintain
at minimum:

1. **Current state** — version, branch, phase status
2. **Open work items** — pending tasks, deferred findings
3. **Key patterns and conventions** — project-specific beyond parent CLAUDE.md
4. **Lessons learned** — debugging insights, cross-OS pitfalls
5. **Project-specific anti-patterns** — beyond the common list

## Update Triggers

Update MEMORY.md after:
- Every audit completion
- Every release
- Every lesson learned
- Every commit (if state tracking changed)

## Content Rules

- Link to supplemental files rather than inlining large reference data
- Volatile data (test counts, commit hashes, CI status) belongs in MEMORY.md,
  not in CLAUDE.md
- Keep MEMORY.md under 200 lines (truncated in context window beyond that)
- Create separate topic files (e.g., `codebase-map.md`, `ci-status.md`) for
  detailed notes and link from MEMORY.md
