# /r:start — Session Initialization

Reload context and display the project status anchor. This is the
recommended first command in any session.

## Protocol

### 1. Clear Context

Run /clear to reset conversation context before loading fresh state.

### 2. Read Governance Index

Read `.claude/governance/index.md` from the current project directory.

If the file does not exist:
- Display a warning: "No governance found. Run /r:init to generate."
- Fall back to basic git commands for the anchor (see step 3 fallback).

### 3. Build Context Anchor

Gather the following data points:

**From governance index (if present):**
- Project name (from `## Project` section)
- Operational mode (from `Mode:` line)
- Plan progress (from `Plan:` line)
- Governance file count (count lines in `## Governance Files` section)

**From git (always):**
- Current branch: `git branch --show-current`
- HEAD hash: `git rev-parse --short HEAD`
- Dirty state: `git status --porcelain | wc -l`

**Governance age:**
- Stat the mtime of `.claude/governance/index.md`
- Calculate hours since last modification
- Flag as stale if >24 hours

Display the anchor:

```
+-- Context Anchor ------------------------------------------------+
| Project: {name}              Branch: {branch}                    |
| HEAD:    {hash}              Dirty: {N} files                    |
| Plan:    {M/N} phases        Mode: {mode}                        |
| Governance: {N} files        Age: {T}h since refresh             |
+------------------------------------------------------------------+
```

**Fallback (no governance):**

```
+-- Context Anchor ------------------------------------------------+
| Project: {basename of cwd}   Branch: {branch}                   |
| HEAD:    {hash}              Dirty: {N} files                    |
| Governance: not initialized                                      |
+------------------------------------------------------------------+
```

### 4. Staleness Warning

If governance age exceeds 24 hours:

```
WARNING: Governance is {T}h old. Run /r:refresh to update.
```

### 5. Dirty State Warning

If more than 5 uncommitted files:

```
WARNING: {N} uncommitted files. Consider committing or stashing
before starting new work.
```

### 6. Load CLAUDE.md

Read the project's `CLAUDE.md` (if present) to internalize project
instructions. Do NOT display its contents — just confirm it was loaded.

## Rules
- Do NOT load governance file contents (architecture.md, etc.) — only
  the index. Agents load what they need just-in-time.
- Do NOT read PLAN.md contents — the index has the summary.
- Do NOT read MEMORY.md — it is optional human context, not operational.
- Keep the anchor under 10 lines. No verbose output.
- This command must complete in under 5 seconds of wall time.
