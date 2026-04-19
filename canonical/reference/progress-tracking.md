# Progress Tracking

Shared protocol for task visibility across all RDF commands that run
multi-phase workflows.

## Creation Rule

**Create tasks sequentially, in phase order, BEFORE any work begins.**
The user must see the full scope of work upfront. Do NOT create tasks
incrementally as you reach each phase — that hides scope and breaks
the progress tracking UX.

**Why sequential, not batched:** When multiple `TaskCreate` calls land
in a single assistant message, the harness processes them concurrently
and the resulting order in the task list is non-deterministic (e.g.
"Phase 1" followed by 7, 6, 5, 3, 4, 2). One `TaskCreate` per message,
issued in plan order, guarantees the display order matches phase order.
The cost (N tool roundtrips upfront) is worth the deterministic UX.

This rule overrides the parent workspace "batch task creation" guidance
for any RDF command that renders a phase-ordered list.

## If TaskCreate tool is available (Claude Code)

Create each task in its own message, in plan/phase order:

```
[message 1] TaskCreate: subject: "Phase 1: ..."
                       activeForm: "Running phase 1"
[message 2] TaskCreate: subject: "Phase 2: ..."
                       activeForm: "Running phase 2"
...
```

Do NOT place multiple `TaskCreate` calls in a single message — parallel
execution breaks display order. This applies even when the consumer's
task list appears in a single code block in the command docs; the block
is a specification of *what* to create, not *how* to submit it.

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
