# Claude Code Cache Health Audit

> **One prompt. Full cache economics report. Works on any Claude Code installation.**

Prompt caching has a TTL. When it expires, your entire conversation context rebuilds at 12.5x the cache read rate. Most users have no visibility into this.

This prompt parses your local `~/.claude/` session transcripts and produces a structured audit of your cache hit rates, idle-gap penalties, and the exact minute your cache cliff lives.

## Quick Start

Paste the prompt below into any Claude Code session. No setup, no dependencies, no API keys. It reads your local JSONL transcripts and produces the report in ~60 seconds.

## The Prompt

```
Analyze my Claude Code session history to evaluate prompt cache health.

DATA LOCATION: Parse all JSONL transcript files under ~/.claude/projects/. Recurse into subdirectories but skip any path containing /subagents/. If no JSONL files are found, check if ~/.claude/sessions.db exists and report that the data may be in SQLite format instead.

SCHEMA VERIFICATION: Before the full scan, parse the first 3 JSONL files found. Confirm that:
- Top-level fields include "timestamp" (ISO string) and "message" (object)
- message.usage contains cache_read_input_tokens, cache_creation_input_tokens, input_tokens
- Print one sample usage block so I can verify the schema is correct
If the schema does not match, stop and report what you found instead of proceeding with bad data.

PRICING: Detect the model from the message.model field in the JSONL data. Apply the correct 5-minute cache tier pricing (per 1M tokens):
- Opus (claude-opus-4-6, claude-opus-4-5):     input $5,  cache_create $6.25,  cache_read $0.50
- Sonnet (claude-sonnet-4-6, claude-sonnet-4-5, claude-sonnet-4-*): input $3,  cache_create $3.75,  cache_read $0.30
- Haiku (claude-haiku-4-5):                     input $1,  cache_create $1.25,  cache_read $0.10
If the model string does not match any above, default to Sonnet pricing and flag it in the overview.
If mixed models are present, report per-model and use a weighted blend for the summary tables.

OUTPUT FORMAT: Render the report exactly as shown below. Do not add narrative paragraphs, commentary, or interpretation between sections. Each section is a header followed by a fixed-width table or key-value block. No prose. Tables only. Save all analysis, interpretation, and recommendations for the DIAGNOSIS section at the end.

===== CLAUDE CODE CACHE HEALTH AUDIT =====

📊 OVERVIEW
Metric                          Value
─────────────────────────────────────────
Sessions analyzed               <N>
Turns with usage data           <N>
Date range                      <YYYY-MM-DD to YYYY-MM-DD>
Total input tokens              <N>B
Primary model                   <model>

📦 SESSION PROFILE
Metric                          Value
─────────────────────────────────────────
Avg context at end              <N>k
Median context at end           <N>k
P90 context at end              <N>k
Max context at end              <N>k
Avg turns per session           <N>
Median turns per session        <N>
Sessions >100k                  <N> (<N>%)
Sessions >200k                  <N> (<N>%)
Sessions >500k                  <N> (<N>%)

📈 CACHE HIT RATE BY WEEK
Week       Sessions   Turns   CacheRead   CacheCreate   FreshInput   Hit%     $/turn
─────────────────────────────────────────────────────────────────────────────────────
YYYY-WNN   <N>        <N>     <N>M        <N>M          <N>K         <N>%     $<N>

🧊 CACHE HIT RATE BY IDLE GAP
Gap          Turns    AvgRead    AvgCreate    Hit%     $/turn    Verdict
─────────────────────────────────────────────────────────────────────────
<1m          <N>      <N>k       <N>k         <N>%     $<N>      <emoji>
1-5m         <N>      <N>k       <N>k         <N>%     $<N>      <emoji>
5-15m        <N>      <N>k       <N>k         <N>%     $<N>      <emoji>
15-60m       <N>      <N>k       <N>k         <N>%     $<N>      <emoji>
1h+          <N>      <N>k       <N>k         <N>%     $<N>      <emoji>

Verdict column: 🟢 hit% >90, 🟡 hit% 50-90, 🔴 hit% <50

💀 WORST CACHE MISSES
Date         Project                  Turn    Gap       Context    Created    Read
─────────────────────────────────────────────────────────────────────────────────
MM-DD HH:MM  <name>                   T<N>    <N>m      <N>k       <N>k       <N>k

Filter: context >100k AND cache_create >50% of total AND gap >5 min. Top 10 by created.

🩺 DIAGNOSIS
Metric                              Value
─────────────────────────────────────────────
Effective cache TTL                 <N> minutes
Cache health                       [🟢 HEALTHY >95% / 🟡 DEGRADED 90-95% / 🔴 BROKEN <90%]
Overall hit rate                    <N>%
Estimated monthly idle-gap cost     $<N>
Idle-gap cost as % of total         <N>%

→ Top recommendation:              <one sentence>
→ Biggest risk:                     <one sentence>

✅ VERIFICATION CHECKSUMS
Check                                                         Result
──────────────────────────────────────────────────────────────────────
Weekly totals vs overview total (within 1%)                   [PASS ✓ / FAIL ✗]
Gap bucket turns vs expected (total - 2*sessions, within 5%)  [PASS ✓ / FAIL ✗]
Idle gap distribution (>80% of turns in <1m bucket)           [PASS ✓ / FAIL ✗]
Zero-total turns (cache_read+create+fresh = 0)                [PASS ✓ / FAIL ✗] (<N> found)
Weekly continuity (no missing weeks in date range)            [PASS ✓ / FAIL ✗]

If any check FAILs, print the failing detail and rerun the analysis before trusting the diagnosis.

===== END AUDIT =====
```

## Reading the Output

| Indicator | Hit Rate | Cliff | $/turn | Meaning |
|-----------|----------|-------|--------|---------|
| 🟢 Healthy | >95% | 55-65 min | Stable week/week | Cache working as intended |
| 🟡 Degraded | 90-95% | <45 min | Rising week/week | Check for version regressions or config changes |
| 🔴 Broken | <90% | No clear cliff | >$0.40 | Cache likely not functioning, investigate |

## Key Concepts

**Cache TTL**: Prompt cache entries expire after a period of inactivity. Empirical measurement across 13.5B tokens shows the effective TTL is ~60 minutes. Activity refreshes the TTL, so continuous prompting keeps the cache warm indefinitely.

**The Cliff**: Cache hit rate does not decay gradually. It drops from ~87% to ~3% between the 30-60 minute and 60+ minute idle windows. This is a cliff, not a curve.

**Rebuild Cost**: When cache expires, the full conversation context rebuilds at cache creation pricing (12.5x read rate, same ratio across all models). A 145k session on Opus 4.6 costs ~$0.91 to rebuild vs ~$0.08 when cached.

**Fixed Overhead**: Claude Code loads ~15k tokens of system prompt and tool schemas on every turn. This overhead is cached during active use but rebuilds on every cache miss, adding ~$0.09 (Opus 4.6) to every idle-gap penalty.

## Workflow Recommendations

1. **Do not leave sessions idle >15 minutes** without intent. Cache decay starts immediately.
2. **Stepping away for an hour?** Run `/clear` first. You pay the full rebuild anyway. Start clean.
3. **60-90 minute focused sessions** stay inside the cache window. No cliff, no compaction, cheapest $/turn.
4. **Run `/context` regularly.** Know your overhead. The gap between what you think is loaded and what is actually loaded is where the silent costs live.

## Attribution

Analysis based on empirical measurement of 584 sessions, 104k turns, and 13.5B tokens across Claude Code v2.1.77 through v2.1.104 (Opus 4.6). Methodology and findings documented in the accompanying [LinkedIn post](https://www.linkedin.com/in/rfxn).
