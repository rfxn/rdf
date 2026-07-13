# Task-Based Coordination Specification

> Maps the current file-based coordination model to Agent Teams task-based
> coordination. Ensures zero regression when switching between modes.

## 1. Current Model: File-Based Coordination

### Communication Channel
- **EM -> Agent:** Work order file (`work-output/current-phase.md`) + prompt
- **Agent -> EM:** Result files (`work-output/phase-result.md`, etc.)
- **Agent -> Agent:** None (isolated subagents cannot communicate)

### Coordination Mechanism
- **Sequencing:** EM dispatches agents one at a time (or parallel via
  multiple Agent tool calls)
- **Dependencies:** EM manages manually — waits for result file before
  dispatching next agent
- **Status tracking:** EM reads status files between dispatches

### File Contract

| Stage | Input Files | Output Files |
|-------|-------------|-------------|
| Scope | PLAN.md | scope-workorder-P{N}.md or scope-validation-{N}.md |
| SE (plan) | current-phase.md | implementation-plan.md, phase-{N}-status.md |
| Challenger | implementation-plan.md | challenge-{N}.md |
| SE (impl) | current-phase.md | phase-result.md, phase-{N}-status.md |
| QA | phase-result.md | qa-phase-{N}-status.md, qa-phase-{N}-verdict.md |
| Sentinel | phase-result.md | sentinel-{N}.md |
| UX Review | phase-result.md | ux-review-{N}.md |
| UAT | phase-result.md | uat-phase-{N}-status.md, uat-phase-{N}-verdict.md |

## 2. New Model: Task-Based Coordination

### Communication Channel
- **EM -> Agent:** TaskCreate (subject + description) + spawn prompt
- **Agent -> EM:** TaskUpdate (completed) + SendMessage (summary)
- **Agent -> Agent:** SendMessage (direct, e.g., QA reads Sentinel findings)

### Coordination Mechanism
- **Sequencing:** TaskCreate with `addBlockedBy` creates dependency chains
- **Dependencies:** Automatic — tasks unblock when predecessors complete
- **Status tracking:** TaskList shows real-time status of all work

### Task Dependency Graph (Tier 2+ Pipeline)

```
[scope-workorder]
       |
  [se-plan] ───────────────────────────
       |                               |
  [challenger]                         |
       |                               |
  [se-implement]                       |
       |                               |
  +----+----+----+                     |
  |         |    |                     |
[qa-gate] [sentinel] [ux-review]       |
  |                                    |
  [uat]                                |
```

### Mapping Table

| File-Based | Task-Based | Notes |
|------------|-----------|-------|
| Write work order file | TaskCreate + prompt | Task description replaces work order |
| Read result file | TaskList + SendMessage | Teammate sends summary on completion |
| Parallel Agent calls | Tasks with same depends_on | Self-claiming handles parallelism |
| EM waits for result | Task auto-unblocks downstream | No polling needed |
| EM reads + decides | Lead reviews task summaries | Delegate mode enforces coordination-only |

## 3. Dual-Mode Invariants

These properties MUST hold in both modes:

1. **Output files are always written.** Even in Agent Teams mode, agents
   write to work-output/ files. This ensures:
   - Post-pipeline analysis works identically
   - Pipeline metrics collection is mode-independent
   - Debugging uses the same file artifacts
   - Fallback to subagent mode loses no data

2. **Prompt content is identical.** The dispatch abstraction generates the
   same prompt text regardless of mode. Only the dispatch mechanism changes.

3. **Pipeline ordering is preserved.** Dependencies enforce the same
   execution order. In subagent mode, EM manages order manually. In Agent
   Teams mode, task blocking enforces order automatically.

4. **Result semantics are identical.** QA verdict files have the same
   format. Sentinel findings have the same structure. EM's merge decision
   logic is mode-independent.

5. **Feature flag is the only switch.** No other configuration changes are
   needed to switch modes. `RDF_AGENT_TEAMS=true|false` is sufficient.

## 4. Agent Teams Benefits (When to Switch)

### Benefits
- **Parallel verification:** QA + Sentinel + UX Review run as independent
  teammates that self-claim work. No EM dispatch overhead.
- **Direct communication:** QA can message Sentinel directly to ask about
  a finding, without going through EM.
- **Reduced EM context:** EM's context window holds only coordination state,
  not the full result of each agent's work.
- **Natural look-ahead:** Teammates auto-claim next unblocked task, enabling
  pipeline overlap without explicit worktree management.

### Costs
- **Token cost:** ~3-4x single session per teammate. A full tier 2+ pipeline
  with 7 teammates costs significantly more than subagent mode.
- **Coordination overhead:** Task status can lag. Teammates may forget to
  mark tasks complete.
- **Experimental API:** Subject to breaking changes. No session resumption
  for in-process teammates.

### Recommendation
- Use subagent mode (default) for all production work
- Use Agent Teams mode for:
  - Large refactors with many parallel tracks
  - Debugging sessions with competing hypotheses
  - When the API stabilizes and token costs are acceptable
- Always test mode switches against a known-good pipeline run

## 5. Future: Hybrid Mode

A future enhancement could use Agent Teams for the parallel verification
group (QA + Sentinel + UX Review) while keeping subagent mode for the
sequential stages (Scope, SE, Challenger). This would capture the primary
benefit (parallel verification) without the full token cost.

Implementation: `rdf_dispatch_pipeline()` would emit subagent instructions
for sequential stages and Agent Teams instructions for parallel groups.
This requires the dispatch library to support mixed-mode output (deferred
to a future phase after the API stabilizes).
