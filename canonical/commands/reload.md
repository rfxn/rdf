First run /clear to reset conversation context.

## Context Anchor

Before reading any files, establish the context anchor. Run `rdf state` (or
`state/rdf-state.sh` directly) against the current working directory:

```bash
rdf state . 2>/dev/null || state/rdf-state.sh . 2>/dev/null
```

If the command returns valid JSON, display the context anchor block:

```
+-- Context Anchor ----------------------------------------------------+
| Project: <project>          Version: <version>                       |
| Branch:  <branch>           HEAD: <hash>                             |
| Dirty:   <yes/no>           Uncommitted: <N> files                   |
| Plan:    <completed>/<total> phases                                  |
| Memory:  <exists/missing>   Age: <N>h                                |
| Audit:   <exists/missing>                                            |
+----------------------------------------------------------------------+
```

**If rdf state is not available** (pre-Phase 2), fall back to basic git commands:

```bash
basename "$(pwd)"
git branch --show-current 2>/dev/null
git rev-parse --short HEAD 2>/dev/null
git status --porcelain 2>/dev/null | wc -l
```

Display a minimal anchor:

```
+-- Context Anchor ----------------------------------------------------+
| Project: <basename>         Branch: <branch>                         |
| HEAD:    <hash>             Uncommitted: <N> files                   |
+----------------------------------------------------------------------+
```

The context anchor ensures the agent knows exactly which project and branch
it is operating in before loading any state files. This prevents cross-project
context drift — the most common session-start friction point.

---

## Load State Files

Then read and internalize the following files from the current project directory,
in order:

1. `CLAUDE.md` — project instructions and constraints
2. `PLAN.md` — current roadmap and phase status
3. `MEMORY.md` — session memory from `/root/.claude/projects/` for this project
4. `AUDIT.md` — audit findings and status (if present)
5. `README.md` or `README` — project overview

For each file found, read it fully. If a file does not exist, skip it silently.

---

## Status Summary

After loading, provide a brief status summary:
- Project name and version (from context anchor)
- Current branch (from context anchor)
- Current phase from PLAN.md (if available)
- Any open audit findings count (if AUDIT.md exists)
- Dirty state warning (if uncommitted changes detected)

If the context anchor showed dirty state or high uncommitted file count (>5),
add a warning:

```
WARNING: <N> uncommitted files detected. Consider committing or stashing
before starting new work.
```
