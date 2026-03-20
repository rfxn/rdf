# Performance Audit Mode

> Operational mode for performance analysis and optimization. Changes
> how agents approach work -- planner identifies bottlenecks, dispatcher
> applies benchmark-aware gates, reviewer checks for regressions.

## Methodology

Follows a structured performance assessment:

1. **Baseline** -- establish current performance metrics
2. **Profile** -- identify hotspots and bottlenecks
3. **Classify** -- categorize issues by type and impact
4. **Optimize** -- targeted fixes with before/after measurement
5. **Verify** -- regression testing to confirm improvements hold

Bottleneck classification:
- CPU-bound (algorithmic complexity, tight loops)
- I/O-bound (disk, network, database queries)
- Memory-bound (allocation pressure, leaks, cache misses)
- Concurrency (lock contention, thread starvation, deadlocks)

## Planner Behavior

- Identify performance-critical paths before proposing changes
- Research profiling tools appropriate to the project's stack
- Quantify expected impact before committing to optimization
- Avoid premature optimization -- measure first
- Default scope context: changes in this mode typically classify as scope:multi-file or scope:cross-cutting

## Quality Gate Overrides

Performance mode adds benchmark verification to quality gates.

| Override | Effect |
|----------|--------|
| Gate 2 (QA) | Must include before/after benchmark comparison |
| Gate 3 (reviewer) | Performance pass findings are MUST-FIX |
| Regression bar | No performance regression beyond 5% on any measured path |

## Reviewer Focus

Modified 4-pass sentinel with performance emphasis:
1. Anti-slop (standard)
2. Regression (ELEVATED -- performance regression detection)
3. Security (standard)
4. **Performance** (ELEVATED -- O(n^2) detection, allocation analysis,
   unbounded queries, missing pagination, cache effectiveness)

## Profiling Protocol

When profiling is part of the assessment:
- Document the profiling tool and methodology used
- Include raw profiling output as evidence
- Identify top-N hotspots with percentage of total time/memory
- Correlate hotspots to source code locations

## Checklist

Before completing a performance phase:
- [ ] Baseline metrics captured before changes
- [ ] Profiling data collected and analyzed
- [ ] Bottleneck classification documented
- [ ] Optimization targeted at measured hotspots (not guesses)
- [ ] Before/after benchmark comparison included in evidence
- [ ] No performance regressions on unrelated paths
- [ ] Memory usage verified (no new leaks introduced)
