First run /clear to reset conversation context.

Then read and internalize the following files from the current project directory, in order:

1. `CLAUDE.md` — project instructions and constraints
2. `PLAN.md` — current roadmap and phase status
3. `MEMORY.md` — session memory from `/root/.claude/projects/` for this project
4. `AUDIT.md` — audit findings and status (if present)
5. `README.md` or `README` — project overview

For each file found, read it fully. If a file does not exist, skip it silently.

After loading, provide a brief status summary:
- Project name and version
- Current branch
- Current phase from PLAN.md (if available)
- Any open audit findings count (if AUDIT.md exists)
