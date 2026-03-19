Read CLAUDE.md before dispatching. Use the Task tool with model claude-sonnet-4-6.
Pass each Task the full CLAUDE.md contents as context.

## Preparation
Create ./audit-output/ if it does not exist.
Remove any stale files from a prior run:
  rm -f ./audit-output/*.md

## Round 1 — Domain agents (spawn all simultaneously)
Each agent writes its output to disk and exits. No findings are passed in-context.
See audit-schema.md Agent Registry for the canonical agent list, command files,
and output filenames. Dispatch all agents plus the context agent:

  Task "context"        model: sonnet  → audit-context.md       writes: audit-output/context.md
  Task "regression"     model: opus    → audit-regression.md    writes: audit-output/agent1.md
  Task "latent"         model: opus    → audit-latent.md         writes: audit-output/agent2.md
  Task "standards"      model: haiku   → audit-standards.md      writes: audit-output/agent3.md
  Task "cli"            model: sonnet  → audit-cli.md            writes: audit-output/agent4.md
  Task "docs"           model: sonnet  → audit-docs.md           writes: audit-output/agent5.md
  Task "config"         model: sonnet  → audit-config.md         writes: audit-output/agent6.md
  Task "test-coverage"  model: sonnet  → audit-test-coverage.md  writes: audit-output/agent7.md
  Task "test-exec"      model: sonnet  → audit-test-exec.md      writes: audit-output/agent8.md
  Task "install"        model: sonnet  → audit-install.md        writes: audit-output/agent9.md
  Task "build-ci"       model: sonnet  → audit-build-ci.md       writes: audit-output/agent10.md
  Task "upgrade"        model: sonnet  → audit-upgrade.md        writes: audit-output/agent11.md
  Task "version"        model: haiku   → audit-version.md        writes: audit-output/agent12.md
  Task "security"       model: opus    → audit-security.md       writes: audit-output/agent13.md
  Task "interfaces"     model: sonnet  → audit-interfaces.md     writes: audit-output/agent14.md
  Task "modernize"      model: opus    → audit-modernize.md      writes: audit-output/agent15.md

Wait until all output files exist before proceeding.

### Progress tracking (lightweight)
Do NOT maintain a full progress table in-context. Do NOT read agent SUMMARY
lines or build finding count tables — the condense-dedup step handles all
data extraction.

Periodically check for completion markers:
  grep -l "COMPLETION:" ./audit-output/agent*.md 2>/dev/null | wc -l

Print status at milestones only:
  `Round 1: <N>/15 agents complete`

When all done:
  `Round 1 complete: all agents + context finished`

## Round 2 — Health checks + Condense-Dedup (spawn both simultaneously)

### Agent health checks
Check every expected agent output file:
1. File exists AND contains `COMPLETION:` marker → **COMPLETE**
2. File exists but NO `COMPLETION:` marker → **PARTIAL** (warn, proceed with file)
3. File does not exist → **FAILED** (error, exclude from condense input)

Print: `Agent Health: <complete>/15 complete, <partial> partial, <failed> failed`
If any agent FAILED, list it by name.

### Condense-Dedup (spawn both simultaneously)
Each condense-dedup agent extracts findings, deduplicates within its group,
applies verification-aware severity adjustment, and outputs a compact table.
See audit-schema.md Agent Registry for Group A/B assignments.

  Task "condense-dedup-a" model: sonnet → audit-condense.md
    Tell it to read: Group A agent output files from the registry
    Tell it to write: audit-output/findings-a.md

  Task "condense-dedup-b" model: sonnet → audit-condense.md
    Tell it to read: Group B agent output files from the registry
    Tell it to write: audit-output/findings-b.md

Exclude any FAILED agent files from condense input.

Tell each condense-dedup task the list of skipped/failed agents so it can
include a `SKIPPED_AGENTS:` header line for downstream coverage tracking.
In full mode, only FAILED agents are skipped.

Wait until both findings-a.md and findings-b.md exist before proceeding.

### Input size gate
After both files exist, count total lines:
  wc -l audit-output/findings-a.md audit-output/findings-b.md audit-output/context.md

Print the total. If total > 300 lines, warn:
  `⚠ Large audit input (<N> lines) — monitoring compile agent`

## Round 3 — Compile
  Task "compile" model: sonnet → audit-compile.md
    Reads: audit-output/findings-a.md, findings-b.md, context.md
    Writes: AUDIT.md

### Round 3 fallback
If the compile agent stalls or fails (no progress for >120s):
1. Count severities from findings files:
   grep -c '|Critical|' audit-output/findings-a.md audit-output/findings-b.md
   grep -c '|Major|' audit-output/findings-a.md audit-output/findings-b.md
2. Write a minimal AUDIT.md:
   - Header with date and finding counts
   - Cat both findings tables under a ## FINDINGS header
   - Mark as: `> Generated in degraded mode — review findings-a.md and findings-b.md`
3. This guarantees a result even if the compile agent dies.

Report completion and the compile agent's summary.
