Read CLAUDE.md before dispatching. Static analysis only — no test execution,
no upgrade path, no full matrix. Use model claude-sonnet-4-6.

Create ./audit-output/ if absent. Remove stale files: rm -f ./audit-output/*.md

## Round 1 — Domain agents (spawn all simultaneously)
Dispatch only agents where Quick=yes in audit-schema.md Agent Registry.
Skipped agents (Quick=no): test-exec (8), install (9), upgrade (11),
modernize (15).

  Task "context"        model: sonnet  → audit-context.md       writes: audit-output/context.md
  Task "regression"     model: opus    → audit-regression.md    writes: audit-output/agent1.md
  Task "latent"         model: opus    → audit-latent.md         writes: audit-output/agent2.md
  Task "standards"      model: haiku   → audit-standards.md      writes: audit-output/agent3.md
  Task "cli"            model: sonnet  → audit-cli.md            writes: audit-output/agent4.md
  Task "docs"           model: sonnet  → audit-docs.md           writes: audit-output/agent5.md
  Task "config"         model: sonnet  → audit-config.md         writes: audit-output/agent6.md
  Task "test-coverage"  model: sonnet  → audit-test-coverage.md  writes: audit-output/agent7.md
  Task "build-ci"       model: sonnet  → audit-build-ci.md       writes: audit-output/agent10.md
  Task "version"        model: haiku   → audit-version.md        writes: audit-output/agent12.md
  Task "security"       model: opus    → audit-security.md       writes: audit-output/agent13.md
  Task "interfaces"     model: sonnet  → audit-interfaces.md     writes: audit-output/agent14.md
  (Skipped — Quick=no: test-exec/8, install/9, upgrade/11, modernize/15)

Wait for all output files before proceeding.

### Progress tracking (lightweight)
Do NOT maintain a full progress table. Do NOT read agent SUMMARY lines.
Periodically check:
  grep -l "COMPLETION:" ./audit-output/agent*.md 2>/dev/null | wc -l

Print at milestones:
  `Round 1: <N>/11 agents complete`

## Round 2 — Health checks + Condense-Dedup

### Agent health checks
Check every expected agent output file:
1. File exists AND contains `COMPLETION:` marker → **COMPLETE**
2. File exists but NO `COMPLETION:` marker → **PARTIAL** (warn, proceed)
3. File does not exist → **FAILED** (error, exclude from condense)

Print: `Agent Health: <complete>/<total> complete, <partial> partial, <failed> failed`

### Condense-Dedup (spawn both simultaneously)
See audit-schema.md for Group A/B assignments. In quick mode, exclude
Quick=no agents from their respective groups.

  Task "condense-dedup-a" model: sonnet → audit-condense.md
    Tell it to read: Group A agent output files (exclude agent9, agent15 — skipped)
    Tell it to write: audit-output/findings-a.md

  Task "condense-dedup-b" model: sonnet → audit-condense.md
    Tell it to read: Group B agent output files (exclude agent8, agent11 — skipped)
    Tell it to write: audit-output/findings-b.md

Exclude any FAILED agent files. Tell each task the full skipped list
(Quick=no + FAILED) for the SKIPPED_AGENTS header.

Wait until both findings files exist before proceeding.

### Input size gate
  wc -l audit-output/findings-a.md audit-output/findings-b.md audit-output/context.md
If total > 300 lines, warn.

## Round 3 — Compile
  Task "compile" model: sonnet → audit-compile.md
    Reads: audit-output/findings-a.md, findings-b.md, context.md
    Writes: AUDIT.md

### Round 3 fallback
If compile stalls (>120s), write minimal AUDIT.md from findings tables:
1. Count severities from findings files
2. Cat both findings tables under ## FINDINGS header
3. Mark: `> Generated in degraded mode (quick audit)`

A quick-mode audit with skipped agents should NOT produce "Overall Health: GREEN"
without noting reduced coverage.
