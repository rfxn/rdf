# Design Notes: Parallel Plan Execution in RDF

**Date:** 2026-03-20
**Status:** Research notes — not yet a spec
**Context:** Gap identified during gate simplification + VPE spec. The
dispatcher describes `[parallel-agent]` mode but inter-phase parallelism
has no owner. This document captures the problem, industry patterns, and
a design direction for a future spec.

---

## 1. The Problem

RDF has two kinds of parallelism, and only one has an owner:

| Type | What | Owner | Status |
|------|------|-------|--------|
| **Intra-phase** | Multiple engineers within ONE phase (Phase 3 has 6 independent files → 3 engineers in worktrees) | Dispatcher `[parallel-agent]` mode | Designed, unreliably executed |
| **Inter-phase** | Multiple PHASES running simultaneously (Phases 1-4 are independent → run all 4 at once) | **Nobody** | Gap |

**Intra-phase** is described in dispatcher.md but relies on the LLM
deciding to spawn multiple Agent tool calls simultaneously. In practice
it serializes — the model "thinks about" parallelism but executes
sequentially.

**Inter-phase** has no mechanism at all. The plan dependency graph
identifies which phases CAN run concurrently, but no command reads that
graph and acts on it.

The VPE could own inter-phase parallelism, but VPE is optional. A user
calling `/r-build` directly needs access to the same capability.

---

## 2. Industry Research

### Claude Code Agent Teams (Anthropic, experimental)

The native platform approach. Team lead + teammates with shared task list.

**Dispatch:** Team lead creates tasks, teammates self-claim via file-lock-based
claiming (`~/.claude/tasks/{team-name}/`). Each teammate is a fully
independent Claude Code instance with its own context window.

**Dependencies:** Tasks support explicit dependency declarations. Blocked
tasks auto-unblock when dependencies complete.

**Merge:** No automated merge. Teammates commit to branches, lead
synthesizes. The docs warn: "Two teammates editing the same file leads
to overwrites. Break the work so each teammate owns a different set of
files."

**Progress:** Task list visible via `Ctrl+T`. Split-pane mode (tmux)
gives each teammate its own pane. Mailbox for inter-agent messaging.

**Failure:** No automatic retry. Teammates may stop on errors. Hooks
provide gates: `TeammateIdle` (exit code 2 sends feedback, keeps
teammate working), `TaskCompleted` (exit code 2 prevents premature
completion).

**Key constraint:** Experimental, behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`
flag. No session resumption for teammates. Recommended 3-5 teammates.
~3-4x token cost of single-session equivalent.

### Superpowers (obra/superpowers)

Two models: current subagent-based, and planned Agent Teams integration.

**Current (`dispatching-parallel-agents` skill):**

Decision flowchart:
1. Multiple independent tasks? → parallel
2. Shared state? → sequential
3. File conflicts? → sequential

Four-stage dispatch: Domain Identification → Task Specification (isolated
context per agent with scope/objectives/constraints/output format) →
Parallel Launch (multiple `Task()` calls) → Coordination.

The `subagent-driven-development` skill (Superpowers 5) defaults to
subagent dispatch using cheaper models (Haiku) when detailed plans exist.

**Planned Agent Teams integration (Issue #469):**

Four phases: detection infrastructure → team mode for subagent-driven-dev
→ team mode for parallel dispatch → within-batch parallelism for plan
execution. Graceful degradation to subagent pattern when teams unavailable.
Tasks with dependencies still sequential; only independent tasks parallelize.

**Merge:** Manual — summary review, conflict detection, full test suite.

**Failure:** Post-hoc spot checks. No retry logic.

### Gas Town (steveyegge/gastown)

Hierarchical model optimized for scale (20-30 parallel agents).

**Dispatch:** Mayor creates convoys of beads (work items with 5-char IDs).
Slings beads to rigs (git repo containers) via CLI:
`gt sling <bead-id> <rig> --agent <runtime>`. Supports multiple agent
runtimes (Claude, Gemini, Codex, Cursor, etc.).

**Dependencies:** Git-backed Beads ledger tracks state. Convoys group
related work with notification flags. State persists across restarts.

**Merge:** Git branches in separate worktrees. Standard git merge — this
is the core design choice. Version control handles merging, not LLM
synthesis. "Git Up, Pull, Push" — deterministic, auditable.

**Progress:** TUI feed (`gt feed`), stuck detection (`gt feed --problems`),
convoy status (`gt convoy list/show`).

**Failure:** Context recovery via `gt prime`. Constant human steering
required. Operational reality: "$100/hour token burn rate at peak,"
auto-merged failing tests, agents deleting code unexpectedly.

**Key insight:** Git worktree isolation is the primary conflict-prevention
mechanism. Each agent gets its own working copy. Merging is a git
operation, not an LLM operation.

### Ruflo (ruvnet/ruflo)

Enterprise-grade orchestration with the most mature dependency and
failure models.

**Dispatch:** Hive Mind message bus. Five execution strategies: parallel,
sequential, adaptive, balanced, stream-chained. Workflows defined in
JSON/YAML:

```json
{
  "tasks": {
    "B": { "agent": "planner", "dependencies": ["A"] },
    "F": { "agent": "reviewer", "dependencies": ["C", "D", "E"] }
  }
}
```

**Dependencies:** Declarative dependency arrays with conditional execution:
`"condition": "tests.passed && coverage > 80"`. PageRank-based knowledge
graph identifies influential patterns.

**Merge:** RETRIEVE-JUDGE-DISTILL-CONSOLIDATE-ROUTE learning loop.
Stream-JSON chaining allows real-time piping between agents.

**Failure:** The most robust handling across all frameworks:
- Byzantine fault-tolerant consensus (proceeds with f < n/3 failures)
- Weighted voting (queens get 3x authority)
- Five consensus algorithms (Raft, Byzantine, Gossip, CRDT, Majority)
- Checkpoints with auto-restore after each stage
- Rollback to previous checkpoints preserving logs
- Exponential backoff retry (configurable, default 3 attempts)
- Circuit breaker (5 failures → stop, reset after 60s)
- Fallback agents for degraded-mode processing

### parallel-worktrees (spillwavesolutions)

Standalone Claude Code skill focused on git worktree isolation.

**Dispatch:** `spawn-parallel.sh` creates worktrees sharing `.git`:
`git worktree add .worktrees/feature-name -b branch-name main`.
Two modes: interactive (separate terminals) or background (`Task` tool
with `run_in_background: true`).

**Dependencies:** Prevention over resolution — use only for "features
with independent parts." No automated dependency graph.

**Merge:** `sync-worktrees.sh` with `--status`, `--merge`, `--interactive`
modes. Agents commit with descriptive messages.

**Progress:** Status files (`.agent-status/task-name.json`) with
RUNNING/COMPLETE/FAILED states.

**Key insight:** "LLM non-determinism as a feature" — N parallel agents
give N valid solutions to choose from.

---

## 3. Comparative Analysis

| Dimension | Agent Teams | Superpowers | Gas Town | Ruflo | Worktrees Skill |
|-----------|------------|-------------|----------|-------|-----------------|
| **Dispatch** | Task list + self-claim | Task() calls per domain | Mayor slings beads via CLI | Hive Mind bus, 5 strategies | spawn-parallel.sh |
| **Dependencies** | Declarative task deps | Manual identification | Git-backed ledger | JSON arrays + conditions | Manual (user) |
| **Isolation** | File ownership convention | None | Git worktrees (core) | Memory namespaces | Git worktrees (core) |
| **Merge** | Manual (lead synthesizes) | Manual (test suite) | Git merge (standard) | Pipeline + stream chain | sync-worktrees.sh |
| **Progress** | Task list + panes | Output format spec | TUI feed + convoy | Hook signals + metrics | Status JSON files |
| **Failure** | Manual replacement | Post-hoc spot check | Human steering | Byzantine + circuit breaker | Status files |
| **Scale** | 3-5 teammates | 1 subagent (current) | 20-30 agents | 60+ agents | N worktrees |
| **Maturity** | Experimental | Stable (subagent) | Operational but rough | Feature-rich on paper | Simple and stable |

---

## 4. What Good Looks Like for RDF

### Design principles (from research)

**P1: Git worktrees are the isolation mechanism.**
Gas Town and the worktrees skill both use git worktrees as the primary
conflict-prevention mechanism. This is the right abstraction for RDF —
each parallel phase gets its own working copy. File ownership boundaries
from the plan are enforced by physical isolation, not convention.

**P2: The plan dependency graph IS the dispatch schedule.**
Ruflo's declarative dependency arrays are the cleanest model. RDF
already has a dependency graph in the plan preamble. The dispatcher (or
build command) reads it and dispatches phases whose dependencies are met.

**P3: Merge is a git operation, not an LLM operation.**
Gas Town gets this right. When parallel phases complete, their worktrees
are merged via standard git merge. If there are conflicts (which the plan
should have prevented via file ownership), the merge fails explicitly
and the user resolves. No LLM synthesis of parallel results.

**P4: Progress comes from the orchestrator, not the workers.**
The orchestrator (build command or VPE) runs in main context and can
update the task list. Workers (dispatcher subagents in worktrees) do
their work and write status files. The orchestrator polls status files
or waits for subagent completion, then updates tasks. This solves the
"frozen task list" problem.

**P5: Failure is per-track, not per-batch.**
From the dispatcher's existing parallel failure semantics: running
engineers are NOT interrupted on peer failure. This applies to
inter-phase parallelism too — if Phase 2 fails, Phase 1/3/4 continue.
Retry is per-phase.

**P6: Graceful degradation to serial.**
If Agent Teams is unavailable, if worktree creation fails, or if the
user prefers sequential execution — the same mechanism falls back to
serial `/r-build N` calls. Parallel is an optimization, not a
requirement.

### What the user experience should look like

```
# Explicit parallel dispatch (user calls directly):
/r-build 1-4

Reading dependency graph...
Phases 1-4 are independent (no shared files). Dispatching in parallel.

  [worktree-1] Phase 1: Replace dispatcher gate selection ......... PASS
  [worktree-2] Phase 2: Update agent finding vocabularies ......... PASS
  [worktree-3] Phase 3: Simplify r-plan phase metadata ............ PASS
  [worktree-4] Phase 4: Simplify r-build dispatch payload ......... PASS

Merging 4 worktrees...
All phases merged cleanly. 4 commits applied.

> **Phases 1-4 complete** (parallel, 4 worktrees)
> Next: Phase 5. Run `/r-build` to continue.
```

```
# Auto-parallel (build detects independent phases):
/r-build --parallel

Reading dependency graph...
Phases 1-4: independent (parallel)
Phase 5: depends on 1-4 (serial, after batch)
Phase 6: independent of 5 (can parallel with 7)
Phase 7: depends on 6 (serial)
Phase 8: depends on all (serial, last)

Dispatching batch 1: Phases 1-4 (parallel)...
  [4 worktrees, same output as above]

Phase 5: sequential...
  Phase 5 complete.

Dispatching batch 2: Phases 6-7 (serial, dependency)...
  Phase 6 complete.
  Phase 7 complete.

Phase 8: sequential (final)...
  Phase 8 complete.

> **All 8 phases complete.** End-of-plan review: PASS.
> Run `/r-ship` to begin the release workflow.
```

```
# VPE manages the same thing transparently:
/r-vpe
  ...
  VPE: Plan ready (8 phases, 4 parallelizable). Ready to build?
  User: Y
  VPE: Building phases 1-4 in parallel...
  [same output]
  VPE: Building phase 5...
  ...
```

### Where the capability lives

```
/r-build (command) — owns the dispatch mechanism
  ├── /r-build N           — single phase (existing)
  ├── /r-build N-M         — range of phases
  ├── /r-build --parallel  — auto-detect independent batches
  └── dependency graph from PLAN.md preamble

/r-vpe (command) — calls /r-build with range/parallel flag
  └── user sees the same thing, managed by VPE

Direct user — calls /r-build --parallel themselves
  └── VPE not required
```

### Implementation sketch

```
/r-build --parallel (or /r-build 1-4):

1. Read PLAN.md
2. Parse dependency graph (Phase Dependencies section)
3. Identify requested phases
4. Validate independence:
   - No file appears in more than one phase's file list
   - No phase in the batch depends on another phase in the batch
   - If validation fails: fall back to serial with explanation
5. For each phase in the parallel batch:
   - Create git worktree: git worktree add .worktrees/phase-N -b phase-N HEAD
   - Dispatch rdf-dispatcher subagent with:
     - isolation: "worktree" (CC native)
     - PROJECT_ROOT set to the worktree path
     - Full dispatch payload for that phase
6. Wait for all subagents to complete
   - Update task list as each completes
   - If any fail: continue others, mark failed phase for retry
7. Merge worktrees:
   - For each completed phase (in plan order):
     git merge phase-N --no-ff
   - If merge conflict: stop, report which phases conflict, suggest
     serializing those phases
   - Clean up worktrees: git worktree remove .worktrees/phase-N
8. Run integration check:
   - Verify no semantic conflicts (grep for duplicate imports,
     conflicting definitions)
   - If issues found: report and suggest manual resolution
9. Quality gates on merged result:
   - QA across the full merged diff
   - Sentinel across the full merged diff (scope:cross-cutting
     since multi-phase merge is inherently cross-cutting)
10. Report results
```

### Failure handling

```
Phase 2 fails during parallel batch 1-4:

  [worktree-1] Phase 1: ......... PASS
  [worktree-2] Phase 2: ......... FAIL (gate: QA MUST-FIX)
  [worktree-3] Phase 3: ......... PASS
  [worktree-4] Phase 4: ......... PASS

  Phase 2 failed. Phases 1, 3, 4 succeeded.

  Options:
  1. Merge phases 1, 3, 4 now — retry phase 2 serially after merge
  2. Retry phase 2 in its worktree (3 max retries)
  3. Pause — review phase 2 failure before proceeding

  [1/2/3]?
```

### Graceful degradation

```
If Agent Teams unavailable (no TeamCreate tool):
  → Use subagent dispatch with isolation: "worktree" (CC native)

If worktree creation fails:
  → Fall back to serial execution with message:
    "Worktree creation failed. Running phases sequentially."

If user prefers serial:
  /r-build          — always serial (existing behavior)
  /r-build 3        — always serial (existing behavior)
  /r-build --serial — explicit serial even for independent phases
```

---

## 5. Relationship to Existing RDF Components

### Dispatcher `[parallel-agent]` mode

This existing mode handles intra-phase parallelism (multiple engineers
within one phase). It stays as-is. The new inter-phase parallelism
is orthogonal — it happens at the build command level, above the
dispatcher.

```
Build command (inter-phase parallelism)
  ├── Phase 1 → dispatcher (may use intra-phase parallelism)
  ├── Phase 2 → dispatcher (serial within phase)
  ├── Phase 3 → dispatcher (serial within phase)
  └── Phase 4 → dispatcher (may use intra-phase parallelism)
```

### VPE

VPE calls `/r-build --parallel` when it detects independent phases in
the plan. The user can do the same without VPE.

### Plan dependency graph

The plan preamble already contains a dependency graph (Section 2.1 of
the plan format). The build command reads this graph to identify
parallel batches. No plan format changes needed — the graph already
exists.

### End-of-plan sentinel

After all phases complete (including parallel batches), the end-of-plan
sentinel runs on the cumulative diff. This is unchanged — it already
operates on the full diff from phase 1 to HEAD.

### Agent Teams future

When Agent Teams stabilizes, the build command's parallel dispatch can
optionally use teammates instead of isolated subagents. The dispatch
mechanism changes (shared task list vs individual Agent calls), but the
user-facing behavior and dependency graph reading are identical.

---

## 6. Open Questions for the Future Spec

1. **Merge order:** When merging parallel worktrees, should they merge
   in plan order (Phase 1, 2, 3, 4) or completion order (fastest first)?
   Plan order is more predictable; completion order is faster.

2. **Quality gates on partial merge:** If phases 1, 3, 4 succeed and
   phase 2 fails, do we run quality gates on the partial merge (1+3+4)
   or wait for all phases? Running on partial merge lets us commit
   progress; waiting ensures the batch is atomic.

3. **Worktree branch naming:** Use `phase-N` branches or a more
   structured naming? Multiple parallel sessions could collide if using
   simple names.

4. **Token cost reporting:** Parallel execution uses 3-4x tokens vs
   serial (each subagent has its own context). Should the build command
   report estimated token cost before dispatching parallel work?

5. **Maximum parallelism:** Agent Teams recommends 3-5 teammates.
   Claude Code can spawn many subagents but each consumes resources.
   Should there be a configurable ceiling (default: 4 parallel phases)?

6. **Agent Teams vs subagent dispatch:** When both are available, which
   should the build command prefer? Agent Teams has richer coordination
   (mailbox, shared tasks) but is experimental. Subagent dispatch is
   stable and simpler.

---

## 7. Sources

- [Claude Code Agent Teams Docs](https://code.claude.com/docs/en/agent-teams)
- [Claude Code Agent Teams Guide (claudefa.st)](https://claudefa.st/blog/guide/agents/agent-teams)
- [Superpowers GitHub](https://github.com/obra/superpowers)
- [Superpowers dispatching-parallel-agents SKILL.md](https://github.com/obra/superpowers/blob/main/skills/dispatching-parallel-agents/SKILL.md)
- [Superpowers Issue #469 — Agent Teams Integration](https://github.com/obra/superpowers/issues/469)
- [Superpowers 5 Blog](https://blog.fsck.com/2026/03/09/superpowers-5/)
- [Gas Town GitHub](https://github.com/steveyegge/gastown)
- [Gas Town: Two Kinds of Multi-Agent (Paddo)](https://paddo.dev/blog/gastown-two-kinds-of-multi-agent/)
- [Gas Town: A Day in Gas Town (DoltHub)](https://www.dolthub.com/blog/2026-01-15-a-day-in-gas-town/)
- [Ruflo GitHub](https://github.com/ruvnet/ruflo)
- [Ruflo Workflow Orchestration Wiki](https://github.com/ruvnet/ruflo/wiki/Workflow-Orchestration)
- [Ruflo SitePoint Guide](https://www.sitepoint.com/deploying-multiagent-swarms-with-ruflo-beyond-singleprompt-coding/)
- [parallel-worktrees Skill](https://github.com/spillwavesolutions/parallel-worktrees)
- [Claude Code Worktrees Guide (claudefa.st)](https://claudefa.st/blog/guide/development/worktree-guide)
