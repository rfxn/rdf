Save current session state to all local tracking files. Read the project's
CLAUDE.md to determine project type, then update each file with current reality.

## 1. Update MEMORY.md

Read the project's MEMORY.md from the claude projects directory. Update:

- **Current State**: branch name (`git branch --show-current`), latest version
  string (grep from source), test count (`grep -rc '@test' tests/*.bats | awk`),
  CI status if `gh` available
- **Completed Work**: prepend any new commits since the last recorded hash
  (`git log <last_hash>..HEAD --oneline`); if no last hash, use last 10 commits
- **Open Items**: read PLAN.md, extract items not marked RESOLVED/COMPLETED/DONE
- **Audit Status**: if AUDIT.md exists, extract severity breakdown and open count

Do NOT remove existing Lessons Learned, Anti-Patterns, or Test Infrastructure
sections — only append if new information was discovered this session.

## 2. Update PLAN.md

Read PLAN.md. For each phase/item:
- Cross-reference against `git log --oneline` — if a commit message references
  the phase and the code change is present, mark it COMPLETED with commit hash
- If work was started but not finished, mark IN PROGRESS with notes on what remains
- Do NOT mark anything COMPLETED without verifying the commit exists
- Do NOT reorder phases or change priority tags
- Update the status summary line at the top (e.g., "Phases 1-10 complete")

## 3. Update AUDIT.md (if exists)

If AUDIT.md exists in the project root:
- Read the REMEDIATION ROADMAP or RECOMMENDED PRIORITY ORDER section
- Cross-reference each finding against `git log` and current source
- If a finding's recommendation was implemented (commit exists + code verified),
  add `RESOLVED <hash>` annotation to that finding
- Update the executive summary counts if any findings were resolved
- Do NOT delete findings — only annotate resolution status

## 4. Update local CLAUDE.md (if applicable)

Read the project's CLAUDE.md. Update ONLY these sections if they exist and
have stale data:
- **Test Scale / Test File Inventory**: recount tests (`grep -rc '@test' tests/*.bats`)
- **Bug Fix Status / Known Issues**: cross-reference PLAN.md for resolved items
- **Git State**: update branch name and commit count if mentioned

Do NOT rewrite architecture, conventions, or workflow sections.
Do NOT touch the parent /root/admin/work/proj/CLAUDE.md.

## 5. Summary

Print a concise diff summary:
```
## Save Progress: <Project> v<version>

MEMORY.md: <N> new commits recorded, <state changes>
PLAN.md: <N> items updated (<completed> completed, <in_progress> in progress)
AUDIT.md: <N> findings resolved (or "no AUDIT.md" / "no changes")
CLAUDE.md: <sections updated> (or "no updates needed")
```

## 6. MEMORY.md Size Check

After updating MEMORY.md, count the total lines. If >= 180 lines, add a
warning to the summary output:

```
WARNING: MEMORY.md is <N> lines (limit: 200). Run /mem-compact to archive
completed sections.
```

Also write a health cache file for the context-bar:
```bash
echo "<rating>|<test_count>|<memory_status>|$(date -Iseconds)" > /tmp/rfxn-health-<project>.cache
```

## Rules
- Read before writing — never overwrite content you haven't read
- Preserve all existing content structure and formatting
- Only update facts that are verifiably stale (confirmed via git/source)
- Do NOT create files that don't already exist (except MEMORY.md)
- Do NOT stage, commit, or push — this is a save operation only
