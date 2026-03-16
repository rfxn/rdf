# GitHub Issue Model v2 — Phase-Level Tracking + Roadmap Planning

> Produced from brainstorming session 2026-03-16.
> Supersedes: Section 5 of rdf-2.0-architecture-design.md (issue granularity,
> workflow, and ecosystem views — labels and core fields are retained).

---

## 1. Problem Statement

RDF 2.0 shipped with per-task GitHub issue tracking: 62 task issues + 8 phase
issues + 1 master = 71 issues for a single project release. Each task issue
required creation, project field assignment, lifecycle status transitions, and
closure — approximately 365 GitHub API calls per release.

Three problems emerged:

1. **Tool usage cost** — each `gh` call is a Claude tool invocation consuming
   tokens. At scale across 13 rfxn projects, the overhead dominates session
   budgets without proportional value.
2. **Ecosystem board noise** — task-level items on the org-level Ecosystem
   Project (#4) drown out meaningful phase-level signals. A cross-project
   dashboard showing 200+ task issues is not actionable.
3. **Async visibility gap** — the operator runs multiple concurrent sessions
   across projects and needs to check progress from any terminal without
   being in-session. PLAN.md is session-local and invisible externally.

---

## 2. Design Decisions

### 2.1 Phase Is the Unit of Work on GitHub

GitHub issues track **phases**, not individual tasks. Each release gets:

- 1 master issue (tracks all phases for the release)
- 1 issue per phase (contains the plan, tracks status on boards)
- 0 task-level issues

Tasks exist in PLAN.md (session context) and as completion comments on the
phase issue (durable async record).

### 2.2 Static Body, Append-Only Comments

The phase issue body is written once at creation and contains the full plan
(task list, acceptance criteria, dependencies). It is **not edited** during
execution — no read-modify-write race conditions.

Progress is tracked via **comments posted on task completion**. This provides:

- Append-only audit trail (safe for concurrent sessions)
- Async visibility from any terminal (`gh issue view N`)
- Natural chronological record of work
- No fragile checklist-editing API calls

### 2.3 Comment Frequency: Per-Task Completion

Agents post one comment per completed task. Not per-task-start, not batched,
not per-phase-only. This balances cost (~62 comment calls per release) against
the operator's need to know exactly where a running phase stands.

**Comment format:**

```markdown
**Task N.M complete** — <one-line summary>

<optional: file list, commit ref, notable decisions>
```

Example:

```markdown
**Task 3.4 complete** — Implemented adapter registry with dependency resolution

Files: lib/cmd/generate.sh, lib/adapter_registry.sh
Commit: abc1234 (Ref #<phase-issue>)
```

### 2.4 Board Hierarchy

Two-level board structure:

| Board | Scope | Shows |
|-------|-------|-------|
| Per-project Development (e.g., #3 for RDF; varies per repo) | Single repo | Phase issues for current release |
| Org-level Ecosystem (#4) | All rfxn repos | Phase issues + initiative issues across all projects |

The ecosystem board becomes a meaningful dashboard: "APF Phase 3: In Progress,
BFD Phase 2: Done, LMD: Ready" — not hundreds of task-level items.

The ecosystem board also serves as the **roadmap planning surface** via
initiative issues (see Section 2.5).

### 2.5 Roadmap: Two Horizons

The ecosystem project provides two distinct roadmap views driven by
two different time fields:

| View | Time Field | Shows | Purpose |
|------|-----------|-------|---------|
| **Planning Roadmap** | Target Date (Date) | Initiatives + releases | Where is everything headed? |
| **Execution Roadmap** | Release (Iteration) | Phase issues in active releases | What is executing now? |

**Planning Roadmap** — the big-picture view. Shows all `type:initiative`
issues (time-boxed directionally) alongside `type:release` issues (committed).
This is where you see "Messenger Service — Q3 2026" next to "geoscope v1.0 —
Q2 2026" next to "APF 2.1.0 — April 2026". Grouped by Project field.

**Execution Roadmap** — the active-work view. Shows only items with a
Release iteration assigned (committed releases and their phase issues).
Items appear here when they move from planning to execution.

An initiative starts on the Planning Roadmap only. When it matures into a
release, it gains a Release iteration and appears on both views. Phase issues
created for the release appear on the Execution Roadmap.

### 2.6 Initiative Issues

A new issue type for roadmap planning: `type:initiative`.

Initiatives represent **planned work that has directional timing but no
release commitment yet**. They sit above releases in the hierarchy:

```
Initiative (type:initiative)     — "Messenger Service"
  └─ Release (type:release)      — "BFD 2.1.0" + "APF 2.1.0"
       └─ Phase (type:phase)     — "Phase 1: NAT redirect plumbing"
            └─ Tasks (comments)  — "Task 1.3 complete — ..."
```

**Initiative issue template:**

```markdown
## <Initiative Title>

### Vision
<2-3 sentences: what this delivers and why it matters>

### Scope
- Project(s): <which rfxn projects are involved>
- Key deliverables:
  - <deliverable 1>
  - <deliverable 2>

### Target Window
<target quarter or date range, e.g., "Q3 2026" or "July-August 2026">

### Dependencies
- Requires: <prerequisite initiatives, releases, or external factors>
- Enables: <what this unblocks>

### Status
Planning | Specced | Executing | Complete

### Related
- Spec: <link to spec doc if exists>
- Releases: <links to release issues when created>
```

**Key properties:**

- **Lightweight** — no phases, no tasks, no agent workflow. Just a
  roadmap placeholder with enough context to plan around.
- **Cross-project** — an initiative can span multiple repos (Messenger
  Service touches BFD + APF). It lives in the primary repo and references
  others.
- **Time-boxed directionally** — Target Date field set to the end of the
  target window (e.g., 2026-09-30 for "Q3 2026"). This positions it on
  the Planning Roadmap without implying a specific ship date.
- **Matures into releases** — when an initiative is specced and ready for
  execution, it spawns release issues with phase issues underneath. The
  initiative issue body is updated with links to the spawned releases.
- **Low API cost** — created once, updated rarely (status changes, release
  links). Typically 3-5 API calls over the initiative's lifetime.

---

## 3. What Changes from v1

### 3.1 Removed

| v1 Element | Disposition |
|------------|-------------|
| `type:task` issues | No longer created |
| Task issue template (v1 spec Section 5.5) | Removed |
| Per-task project field management | Eliminated (largest cost savings) |
| Per-task status transitions | Replaced by phase-level transitions |
| Deliverable cross-references (`-> #<task-issue>`) | Replaced by inline task list |

### 3.2 Retained (unchanged)

| Element | Notes |
|---------|-------|
| Label taxonomy (v1 spec Section 5.1) | All existing labels kept. `type:task` retained for historical issues and standalone work items (one-off fixes not part of a release phase); not used for release-phase tracking |
| Existing custom fields | Phase, Status, Effort, Assignee Role, Priority, Release |
| Workflow states (v1 spec Section 5.3) | Backlog → Ready → In Progress → In Review → Done |
| `rdf github` CLI commands | setup, sync-labels, ecosystem-init, ecosystem-add |

### 3.3 Added

| Element | Scope | Notes |
|---------|-------|-------|
| `type:initiative` label | All repos | New issue type for roadmap planning items |
| `type:release` label | All repos | New issue type for release tracking (was implicit via milestone) |
| Start Date field (Date) | Ecosystem project (#4) | Roadmap bar start — when work begins |
| Target Date field (Date) | Ecosystem project (#4) | Roadmap bar end — when work targets completion |
| `geoscope` option | Ecosystem Project field | New project in the ecosystem |
| Planning Roadmap view | Ecosystem project (#4) | Roadmap layout: Start Date → Target Date, grouped by Project |
| Execution Roadmap view | Ecosystem project (#4) | Roadmap layout using Release iteration, grouped by Project |
| Initiative issue template | All repos | Lightweight planning template (see Section 2.6) |
| Release issue template | All repos | Master issue for a versioned release (see Section 3.5) |

**Required fields on every ecosystem item:**

| Field | Required | Notes |
|-------|----------|-------|
| Status | Always | Todo → In Progress → Done |
| Project | Always | Which rfxn project (group-by on Cross-Project Board) |
| Priority | Always | P1/P2/P3 (sort/filter on all views) |
| Effort | Always | XS/S/M/L/XL aggregate (sort on Backlog views) |
| Start Date | For roadmap | Gantt bar start (items without dates invisible on Roadmap) |
| Target Date | For roadmap | Gantt bar end |

### 3.4 Modified

**Phase issue template** — deliverables become an inline task list (no
cross-references to task issues):

```markdown
## Phase N: <Title>

### Goal
<1-2 sentences>

### Detailed Design
<Full design from spec/plan>

### Tasks
- N.1: <task description> [Effort: S]
- N.2: <task description> [Effort: M]
- N.3: <task description> [Effort: L]

<!-- Progress tracked via comments, not checkboxes -->

### Acceptance Criteria
- <criterion 1>
- <criterion 2>

### Dependencies
- Depends on: #<phase-issue>
- Blocks: #<phase-issue>
```

Note: the task list in the body is **static reference only**. Plain bullets
(not checkboxes) prevent false progress signals from manual web UI edits.
Progress is tracked exclusively via comments.

**Effort field** — set on the phase issue as the aggregate effort for the
phase (L or XL typically), not per-task.

**Phase field** — set on the phase issue. Unchanged semantically.

### 3.5 Release Issue Template

Replaces the v1 "master issue" concept with an explicit `type:release` issue.
One per versioned release, serves as the parent for all phase issues.

```markdown
## <Project> <Version>

### Overview
<1-2 sentences: what this release delivers>

### Phases
- #<phase-1-issue>: <title> — <status>
- #<phase-2-issue>: <title> — <status>

### Initiative
Parent: #<initiative-issue> (if applicable)

### Release Checklist
- Spec: <link>
- Plan: <link>
- Changelog: updated
- Tests: passing on all OS targets
- QA: approved
- UAT: approved
```

### 3.6 Updated Ecosystem Project Views

The v1 ecosystem project had 4 views. v2 replaces the single Roadmap view
with two specialized views and adds initiative-aware filtering:

| View | Layout | Field/Filter | Purpose |
|------|--------|-------------|---------|
| **Kanban** | Board | Status | **DEFAULT** — cross-project working view |
| Cross-Project Board | Board | Project | Work grouped by project |
| **Planning Roadmap** | Roadmap | Target Date, grouped by Project | Big-picture: initiatives + releases on a timeline |
| **Execution Roadmap** | Roadmap | Release (Iteration), grouped by Project | Active work: phase issues in committed releases |
| Release Gate | Table | filtered by `release-gate` label | Blockers per project |

The per-project Development board (#3) views are unchanged — it only shows
phase issues for the current release. Initiatives and releases live on the
ecosystem board.

---

## 4. Agent Workflow

### 4.1 Phase Lifecycle (EM / mgr)

```
Plan approved (EM confirms scope output, post-Challenger if tier 2+)
  → Create phase issue (body = plan + tasks + acceptance criteria)
  → Add to per-project board and ecosystem project
  → Set fields: Phase, Status=Ready, Effort, Assignee Role
  → Dispatch agent

Agent picks up
  → Set Status=In Progress

Agent completes each task
  → Post comment on phase issue

All tasks complete
  → Set Status=In Review (if QA gate)
  → QA/Sentinel review
  → Set Status=Done
  → Close issue (gh issue close N)
```

### 4.2 Commit References

Agents reference the **phase issue** in commits:

```
Ref #<phase-issue>
```

Not task issues (they don't exist). Multiple commits per phase issue is
expected and normal.

### 4.3 Blocker Handling

If a task within a phase is blocked:

1. Agent posts a comment on the phase issue describing the blocker
2. If the entire phase is blocked, set Status=Backlog and add `blocked` label
3. When unblocked, set Status=In Progress and remove `blocked` label

No separate blocker issues unless the blocker is a cross-phase dependency
that needs its own tracking.

---

## 5. Initiative Lifecycle

### 5.1 States

Initiatives use a 4-state lifecycle tracked in the issue body's Status
section (not the board Status field, which tracks execution state).
The board Status field is the source of truth for board views; the body
Status section is a human-readable reference. Both must be updated
together — the mapping table below defines the correspondence:

```
Planning → Specced → Executing → Complete
```

| State | Meaning | Board Status | Target Date |
|-------|---------|-------------|-------------|
| Planning | Idea captured, scope rough | Backlog | Set to target quarter end |
| Specced | Spec written, plan exists | Ready | Refined if needed |
| Executing | Release issues created, work underway | In Progress | Unchanged |
| Complete | All spawned releases shipped | Done | Unchanged |

### 5.2 Maturation: Initiative → Release → Phases

```
1. Initiative created (type:initiative)
   - Target Date set (e.g., 2026-09-30 for Q3)
   - Added to ecosystem project
   - Appears on Planning Roadmap

2. Spec + plan written (offline — no API cost)
   - Initiative body updated: Status → Specced, spec link added
   - 1 API call

3. Release(s) created (type:release)
   - One per project involved (e.g., BFD 2.1.0 + APF 2.1.0)
   - Target Date set on each, Release iteration assigned
   - Added to ecosystem project + per-project boards
   - Initiative body updated with release links
   - ~4-8 API calls per release issue

4. Phase issues created under each release
   - Normal v2 phase workflow (Section 4.1)
   - Phase issues reference release issue in Dependencies

5. Execution proceeds per Section 4
   - Initiative status updated to Executing
   - 1 API call

6. All releases complete
   - Initiative status updated to Complete, issue closed
   - 2 API calls
```

**Total initiative overhead:** ~10-15 API calls over the initiative's
entire lifecycle (weeks to months). Negligible compared to phase execution.

### 5.3 Cross-Project Initiatives

When an initiative spans multiple projects (e.g., Messenger Service spans
BFD + APF):

- The initiative issue lives in the **primary project's repo** (the one
  doing the most work — BFD for Messenger Service)
- It references the secondary project's release issues in its body
- Both release issues appear on the ecosystem Planning Roadmap under
  their respective Project field values
- The initiative appears once, grouped with the primary project

### 5.4 Seeding the Roadmap

Known planned work can be captured as initiatives immediately:

| Initiative | Project(s) | Target Window | Status |
|-----------|-----------|---------------|--------|
| Messenger Service | BFD + APF | Q3 2026 | Planning |
| geoscope v1.0 | geoscope | Q2 2026 | Specced |
| CSF Migration | APF | TBD | Planning |

These are created as `type:initiative` issues during the migration phase
(Section 7) and placed on the Planning Roadmap.

---

## 6. Cost Comparison

### Assumptions

- 8 phases, 62 tasks, 9 phase/master issues
- **v1 issues managed:** 71 (62 task + 8 phase + 1 master)
- **v2 issues managed:** 9 (8 phase + 1 master)
- **Fields per phase issue:** 4 (Phase, Status initial=Ready, Effort, Assignee Role).
  Initiative and release issues have additional fields (Target Date, Release iteration)
  but are low-volume (3-5 per cycle) so their overhead is negligible
- **v1 status transitions per task:** 2 (Ready→In Progress, In Progress→Done;
  most tasks skip In Review — only phase issues go through QA gate)
- **v2 status transitions per phase:** 3 (Ready→In Progress, In Progress→In Review, In Review→Done)
- **Labels/milestones:** v1 bootstraps 20 labels + milestone + issue creation overhead;
  v2 reuses existing labels, fewer milestone ops
- **Issue comments (v2):** ~62 task-completion comments (floor estimate; QA/Sentinel
  review comments add a variable number, typically 5-15 per release)

### Per-release API call estimate (8 phases, ~62 tasks)

| Operation | v1 (per-task) | v2 (per-phase) | Notes |
|-----------|---------------|----------------|-------|
| Create issues | 71 | 9 | 62 task issues eliminated |
| Set project fields | 284 | 36 | 71×4 fields vs 9×4 fields |
| Status transitions | 142 | 27 | 71×2 vs 9×3 |
| Close issues | 71 | 9 | |
| Issue comments | 0 | ~70 | ~62 task + ~8 QA/review |
| Labels/milestones | ~30 | ~15 | One-time bootstrap lighter in v2 |
| **Total** | **~598** | **~166** | |
| **Savings** | — | **~72%** | **~432 calls eliminated** |

At scale across APF + BFD + LMD releases in the same cycle, savings
compound: ~1,296 calls avoided per triple-project release.

---

## 7. Migration Plan

### 7.1 Existing RDF Issues (v2.0.0)

72 of 73 issues are Done. One (#22) is open (P3 backlog debt).

**Actions:**

1. Identify task-level items on each project board:
   ```bash
   # List all items on the RDF Dev board, filter by type:task label
   gh project item-list 3 --owner rfxn --format json | \
     jq '.items[] | select(.labels[]?.name == "type:task") | {id, title, number}'
   ```
2. Remove each task-level item from RDF Development project (#3) via
   `gh project item-delete` using the item IDs from step 1
3. Repeat for Ecosystem project (#4) if task-level items are present
4. Keep 8 phase issues + 1 master issue on both boards — verify they
   remain after task item removal
5. Migrate #22 content into the relevant phase issue as a comment or
   fold into the next release's planning
6. Do not delete or close any issues — they are historical record

### 7.2 Forward Application

All future rfxn project work follows v2:

- New releases create phase issues only
- `rdf github setup` updated to document the phase-level convention
- `feedback_github_rituals.md` memory updated to reflect v2 workflow
- Agent prompts (mgr.md, sys-eng.md, sys-qa.md, sys-sentinel.md, and any
  other agents with GitHub issue management instructions) updated to post
  comments instead of managing task issues

### 7.3 Ecosystem Board Updates

1. Remove task-level items from ecosystem board (same query as 7.1)
2. Add **Target Date** field (Date type) to ecosystem project
3. Create **Planning Roadmap** view (Roadmap layout, Target Date, grouped by Project)
4. Reconfigure existing "Project Roadmap" view → rename to **Execution Roadmap**,
   change layout field from Project to Release (Iteration), set group-by to Project
5. Verify Kanban, Cross-Project Board, and Release Gate views still function

### 7.4 New Labels

Add to all rfxn repos via `rdf github sync-labels`:

| Label | Color | Use |
|-------|-------|-----|
| `type:initiative` | #7057FF | Roadmap planning item — directional, time-boxed |
| `type:release` | #1D76DB | Versioned release tracking — parent for phase issues |

### 7.5 Seed Initiatives

Create `type:initiative` issues for known planned work:

| Initiative | Repo | Target Date | Status |
|-----------|------|-------------|--------|
| Messenger Service | rfxn/brute-force-detection | 2026-09-30 | Planning |
| geoscope v1.0 | rfxn/geoscope | 2026-06-30 | Specced |
| CSF Migration | rfxn/advanced-policy-firewall | (empty) | Planning |

Add each to ecosystem project with Target Date and Project fields set.
These appear immediately on the Planning Roadmap.

**Note:** Initiatives with no target date (empty Target Date field) will
not appear on the Planning Roadmap — the Roadmap layout requires a date
to position items on the timeline. These initiatives are still visible on
the Kanban and Cross-Project Board views. When a target window is known,
set Target Date to make the initiative appear on the roadmap.

### 7.6 Convert Existing Master Issues to type:release

The v1 "master issue" for RDF 2.0.0 (identified by title pattern
"RDF 2.0.0" or by `type:phase` label on the top-level release tracker)
should be relabeled from `type:phase` to `type:release` and given a
Target Date. This brings completed releases onto the Planning Roadmap
as historical anchors. Apply the same treatment to master issues in
other repos (APF, BFD, LMD) if they exist.

---

## 8. Documentation Update Scope

The v2 issue model changes how agents interact with GitHub, which
surfaces are tracked, and how the roadmap is structured. The following
documentation must be updated to reflect the new model.

### 8.1 High Priority — Core Model + Agent Workflow

| File | What Changes |
|------|-------------|
| `canonical/commands/mgr.md` | Phase-level issue management, board reading, initiative awareness |
| `canonical/commands/sys-eng.md` | Post task-completion comments instead of managing task issues |
| `canonical/agents/mgr.md` | Board reading, delegation, initiative/release lifecycle |
| `canonical/agents/sys-eng.md` | Phase protocol, commit references to phase issues |
| `canonical/commands/sys-qa.md` | Post review comments on phase issues |
| `canonical/agents/sys-sentinel.md` | Post findings as phase issue comments |
| `docs/specs/2026-03-16-rdf-2.0-architecture-design.md` | Section 5 — add superseded-by reference to this spec |
| `docs/plans/github-project-ids.md` | Add Target Date field ID, new label definitions, remove task-level item ID map |

### 8.2 Medium Priority — Release + Audit Workflow

| File | What Changes |
|------|-------------|
| `canonical/commands/rel-prep.md` | Release issue creation uses `type:release`, links to initiative |
| `canonical/commands/rel-ship.md` | Issue closure at release level, initiative status update |
| `canonical/commands/rel-merge.md` | Phase transition tracking via phase issues |
| Audit commands (`audit-context.md`, etc.) | Findings reference phase issues, not task issues |

### 8.3 Diagrams + Published Documentation

| File | What Changes |
|------|-------------|
| `reference/diagrams.md` | Update Mermaid diagrams: issue workflow, pipeline flow, board views |
| `README.md` | Update GitHub integration section, add roadmap/initiative overview |
| `RDF.md` | Architecture section — updated issue hierarchy, two-roadmap model |
| `WORKFORCE.md` | Agent responsibilities updated if delegation flow changes |

### 8.4 Auto-Generated (No Manual Edit)

All adapter output files regenerate from canonical via `rdf generate`:
- `adapters/claude-code/output/commands/` (69 files)
- `adapters/claude-code/output/agents/` (13 files)
- `adapters/gemini-cli/output/`, `adapters/codex/output/`, `adapters/agents-md/output/`

### 8.5 Memory + Governance

| File | What Changes |
|------|-------------|
| `feedback_github_rituals.md` (memory) | Rewrite for v2 phase-level workflow |
| Profile governance files (4) | Update if GitHub integration instructions change |

---

## 9. Open Questions

None for implementation. Future considerations:

- **Automated phase progress** — could parse comment count vs task count to
  show "4/7 tasks complete" on the board. Deferred until the manual model
  proves insufficient.
- **Cross-phase dependency tracking** — currently handled via `Depends on:`
  in issue body. If this proves insufficient, consider GitHub issue linking.
- **Initiative decomposition tooling** — a future `rdf github initiative`
  subcommand could automate spawning release + phase issues from an
  initiative. Deferred until the manual workflow proves burdensome.

---

## 10. Summary

### Issue Hierarchy

```
Initiative (type:initiative)     — planning horizon, directional timing
  └─ Release (type:release)      — committed version, specific timeline
       └─ Phase (type:phase)     — execution unit, tracked on boards
            └─ Tasks (comments)  — progress trail, async visibility
```

### Comparison

| Dimension | v1 | v2 |
|-----------|----|----|
| Issue granularity | Per-task (62 + 8 + 1) | Per-phase (8 + 1) + initiatives |
| API calls/release | ~598 | ~166 |
| Async visibility | Full (issue per task) | Full (comments per task) |
| Board signal | Noisy (62 items) | Clean (phases + initiatives) |
| Ecosystem view | Task-level noise | Phase-level signal + roadmap |
| Roadmap | Single view (Release iteration) | Two views: Planning (Target Date) + Execution (Release) |
| Planning horizon | None — only active work visible | Initiatives show future planned work |
| Cross-project | Flat item list | Initiatives span projects, grouped on roadmap |
| Migration | — | Remove task items, add labels/fields/views, seed initiatives |
