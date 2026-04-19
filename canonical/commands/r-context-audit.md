# /r-context-audit — Context Weight Audit

Measure, score, and report on Claude Code context overhead for this
workspace. Identifies bloat, tracks drift from baseline, and produces
actionable optimization recommendations.

Run periodically (weekly, or after adding skills/memory/governance)
to catch context creep before it impacts session quality.

## Arguments
- `$ARGUMENTS` — optional: `--fix` to apply Tier 1 quick wins automatically

## Protocol

### 1. Run Measurement Script

Execute the automated measurement script:

```bash
bash rdf/state/context-audit.sh 2>/dev/null
```

If a baseline file exists at `~/.rdf/context-audit-baseline.json`,
run with comparison mode:

```bash
bash rdf/state/context-audit.sh --baseline ~/.rdf/context-audit-baseline.json 2>/dev/null
```

Parse the JSON output. Do NOT make additional file reads or greps —
the script measures everything.

### 2. Render Report

Use this exact format. Keep it under 40 lines.

```
## Context Audit — {date}

**Score: {N}/100** [{CLEAN|NEEDS_WORK|BLOATED|CRITICAL}]
**Boot cost: {N}K tokens** ({N}% of 200K context)

### Always-Loaded Breakdown

| Component | Lines | Bytes | ~Tokens | % of boot |
|-----------|------:|------:|--------:|----------:|
| Workspace CLAUDE.md | {N} | {N} | {N} | {N}% |
| Memory index | {N} | {N} | {N} | {N}% |
| Memory satellites ({N}) | {N} | {N} | {N} | {N}% |
|   Archives ({N}) | {N} | {N} | {N} | {N}% |
| Global CLAUDE.md | {N} | {N} | {N} | {N}% |
| Settings | {N} | {N} | {N} | {N}% |
| Skill listing ({N}) | — | {N} | {N} | {N}% |

### rdf-state.sh Output ({N} repos measured)

| Field | Bytes | % | Consumers | Status |
|-------|------:|--:|-----------|--------|
| work_output_files | {N} | {N}% | {list or NONE} | {WASTE/OK} |
| insights | {N} | {N}% | {list} | {DUPLICATED/OK} |
| session_last | {N} | {N}% | {list} | {OVERSIZED/OK} |
| Core fields | {N} | {N}% | Multiple | OK |

### Work-Output Accumulation

| Metric | Value |
|--------|------:|
| Total .md files across repos | {N} |
| Heaviest repo | {name} ({N} files) |

### Session History

| Metric | Value |
|--------|------:|
| JSONL session files | {N} |
| Total session data | {N} GB |
| History entries | {N} |

### Findings

{Bulleted list of issues, sorted by impact. Format:}
- **[CRITICAL|WARNING|INFO]** {description} — **Fix:** {one-line action}

### Delta from Baseline

{Only if --baseline was used and delta exists in JSON:}

| Metric | Was | Now | Change |
|--------|----:|----:|-------:|
| {metric} | {N} | {N} | {+/-N} |

{If no baseline: "No baseline found. Run with `--save-baseline` to establish one."}
```

Score labels:
- 90-100: CLEAN
- 70-89: NEEDS_WORK
- 50-69: BLOATED
- 0-49: CRITICAL

### 3. Recommendations

After the report, emit a prioritized fix list in three tiers:

**Tier 1 — Quick wins (no behavioral change):**
- Remove dead fields from rdf-state.sh
- Compact memory archives
- Prune stale memory satellites

**Tier 2 — Structural (requires planning):**
- Split CLAUDE.md into base + reference
- Add --lite mode to /r-start
- Consolidate settings allow rules

**Tier 3 — Architectural (multi-session):**
- Minimal-context subagent dispatch
- Project-affinity memory loading
- Subagent token budget caps

Only recommend tiers where the audit found actual issues.

### 4. Save Baseline (if requested)

If the user confirms, or if `--save-baseline` was passed:

```bash
cp /tmp/context-audit-*.json ~/.rdf/context-audit-baseline.json
```

The baseline file is used by future runs to detect drift.

### 5. Auto-Fix (if --fix)

If `--fix` was passed, apply these automatically:

1. **Memory compact** — invoke `/r-util-mem-compact --apply`
2. **State output** — if `work_output_files` field exists and has
   zero consumers, note the fix location in rdf-state.sh
3. **Settings** — add `autocompact_percentage_override: 75` if missing

Do NOT auto-modify CLAUDE.md or skill definitions. Show diffs and
ask for confirmation on instruction files.

## Scoring Criteria

| Condition | Points |
|-----------|-------:|
| Memory satellites > 15 | -10 |
| Memory archives > 10KB | -10 |
| MEMORY.md >= 180 lines | -5 |
| MEMORY.md >= 200 lines | -10 |
| Workspace CLAUDE.md > 200 lines | -10 |
| Workspace CLAUDE.md > 400 lines | -10 |
| rdf-state.sh work_output waste > 5KB | -10 |
| rdf-state.sh insights duplication > 5KB | -5 |
| Boot tokens > 40K | -10 |
| Boot tokens > 60K | -10 |

Score floor: 0. Base: 100.

## Repeatable Pattern

This audit is designed to run as a recurring health check:

1. **Weekly**: Run `/r-context-audit` to catch drift
2. **After adding skills/memory**: Run to verify impact
3. **Before major builds**: Run to ensure headroom
4. **After /r-init or /r-refresh**: Run to verify governance didn't bloat
5. **Quarterly**: Compare against baseline, update baseline if score improved

The measurement script (`rdf/state/context-audit.sh`) can also be
called from CI, cron, or other automation — it outputs pure JSON
with no side effects.
