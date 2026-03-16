# Crash Resilience & Session Safety

Extracted from parent CLAUDE.md for on-demand reference.
See also `reference/framework.md` for the full artifact taxonomy and handoff model.

---

## Checkpoint Discipline

- **Commit after every completed logical unit** — do not accumulate large uncommitted diffs.
  If a crash occurs mid-session, uncommitted changes are the primary data-loss vector.
- **Run `/mem-save` before any long-running operation** — audits, full test suites,
  and multi-agent dispatches are crash-prone windows. Save state first.
- **Run `/mem-save` after every commit** — ensures MEMORY.md, PLAN.md, and AUDIT.md
  reflect the latest committed state and are recoverable independently of chat context.

## Preserve Input Context

- When pasting multi-line specs, task lists, or finding batches into a session,
  **write them to a file first** (e.g., PLAN.md, a scratch file) before acting on them.
  Chat-only context is lost on crash; files on disk survive.
- For planning prompts with pasted content: save the pasted input to PLAN.md or a
  working file as the first action, before beginning analysis.

## Recovery Protocol

After a crash or new session start:

1. **Assess git state:** `git status`, `git diff --stat`, `git log --oneline -5`
2. **Check session manifest:** read `work-output/session.md` for previous session's
   dispatch history and which phases were completed vs in-progress
3. **Check in-flight registry:** read `work-output/in-flight.md` for stale RUNNING
   entries — these indicate agents that were active when the session crashed
4. **For each stale in-flight entry:**
   - Check spool (`work-output/spool/`) for a completion event matching the agent ID
   - If spool event exists: agent finished but EM crashed before reading the result
     → read the result file, resume pipeline from QA dispatch
   - If no spool event: agent crashed mid-execution
     → check `git diff` for uncommitted changes, warn user, recommend recovery
5. **Check for stale worktrees:** `git branch | grep -E '\-p[0-9]+-'` — stale
   worktree branches indicate crashed parallel sessions
6. **If uncommitted changes exist:** review and either commit or stash before resuming
7. **If resume fails:** start fresh with `/reload` — MEMORY.md and PLAN.md provide continuity

## Cross-Session State Priority

When reconstructing state, use these sources in priority order:

| Source | Reliability | Tells you |
|--------|-------------|-----------|
| `git log` + `git diff` | Authoritative | What was committed, what's pending |
| PLAN.md | High | Phase completion status |
| MEMORY.md | High (if saved) | State summary, lessons, open items |
| work-output/session.md | Forensic | Previous session's dispatch history |
| work-output/in-flight.md | Forensic | What was running when session ended |
| Spool JSONL | Archival | Agent completion times and outcomes |
