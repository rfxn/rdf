Read the current project's PLAN.md, MEMORY.md, and AUDIT.md (if present),
then produce a concise status report. If run from the parent
/root/admin/work/proj directory, read ALL projects for a cross-project view.

## Single-project output
```
## <Project> v<version> — <branch>
Status: <phase summary>
Tests: <count> across <files> files, <CI targets> CI targets
Open work: <count> items (<must>M / <should>S / <defer>D)

### Next items (priority order)
1. [MUST] <description> — <file>:<context>
2. [SHOULD] <description>
...

### Audit findings (if AUDIT.md exists)
Health: RED/YELLOW/GREEN
Findings: <total> unique — <C> Critical, <M> Major, <m> Minor, <I> Info
Resolved: <N>/<total> (<percent>%)

| Phase | Severity | Open | Resolved | Blocked by |
|-------|----------|------|----------|------------|
| P1-Immediate | Critical | <n> | <n> | — |
| P2-NextRelease | Major | <n> | <n> | F-NNN |
| P3-Backlog | Minor+Info | <n> | <n> | — |

Top unresolved:
- F-NNN | <severity> | <title> — <file>
- F-NNN | <severity> | <title> — <file>
- F-NNN | <severity> | <title> — <file>

### Recent commits (last 5)
- <hash> — <message>

### Blockers / Warnings
- <any Critical/Major audit findings still open>
- <any regressed items from audit>
- <any CI failures>
```

## Cross-project output (from parent dir)
```
| Project | Version | Branch | Open | Tests | Audit | Last Commit |
|---------|---------|--------|------|-------|-------|-------------|
| APF     | 2.0.2   | 2.0.2  | 0M/0S| 398   | GREEN | <date>      |
| LMD     | 2.0.1   | 2.0.1  | 2L   | 285   | YELLOW 5M | <date> |
| BFD     | 2.0.1   | 2.0.1  | 7D   | 731   | — | <date>       |
```

Then per-project summaries with open items and audit highlights only.
Audit column shows: `—` (no AUDIT.md), or `GREEN`/`YELLOW <n>M`/`RED <n>C`
with the driving metric.

## Audit parsing rules
When AUDIT.md exists, extract:
1. **Health rating** from EXECUTIVE SUMMARY (RED/YELLOW/GREEN)
2. **Severity counts** from STATISTICS or the `Findings:` header line
3. **Resolved count** by counting findings annotated with `RESOLVED`
4. **Roadmap phase breakdown** from REMEDIATION ROADMAP sections
5. **Top 3 unresolved** — highest severity first, then by F-NNN order
6. **Regressed items** from PRIOR WORK STATUS — any regressed item is a blocker

If AUDIT.md uses the older format (RECOMMENDED PRIORITY ORDER instead of
REMEDIATION ROADMAP), extract the top 3 items from that list instead and
skip the phase breakdown table.

## Rules
- Read PLAN.md, MEMORY.md, AUDIT.md, and run `git log --oneline -5` per project
- Do NOT modify any files
- Do NOT run tests
- Keep output concise — this is a status check, not an audit
