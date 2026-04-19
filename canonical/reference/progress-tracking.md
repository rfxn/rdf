# Progress Tracking

Shared protocol for task visibility across all RDF commands that run
multi-phase workflows.

## Batch Creation Rule

**CRITICAL: Create ALL tasks in a single batch BEFORE any work begins.**
The user must see the full scope of work upfront. Do NOT create tasks
incrementally as you reach each phase — that hides scope and breaks
the progress tracking UX.

## If TaskCreate tool is available (Claude Code)

Create all tasks in ONE message (single tool-call batch). Example
shape (task names are command-specific):

```
TaskCreate: subject: "Phase one"
  activeForm: "Running phase one"
TaskCreate: subject: "Phase two"
  activeForm: "Running phase two"
```

Then as work progresses: mark each `in_progress` → `completed`.
For >30s operations, update activeForm with progress text.

For phases that don't apply (no PLAN.md, no AUDIT.md), mark
`completed` immediately with no spinner — the task still appears
in the list so the user sees the full scope.

## If TaskCreate is NOT available (Gemini CLI, Codex)

Output the FULL checklist BEFORE starting any work:

```
- [ ] Phase one
- [ ] Phase two
```

Then update each `[ ]` → `[x]` as phases complete, or `[-]` for
skipped phases.
