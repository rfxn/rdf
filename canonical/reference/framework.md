# rfxn Development Framework (RDF) v3.0

Artifact taxonomy, handoff model, and session continuity protocol for all
rfxn projects. Authoritative reference for what each artifact is, where it
lives, who writes it, and how it survives sessions.

---

## Artifact Taxonomy

Six categories. Each artifact has a fixed location, format, lifecycle, and
ownership.

### Category 1: Governance (stable)

Constraints, conventions, and reference documentation. Changed only when
the framework evolves. Never contains volatile data.

| Artifact | Location | Owner |
|----------|----------|-------|
| Parent CLAUDE.md | `/root/admin/work/proj/CLAUDE.md` | Human |
| Project CLAUDE.md | `<project>/CLAUDE.md` | Human |
| Governance index | `<project>/.rdf/governance/index.md` | `/r-init` |
| Governance files | `<project>/.rdf/governance/*.md` | `/r-init`, `/r-refresh` |
| `ignore.md` | `<project>/.rdf/governance/ignore.md` | `/r-init`, `/r-refresh` (agents consume: grep-exclude input) |
| Shared reference | `/root/admin/work/proj/reference/*.md` | Human |
| Project reference | `<project>/reference/*.md` | Human |

**Rules:**
- Parent CLAUDE.md is authoritative; project CLAUDE.md inherits, never repeats
- Governance index is always loaded (~50 lines, ~100-150 tokens)
- Other governance files loaded just-in-time by agents via index pointers
- All governance artifacts excluded from git via `.git/info/exclude`

### Category 2: State (volatile)

Current project status, roadmaps, and audit findings. Updated after every
commit, phase completion, or audit run.

| Artifact | Location | Owner | Mandatory |
|----------|----------|-------|-----------|
| MEMORY.md | Auto-memory dir | `/r-save` | All projects |
| PLAN.md | `<project>/PLAN.md` | `/r-plan`, `/r-save` | When active work |
| AUDIT.md | `<project>/AUDIT.md` | `/r-audit`, `/r-save` | After audit run |
| spec-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-spec` | During design |
| ship-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-ship` | During release |
| vpe-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-vpe` | During VPE pipeline |
| build-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-build` | During parallel build |
| session-log.jsonl | `.rdf/work-output/` | `/r-save` | When active work |
| insights.jsonl | `~/.rdf/` | `/r-save` | Rolling 30 entries |
| lessons-learned.md | `~/.rdf/` | `/r-save` (user-promoted) | Cross-session wisdom |
| config.json | `~/.rdf/` | `/r-save` (auto setting) | RDF preferences |

**`~/.rdf/`:** Tool-agnostic RDF operational state. Never tracked in git.
Referenced by parent CLAUDE.md / GEMINI.md / AGENTS.md for agent discovery.

**MEMORY.md:** 200-line hard limit. Overflow to topic files.

**PLAN.md status markers:**
- `pending` — not started
- `in-progress` — engineer dispatched
- `complete` — committed
- `deferred` — postponed
- `blocked` — waiting on dependency

### Category 3: Execution (transient)

Agent work products created during a session. Structured files in
`.rdf/work-output/` passed between agents as handoff contracts.

| Artifact | Writer | Reader |
|----------|--------|--------|
| `phase-N-status-<SESSION_ID>.md` | engineer | dispatcher |
| `phase-N-result-<SESSION_ID>.md` | engineer | dispatcher |
| `qa-phase-N-verdict-<SESSION_ID>.md` | qa | dispatcher |
| `sentinel-N-<SESSION_ID>.md` | reviewer | dispatcher |
| `sentinel-plan-final-<SESSION_ID>.md` | reviewer (via dispatcher) | dispatcher |
| `uat-phase-N-verdict-<SESSION_ID>.md` | uat | dispatcher |

**Session Identity (`RDF_SESSION_ID`):** Set by the `rdf_session_init`
helper in `state/rdf-bus.sh`. UUIDv7 string. Subagents inherit from
parent (env passthrough). Used as filename suffix for transient state
files to prevent collisions between concurrent sessions on the same
repository. Helper functions:
- `rdf_session_init` — generate UUIDv7 if `RDF_SESSION_ID` is unset; export
- `rdf_scoped_filename <basepath>` — derive `<basepath>-$RDF_SESSION_ID.<ext>`
- `rdf_session_short` — last 12 chars for log display
- `rdf_parse_phase_scope <plan> <N>` — extract phase Files + Tests-may-touch
  for the pre-commit hook (see Phase 4 below and `plan-schema.md` Rule 8)

Concurrent-session coordination design: `docs/specs/2026-04-25-concurrent-sessions-design.md`.

**Engineer result schema:**
```
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
PHASE: <N>
COMMIT_HASH: <sha>
FILES_CHANGED: <list>
TDD_EVIDENCE:
  TESTS: <test names, red/green output>
  COVERAGE_DELTA: <if measurable>
EVIDENCE:
  - <claim>: <path>:<line> | <cmd> → <output> | <sha> <message>
  - <claim>: <path>:<line> | <cmd> → <output> | <sha> <message>
GOVERNANCE_APPLIED: <constraints and how>
CONCERNS: <if DONE_WITH_CONCERNS>
```

**EVIDENCE block grammar:**
- Each line is one claim with ≥1 citation
- Citation forms: `<path>:<line>` | `<cmd> → <output>` | `<sha> <message>`
- Arrow accepted as U+2192 (`→`) or ASCII (`->`)
- Multiple citations per claim joined with ` | ` (space-pipe-space)
- Required for STATUS: DONE or DONE_WITH_CONCERNS (≥1 non-empty line)
- Optional for STATUS: BLOCKED or NEEDS_CONTEXT

**Structural check** (dispatcher Gate 1, implemented in Phase 2):
- Block exists (`^EVIDENCE:` followed by indented `-` lines)
- Non-empty when STATUS requires it
- Empty EVIDENCE on DONE → verdict NEEDS_CONTEXT with feedback "EVIDENCE block missing required citation"

**QA verdict schema:**
```
RESULT: PASS | FAIL
SCOPE: <files reviewed>
CHECKS:
  LINT: PASS | FAIL
  TESTS: PASS | FAIL
  ANTI_PATTERNS: PASS | FAIL
  CONVENTIONS: PASS | FAIL
FAILURES: <actionable fix suggestions>
```

### Category 4: Orchestration (agent definitions)

Agent personas, commands, hooks, and scripts that define the pipeline.

| Artifact | Location | Format |
|----------|----------|--------|
| Agent definitions | `canonical/agents/*.md` | Pure markdown |
| Commands | `canonical/commands/*.md` | Pure markdown |
| Hook scripts | `canonical/scripts/*.sh` | Bash |
| Agent metadata | `adapters/claude-code/agent-meta.json` | JSON |
| Hook config | `~/.claude/settings.json` | JSON |

**Agent naming:** `rdf-{role}` (e.g., `rdf-engineer`, `rdf-qa`)

**Command naming:**
- `/r-{name}` — lifecycle commands (17)
- `/r-util-{subject}-{verb}` — utility commands (14)

### Category 5: Integration (monitoring)

Contracts between the framework and the monitoring system.

| Collector | Reads | Refresh |
|-----------|-------|---------|
| collect-projects.sh | Git state, version files | 15s |
| collect-activity.sh | `git log` across projects | 30s |
| collect-plans.sh | PLAN*.md phase status | 30s |
| collect-audits.sh | AUDIT.md severity counts | 60s |
| collect-agents.sh | .rdf/work-output/*.md status | 3s |
| collect-spool.sh | .rdf/work-output/spool/*.jsonl | 5s |

### Category 6: Archive (historical)

| Artifact | Location |
|----------|----------|
| Archived plans | `docs/plans/archived/` |
| v2 agents | removed in 3.0.1 (see git history) |
| v2 commands | removed in 3.0.1 (see git history) |
| CHANGELOG | `<project>/CHANGELOG` |

---

## Handoff Model

### Agent Pipeline

The dispatcher orchestrates a sequential pipeline. Each transition is a
structured file in `.rdf/work-output/`.

```
dispatcher ──[phase context]──→ engineer ──[result]──→ dispatcher
                                                          │
                               ┌──────────────────────────┤
                               ▼                          ▼
                      qa ──[verdict]──→          reviewer ──[findings]──→
                      dispatcher                 dispatcher
                               │
                               ▼
                      uat ──[verdict]──→ dispatcher
```

**Verification depth** is managed by the dispatcher. It classifies each
phase by change scope, derived automatically from the file list,
description, and governance context:

  docs          — changelog, README, comments
  focused       — single file, config, one function
  multi-file    — 2+ files, standard feature/refactor work
  cross-cutting — install, CLI, cross-OS, breaking changes
  sensitive     — security, shared libs, data migration

Higher scope = more verification. The dispatcher manages this
automatically. See dispatcher.md for the full derivation logic.

**Parallel variant:**
- Dispatcher validates file ownership boundaries (no overlap)
- Each engineer runs in an isolated git worktree
- Integration check after all engineers complete
- QA runs across full diff after merge

**Inter-phase parallelism:**
- `/r-build --parallel` reads the plan dependency graph
- Independent phases dispatch concurrently (max 4)
- Isolation auto-derived from scope: file-gated or git worktree
- Results merge in plan order (deterministic)
- See r-build.md for the full dispatch protocol.

### Cross-Session Continuity

The `/r-save` → `/r-start` loop provides structured session handoff:

```
Session N:  work → /r-save (syncs PLAN.md, MEMORY.md, writes session-log)
Session N+1: /r-start (reads session-log, shows plan progress, last session summary)
```

State sources, in order of reliability:

| Source | Reliability | What it provides |
|--------|-------------|-----------------|
| `git log` + `git diff` | Authoritative | Committed and uncommitted state |
| PLAN.md | High | Phase completion status (synced by `/r-save`) |
| session-log.jsonl | High | Session summaries (commits, phases completed) |
| MEMORY.md | High (if saved) | State summary, open items |
| AUDIT.md | High | Outstanding findings |
| .rdf/work-output/ | Forensic | In-flight state at session end |

Git is the true record. `/r-save` creates convenience summaries.
`/r-start` reads them for a warm handoff.

---

## Project Presence Requirements

| Artifact | Shell project | Shared library |
|----------|---------------|----------------|
| CLAUDE.md | Required | Required |
| MEMORY.md | Required | Required |
| PLAN.md | When active | When active |
| AUDIT.md | After audit | After audit |
| CHANGELOG | Required | Required |
| tests/ | Required | Required |

---

## Exclusion Protocol

Working artifacts excluded from git via `.git/info/exclude`:

```
CLAUDE.md
PLAN*.md
AUDIT.md
MEMORY.md
.rdf/
```

Never use `.gitignore` for these — exclusion rules stay local.
