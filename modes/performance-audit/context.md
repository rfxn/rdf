# Performance Audit Mode

> Operational mode for performance analysis and optimization. Changes
> how agents approach work -- planner identifies bottlenecks, dispatcher
> applies benchmark-aware gates, reviewer checks for regressions.

## Methodology

Follows a structured performance assessment:

1. **Baseline** -- establish current performance metrics with measured data
2. **Profile** -- identify hotspots and bottlenecks with profiling tools
3. **Classify** -- categorize issues by type and measured impact
4. **Optimize** -- targeted fixes with before/after measurement
5. **Verify** -- regression testing to confirm improvements hold

Bottleneck classification:
- CPU-bound (algorithmic complexity, tight loops)
- I/O-bound (disk, network, database queries)
- Memory-bound (allocation pressure, leaks, cache misses)
- Concurrency (lock contention, thread starvation, deadlocks)

## Evidence Discipline

Performance findings must be backed by measurement, not code-reading
intuition. "Looks like O(n^2)" is a hypothesis, not a finding.

**Measured vs suspected:**

| Category | Evidence required | Status |
|----------|-------------------|--------|
| Measured bottleneck | Profiling data with time/memory attribution | Confirmed finding |
| Suspected bottleneck | Code-level reasoning without profiling data | Hypothesis -- labeled as such |
| Pattern-match guess | "This loop looks slow" | Not reportable -- profile first |

**Measurement protocol:**
- Include input size, iteration count, and wall-clock or CPU time
- Correlate hotspots to specific source locations (file:line)
- Capture baseline BEFORE any optimization -- no baseline, no optimization
- When profiling tools are unavailable, clearly label all findings as
  hypotheses and recommend specific profiling steps to confirm

**False positive prevention:**
- A function appearing in a hot path does not mean it is the bottleneck --
  verify it consumes a meaningful percentage of total time
- Algorithmic complexity claims require input-size scaling evidence, not
  just loop nesting depth
- Memory "leak" claims require evidence of growth over time, not just
  high absolute usage

## Planner Behavior

- Identify performance-critical paths before proposing changes
- Research profiling tools appropriate to the project's stack
- Quantify expected impact before committing to optimization
- Avoid premature optimization -- measure first
- Plan baseline capture as an explicit phase, not an afterthought
- Default scope context: changes in this mode typically classify as scope:multi-file or scope:cross-cutting

## Quality Gate Overrides

Performance mode adds benchmark verification to quality gates.

| Override | Effect |
|----------|--------|
| Gate 2 (QA) | Must include before/after benchmark comparison |
| Gate 3 (reviewer) | Performance pass findings are MUST-FIX |
| Regression bar | No performance regression beyond 5% on any measured path |
| Evidence requirement | Findings without measurement data are returned as hypotheses |

## Reviewer Focus

Modified 4-pass sentinel with performance emphasis:
1. Anti-slop (standard)
2. Regression (ELEVATED -- performance regression detection)
3. Security (standard)
4. **Performance** (ELEVATED -- O(n^2) detection, allocation analysis,
   unbounded queries, missing pagination, cache effectiveness)

Reviewer additionally checks:
- Every reported bottleneck backed by measurement, not code inspection alone
- Baseline exists before optimization was attempted
- Hypotheses clearly labeled and not mixed with confirmed findings

## Profiling Protocol

When profiling is part of the assessment:
- Document the profiling tool and methodology used
- Include raw profiling output as evidence
- Identify top-N hotspots with percentage of total time/memory
- Correlate hotspots to source code locations

## Checklist

Before completing a performance phase:
- [ ] Baseline metrics captured before changes (with methodology documented)
- [ ] Profiling data collected and analyzed
- [ ] Bottleneck classification documented with measured evidence
- [ ] Every reported bottleneck backed by measurement (not code-pattern inference)
- [ ] Suspected-but-unmeasured issues labeled as hypotheses, not findings
- [ ] Optimization targeted at measured hotspots (not guesses)
- [ ] Before/after benchmark comparison included in evidence
- [ ] No performance regressions on unrelated paths
- [ ] Memory usage verified (no new leaks introduced)
