# Crash Resilience & Session Safety

Extracted from parent CLAUDE.md for on-demand reference.
See also `reference/framework.md` for the full artifact taxonomy and handoff model.

---

## Session Lifecycle

The recommended workflow for every session:

```
/r:start         ← warm handoff: loads plan, last session summary, warnings
  ... work ...
/r:save          ← state sync: updates PLAN.md, MEMORY.md, session log
```

`/r:save` writes to `.rdf/work-output/session-log.jsonl` so the next `/r:start`
can show what happened. Git is the authoritative record; `/r:save` creates
convenience summaries.

## Checkpoint Discipline

- **Commit after every completed logical unit** — do not accumulate large uncommitted diffs.
  If a crash occurs mid-session, uncommitted changes are the primary data-loss vector.
- **Run `/r:save` before any long-running operation** — audits, full test suites,
  and multi-agent dispatches are crash-prone windows. Save state first.
- **Run `/r:save` at session end** — ensures PLAN.md, MEMORY.md, and session-log.jsonl
  reflect the latest state and are recoverable independently of chat context.

## Preserve Input Context

- When pasting multi-line specs, task lists, or finding batches into a session,
  **write them to a file first** (e.g., PLAN.md, a scratch file) before acting on them.
  Chat-only context is lost on crash; files on disk survive.
- For planning prompts with pasted content: save the pasted input to PLAN.md or a
  working file as the first action, before beginning analysis.

## Recovery Protocol

After a crash or new session start:

1. **Run `/r:start`** — displays session anchor, plan progress, last session summary,
   agent activity, and warnings. This is the primary recovery entry point.
2. **Assess git state:** `git status`, `git diff --stat`, `git log --oneline -5`
3. **Check .rdf/work-output/session-log.jsonl** for the last session's summary — what
   phases were completed, what was in progress, how many commits were made.
4. **Check .rdf/work-output/agent-feed.log** for stale AGENT_STOP entries — these show
   agents that completed but may not have been followed up on.
5. **Check for stale status files:** `.rdf/work-output/phase-*-status.md` files with
   mtime >1 hour indicate interrupted work.
6. **Check for progress files** that indicate interrupted workflows:
   - `.rdf/work-output/spec-progress.md` -- design session in progress; contains topic,
     phase, and decisions made so far. Resume with `/r:spec --resume`.
   - `.rdf/work-output/ship-progress.md` -- release workflow in progress; contains stage
     and PR URL. Resume with `/r:ship` (auto-detects).
   - `.rdf/work-output/vpe-progress.md` -- VPE pipeline state; contains current stage
     and per-repo status. Resume with `/r:vpe --resume`.
7. **If uncommitted changes exist:** review and either commit or stash before resuming.
8. **If resume fails:** `/r:start` + PLAN.md provide enough continuity to restart
   from the last completed phase.

## Cross-Session State Priority

When reconstructing state, use these sources in priority order:

| Source | Reliability | Tells you |
|--------|-------------|-----------|
| `git log` + `git diff` | Authoritative | What was committed, what's pending |
| PLAN.md | High | Phase completion status (synced by `/r:save`) |
| session-log.jsonl | High | Session summaries (commits, phases, timestamps) |
| MEMORY.md | High (if saved) | State summary, open items |
| AUDIT.md | High | Outstanding findings |
| agent-feed.log | Forensic | Agent completion events |
| .rdf/work-output/*.md | Forensic | In-flight state at session end |
