# /r-plan — Planning Command

Take a spec (or equivalent input) and decompose it into an
execution-grade implementation plan (PLAN.md). You never write code.
You produce plans.

This is the second stage of the spec-plan-build-ship pipeline.

`$ARGUMENTS` — input source for the plan:

```
/r-plan                          — auto-detect most recent spec in docs/specs/
/r-plan docs/specs/foo.md        — file path (contains / or ends with .md)
/r-plan https://github.com/...   — GitHub URL (starts with http/https)
/r-plan #42                      — issue shorthand (# + digits)
/r-plan --resume                 — resume interrupted planning session
```

**Argument detection logic:**
- Contains `/` or ends with `.md` → file path → read as spec input
- Starts with `http` or `https` → GitHub URL → fetch via `gh`
- Starts with `#` followed by digits → issue shorthand → `gh issue view {N}`
- Equals `--resume` → resume from existing PLAN.md (see Resume Protocol)
- No argument → scan `docs/specs/` for most recent file by mtime

**Input validation:**
- File path: verify file exists and is readable
- GitHub URL: verify `gh` CLI available, fetch and validate response
- Issue shorthand: verify `gh` CLI available, fetch issue body
- Auto-detect: scan `docs/specs/` sorted by mtime descending, use
  most recent. If `docs/specs/` is empty or missing, offer transparent
  delegation to `/r-spec`:
  ```
  "No spec found. Would you like to start with /r-spec to design
  one first? [Y/n]"
  ```
  If Y: run the `/r-spec` workflow inline, then continue into
  planning when the spec is complete. If N: stop.

---

## Task List Protocol

At command startup, create tasks for live progress tracking:

```
TaskCreate:
  subject: "Read codebase and spec, plan decomposition strategy"
  activeForm: "Reading codebase and spec"
TaskCreate:
  subject: "Write execution-grade implementation phases"
  activeForm: "Writing implementation phases"
TaskCreate:
  subject: "Challenge review and user approval"
  activeForm: "Reviewing plan"
```

Issue each `TaskCreate` in its own message, in the order shown — see
[reference/progress-tracking.md](../reference/progress-tracking.md)
for why parallel batches break display order.

Lifecycle: all tasks start `pending`. Before starting each step,
mark its task `in_progress`. After completing, mark `completed`.

---

## Resume Protocol

If `--resume` is specified or PLAN.md exists with incomplete phases:

1. Read existing PLAN.md
2. Detect phase completion status:
   - A phase is **complete** if it has a trailing `---` horizontal
     rule before the next phase heading (or EOF)
   - A phase without a trailing `---` is **truncated** — regenerate it
   - Compare the preamble's `**Phases:** {N}` count against actual
     phase headings to detect **missing** phases
3. Present resume state:
   ```
   Resuming plan for: {topic}
   Written: {M} phases complete
   Truncated: Phase {N} (will regenerate)
   Missing: Phases {N+1}-{total}

   Continue? [Y/start fresh]
   ```
4. If continuing: skip complete phases, regenerate truncated, write
   missing. If starting fresh: delete PLAN.md and begin from Step 1.

---

## Step 1: Read + Analyze

Mark task "Read codebase and spec" as `in_progress`.

Plans must be **execution-grade**: a fresh agent with zero codebase
context can execute any phase mechanically, step by step, without
asking questions or reading the spec. This is the difference between
an architect's outline and construction blueprints.

### 1.1 Read the Spec

Read the input source (spec file, GitHub issue, or URL) in full.
Extract:
- Goals and non-goals
- Architecture decisions and file map
- Dependency tree
- Conventions and patterns
- Verification commands
- Risks and mitigations

### 1.2 Read the Codebase

Before writing any phase, read every file that will be touched.
Collect:
- Exact line numbers for code that will be moved, modified, or deleted
- Function signatures and their current locations
- Existing boilerplate patterns and conventions
- Variable names, source guard patterns, version formats
- Test file references to files being changed

This is mandatory. Plans written without reading the codebase produce
vague phases ("extract functions to new file") that block the engineer
with ambiguity. Plans written after reading the codebase produce
precise phases ("cut lines 61-173 from functions.apf, paste after
boilerplate in apf_ipt.sh").

Mark task "Read codebase and spec" as `completed`.

---

## Step 2: Write PLAN.md

Mark task "Write execution-grade implementation phases" as `in_progress`.

### 2.1 Write Plan Preamble

Every plan starts with four sections before any phases:

**Header:**

```markdown
# Implementation Plan: {topic}

**Goal:** {1-2 sentence description of what is being built/changed}

**Architecture:** {brief description of the approach}

**Tech Stack:** {language, version floor, test framework, key tools}

**Spec:** docs/specs/{filename}

**Phases:** {N}
```

The `**Phases:** {N}` line enables crash recovery — compare against
actual phase headings to detect missing phases on resume.

**Conventions:**

Define patterns used across multiple phases ONCE here so phases can
reference them without repetition:

```markdown
## Conventions

**Boilerplate** — every new file starts with:
{exact template with placeholders marked}

**Naming pattern** — {convention for new files, functions, variables}

**Commit message format** — {project-specific format}

**CRITICAL:** {project-specific constraints — e.g., "never git add -A"}
```

**File Map:**

One table listing ALL files across the entire plan:

```markdown
## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|

### Deleted Files
| File | Reason |
|------|--------|
```

Every new or modified file must have a corresponding test file column
entry. If no test applies, state `N/A (config)` or `N/A (docs)`.

**Phase Dependencies:**

Structured dependency list — required for all plans. `/r-build
--parallel` reads this to determine which phases can run concurrently.

Format:
- Phase N: none          — no dependencies, eligible for first batch
- Phase N: [1, 2]        — depends on phases 1 and 2 completing first

Example:
- Phase 1: none
- Phase 2: none
- Phase 3: [1, 2]
- Phase 4: [1, 2]
- Phase 5: [3, 4]
- Phase 6: none
- Phase 7: [6]
- Phase 8: [1, 2, 3, 4, 5, 6, 7]

If all phases are strictly sequential:
- Phase 1: none
- Phase 2: [1]
- Phase 3: [2]
...

The ASCII art dependency graph from prior plans is still permitted
as a supplementary visual aid but is not read by the build command.
The structured list is the machine-parseable source of truth.

### 2.2 Decompose Into Phases

Break the spec into numbered implementation phases. Each phase is a
unit of work that can be committed independently.

Guidelines for decomposition:
- **One logical change per phase** — never batch unrelated changes
- **Dependencies flow forward** — phase N never depends on phase N+1
- **Tests are part of the phase** — not a separate phase
- **Infrastructure before features** — scaffolding, types, interfaces
  come before implementation
- **Smaller is better** — prefer 8 small phases over 4 large ones

### 2.3 Tag Each Phase

For each phase, provide orchestration metadata:

**Execution mode** (how the dispatcher runs it):
- `[serial-context]` — 1 file, simple change, stays in main session
- `[serial-agent]` — 2-5 files or files with dependencies, one subagent
- `[parallel-agent]` — 6+ independent files, parallel subagents

The dispatcher automatically classifies change scope and selects
quality gates based on the phase's file list, description, and
governance context. No risk, type, or gate tagging is needed in the
plan — the dispatcher derives these at execution time.

Note: `[parallel-agent]` mode is for INTRA-PHASE parallelism
(multiple engineers within one phase). INTER-PHASE parallelism
(multiple phases running concurrently) is handled by `/r-build
--parallel`, which reads the Phase Dependencies list above. The
planner does not need to think about inter-phase parallelism — the
build command derives it from the dependency graph.

### 2.4 Identify File Ownership Boundaries

For any `[parallel-agent]` phase, explicitly list which files belong
to which parallel track. No file may appear in more than one track.

If files cannot be cleanly separated, downgrade to `[serial-agent]`.

### 2.5 Write Steps Within Each Phase

This is the critical section. Each phase contains numbered steps with
checkboxes. Each step is 2-5 minutes of work.

**Every step must include:**

1. **Action** — what to do (create file, modify function, delete lines)
2. **Exact code** — the literal code to write, or the exact old→new
   change. For new files: show the complete file content or enough to
   be unambiguous. For modifications: show the old lines and new lines.
3. **Location** — file path and line numbers in the CURRENT file state
   (not the state after prior steps — use function names when line
   numbers will shift)
4. **Verification** — command to run after this step AND the expected
   output. Never write a bare command without showing what success
   looks like:
   ```bash
   grep -c '\.rdf/governance/' canonical/agents/engineer.md
   # expect: 1
   ```

**The final step of every phase is a commit step** with a pre-written
commit message.

**Self-correction notes:** When you discover a subtlety mid-planning
(dependency ordering, scoping issue, variable shadowing, a "wait —
this won't work because..."), preserve the reasoning inline. These
notes prevent the engineer from re-discovering the same gotcha.

**Edge case propagation:** If the spec (Section 11b) lists edge
cases, each edge case must map to at least one step in the plan.
Check the spec's edge case table and verify coverage. If an edge
case is deferred, note it explicitly with rationale.

### 2.6 Phase Format

The complete format for each phase:

```markdown
---

### Phase {N}: {description}

{1-2 sentence summary of what this phase does and why}

**Files:**
- Create: `path/to/new.file` (test: `tests/new.bats`)
- Modify: `path/to/existing.file` (what changes)
- Delete: `path/to/removed.file` (why)

- **Mode**: {serial-context | serial-agent | parallel-agent}
- **Accept**: {acceptance criteria — concrete, testable, pass/fail}
- **Test**: {test file + test names, or verification commands with expected output}
- **Edge cases**: {spec edge cases covered by this phase, or "none"}

- [ ] **Step 1: {action}**

  {exact code block or old→new diff}

- [ ] **Step 2: Verify**

  ```bash
  {command}
  # expect: {expected output}
  ```

- [ ] **Step 3: Commit**

  {git add + git commit with pre-written message}

---
```

**Mandatory phase metadata fields:** Mode, Accept, Test, Edge cases.
Omitting any field is a plan quality failure.

**Accept criteria** must be concrete and testable — "governance works"
is not acceptable. "grep -c '.rdf/governance/' in all 4 agent files
returns 1 each" is acceptable.

**Test field** must name specific test files or verification commands
with expected output. "run tests" is not acceptable.

Every phase MUST end with a `---` horizontal rule. This is the crash
safety marker — a phase without a trailing `---` is considered
truncated and will be regenerated on `--resume`.

Mark task "Write execution-grade implementation phases" as `completed`.

---

## Step 3: Review + Approve

Mark task "Challenge review and user approval" as `in_progress`.

### 3.1 Plan Review

After writing the full plan, dispatch the reviewer agent in challenge
mode with `model: "sonnet"`. Challenge review is structural
pattern-matching — Sonnet handles it at full quality. The dispatch prompt
must include the quality standard as an explicit checklist:

```
Review this implementation plan against the quality standard. Each
criterion is checked independently — if ANY fail, finding is MUST-FIX:

1. Can a fresh agent execute any phase without reading the spec?
   Check: steps have exact code blocks, not references to "the spec"
2. Every verification step includes expected output?
   Check: every verify step has "# expect:" comment
3. Every phase has all 4 metadata fields?
   Check: Mode, Accept, Test, Edge cases present
4. Accept criteria are concrete and testable?
   Check: Accept lines contain commands or measurable conditions
5. Test field names specific tests?
   Check: Test lines have file paths or exact commands, not "run tests"
6. Edge cases from spec mapped to phases?
   Check: read spec Section 11b, verify each edge case appears in a phase
7. Structured dependency list present?
   Check: Phase Dependencies section has `- Phase N: none` or `- Phase N: [deps]` for every phase
8. File Map has test column?
   Check: every new/modified file has a test file entry or "N/A (reason)"

Also review for:
- Steps that are vague or ambiguous (missing code, missing line refs)
- Dependency ordering errors (phase N uses something from phase N+1)
- File ownership conflicts in parallel phases
- Commit messages that don't match project conventions

Calibration: only flag MUST-FIX(blocking-concern) if the issue would
prevent an engineer from executing the step without guessing. Style
preferences, naming opinions, and alternative approaches are
INFORMATIONAL(risk-area), not MUST-FIX.

File: PLAN.md
Mode: challenge
```

Fix issues and re-dispatch (max 3 cycles). If MUST-FIX findings
remain after 3 cycles, present to the user for resolution.

### 3.2 User Approval

Present the plan summary:

```
Plan written to: PLAN.md
{N} phases | {serial count} serial, {parallel count} parallel
Estimated gates: {total gate invocations across all phases}

Please review the plan. Approve to finalize, or request changes.
[approve/change/replan]
```

Wait for user approval. If the user requests changes:
- Adjust phases, re-tag, rewrite PLAN.md
- Do NOT re-run the spec design phases — use `/r-spec` for that

### 3.3 Commit Planning Artifacts

After approval, offer to commit:

```
Commit the plan? [Y/n]
```

If yes, commit PLAN.md (and spec if not already committed):
```
Add {topic} implementation plan

[New] PLAN.md — {N}-phase implementation plan
```

Mark task "Challenge review and user approval" as `completed`.

---

## Completion Handoff

After all steps complete, present the pipeline handoff:

```
> **Plan ready** — `PLAN.md` ({N} phases)
> Run `/r-build` to begin execution, or `/r-build 3` for a specific phase.
```

---

## Plan Quality Standard

A plan is execution-grade when ALL of the following are true. These
are not aspirational — the reviewer checks each one and any failure
is MUST-FIX.

1. A fresh agent can execute any phase without reading the spec
2. Every create/modify action has exact code or exact old→new diff
3. Every verification step includes expected output (`# expect:`)
4. No step says "update X" without showing what the update is
5. Line references point to current file state (verified by reading)
6. Commit messages are pre-written with proper tag format
7. Every phase ends with a `---` crash safety marker
8. Every phase has all 4 metadata fields (Mode, Accept, Test, Edge cases)
9. Accept criteria are concrete and testable (grep/wc/diff commands)
10. Test field names specific test files or verification commands
11. Edge cases from the spec are mapped to phases (none missed)
12. File Map includes test file column for every new/modified file
13. Structured dependency list present (all plans)

A plan that says "extract functions to new file" is an outline.
A plan that says "cut lines 61-173 from functions.apf, paste after
boilerplate in apf_ipt.sh, add sourcing line to hub, run bash -n,
expect exit 0" is execution-grade.

---

## Formatting Guide

| Primitive | Syntax | Best for |
|-----------|--------|----------|
| **Table** | `\| col \| col \|` | File maps, phase summaries, decision tables |
| **Task list** | `- [x]` / `- [ ]` | Phase steps, progress tracking |
| **Blockquote** | `>` | Handoff prompts, self-correction notes |
| **Bold** | `**text**` | Labels, phase metadata keys |
| **Italic** | `*text*` | Status keywords |
| **Inline code** | `` `text` `` | Paths, commands, file names, hashes |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

---

## Rules

- **Never write implementation code** — the planner produces plans
  only. Implementation is for `/r-build`.
- **Always read files before referencing them** — line numbers, function
  names, and patterns must come from reading the actual code, never
  from memory or inference.
- **Wait at every gate** — do not proceed past user approval without
  confirmation.
- **Reviewer dispatch is mandatory** — challenge review before
  presenting the plan for approval. Do not skip it.
- **Phase tags are binding** — the dispatcher uses them to determine
  execution strategy. Tag carefully.
- **File ownership boundaries must be explicit** — for parallel phases,
  list every file per track. Ambiguity causes merge conflicts.
- **Plans are execution-grade or they are not done** — if a step says
  "update X" without showing the exact change, the plan is incomplete.
  Go back and read the file, find the exact lines, and write the diff.
- **Crash safety markers are mandatory** — every phase ends with `---`.
  This enables `--resume` to detect truncated phases.
