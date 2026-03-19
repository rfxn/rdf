# /r:plan — Planning Command

Take a spec (or equivalent input) and decompose it into an
execution-grade implementation plan (PLAN.md). You never write code.
You produce plans.

This is the second stage of the spec-plan-build-ship pipeline.

`$ARGUMENTS` — input source for the plan:

```
/r:plan                          — auto-detect most recent spec in docs/specs/
/r:plan docs/specs/foo.md        — file path (contains / or ends with .md)
/r:plan https://github.com/...   — GitHub URL (starts with http/https)
/r:plan #42                      — issue shorthand (# + digits)
/r:plan --resume                 — resume interrupted planning session
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
  delegation to `/r:spec`:
  ```
  "No spec found. Would you like to start with /r:spec to design
  one first? [Y/n]"
  ```
  If Y: run the `/r:spec` workflow inline, then continue into
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

Every plan starts with three sections before any phases:

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
| File | Lines | Purpose |
|------|-------|---------|

### Modified Files
| File | Changes |
|------|---------|

### Deleted Files
| File | Reason |
|------|--------|
```

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

**Risk level:**
- `risk:low` — config, docs, trivial changes
- `risk:medium` — new features, refactors with existing tests
- `risk:high` — security, data migration, breaking changes

**Type:**
- `type:config` — configuration, scaffolding
- `type:feature` — new functionality
- `type:refactor` — restructure without behavior change
- `type:security` — security-related changes
- `type:user-facing` — CLI, UI, output format changes
- `type:data-migration` — data format or schema changes

**Quality gates** (derived from risk + type):
- risk:low, type:config — Gate 1 only (engineer self-report)
- risk:medium, type:feature — Gates 1 + 2 (+ QA)
- risk:high or type:security — Gates 1 + 2 + 3 (+ reviewer sentinel)
- type:user-facing — Gates 1 + 2 + 4 (+ UAT)
- risk:high, type:user-facing — All 4 gates

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
4. **Verification** — command to run after this step (bash -n, grep,
   test command)

**The final step of every phase is a commit step** with a pre-written
commit message.

**Self-correction notes:** When you discover a subtlety mid-planning
(dependency ordering, scoping issue, variable shadowing, a "wait —
this won't work because..."), preserve the reasoning inline. These
notes prevent the engineer from re-discovering the same gotcha.

### 2.6 Phase Format

The complete format for each phase:

```markdown
---

### Phase {N}: {description}

{1-2 sentence summary of what this phase does and why}

**Files:**
- Create: `path/to/new.file`
- Modify: `path/to/existing.file` (what changes)
- Delete: `path/to/removed.file` (why)

- **Mode**: {serial-context | serial-agent | parallel-agent}
- **Risk**: {low | medium | high}
- **Type**: {config | feature | refactor | ...}
- **Gates**: {G1 | G1+G2 | ...}
- **Accept**: {acceptance criteria — concrete, testable}
- **Test**: {test strategy}

- [ ] **Step 1: {action}**

  {exact code block or old→new diff}

- [ ] **Step 2: Verify**

  {verification commands}

- [ ] **Step 3: Commit**

  {git add + git commit with pre-written message}

---
```

Every phase MUST end with a `---` horizontal rule. This is the crash
safety marker — a phase without a trailing `---` is considered
truncated and will be regenerated on `--resume`.

Mark task "Write execution-grade implementation phases" as `completed`.

---

## Step 3: Review + Approve

Mark task "Challenge review and user approval" as `in_progress`.

### 3.1 Plan Review

After writing the full plan, dispatch the reviewer agent in challenge
mode:

```
Review this implementation plan for:
- Steps that are vague or ambiguous (missing code, missing line refs)
- Missing verification steps
- Dependency ordering errors (phase N uses something from phase N+1)
- File ownership conflicts in parallel phases
- Missing edge cases from the spec

File: PLAN.md
Mode: challenge
```

Fix issues and re-dispatch (max 3 cycles). If BLOCKING findings
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
- Do NOT re-run the spec design phases — use `/r:spec` for that

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
> Run `/r:build` to begin execution, or `/r:build 3` for a specific phase.
```

---

## Plan Quality Standard

A plan is execution-grade when:
1. A fresh agent can execute any phase without reading the spec
2. Every create/modify action has exact code or exact old→new diff
3. Every step has a verification command
4. No step says "update X" without showing what the update is
5. Line references point to current file state (verified by reading)
6. Commit messages are pre-written with proper tag format
7. Every phase ends with a `---` crash safety marker

A plan that says "extract functions to new file" is an outline.
A plan that says "cut lines 61-173 from functions.apf, paste after
boilerplate in apf_ipt.sh, add sourcing line to hub, run bash -n"
is execution-grade.

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
  only. Implementation is for `/r:build`.
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
