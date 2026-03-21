# Design: Parallel Plan Execution

**Date:** 2026-03-21
**Author:** Ryan MacDonald / Claude
**Status:** Implemented (3.0.4)
**Project:** RDF (rfxn Development Framework)

---

## 1. Problem Statement

RDF has two kinds of parallelism, and only one has an owner:

| Type | What | Owner | Status |
|------|------|-------|--------|
| **Intra-phase** | Multiple engineers within ONE phase | Dispatcher `[parallel-agent]` mode | Described, unreliably executed |
| **Inter-phase** | Multiple PHASES running simultaneously | **Nobody** | Gap |

**Inter-phase parallelism has no mechanism.** The plan dependency graph
identifies which phases CAN run concurrently, but no command reads that
graph and acts on it. Today `/r:build` dispatches one dispatcher
subagent at a time; VPE calls `/r:build` per phase in a serial loop.

Evidence: the gate simplification plan (8 phases, just shipped) had
phases 1-4 fully independent — no shared files, no semantic
dependencies. They ran serially because the build command has no
parallel dispatch path. Estimated waste: 3x wall-clock time.

**The dependency graph is not machine-parseable.** The current plan
format uses free-text in the Phase Dependencies section:
```
All phases sequential — no parallelization.
Phases 1-2: Core engine changes
Phase 5: depends on 1-4
```
A human can read this. `/r:build --parallel` cannot.

**Isolation level is one-size-fits-all.** The dispatcher's
`[parallel-agent]` mode uses file ownership gates for intra-phase
work, which is correct for engineers sharing a working tree. But
inter-phase parallelism operates at a higher level — multiple
dispatcher instances each running full gate pipelines. The isolation
requirements differ by scope: `scope:multi-file` phases can share a
working tree with file gates, but `scope:cross-cutting` phases need
physical filesystem isolation via git worktrees.

### Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Inter-phase parallel dispatch | Not possible | `/r:build --parallel` dispatches batches |
| Dependency graph format | Free-text (human-only) | Structured list (machine-parseable) |
| Isolation level selection | Fixed (file gates only) | Auto-derived from scope classification |
| Max concurrent dispatchers | 1 | 4 (configurable) |
| Parallel failure handling | N/A | Per-phase, user decides with recommendations |

---

## 2. Goals

1. `/r:build --parallel` reads PLAN.md dependency graph and dispatches independent phases concurrently
2. Dependency graph in PLAN.md uses a structured, machine-parseable format (`- Phase N: [deps]` or `none`)
3. Isolation level auto-derived from scope classification: `scope:multi-file` → parallel-agent (file-gated), `scope:cross-cutting`/`scope:sensitive` → parallel-worktree
4. `--worktree` flag overrides auto-derivation to force git worktree isolation
5. `/r:build N-M` range syntax dispatches a specific set of phases in parallel (after dependency validation)
6. Maximum parallelism ceiling of 4 (configurable via `--max N`)
7. Partial failure handling: user decides (merge successes / retry / pause), build command recommends based on failure gate
8. Parallel worktree results merge in plan order (deterministic)
9. VPE calls `/r:build --parallel` once for its entire build stage
10. File ownership validation at dispatch time: no file appears in two phases within the same parallel batch

---

## 3. Non-Goals

- Fixing intra-phase `[parallel-agent]` reliability (deferred to Agent Teams)
- Agent Teams integration (future transport layer, not in scope)
- Parallel quality gates within a single phase (dispatcher-internal, unchanged)
- Changing the dispatcher's execution modes (serial-context, serial-agent, parallel-agent stay as-is)
- Adding new agents
- Changing the scope classification system (shipped in 3.0.3, stable)
- Modifying `/r:spec`, `/r:ship`, `/r:init`, `/r:refresh`, `/r:audit`
- Nested parallelism (parallel dispatchers each running parallel engineers) — the dispatcher downgrades to serial-agent when invoked as part of an inter-phase parallel batch

---

## 4. Architecture

### 4.1 File Map

#### New Files

| File | Est. Lines | Purpose | Test File |
|------|-----------|---------|-----------|
| (none) | | | |

#### Modified Files

| File | Lines (current) | Lines (after) | Changes | Test File |
|------|----------------|---------------|---------|-----------|
| `canonical/commands/r-build.md` | 116 | ~220 | Add parallel dispatch protocol (Sections 2b, 5b, 6b, 7b) | N/A (manual verification) |
| `canonical/commands/r-plan.md` | 502 | ~513 | Formalize dependency graph format in Section 2.1, update Section 2.3 mode list | N/A (manual verification) |
| `canonical/commands/r-vpe.md` | 209 | ~214 | Update Stage 4 to call `/r:build --parallel` once | N/A (manual verification) |
| `canonical/agents/dispatcher.md` | 281 | ~289 | Add nested-parallel downgrade note to parallel-agent mode | N/A (manual verification) |
| `canonical/reference/framework.md` | 233 | ~241 | Add inter-phase parallelism summary to pipeline section | N/A (manual verification) |
| `reference/diagrams.md` | 490 | ~510 | Add parallel dispatch flow diagram to Section 3 | N/A (manual verification) |
| `canonical/commands/r-start.md` | 224 | ~227 | Add build-progress.md to in-flight signals | N/A (manual verification) |
| `canonical/commands/r-status.md` | 202 | ~206 | Add parallel batch status to pipeline section | N/A (manual verification) |
| `canonical/reference/session-safety.md` | 75 | ~77 | Add build-progress.md to recovery signals | N/A (manual verification) |

#### No-Touch Files

| File | Reason |
|------|--------|
| `canonical/agents/planner.md` | Planner protocol unchanged |
| `canonical/agents/engineer.md` | Engineer protocol unchanged |
| `canonical/agents/reviewer.md` | Reviewer protocol unchanged |
| `canonical/agents/qa.md` | QA protocol unchanged |
| `canonical/agents/uat.md` | UAT protocol unchanged |
| `canonical/commands/r-spec.md` | Spec command unchanged |
| `canonical/commands/r-ship.md` | Ship command unchanged |
| `canonical/commands/r-review.md` | Review command unchanged |

### 4.2 Size Comparison

| Component | Before | After | Delta |
|-----------|--------|-------|-------|
| r-build.md | 116 | ~220 | +104 (parallel dispatch is the major addition) |
| r-plan.md | 502 | ~513 | +11 (dependency graph format) |
| r-vpe.md | 209 | ~214 | +5 (single-call build stage) |
| dispatcher.md | 281 | ~289 | +8 (downgrade note) |
| framework.md | 233 | ~241 | +8 |
| Other files | 991 | ~1020 | +29 |
| **Total delta** | | | **+165** |

### 4.3 Dependency Tree

```
/r:build --parallel (command — extended)
  ├── reads PLAN.md Phase Dependencies (structured list)
  ├── computes parallel batches from dependency graph
  ├── validates file ownership (no overlap within batch)
  ├── derives isolation level per phase (scope classification)
  │
  ├── parallel-agent dispatch (file-gated, scope:multi-file)
  │     ├── dispatches N rdf-dispatcher subagents
  │     │     └── each dispatcher runs serial-context or serial-agent
  │     │           (downgrades from parallel-agent to avoid nesting)
  │     ├── waits for all to complete
  │     └── reports results per phase
  │
  ├── parallel-worktree dispatch (scope:cross-cutting/sensitive)
  │     ├── creates git worktree per phase
  │     ├── dispatches N rdf-dispatcher subagents (isolation: "worktree")
  │     ├── waits for all to complete
  │     ├── merges worktrees in plan order
  │     └── runs post-merge quality gate (scope:cross-cutting)
  │
  ├── partial failure handling
  │     ├── recommends action based on failure gate
  │     └── user decides: merge successes / retry / pause
  │
  └── end-of-plan sentinel (unchanged — runs on cumulative diff)

/r:vpe Stage 4 (command — simplified)
  └── calls /r:build --parallel once (replaces per-phase loop)

/r:plan Section 2.1 (command — extended)
  └── produces structured dependency list in PLAN.md preamble
```

### 4.4 Key Changes

**Design principle: scope classification drives isolation, not just
gate selection.** The 3.0.3 scope classification already tells the
dispatcher how much verification a phase needs. This spec extends it:
scope also determines how much *isolation* a phase needs when running
in parallel. Same signal, two consumers.

**1. `/r:build` gains parallel dispatch.** The build command reads
the plan dependency graph, identifies which phases are independent,
validates file ownership boundaries, and dispatches multiple
dispatcher subagents concurrently. Three new invocation forms:

```
/r:build --parallel       — auto-batch all pending phases
/r:build 1-4              — dispatch phases 1-4 (validates independence)
/r:build 1-4 --worktree   — force worktree isolation for the batch
```

**2. Isolation auto-derivation.** For each phase in a parallel batch,
the build command reads the scope classification (same derivation
rules the dispatcher uses for gate selection) and selects isolation:

```
scope:docs          → parallel-agent (file-gated — lightweight, no conflict risk)
scope:focused       → parallel-agent (file-gated — single file, no conflict risk)
scope:multi-file    → parallel-agent (file-gated, shared worktree)
scope:cross-cutting → parallel-worktree (git worktree isolation)
scope:sensitive     → parallel-worktree (git worktree isolation)
```

All phases in a parallel batch are dispatched concurrently regardless
of scope. Scope determines only the isolation mechanism, not whether
to parallelize. If a batch contains phases with different isolation
requirements, the entire batch runs at the highest isolation level.
A single `scope:cross-cutting` phase in a batch of `scope:multi-file`
phases promotes the whole batch to parallel-worktree.

**3. Structured dependency graph.** The plan preamble's Phase
Dependencies section changes from free-text to a machine-parseable
list:

```
## Phase Dependencies
- Phase 1: none
- Phase 2: none
- Phase 3: [1, 2]
- Phase 4: [1, 2]
- Phase 5: [3, 4]
- Phase 6: none
- Phase 7: [6]
- Phase 8: [1, 2, 3, 4, 5, 6, 7]
```

`none` means independent — eligible for any parallel batch. `[N, M]`
means depends on phases N and M completing first. The build command
computes batches from this graph at dispatch time.

**4. Nested parallel downgrade.** When a dispatcher subagent is
invoked as part of an inter-phase parallel batch, it downgrades
`[parallel-agent]` mode to `[serial-agent]`. This prevents nested
parallelism (parallel dispatchers each running parallel engineers),
which would be unpredictable and hard to debug. The dispatcher
receives a `PARALLEL_BATCH: true` flag in its dispatch payload to
trigger this downgrade.

**5. VPE simplification.** VPE's Stage 4 (Build) changes from a
serial per-phase loop to a single `/r:build --parallel` call. VPE
receives the aggregate result and reports it. This is consistent
with the design decision that VPE orchestrates *between* pipeline
stages, not within them.

### 4.5 Dependency Rules

- Parallel dispatch must not alter the end-of-plan sentinel threshold
  or its execution (it still runs on the cumulative diff after all
  phases complete)
- The dispatcher's scope classification logic is unchanged — the build
  command reads the same classification, it does not re-derive
- File ownership validation at the build command level is independent
  of the dispatcher's intra-phase file ownership validation
- Git worktree branches must not collide across concurrent sessions
- The `--parallel` flag is purely additive — `/r:build N` (single
  phase) continues to work exactly as before

---

## 5. File Contents

### 5.1 `canonical/commands/r-build.md` — Parallel Dispatch

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Invocation | `/r:build [N]` | `/r:build [N \| N-M \| --parallel] [--worktree] [--max N]` | 6 |
| Section 2 (Identify Target) | Single phase targeting | Add batch targeting (range and auto-parallel) | 25-33 |
| Section 5 (Dispatch Payload) | Single dispatcher dispatch | Add PARALLEL_BATCH flag | 64-82 |
| New Section 6b | N/A | Parallel dispatch protocol | new |
| Section 7 (Report Result) | Single phase result | Add batch result reporting with partial failure | 92-107 |
| New Section 8 | N/A | Parallel failure handling with recommendations | new |

**New invocation line:**

```
`/r:build [N | N-M | --parallel] [--worktree] [--max N]`

Arguments:
  N            — single phase (existing behavior)
  N-M          — range of phases (e.g., 1-4) — dispatch in parallel
  --parallel   — auto-batch all pending phases by dependency graph
  --worktree   — force git worktree isolation (overrides auto-derivation)
  --max N      — maximum concurrent dispatchers (default: 4)
  (no args)    — next pending phase, serial (existing behavior)
```

**New Section 2b: Identify Parallel Batch**

```
### 2b. Identify Parallel Batch

If arguments contain a range (N-M) or --parallel:

1. Read Phase Dependencies from PLAN.md preamble
   - Parse structured list: `- Phase N: none` or `- Phase N: [deps]`
   - If no structured list found, fall back to serial with warning:
     "Phase Dependencies section not in structured format. Running
     serially. Use the format: `- Phase N: none` or `- Phase N: [1, 2]`"

2. Determine target phases:
   - Range (N-M): phases N through M inclusive
   - --parallel: all phases with Status: pending
   - If any phase has Status: in-progress, warn and ask:
     "Phase {N} is in-progress (may be from a prior session).
     Include in parallel batch? [Y/skip/abort]"

3. Compute parallel batches from dependency graph:
   - A phase is eligible for a batch when all its dependencies are
     complete (already done or in a prior batch)
   - Phases with `none` dependencies are eligible for the first batch
   - Group eligible phases into batches, respecting --max ceiling
   - Result: ordered list of batches, each batch is a set of
     independent phases

4. Validate file ownership within each batch:
   - For each batch: collect all files from all phases in the batch
   - Parse the **Files:** field from each phase: extract paths from
     lines matching `Create: \`path\``, `Modify: \`path\``, or
     `Delete: \`path\``. This is a best-effort heuristic — if paths
     cannot be extracted (free-form text), skip validation with
     warning: "Cannot parse file list for Phase {N}. Proceeding
     without file ownership validation."
   - If any file appears in more than one phase: split conflicting
     phases into separate batches, warn:
     "Phases {N} and {M} both modify {file}. Serializing."
   - Re-validate after splitting

5. Derive isolation level per batch:
   - For each phase in the batch, derive scope classification
     (same rules as dispatcher: file list + description + governance)
   - Batch isolation = highest scope in the batch:
     scope:multi-file or below → parallel-agent (file-gated)
     scope:cross-cutting or sensitive → parallel-worktree
   - If --worktree flag is set: force parallel-worktree regardless

6. Present dispatch plan to user:
   "Parallel dispatch plan:
    Batch 1 (parallel, {isolation}): Phases {list}
    Batch 2 (serial): Phase {N} (depends: batch 1)
    Batch 3 (parallel, {isolation}): Phases {list}
    Batch 4 (serial): Phase {N} (depends: all)

    {total phases} phases in {total batches} batches. Proceed? [Y/n]"

   Wait for user confirmation.
```

**New Section 6b: Parallel Dispatch Execution**

```
### 6b. Dispatch Parallel Batch

For each batch in the dispatch plan (sequential between batches,
parallel within each batch):

**File-gated dispatch (parallel-agent):**
1. Create task per phase in the batch
2. Dispatch N rdf-dispatcher subagents simultaneously
   - Each gets the standard dispatch payload (Section 5) plus:
     PARALLEL_BATCH: true
   - Each operates on the shared working tree
   - File ownership enforced by the plan (validated in 2b.4)
3. Wait for all subagents in the batch to complete
4. Collect results: PASS or FAIL per phase

**Worktree dispatch (parallel-worktree):**
1. Create task per phase in the batch
2. For each phase, create a git worktree:
   git worktree add .worktrees/rdf-phase-{N}-{session-id} -b rdf/phase-{N}-{session-id} HEAD
   (session-id = 8-char random hex, prevents cross-session collisions)
3. Dispatch N rdf-dispatcher subagents simultaneously
   - Each gets the standard dispatch payload plus:
     PARALLEL_BATCH: true
     PROJECT_ROOT: {worktree path}
   - Each dispatched with isolation: "worktree"
4. Wait for all subagents in the batch to complete
5. Merge completed worktrees in plan order:
   For each completed phase (in plan order, N ascending):
     git rebase main rdf/phase-{N}-{session-id}
     git merge --ff-only rdf/phase-{N}-{session-id}
   This produces a clean linear history — phase commits appear in
   plan order with no merge commit artifacts.
   If rebase conflict: stop, report conflicting phases, enter
   failure handling (Section 8)
6. Clean up worktrees:
   git worktree remove .worktrees/rdf-phase-{N}-{session-id}
   git branch -d rdf/phase-{N}-{session-id}
7. Collect results: PASS or FAIL per phase

**Post-batch quality gate (worktree dispatch only):**
After merging all worktrees in a batch, run a batch-level QA check:
- Dispatch rdf-qa subagent across the combined diff of all phases
  in the batch
- This catches semantic conflicts that file ownership validation
  cannot detect (e.g., two phases both adding the same function name
  to different files)
- If QA finds issues: enter failure handling (Section 8)

**Progress tracking:**
Write batch progress to `.rdf/work-output/build-progress.md`:
  DISPATCH_MODE: parallel
  TOTAL_PHASES: {N}
  TOTAL_BATCHES: {N}
  CURRENT_BATCH: {N}
  BATCH_PHASES: [list]
  COMPLETED_PHASES: [list]
  FAILED_PHASES: [list]

After each batch completes, update and proceed to the next batch.
After all batches complete, proceed to end-of-plan sentinel
(unchanged — runs on cumulative diff from phase 1 to HEAD).
```

**New Section 8: Parallel Failure Handling**

```
### 8. Parallel Failure Handling

When one or more phases in a parallel batch fail:

1. Wait for all phases in the batch to complete (do not interrupt
   running phases on peer failure)

2. Classify each failure:
   - Gate 1 (engineer self-report) failure → recommendation: retry
   - Gate 2 (QA) failure → recommendation: retry
   - Gate 3 (sentinel) MUST-FIX → recommendation: retry
   - Gate 3 (sentinel) architectural concern → recommendation: pause
   - Merge conflict → recommendation: serialize conflicting phases
   - Post-batch QA failure → recommendation: pause

3. Present to user with recommendation:
   "Batch {N} results:
    [PASS] Phase 1: Replace dispatcher gate selection
    [FAIL] Phase 2: Update agent finding vocabularies (Gate 2: lint)
    [PASS] Phase 3: Simplify r-plan metadata
    [PASS] Phase 4: Simplify r-build dispatch payload

    Phase 2 failed at Gate 2 (QA lint error).
    **Recommendation: retry** — lint errors are typically fixable.

    Options:
    [1] Merge phases 1, 3, 4 now — retry phase 2 after merge
    [2] Retry phase 2 in isolation (attempt 2/3)
    [3] Pause — review failure before proceeding"

4. Execute user's choice:
   - Option 1: Merge successful phases in plan order, then dispatch
     phase 2 serially against new HEAD
   - Option 2: Re-dispatch phase 2's dispatcher subagent (same
     isolation level, max 3 total attempts)
   - Option 3: Write progress to build-progress.md, stop. User can
     resume with `/r:build --parallel` (reads progress file)
```

### 5.2 `canonical/commands/r-plan.md` — Structured Dependency Graph

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 2.1 (Phase Dependencies) | ASCII art dependency graph, optional, only for parallel-agent | Structured dependency list, mandatory for all plans | 196-216 |
| Section 2.3 (Tag Each Phase) | 3 mode options | Note about parallel-worktree as inter-phase isolation | 231-243 |
| Plan Quality Standard item 13 | "Dependency graph present if any phase is [parallel-agent]" | "Structured dependency list present in all plans" | 458 |

**New Phase Dependencies format (replaces Section 2.1):**

```
## Phase Dependencies

Structured dependency list — required for all plans. `/r:build
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
```

**Updated Section 2.3 note:**

Add after the execution mode list:

```
Note: `[parallel-agent]` mode is for INTRA-PHASE parallelism
(multiple engineers within one phase). INTER-PHASE parallelism
(multiple phases running concurrently) is handled by `/r:build
--parallel`, which reads the Phase Dependencies list above. The
planner does not need to think about inter-phase parallelism — the
build command derives it from the dependency graph.
```

**Updated Plan Quality Standard:**

```
13. Structured dependency list present (all plans)
```

### 5.3 `canonical/commands/r-vpe.md` — Single-Call Build Stage

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Stage 4 (Build) | Per-phase loop calling `/r:build {N}` | Single call to `/r:build --parallel` | 152-177 |

**New Stage 4:**

```
## Stage 4: Build (invokes /r:build --parallel)

Mark task "Build" as in_progress.

Invoke /r:build --parallel. The build command handles all phase
orchestration: dependency graph reading, batch computation, parallel
dispatch, merge, quality gates, and failure handling.

VPE receives the aggregate result:
- All phases passed → continue to ship
- Failures exist → present to user:
  "Build completed with failures:
   {failure summary from /r:build}
   [retry-failed / pause / continue-to-ship]"
  Wait for user decision.

After all phases complete:
  "All {N} phases complete. End-of-plan review: {verdict}.
   Ready to ship? [Y/pause]"

Write state after build completes:
  STAGE: build
  STATUS: complete
  COMPLETED_PHASES: [1, 2, ..., N]

Mark task "Build" as completed when all phases pass.
```

### 5.4 `canonical/agents/dispatcher.md` — Nested Parallel Downgrade

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| [parallel-agent] mode | Always available | Downgrade to [serial-agent] when PARALLEL_BATCH: true | 30-37 |
| Dispatch payload | No PARALLEL_BATCH field | Read PARALLEL_BATCH flag | 13-16 |

**New text in [parallel-agent] section:**

```
**[parallel-agent]** — large changes, parallel subagents
- Validate file ownership boundaries (no overlapping files)
- Spawn N engineer subagents, each with isolated file set
- Each engineer follows TDD independently
- Wait for all to complete
- Run integration check for semantic conflicts
- If conflicts: serialize conflicting tracks and re-run
- Spawn qa subagent across full diff

**Nested parallel downgrade:** When the dispatch payload contains
`PARALLEL_BATCH: true`, this dispatcher is running as part of an
inter-phase parallel batch managed by /r:build. In this case,
downgrade [parallel-agent] to [serial-agent] to avoid nested
parallelism. Log: "Downgraded to serial-agent (parallel batch)."
```

### 5.5 `canonical/reference/framework.md` — Inter-Phase Parallelism

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Pipeline section (after parallel variant) | Only describes intra-phase parallelism | Add inter-phase parallelism summary | after 181 |

**New text:**

```
**Inter-phase parallelism:**
- `/r:build --parallel` reads the plan dependency graph
- Independent phases dispatch concurrently (max 4)
- Isolation auto-derived from scope: file-gated or git worktree
- Results merge in plan order (deterministic)
- See r-build.md for the full dispatch protocol.
```

### 5.6 `reference/diagrams.md` — Parallel Dispatch Flow

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 3 (Engineering Pipeline) | Serial phase dispatch only | Add parallel batch flow | after existing content |

**New subsection:**

```
### Inter-Phase Parallel Dispatch

/r:build --parallel reads the dependency graph and dispatches batches:

  PLAN.md Phase Dependencies
         │
         ▼
  ┌─────────────────────┐
  │  Compute Batches    │ ← dependency graph + file ownership
  └────────┬────────────┘
           │
    ┌──────┴──────┐
    ▼             ▼
  Batch 1       Batch 2 (waits for batch 1)
  ┌───┬───┐     ┌───┐
  │P1 │P2 │     │P5 │
  │P3 │P4 │     └───┘
  └───┴───┘
    │ │ │ │
    ▼ ▼ ▼ ▼
  dispatcher dispatcher dispatcher dispatcher
    │ │ │ │
    ▼ ▼ ▼ ▼
  ┌───────────┐
  │  Merge    │ ← plan order (deterministic)
  └─────┬─────┘
        ▼
  Post-batch QA (worktree mode only)
        │
        ▼
  Next batch or end-of-plan sentinel

Isolation selection:
  scope:multi-file    → file-gated (shared worktree)
  scope:cross-cutting → git worktree per phase
  scope:sensitive     → git worktree per phase
  --worktree flag     → force git worktree
```

### 5.7 `canonical/commands/r-start.md` — Build Progress Signal

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| In-flight signals | Detects spec-progress, vpe-progress, ship-progress | Add build-progress.md detection | Signal list |

**New signal:**

```
- build-progress.md exists → "Build: batch {N}/{total}, {completed}/{total} phases"
```

### 5.8 `canonical/commands/r-status.md` — Parallel Batch Status

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Pipeline section | Shows build phase count | Add parallel batch status when active | Pipeline detection |

**New pipeline entry (conditional):**

```
| **Build** | *parallel* | Batch {N}/{total}: Phases {list} |
```

Only shown when build-progress.md exists and DISPATCH_MODE is
parallel. Otherwise the existing serial build display is unchanged.

### 5.9 `canonical/reference/session-safety.md` — Build Recovery Signal

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Recovery signals | 9 signals including vpe-progress.md | Add build-progress.md | Recovery section |

**New recovery signal:**

```
- .rdf/work-output/build-progress.md → Parallel build state, resume with /r:build --parallel
```

---

## 5b. Examples

### Example 1: Auto-parallel dispatch

```
$ /r:build --parallel

Reading PLAN.md...
8 phases, dependency graph:
  - Phase 1: none
  - Phase 2: none
  - Phase 3: [1, 2]
  - Phase 4: [1, 2]
  - Phase 5: [3, 4]
  - Phase 6: none
  - Phase 7: [6]
  - Phase 8: [1, 2, 3, 4, 5, 6, 7]

  Batch 1 (parallel, file-gated): Phases 1, 2, 6
  Batch 2 (parallel, file-gated): Phases 3, 4, 7
  Batch 3 (serial): Phase 5 (depends: 3, 4)
  Batch 4 (serial): Phase 8 (depends: all)

8 phases in 4 batches. Proceed? [Y/n]

User: Y

Dispatching batch 1 (3 phases, parallel-agent)...
  [PASS] Phase 1: Replace dispatcher gate selection
  [PASS] Phase 2: Update agent finding vocabularies
  [PASS] Phase 6: Create VPE command

Batch 1 complete. Dispatching batch 2...
  [PASS] Phase 3: Simplify r-plan metadata
  [PASS] Phase 4: Simplify r-build dispatch payload
  [PASS] Phase 7: Add VPE integration points

Batch 2 complete. Dispatching batch 3...
  [PASS] Phase 5: Update documentation surfaces

Batch 3 complete. Dispatching batch 4...
  [PASS] Phase 8: Regenerate and verify

All 8 phases complete. End-of-plan review: PASS.
Run /r:ship to begin the release workflow.
```

### Example 2: Range dispatch with worktree override

```
$ /r:build 1-4 --worktree

Validating phases 1-4...
  Dependencies: all "none" — independent
  File ownership: no overlaps
  Isolation: forced worktree (--worktree flag)

Creating worktrees...
  .worktrees/rdf-phase-1-a3f8b2c1
  .worktrees/rdf-phase-2-a3f8b2c1
  .worktrees/rdf-phase-3-a3f8b2c1
  .worktrees/rdf-phase-4-a3f8b2c1

Dispatching 4 phases (parallel-worktree)...
  [PASS] Phase 1 (47s)
  [PASS] Phase 3 (32s)
  [PASS] Phase 4 (28s)
  [PASS] Phase 2 (51s)

Merging in plan order (1, 2, 3, 4)...
All merged cleanly. Post-batch QA: PASS.

> **Phases 1-4 complete** (parallel, 4 worktrees)
> Next: Phase 5. Run `/r:build` to continue.
```

### Example 3: Partial failure with recommendation

```
$ /r:build --parallel

Dispatching batch 1 (4 phases, parallel-agent)...
  [PASS] Phase 1
  [FAIL] Phase 2 (Gate 2: bash -n syntax error in reviewer.md)
  [PASS] Phase 3
  [PASS] Phase 4

Phase 2 failed at Gate 2 (QA lint error).
**Recommendation: retry** — lint errors are typically fixable.

Options:
[1] Merge phases 1, 3, 4 now — retry phase 2 after merge
[2] Retry phase 2 in isolation (attempt 2/3)
[3] Pause — review failure before proceeding

User: 1

Merging phases 1, 3, 4...
Dispatching phase 2 serially against new HEAD...
  [PASS] Phase 2 (retry 1)

All batch 1 phases complete. Continuing...
```

### Example 4: VPE uses parallel build

```
$ /r:vpe

[... intake, spec, plan stages ...]

VPE: Plan ready: PLAN.md (6 phases)
     Ready to build? [Y/pause]

User: Y

VPE: Invoking /r:build --parallel...

  Batch 1 (parallel): Phases 1, 2, 3
  Batch 2 (serial): Phase 4
  Batch 3 (parallel): Phases 5, 6

  All 6 phases complete. End-of-plan review: PASS.
  Ready to ship? [Y/pause]

User: Y

[... /r:ship ...]
```

---

## 6. Conventions

### Execution Primitive Summary

After this change, RDF supports 4 execution primitives across 2 levels:

| Primitive | Isolation | Parallelism | Used by |
|-----------|-----------|-------------|---------|
| `serial-context` | None (main session) | None | Dispatcher (intra-phase) |
| `serial-agent` | Context window | None | Dispatcher (intra-phase) |
| `parallel-agent` | Context window + file gates | Yes | Dispatcher (intra-phase), Build command (inter-phase) |
| `parallel-worktree` | Git worktree | Yes | Build command (inter-phase) |

### Scope-to-Isolation Mapping

| Scope | Gate Selection (dispatcher) | Isolation Selection (build cmd) |
|-------|---------------------------|-------------------------------|
| `docs` | G1 only | parallel-agent (file-gated) |
| `focused` | G1+G2 | parallel-agent (file-gated) |
| `multi-file` | G1+G2+G3-lite | parallel-agent (file-gated) |
| `cross-cutting` | G1+G2+G3-full | parallel-worktree |
| `sensitive` | G1+G2+G3-full | parallel-worktree |

### Worktree Branch Naming

```
rdf/phase-{N}-{session-id}
```

Where `session-id` is an 8-character random hex string generated once
per `/r:build` invocation. This prevents collisions between concurrent
sessions (different terminals running different plans).

### Build Progress State File

```
DISPATCH_MODE: parallel | serial
TOTAL_PHASES: {N}
TOTAL_BATCHES: {N}
CURRENT_BATCH: {N}
BATCH_PHASES: 1,2,3,4
COMPLETED_PHASES: 1,3,4
FAILED_PHASES: 2
ISOLATION: parallel-agent | parallel-worktree
SESSION_ID: {8-char hex}
```

Written to `.rdf/work-output/build-progress.md`. Read by `/r:build
--parallel` on resume and by `/r:start` for in-flight signal display.

---

## 7. Interface Contracts

### Dispatch Payload Changes

The `/r:build` dispatch payload to the dispatcher adds one field:

```
Added:
  PARALLEL_BATCH: true | false
```

When `true`, the dispatcher downgrades `[parallel-agent]` to
`[serial-agent]` to prevent nested parallelism. All other payload
fields are unchanged.

### Plan Metadata Changes

The Phase Dependencies section in PLAN.md changes from free-text to
structured format:

```
Before:
  ## Phase Dependencies
  All phases sequential — no parallelization.
  Phases 1-2: Core engine changes
  Phase 5: depends on 1-4

After:
  ## Phase Dependencies
  - Phase 1: none
  - Phase 2: none
  - Phase 3: [1, 2]
  - Phase 4: [1, 2]
  - Phase 5: [3, 4]
```

### New State File

`build-progress.md` (written by `/r:build --parallel`, read by
`/r:start`, `/r:status`, and `/r:build --parallel` on resume):

Schema documented in Section 6 (Build Progress State File).

### VPE Build Stage Contract

VPE Stage 4 changes from per-phase invocation to single invocation:

```
Before: for each phase → /r:build {N}
After:  /r:build --parallel (single call)
```

VPE reads the build result (PASS/FAIL + failure details) and
handles its pipeline flow accordingly.

---

## 8. Migration Safety

### Backward Compatibility

- `/r:build N` (single phase) continues to work exactly as before —
  all new behavior is gated behind `--parallel`, range syntax, or
  `--worktree` flags
- Plans without structured dependency lists fall back to serial
  dispatch with a warning — no breakage
- Plans with old-format ASCII dependency graphs are unaffected — the
  build command only parses the structured `- Phase N:` format
- VPE's per-phase fallback: if `/r:build --parallel` fails (e.g.,
  no dependency list), VPE falls back to the per-phase loop
- The dispatcher's `PARALLEL_BATCH` flag defaults to `false` when
  absent — existing dispatch payloads work unchanged

### Upgrade Path

- No data migration needed — these are command/agent definition changes
- `rdf generate claude-code` regenerates all deployed files
- Existing PLAN.md files with free-text dependencies continue to work
  (serial fallback)
- New plans produced by `/r:plan` will include structured dependency
  lists automatically

### Rollback

Revert the canonical commits and run `rdf generate claude-code`.
Plans with structured dependency lists are harmless — `/r:build`
ignores them if it doesn't understand the format. No data to undo.

### Test Suite Impact

- No BATS tests affected — RDF tests are manual verification +
  shellcheck + frontmatter-free checks
- Verification: `rdf generate claude-code` produces valid output

---

## 9. Dead Code and Cleanup

| Finding | File | Action |
|---------|------|--------|
| VPE Stage 4 per-phase loop | canonical/commands/r-vpe.md | Replace with single /r:build --parallel call |
| "All phases sequential" free-text in plan template | canonical/commands/r-plan.md | Replace with structured list format |
| Plan Quality Standard item 13 phrasing | canonical/commands/r-plan.md | Update to "Structured dependency list present" |

---

## 10a. Test Strategy

| Goal | Test method | Verification |
|------|-------------|--------------|
| Goal 1: /r:build --parallel dispatch | Read r-build.md | Section 2b and 6b exist with batch computation logic |
| Goal 2: Structured dependency list | Read r-plan.md | Section 2.1 has `- Phase N:` format documentation |
| Goal 3: Isolation auto-derivation | Read r-build.md | Section 2b.5 has scope-to-isolation mapping |
| Goal 4: --worktree override | Read r-build.md | Invocation line includes `--worktree` flag |
| Goal 5: Range syntax | Read r-build.md | Invocation line includes `N-M` syntax |
| Goal 6: Max parallelism ceiling | Read r-build.md | `--max N` flag with default 4 |
| Goal 7: Partial failure handling | Read r-build.md | Section 8 exists with recommendation logic |
| Goal 8: Plan order merge | Read r-build.md | Section 6b specifies "in plan order, N ascending" |
| Goal 9: VPE single call | Read r-vpe.md | Stage 4 calls `/r:build --parallel` once |
| Goal 10: File ownership validation | Read r-build.md | Section 2b.4 validates no file overlap |

## 10b. Verification Commands

```bash
# Goal 1: Parallel dispatch protocol exists
grep -c 'Parallel Batch\|parallel batch' canonical/commands/r-build.md
# expect: >= 3

# Goal 2: Structured dependency list format documented
grep -c 'Phase.*: none\|Phase.*: \[' canonical/commands/r-plan.md
# expect: >= 4

# Goal 3: Scope-to-isolation mapping
grep -c 'scope:multi-file.*parallel-agent\|scope:cross-cutting.*worktree' canonical/commands/r-build.md
# expect: >= 2

# Goal 4: --worktree flag
grep -c '\-\-worktree' canonical/commands/r-build.md
# expect: >= 3

# Goal 5: Range syntax N-M
grep -c 'N-M\|N \| N-M' canonical/commands/r-build.md
# expect: >= 2

# Goal 6: Max parallelism
grep -c '\-\-max\|default: 4\|max.*4' canonical/commands/r-build.md
# expect: >= 2

# Goal 7: Failure handling with recommendations
grep -c 'Recommendation.*retry\|Recommendation.*pause' canonical/commands/r-build.md
# expect: >= 2

# Goal 8: Plan order merge
grep 'plan order' canonical/commands/r-build.md
# expect: >= 1

# Goal 9: VPE single call
grep 'r:build --parallel' canonical/commands/r-vpe.md
# expect: >= 1

# Goal 10: File ownership validation
grep -c 'file.*appears.*more than one\|file overlap\|no overlap' canonical/commands/r-build.md
# expect: >= 1

# Cross-reference: PARALLEL_BATCH in dispatcher
grep 'PARALLEL_BATCH' canonical/agents/dispatcher.md
# expect: >= 1

# Cross-reference: build-progress.md in start and session-safety
grep 'build-progress' canonical/commands/r-start.md
# expect: >= 1
grep 'build-progress' canonical/reference/session-safety.md
# expect: >= 1

# Cross-reference: no VPE references in r-build
grep -ci 'vpe' canonical/commands/r-build.md
# expect: 0

# rdf generate produces valid output
bash bin/rdf generate claude-code 2>&1 | tail -3
# expect: success message, no errors
```

---

## 11. Risks

1. **Git worktree merge conflicts despite file ownership validation.**
   Phases may not share files but could create conflicting state
   (e.g., both adding the same function name to different files,
   both modifying the same line in a shared config). *Mitigation:*
   Post-batch QA check runs after worktree merge to catch semantic
   conflicts. File ownership validation catches file-level conflicts
   at dispatch time.

2. **Session ID collisions.** Two concurrent `/r:build --parallel`
   invocations could generate the same 8-char hex session ID.
   *Mitigation:* 8 hex chars = 4 billion possibilities. Collision
   is astronomically unlikely for human-initiated sessions. If it
   occurs, `git worktree add` fails (branch already exists) and the
   build command falls back to serial with an error message.

3. **Context window pressure from parallel dispatchers.** Each
   dispatcher subagent consumes a full context window. 4 concurrent
   dispatchers = 4x token cost. *Mitigation:* Default max of 4
   concurrent dispatchers. Configurable via `--max` for users who
   want to limit cost. Each dispatcher is an independent subagent
   with its own context — no shared context pressure.

4. **Dependency graph errors in PLAN.md.** Planner declares phases
   independent (`none`) when they actually have semantic dependencies.
   *Mitigation:* File ownership validation catches file-level
   conflicts. Post-batch QA catches semantic conflicts. End-of-plan
   sentinel catches cumulative regressions. Three layers of defense.

5. **Nested parallelism escape.** Dispatcher receives
   `PARALLEL_BATCH: true` but the LLM ignores the downgrade
   instruction and attempts `[parallel-agent]` mode anyway.
   *Mitigation:* The downgrade is documented as a hard rule in the
   dispatcher spec. LLMs reliably follow explicit behavioral rules
   in agent definitions. If it occurs, the worst case is slower
   execution (nested subagents), not incorrect results.

6. **Worktree cleanup on crash.** If the build command crashes
   mid-batch, worktrees and branches are left behind. *Mitigation:*
   `build-progress.md` records the session ID. On resume
   (`/r:build --parallel`), the build command detects existing
   worktrees with the recorded session ID and offers: "Found
   orphaned worktrees from a prior session. Clean up? [Y/n]"

---

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| All phases are strictly sequential (Phase N depends on N-1) | `/r:build --parallel` computes single-phase batches, runs serially | Degrades gracefully — same result as `/r:build` without `--parallel` |
| Plan has no Phase Dependencies section | Fall back to serial with warning message | Warning: "Phase Dependencies section not found. Running serially." |
| Phase Dependencies section uses old free-text format | Fall back to serial with warning message | Warning: "Phase Dependencies not in structured format." |
| Two phases in a batch modify the same file | Split into separate batches at validation time | Warning: "Phases N and M both modify {file}. Serializing." |
| Mixed scope levels in one batch (multi-file + cross-cutting) | Entire batch promoted to highest isolation level | Cross-cutting phase promotes batch to parallel-worktree |
| `--max 1` specified | All phases run serially (batches of 1) | Effectively `/r:build` in serial mode but with batch structure |
| Worktree creation fails (disk full, permissions) | Fall back to file-gated parallel or serial | Warning: "Worktree creation failed. Falling back to {mode}." |
| Phase 2 fails, user merges 1,3,4 — but phase 5 depends on 2 | Phase 5 remains blocked until phase 2 completes | Dependency graph prevents premature dispatch of phase 5 |
| `/r:build --parallel` invoked with only 1 pending phase | Single phase dispatched serially (no parallel overhead) | Detects single-phase batch, skips parallel machinery |
| Git merge conflict during worktree merge | Stop merge, report conflicting phases, enter failure handling | User decides: serialize conflicting phases or manual resolve |
| Concurrent sessions run `/r:build --parallel` on same repo | Session IDs prevent branch name collisions | Separate worktree directories and branch names per session |
| VPE calls `/r:build --parallel` but plan has no dependency list | Build command falls back to serial internally; VPE receives aggregate result | VPE does not need fallback logic — `/r:build --parallel` handles degradation |

---

## 12. Open Questions

None. All design decisions resolved during brainstorming:
- Q1: /r:build owns parallel dispatch directly (Option A)
- Q1b: Isolation auto-derived from scope classification (Approach 2)
- Q2: Structured dependency list in PLAN.md (Option A)
- Q3: Plan order merge (Option A)
- Q4: User decides on partial failure with recommendations (Option C)
- Q5: Fixed ceiling default 4, configurable --max (Option B)
- Q6: Keep intra-phase [parallel-agent] as-is, don't fix (Option C)
- Q7: File ownership + dependency declaration validation (Option B)
- Q8: VPE calls /r:build --parallel once (Option A)
