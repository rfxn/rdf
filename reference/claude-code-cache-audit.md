Analyze my Claude Code session history for token efficiency: cache health, context discipline, tool use, and work output per token.

RULES
- Everything you need is on disk. No web, no pricing research, no dollar figures anywhere.
- Do not read transcripts into context. Write one Python script that prints aggregates. Revise it only to fix a failed check.
- Numbers and patterns only. No code, file contents, prompts, or customer data. Project names are fine.

DATA
- Parse all JSONL files under ~/.claude/projects/. Main-thread analysis skips any path containing /subagents/. Parse subagent files separately and use them only for token share.
- Group turns by the top-level sessionId field, not by file. Merge all files sharing a sessionId and sort by timestamp before computing per-session metrics.
- One API response can span several JSONL lines carrying identical usage. Count usage once per message.id.
- SCHEMA CHECK first: parse 3 files and confirm timestamp, sessionId, message.model, and message.usage with input_tokens, cache_creation_input_tokens, cache_read_input_tokens, output_tokens. Print one sample usage block. If the schema does not match, stop and report what you found.

DEFINITIONS
- Fresh input = input_tokens + cache_creation_input_tokens. Hit% = cache_read / (cache_read + fresh input).
- Idle gap = time since the previous turn in the same session.
- Rebuild = a turn with context >50k where cache_creation is >50% of its input.
- Read-equivalent units (RE) show the relative weight of tokens: cache read x1, cache write x12.5 (5-min TTL) or x20 (1-hour TTL), uncached input x10, output x50. RE is a relative measure. Never convert it to money.
- If message.usage.cache_creation splits writes by TTL (ephemeral_5m / ephemeral_1h), use the split. Otherwise treat writes as 5-min and say so.
- Edits = Edit, Write, MultiEdit, NotebookEdit calls. Commits = Bash calls containing "git commit". Tool result tokens = characters / 4.

OUTPUT FORMAT: Print the report inline as your reply. Do not write it to a file. Each section is a header followed by a fixed-width table or key-value block. No prose outside DIAGNOSIS and WORKING AGREEMENT. After ===== END AUDIT ===== stop.

===== CLAUDE CODE TOKEN EFFICIENCY AUDIT =====

📊 OVERVIEW
Metric                          Value
─────────────────────────────────────────
Sessions analyzed               <N>
Turns with usage data           <N>
Date range                      <YYYY-MM-DD to YYYY-MM-DD>
Total tokens                    <N>M
Fresh input / Cache read        <N>M / <N>M
Output tokens                   <N>M
Cache writes 5m / 1h            <N>% / <N>%
Subagent share of RE            <N>%
Primary model                   <model>

📦 SESSION PROFILE
Metric                          Value
─────────────────────────────────────────
Avg / Median context at end     <N>k / <N>k
P90 / Max context at end        <N>k / <N>k
Avg / Median turns per session  <N> / <N>
Sessions >100k                  <N> (<N>%)
Sessions >200k                  <N> (<N>%)
Sessions >500k                  <N> (<N>%)

📈 BY WEEK
Week       Sessions  Turns  CacheRead  CacheWrite  FreshInput  Output  Hit%  RE/turn
──────────────────────────────────────────────────────────────────────────────────────
YYYY-WNN   <N>       <N>    <N>M       <N>M        <N>K        <N>K    <N>%  <N>k

🧊 BY IDLE GAP
Gap      Turns  AvgRead  AvgWrite  Hit%  RE/turn  Verdict
──────────────────────────────────────────────────────────
<1m      <N>    <N>k     <N>k      <N>%  <N>k     <emoji>
1-5m     <N>    <N>k     <N>k      <N>%  <N>k     <emoji>
5-15m    <N>    <N>k     <N>k      <N>%  <N>k     <emoji>
15-60m   <N>    <N>k     <N>k      <N>%  <N>k     <emoji>
1h+      <N>    <N>k     <N>k      <N>%  <N>k     <emoji>
Verdict: 🟢 hit% >90, 🟡 50-90, 🔴 <50

💀 WORST REBUILDS
Date         Project              Turn   Gap    Context  Written  Read
──────────────────────────────────────────────────────────────────────
MM-DD HH:MM  <name>               T<N>   <N>m   <N>k     <N>k     <N>k
Filter: rebuilds with gap >5 min. Top 10 by tokens written.

🔧 TOOL USE
Tool / MCP server     Calls  Avg result  Max result  Share of result tokens
──────────────────────────────────────────────────────────────────────────
<name>                <N>    <N>k        <N>k        <N>%
Top 10 by share, then:
File re-read rate (same file, same session)        <N>%
Tool results >20k tokens per week                  <N>
Sessions with 3+ consecutive failing test/build    <N>%

🛠 WORK OUTPUT
Edits                           <N>
Commits                         <N>
RE per edit                     <N>k
RE per commit                   <N>k

🎯 SCORECARD
Metric                               Mine    Target       Status
──────────────────────────────────────────────────────────────────
Cache hit rate                       <N>%    ≥ 95%        <status>
Idle-gap rebuild share of RE         <N>%    ≤ 10%        <status>
Sessions >200k context               <N>%    ≤ 20%        <status>
File re-read rate                    <N>%    ≤ 10%        <status>
Tool results >20k per week           <N>     ≤ 5          <status>
Failing test/build loop sessions     <N>%    ≤ 5%         <status>
RE per edit                          <N>k    baseline     Baseline
RE per commit                        <N>k    baseline     Baseline
Status: Pass, Watch (within 25% of target), Miss, Baseline

🩺 DIAGNOSIS
Effective cache TTL (where the cliff lands)   <N> minutes
Cache health                                   [🟢 HEALTHY >95% / 🟡 DEGRADED 90-95% / 🔴 BROKEN <90%]
Top 3 drivers (pattern | share of RE | fix | tradeoff):
1. <one line>
2. <one line>
3. <one line>
Waste:                <one line>
Productive heavy use: <one line>
Biggest risk:         <one line>

📝 WORKING AGREEMENT
3 to 5 habits I'll adopt, one line each.

✅ VERIFICATION CHECKSUMS
Check                                                          Result
───────────────────────────────────────────────────────────────────────
Weekly totals vs overview total (within 1%)                    [PASS ✓ / FAIL ✗]
Gap bucket turns vs expected (total - 2*sessions, within 5%)   [PASS ✓ / FAIL ✗]
Idle gap distribution (>80% of turns in <1m bucket)            [PASS ✓ / FAIL ✗]
Zero-total turns (cache_read+write+fresh = 0)                  [PASS ✓ / FAIL ✗] (<N> found)
Weekly continuity (no missing weeks in date range)             [PASS ✓ / FAIL ✗]
Session grouping (JSONL files vs unique sessionIds)            [PASS ✓ / FAIL ✗] (<N> files, <N> sessions)
Usage dedupe (JSONL lines vs unique message.ids)               [PASS ✓ / FAIL ✗] (<N> lines, <N> ids)
Worst rebuilds turn numbers (no T1 unless single-turn)         [PASS ✓ / FAIL ✗]
If any check fails, fix the root cause and rerun from scratch. Do not print a diagnosis on data that failed verification.

📋 SUMMARY JSON
{"period_start":"","period_end":"","sessions":0,"turns":0,"total_tokens":0,"fresh_input_tokens":0,"cache_read_tokens":0,"output_tokens":0,"cache_write_5m_share":0,"cache_hit_rate":0,"effective_ttl_minutes":0,"idle_rebuild_re_share":0,"re_total":0,"re_per_turn":0,"re_per_edit":0,"re_per_commit":0,"sessions_over_200k_share":0,"subagent_re_share":0,"file_reread_rate":0,"large_tool_results_per_week":0,"failing_loop_session_share":0,"model_token_share":{"opus":0,"sonnet":0,"haiku":0,"other":0},"scorecard":{"pass":0,"watch":0,"miss":0},"top_drivers":["","",""]}

===== END AUDIT =====
