# Design: spec-plan-build-ship Command Pipeline

**Date:** 2026-03-19
**Author:** Ryan MacDonald / Claude
**Status:** Draft
**Project:** RDF (rfxn Development Framework)

---

## 1. Problem Statement

The current `/r:plan` command is a 5-phase monolith (811 lines) that
conflates three distinct cognitive activities:

- **Understanding the problem** (discover + brainstorm) — phases 1-2
- **Designing the solution** (write spec, review) — phase 3
- **Decomposing into executable work** (plan phases) — phase 4

This creates friction at every entry point:

| User situation | What they need | Current path | Friction |
|---------------|----------------|--------------|----------|
| Vague idea | Full pipeline | `/r:plan` | Works, but 5 phases is heavy |
| Existing spec or GH issue | Spec → plan | `/r:plan` | Forces discover + brainstorm first |
| Existing PLAN.md | Execute | `/r:build` | Works, name is acceptable |
| Interrupted session | Resume | None | Must remember where they stopped |

Additionally, `/r:plan` names itself "plan" but spends 75% of its
runtime on design work (brainstorming, research, spec writing). The
name lies about what the command does.

The superpowers skills already decompose correctly — `brainstorming`
and `writing-plans` are independent skills. RDF commands should
compose the same way.

## 2. Goals

1. Each command produces exactly one artifact type
2. Users can enter the pipeline at any point matching their current state
3. Every command tells the user the next step (handoff prompt)
4. Interrupted sessions can resume from the last checkpoint (crash safety)
5. Live task list progress via TaskCreate/TaskUpdate in every command
6. Adversarial challenge review at every design and planning gate
7. Research-driven option exploration preserved from current `/r:plan`
8. Zero loss of current `/r:plan` capabilities — everything moves, nothing is deleted

## 3. Non-Goals

- Changing the dispatcher agent or its execution model
- Modifying the engineer, QA, UAT, or reviewer subagents
- Changing the quality gate system
- Adding new governance file types
- Modifying `/r:init`, `/r:refresh`, `/r:status`, or other commands
- Changing the spec document format or section structure

## 4. Architecture

### 4.1 Pipeline Overview

```
/r:spec                         /r:plan                    /r:build              /r:ship
────────────────────────────    ───────────────────────    ──────────────────    ──────────
idea → research → design doc    spec → PLAN.md             PLAN.md → code        code → release

INPUT:  user request or         INPUT: spec path,          INPUT: PLAN.md        INPUT: complete branch
        GitHub issue URL                GH issue, or       OUTPUT: committed     OUTPUT: PR + tag
OUTPUT: docs/specs/*.md                 auto-detect                code
        committed               OUTPUT: PLAN.md
                                        committed

ARTIFACT: spec document         ARTIFACT: impl plan        ARTIFACT: code        ARTIFACT: release
NEXT: /r:plan                   NEXT: /r:build             NEXT: /r:ship         NEXT: done
```

### 4.2 Command Boundaries

| Current `/r:plan` phase | New command | Rationale |
|-------------------------|------------|-----------|
| Phase 1: Discover (1.1-1.3) | `/r:spec` | Understanding the problem is design work |
| Phase 2: Brainstorm (2.1-2.5) | `/r:spec` | Research + options is design work |
| Phase 3: Spec (3.1-3.6) | `/r:spec` | Writing the spec is the design output |
| Phase 4: Plan (4.1-4.9) | `/r:plan` | This IS planning — decomposition into phases |
| Phase 5: Handoff (5.1-5.2) | `/r:plan` (end) | Plan handoff points to `/r:build` |
| N/A | `/r:build` | Unchanged — dispatches dispatcher for execution |
| N/A | `/r:ship` | Unchanged — release workflow |

### 4.3 File Map

#### New Files

| File | Est. Lines | Purpose |
|------|-----------|---------|
| `canonical/commands/r-spec.md` | ~500 | Design command: discover → brainstorm → spec → review |
| `canonical/commands/r-plan.md` | ~350 | Planning command: spec → PLAN.md → review → handoff |

#### Modified Files

| File | Changes |
|------|---------|
| `canonical/commands/r-plan.md` | **Replaced** — current 811-line monolith becomes the new ~350-line planning-only command |
| `canonical/commands/build.md` | Add task list integration, next-step handoff to `/r:ship` |
| `canonical/commands/r-ship.md` | Verify task list integration already present (from formatting pass) |
| `canonical/commands/r-start.md` | Update in-flight detection to recognize `spec-progress.md` and `ship-progress.md` |
| `canonical/commands/r-status.md` | Update to show spec + plan + build pipeline status |
| `canonical/commands/r-save.md` | Update to sync spec progress state |
| `canonical/commands/r-mode.md` | Replace single "Planner" row in agents table with "Spec Designer" and "Planner" rows |
| `canonical/commands/r-refresh.md` | Add `spec-progress.md` and `ship-progress.md` to state artifact recognition |
| `canonical/commands/r-init.md` | Update "Next Steps" table: `/r:spec` first, `/r:plan` second |
| `canonical/agents/planner.md` | Narrow scope to plan decomposition only (remove discover/brainstorm/spec phases) |
| `canonical/agents/reviewer.md` | Update invocation docs: "Invoked during `/r:spec` or `/r:plan`" |
| `reference/framework.md` | Update pipeline diagram and command inventory |
| `reference/session-safety.md` | Add `spec-progress.md` and `ship-progress.md` to recovery signals |

#### Deleted Files

None. The old `/r:plan` content is split, not deleted.

### 4.4 Dependency Chain

```
/r:spec (standalone — no deps)
  ↓ produces docs/specs/*.md
/r:plan (reads spec)
  ↓ produces PLAN.md
/r:build (reads PLAN.md, dispatches rdf-dispatcher)
  ↓ produces committed code
/r:ship (reads branch state)
  ↓ produces release PR
```

No circular dependencies. Each command reads the artifact of the
previous command and produces input for the next.

## 5. Command Specifications

### 5.1 `/r:spec` — Design Command

**Purpose:** Guide the user from idea to architecture-grade spec
through research-driven collaborative dialogue.

**Invocation:**

```
/r:spec                          — start from scratch (discover → brainstorm → spec)
/r:spec https://github.com/...   — GitHub URL as design seed (fetched, used as problem statement)
/r:spec #42                      — issue shorthand (gh issue view 42, used as problem statement)
/r:spec --resume                 — resume interrupted design session
```

**Argument detection logic** (same pattern as `/r:plan`):
- Starts with `http` or `https` → GitHub URL → fetch as design seed
- Starts with `#` followed by digits → issue shorthand → fetch issue body
- Equals `--resume` → resume from `spec-progress.md`
- No argument → start fresh design session

When a GitHub issue or URL is provided, it becomes the starting
context for the Discover phase — the user still goes through
brainstorming and design questions, but the problem statement is
pre-populated from the issue body.

**Task list (created at startup):**

```
TaskCreate: "Discover project context and scope"
  activeForm: "Discovering project context"
TaskCreate: "Research design questions"
  activeForm: "Researching design options"
TaskCreate: "Write architecture-grade spec"
  activeForm: "Writing spec"
TaskCreate: "Challenge review and user approval"
  activeForm: "Reviewing spec"
```

**Phases (3 internal phases, user sees task progress):**

**Phase 1 — Discover:**
- Read governance index (or CLAUDE.md fallback)
- Read existing plans, specs, issues
- Assess scope (single-spec vs multi-spec)
- Present scope assessment, wait for user confirmation
- Content: identical to current `/r:plan` Phase 1

**Phase 2 — Brainstorm + Research:**
- Identify design questions
- For each question: research → present 3+ options → user selects
- Adversarial posture: challenge assumptions with evidence
- One question at a time, multiple choice preferred
- Brainstorm summary with decision table
- Wait for user confirmation
- Content: identical to current `/r:plan` Phase 2

**Phase 3 — Write + Review Spec:**
- Read codebase (mandatory — specs without evidence are wishes)
- Write architecture-grade spec to `docs/specs/YYYY-MM-DD-{topic}-design.md`
- Spec sections: Problem, Goals, Non-Goals, Architecture, File Contents,
  Conventions, Interface Contracts, Migration Safety, Dead Code,
  Verification, Risks, Open Questions
- Dispatch reviewer in challenge mode (max 3 cycles)
- User approval gate
- Commit spec
- Content: identical to current `/r:plan` Phase 3

**Crash safety:**
- After each design question is resolved, append to
  `work-output/spec-progress.md`:
  ```
  TOPIC: {topic}
  PHASE: {discover|brainstorm|spec|review}
  SPEC_PATH: {path if written}
  DECISIONS:
  - Q1: {question} → {decision}
    RATIONALE: {2-3 sentences: key trade-off, research cite, why alternatives were rejected}
  - Q2: {question} → {decision}
    RATIONALE: {2-3 sentences}
  ```
  The RATIONALE line preserves enough context for a fresh session to
  understand not just *what* was decided but *why*. This is cheap to
  record (it already exists in the brainstorm summary table) and
  dramatically improves resume fidelity.
- On `--resume`: read `spec-progress.md`, reconstruct state, present
  prior decisions with rationale to the user, resume from the next
  unresolved question

**Completion handoff:**
```
> **Spec complete** — `docs/specs/{filename}`
> Reviewed and approved. Run `/r:plan` to create the implementation plan.
```

### 5.2 `/r:plan` — Planning Command

**Purpose:** Take a spec (or equivalent input) and decompose it into
an execution-grade implementation plan (PLAN.md).

**Invocation:**

```
/r:plan                          — auto-detect most recent spec in docs/specs/
/r:plan docs/specs/foo.md        — file path (contains / or ends with .md)
/r:plan https://github.com/...   — GitHub URL (starts with http/https)
/r:plan #42                      — issue shorthand (# + digits)
/r:plan --resume                 — resume interrupted planning session
```

**Argument detection logic:**
- Contains `/` or ends with `.md` → file path → read as spec
- Starts with `http` or `https` → GitHub URL → `gh issue view` or `gh pr view`
- Starts with `#` followed by digits → issue shorthand → `gh issue view {N}`
- Equals `--resume` → resume from `PLAN.md` work-in-progress
- No argument → scan `docs/specs/` for most recent file by mtime

**Input validation:**
- File path: verify file exists and is readable
- GitHub URL: verify `gh` CLI available, fetch and validate response
- Issue shorthand: verify `gh` CLI available, fetch issue body
- Auto-detect: if `docs/specs/` empty or missing, offer transparent
  delegation: `"No spec found. Would you like to start with /r:spec
  to design one first? [Y/n]"` — if Y, run the `/r:spec` workflow
  inline (preserving the single-command UX for users who expect it),
  then continue into planning when the spec is complete. If N, stop.

**Task list (created at startup):**

```
TaskCreate: "Read codebase and spec, plan decomposition strategy"
  activeForm: "Reading codebase and spec"
TaskCreate: "Write execution-grade implementation phases"
  activeForm: "Writing implementation phases"
TaskCreate: "Challenge review and user approval"
  activeForm: "Reviewing plan"
```

**Protocol (3 steps):**

**Step 1 — Read + Analyze:**
- Read the spec (or issue body) in full
- Read every file referenced in the spec
- Collect: line numbers, function signatures, existing patterns,
  test file references, variable names, source guard patterns
- Determine decomposition strategy: how many phases, what order,
  what parallelism
- Content: identical to current `/r:plan` Phase 4.1

**Step 2 — Write PLAN.md:**
- Write plan preamble (header, conventions, file map)
- Write each phase with: files, mode, risk, type, gates, accept,
  numbered steps with exact code, verification, commit step
- Content: identical to current `/r:plan` Phases 4.2-4.7
- All phases are execution-grade: a fresh agent can execute any
  phase mechanically without reading the spec

**Step 3 — Review + Approve:**
- Dispatch reviewer in challenge mode (max 3 cycles)
- Fix blocking findings, present concerns to user
- User approval gate
- Commit PLAN.md (and spec if not already committed)
- Content: identical to current `/r:plan` Phases 4.8-4.9

**Crash safety:**
- PLAN.md itself is the state file — phases written so far are
  preserved even if the session dies mid-planning
- **Phase completion marker:** every fully-written phase ends with a
  `---` horizontal rule. A phase heading without a trailing `---`
  before the next heading (or EOF) is considered truncated and will
  be regenerated on resume
- The plan preamble records the expected phase count: `**Phases:** {N}`
  — compare against actual phase headings to detect missing phases
- On `--resume`: read existing PLAN.md, identify complete phases
  (have trailing `---`), truncated phases (regenerate), and missing
  phases (generate), continue from there
- After review, if user requests changes: modify PLAN.md in place,
  do not regenerate from scratch

**Completion handoff:**
```
> **Plan ready** — `PLAN.md` ({N} phases)
> Run `/r:build` to begin execution, or `/r:build 3` for a specific phase.
```

### 5.3 `/r:build` — Build Command (updates only)

The existing `build.md` stays as-is with these additions:

**Task list integration:**
- On startup, read PLAN.md and create one task per phase:
  ```
  TaskCreate: "Phase 1: {description}"
    activeForm: "Building Phase 1: {short desc}"
  ```
- Mark completed phases as `[x]` immediately
- Mark the target phase as `in_progress` before dispatching
- Mark it `completed` when dispatcher returns PASS

**Next-step handoffs:**

After a phase completes:
```
> **Phase {N} complete** — {description}
> Next: Phase {N+1} — {description}. Run `/r:build` to continue.
```

After all phases complete:
```
> **All {N} phases complete.**
> Run `/r:ship` to begin the release workflow.
```

**Crash safety (already exists):**
- `work-output/phase-N-status.md` written by dispatcher
- `work-output/current-phase.md` tracks active dispatch
- `/r:build` auto-detects next pending phase on resume

### 5.4 `/r:ship` — Ship Command (updates only)

The existing `r-ship.md` stays as-is with these additions:

**Task list integration (already present from formatting pass):**
- Verify tasks are created for each stage
- Verify `activeForm` provides spinner text

**Crash safety:**
- Write `work-output/ship-progress.md` after each stage:
  ```
  STAGE: {preflight|verify|prep|publish|report}
  STATUS: {complete|in-progress}
  PR_URL: {if created}
  ```
- On re-invocation: detect `ship-progress.md`, offer resume

**Completion:**
```
> **Released** — PR {url}
> Merge when CI passes. Pipeline complete.
```

## 6. Cross-Cutting Concerns

### 6.1 `/r:start` In-Flight Detection

Update r-start's in-flight scan (step 4) to detect:
- `work-output/spec-progress.md` → signal: "Spec in progress"
- `PLAN.md` with incomplete phases → signal: "Plan exists, not all phases done"
- `work-output/ship-progress.md` → signal: "Ship in progress"

### 6.2 `/r:save` State Sync

Update r-save to:
- Sync `work-output/spec-progress.md` if present
- Record spec/plan/build/ship pipeline stage in session log

### 6.3 `/r:status` Dashboard

Update r-status to show pipeline position:
```
### Pipeline
| Stage | Status | Artifact |
|-------|--------|----------|
| **Spec** | *complete* | `docs/specs/2026-03-19-foo.md` |
| **Plan** | *complete* | `PLAN.md` (8 phases) |
| **Build** | *in-progress* | Phase 3/8 |
| **Ship** | *pending* | — |
```

### 6.4 Adversarial Review Integration

Both `/r:spec` and `/r:plan` dispatch the reviewer agent in challenge
mode. The review protocol is preserved exactly from the current
`/r:plan` — the same rigor, the same max-3-cycle limit, the same
blocking/concern/suggestion classification.

The key difference: reviews happen at the right scope.
- Spec review challenges the DESIGN (architecture, migration safety,
  risks, missing analysis)
- Plan review challenges the EXECUTION (ambiguous steps, dependency
  ordering, missing verification, file ownership)

Currently both reviews happen in the same monolith, which means a
spec review finding can block plan writing even though they're
independent concerns.

### 6.5 Task List Lifecycle

```
Command start → TaskCreate (all phases as pending)
Phase start   → TaskUpdate (in_progress, activeForm shows spinner)
Phase end     → TaskUpdate (completed)
Command end   → all tasks completed, handoff blockquote displayed
```

The `activeForm` parameter drives the spinner text. Every task must
have a verb-phrase activeForm so the user sees meaningful progress:
"Discovering project context...", "Writing implementation phases...",
"Running preflight checks..."

## 7. Conventions

### 7.1 State File Format

All state files in `work-output/` use the same key-value format:

```
KEY: value
KEY: value
SECTION:
- item
- item
```

Readable by grep, parseable by simple bash, human-readable in editors.

### 7.2 Handoff Blockquote

Every command ends with a blockquote containing:
1. Bold status line (what just completed)
2. Artifact path in inline code
3. Next command suggestion

```
> **{Status}** — `{artifact path}`
> {Next step instruction with inline code command.}
```

### 7.3 Spec Path Convention

Specs are written to:
```
docs/specs/YYYY-MM-DD-{topic}-design.md
```

The `/r:plan` auto-detect scans this directory, sorted by mtime
descending, and uses the most recent file.

## 8. Interface Contracts

### 8.1 CLI Changes

| Before | After |
|--------|-------|
| `/r:plan` (full pipeline) | `/r:spec` (design) + `/r:plan` (decompose) |
| `/r:plan` with no args | `/r:spec` with no args (same UX for "I have an idea") |
| `/r:build` (unchanged) | `/r:build` (+ task lists + handoffs) |
| `/r:ship` (unchanged) | `/r:ship` (+ crash safety) |

### 8.2 New Arguments

| Command | Arguments | Behavior |
|---------|-----------|----------|
| `/r:spec` | none | Start fresh design session |
| `/r:spec` | `--resume` | Resume interrupted spec session |
| `/r:plan` | none | Auto-detect spec from `docs/specs/` |
| `/r:plan` | `path/to/file.md` | Use file as spec input |
| `/r:plan` | `https://github.com/...` | Read GitHub URL as spec input |
| `/r:plan` | `#42` | Read GitHub issue #42 as spec input |
| `/r:plan` | `--resume` | Resume interrupted planning session |
| `/r:build` | (unchanged) | `[N]` for specific phase |
| `/r:ship` | (unchanged) | `[base-branch]` override |

### 8.3 Backward Compatibility

Users who currently type `/r:plan` expecting the full pipeline get
a transparent delegation: if no spec exists, `/r:plan` offers to
run `/r:spec` inline first, then continues into planning. The
single-command UX is preserved — the internal decomposition is
invisible unless the user explicitly enters at `/r:spec`.

- `/r:plan` with no args, no spec → delegates to `/r:spec` (with
  user confirmation), then continues to planning
- `/r:plan` with no args, spec exists → uses most recent spec
- `/r:plan` with explicit arg → uses that input directly

## 9. Migration Safety

### 9.1 Adapter Generation

The `rdf generate claude-code` command auto-generates slash command
registrations from canonical files. Adding `r-spec.md` to
`canonical/commands/` will auto-register `/r-spec` as a slash
command. No adapter changes needed.

### 9.2 Documentation

- RDF README.md: update command inventory to show 4-command pipeline
- `canonical/reference/framework.md`: update pipeline diagram
- `canonical/reference/session-safety.md`: add `spec-progress.md` and `ship-progress.md` to recovery signals

### 9.3 MEMORY.md References

Update parent MEMORY.md "Workflow Commands" section to reflect the
new command count and pipeline structure.

## 10. Verification

```bash
# All 4 command files exist and are non-empty
wc -l canonical/commands/r-spec.md canonical/commands/r-plan.md \
     canonical/commands/build.md canonical/commands/r-ship.md

# Generate deploys successfully
bash bin/rdf generate claude-code 2>&1 | tail -3

# Slash commands registered (check output includes r-spec)
grep -l 'r-spec\|r-plan\|build\|r-ship' adapters/claude-code/output/commands/*.md

# No references to old 5-phase structure remain
grep -rn 'PHASE 1: DISCOVER\|PHASE 2: BRAINSTORM\|PHASE 5: HANDOFF' \
  canonical/commands/
# expect: 0 hits

# Cross-references between pipeline commands are valid
grep -n '/r:plan\|/r:spec\|/r:build\|/r:ship' canonical/commands/r-spec.md
grep -n '/r:plan\|/r:spec\|/r:build\|/r:ship' canonical/commands/r-plan.md

# Integration points updated — no stale references
grep -rn 'Run /r:plan' canonical/commands/r-init.md  # should mention /r:spec first
grep -n 'Planner' canonical/commands/r-mode.md       # should show split roles
grep -n '/r:plan spec' canonical/agents/reviewer.md   # should reference /r:spec
grep -rn 'PHASE 1: DISCOVER' canonical/agents/       # expect: 0 hits in planner.md

# Planner agent scope narrowed
grep -c 'brainstorm\|Brainstorm' canonical/agents/planner.md  # expect: 0
```

## 11. Risks

1. **User muscle memory** — Users accustomed to `/r:plan` for the
   full pipeline will need to learn `/r:spec`. Mitigation: helpful
   redirect message when `/r:plan` is invoked without a spec.

2. **State file proliferation** — Adding `spec-progress.md` and
   `ship-progress.md` to `work-output/`. Mitigation: files are
   small, cleaned up by `/r:save`, detected by `/r:start`.

3. **Spec-plan coupling** — If the spec format changes, `/r:plan`'s
   parsing may break. Mitigation: `/r:plan` reads specs as prose
   (not structured parsing), so format changes are transparent.

4. **Resume fidelity** — Crash recovery from `spec-progress.md`
   preserves decisions and rationale but not full conversational
   context. Mitigation: RATIONALE lines capture the key trade-off
   per decision. A resumed session presents these to the user before
   continuing, so context is reconstructed from structured data.

5. **State model asymmetry** — `/r:spec` and `/r:ship` use dedicated
   progress files while `/r:plan` uses PLAN.md itself as state.
   This is intentional: PLAN.md is incrementally written (phases
   accumulate), making it a natural state file. Specs are atomic
   (the entire document is written at once in Phase 3), so a
   separate progress file tracks the preceding conversational phases.
   `/r:start` in-flight detection handles all three patterns.

## 12. Open Questions

None. Design decisions were resolved during the brainstorming session:
- Split boundaries confirmed (phases 1-3 → spec, phase 4-5 → plan)
- `--from` flag eliminated in favor of argument type detection
- `--resume` flag for crash recovery
- Task list integration via TaskCreate/TaskUpdate
- Adversarial review preserved at both spec and plan gates
