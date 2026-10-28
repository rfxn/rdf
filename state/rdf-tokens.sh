#!/usr/bin/env bash
# state/rdf-tokens.sh — local token usage report from Claude Code transcripts and Codex rollouts
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# shellcheck disable=SC2016  # literal $ in single-quoted jq programs
set -euo pipefail

RDF_CLAUDE_PROJECTS="${RDF_CLAUDE_PROJECTS:-${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/projects}"
RDF_TOKENS_CACHE="${RDF_TOKENS_CACHE:-${HOME}/.rdf/cache/tokens}"
_TOK_SELF="${BASH_SOURCE[0]}"
_TOK_CACHE_FMT=1  # bump when the worker's bash side changes what an entry holds; the jq programs are checksummed
_TOK_WORK=""
_TOK_SINCE=""
_TOK_LOOKBACK=""
_TOK_TTL_1H=3600  # 1h cache TTL; also how far before the window rebuild detection looks for a predecessor
_TOK_NOCACHE=0
_TOK_VIEW=""
_TOK_TOP=10
_TOK_TZOFF=0
_TOK_JQ_LOCAL='def lfmt($f; $tz): (. + $tz) | strftime($f);'
trap '[ -z "$_TOK_WORK" ] || command rm -rf "$_TOK_WORK"' EXIT

_tok_usage() {
    cat <<'USAGE'
Usage: rdf tokens [options]

Local token usage report from Claude Code transcripts and Codex CLI rollouts:
deduplicated usage, list-price cost, and breakdowns by cost class, model,
agent, context depth, subagent boot cost, cache rebuilds and effort; for Codex
also by kind (review = read-only sandbox, write) and the plan quota peak.
With no tool option the report covers Claude Code and, when the scope has
Codex usage, Codex too, with a combined total and the top sessions.

Scope:
  --project DIR      project directory (default: current directory)
  --all              every project, with a by-project breakdown
  --session ID       one session and its subagents, found under any project
                     (ignores the window): a Claude Code id, else a Codex id
  --transcripts DIR  Claude Code transcript directory (implies --claude)
  --days N           window: last N days (default 30)
  --since YYYY-MM-DD window start, UTC midnight (overrides --days)

Tools (Claude Code counts sessions started in the project directory, Codex
counts rollouts whose cwd is the project, below it, or one of the project's
Claude Code scratchpads; the Codex plan quota peak is account-wide):
  --claude           Claude Code transcripts only
  --codex            Codex CLI rollouts only

Views:
  --by VIEW          a table instead of the full report: day, week or month
                     (local time; with jq 1.5, today's UTC offset), session
                     (top sessions by cost) or project (implies --all)
  --top N            rows in the --by session and by-project tables (default
                     10; the full report lists at most 5 sessions)

Output:
  --json             full JSON report
  --summary          compact JSON object for session logs
  --pricing          print the embedded price table, its date and sources
  --no-cache         neither read nor write the row cache
  help               this text

Environment:
  RDF_CLAUDE_PROJECTS  transcript root (default: $CLAUDE_CONFIG_DIR/projects,
                       else ~/.claude/projects)
  CODEX_HOME           Codex home (default: ~/.codex); sessions/ and
                       archived_sessions/ are read
  RDF_TOKENS_CACHE     row cache (default: ~/.rdf/cache/tokens); holds usage
                       metadata (token counts, ids, models, effort, timestamps,
                       paths, Codex quota samples), never message content, and
                       is safe to delete
  RDF_TOKENS_JOBS      parallel extraction workers (default: CPU count)

Prices are list prices copied from the Anthropic and OpenAI pricing pages
(see --pricing for the date and links), applied as API-equivalent estimates;
subscription plans bill differently. Fast mode, the Haiku 5.5 long-prompt tier
and US data residency are priced when transcripts record them. Transcripts and
rollouts are read locally; nothing is sent anywhere.
Known limitation: --session on a resumed or forked session includes the
history it copied from its parent.
USAGE
}

_tok_die() {
    printf 'rdf-tokens: error: %s\n' "$1" >&2
    exit "${2:-1}"
}

# _tok_slug dir — Claude Code project-directory slug
_tok_slug() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9-]/-/g'
}

# _tok_find_dir project — transcripts dir for a project, logical path first; returns 1 with the reason on stdout
_tok_find_dir() {
    local project="$1" logical physical a b
    logical="$(cd "$project" 2>/dev/null && pwd)" || { printf 'no such directory: %s' "$project"; return 1; }  # unreadable dir reported as missing
    physical="$(cd "$project" && pwd -P)" || { printf 'no such directory: %s' "$project"; return 1; }
    a="${RDF_CLAUDE_PROJECTS}/$(_tok_slug "$logical")"
    b="${RDF_CLAUDE_PROJECTS}/$(_tok_slug "$physical")"
    if [ -d "$a" ]; then
        printf '%s' "$a"
    elif [ -d "$b" ]; then
        printf '%s' "$b"
    else
        printf 'no transcripts for %s (looked in %s and %s)' "$logical" "$a" "$b"
        return 1
    fi
}

# _tok_prices — USD-per-MTok list prices copied from the sources below; /r-env diffs them against the live pages
_tok_prices() {
    cat <<'JSON'
{"as_of": "2026-10-24",
 "sources": {"anthropic": "https://platform.claude.com/docs/en/about-claude/pricing",
             "openai": "https://developers.openai.com/api/docs/pricing",
             "codex_plans": "https://developers.openai.com/codex/pricing"},
 "anthropic": {
  "claude-fable-5-1":  {"in": 10, "out": 50, "cw5": 12.5, "cw1h": 20, "cr": 0.25, "residency": true},
  "claude-mythos-5-1": {"in": 10, "out": 50, "cw5": 12.5, "cw1h": 20, "cr": 0.25, "residency": true},
  "claude-fable-5":    {"in": 10, "out": 50, "cw5": 12.5, "cw1h": 20, "cr": 1, "residency": true},
  "claude-mythos-5":   {"in": 10, "out": 50, "cw5": 12.5, "cw1h": 20, "cr": 1, "residency": true},
  "claude-opus-5-5":   {"in": 4, "out": 20, "cw5": 5, "cw1h": 8, "cr": 0.2, "fast": {"in": 8, "out": 40}, "residency": true},
  "claude-opus-5":     {"in": 5, "out": 25, "cw5": 6.25, "cw1h": 10, "cr": 0.5, "fast": {"in": 10, "out": 50}, "residency": true},
  "claude-opus-4-8":   {"in": 5, "out": 25, "cw5": 6.25, "cw1h": 10, "cr": 0.5, "fast": {"in": 10, "out": 50}, "residency": true},
  "claude-opus-4-7":   {"in": 5, "out": 25, "cw5": 6.25, "cw1h": 10, "cr": 0.5, "residency": true},
  "claude-opus-4-6":   {"in": 5, "out": 25, "cw5": 6.25, "cw1h": 10, "cr": 0.5, "residency": true},
  "claude-opus-4-5":   {"in": 5, "out": 25, "cw5": 6.25, "cw1h": 10, "cr": 0.5},
  "claude-opus-4-1":   {"in": 15, "out": 75, "cw5": 18.75, "cw1h": 30, "cr": 1.5},
  "claude-opus-4":     {"in": 15, "out": 75, "cw5": 18.75, "cw1h": 30, "cr": 1.5},
  "claude-sonnet-5-5": {"in": 2, "out": 10, "cw5": 2.5, "cw1h": 4, "cr": 0.1, "residency": true},
  "claude-sonnet-5":   {"in": 2, "out": 10, "cw5": 2.5, "cw1h": 4, "cr": 0.2, "residency": true},
  "claude-sonnet-4-6": {"in": 3, "out": 15, "cw5": 3.75, "cw1h": 6, "cr": 0.3, "residency": true},
  "claude-sonnet-4-5": {"in": 3, "out": 15, "cw5": 3.75, "cw1h": 6, "cr": 0.3},
  "claude-sonnet-4":   {"in": 3, "out": 15, "cw5": 3.75, "cw1h": 6, "cr": 0.3},
  "claude-haiku-5-5":  {"in": 0.1, "out": 0.5, "cw5": 0.125, "cw1h": 0.2, "cr": 0.01, "residency": true,
                        "long": {"over": 100000, "in": 0.5, "out": 2.5, "cw5": 0.625, "cw1h": 1, "cr": 0.05}},
  "claude-haiku-4-5":  {"in": 1, "out": 5, "cw5": 1.25, "cw1h": 2, "cr": 0.1},
  "claude-3-5-haiku":  {"in": 0.8, "out": 4, "cw5": 1, "cw1h": 1.6, "cr": 0.08}},
 "openai_long_over": 272000,
 "openai": {
  "gpt-6-astra":   {"in": 10, "out": 50, "cr": 1, "cw": 12.5, "long": {"in": 20, "out": 75, "cr": 2, "cw": 25},
                    "fast": {"in": 20, "out": 100, "cr": 2, "cw": 25, "long": {"in": 40, "out": 150, "cr": 4, "cw": 50}}},
  "gpt-6.1-sol":   {"in": 2, "out": 10, "cr": 0.1, "cw": 2.5, "long": {"in": 4, "out": 15, "cr": 0.2, "cw": 5},
                    "fast": {"in": 4, "out": 20, "cr": 0.2, "cw": 5, "long": {"in": 8, "out": 30, "cr": 0.4, "cw": 10}}},
  "gpt-6-sol":     {"in": 2, "out": 10, "cr": 0.2, "cw": 2.5, "long": {"in": 4, "out": 15, "cr": 0.4, "cw": 5},
                    "fast": {"in": 4, "out": 20, "cr": 0.4, "cw": 5, "long": {"in": 8, "out": 30, "cr": 0.8, "cw": 10}}},
  "gpt-6-luna":    {"in": 0.1, "out": 0.5, "cr": 0.01, "cw": 0.125, "long": {"in": 0.2, "out": 0.75, "cr": 0.02, "cw": 0.25},
                    "fast": {"in": 0.2, "out": 1, "cr": 0.02, "cw": 0.25, "long": {"in": 0.4, "out": 1.5, "cr": 0.04, "cw": 0.5}}},
  "gpt-5.6-sol":   {"in": 4, "out": 20, "cr": 0.4, "cw": 5, "long": {"in": 8, "out": 30, "cr": 0.8, "cw": 10},
                    "fast": {"in": 8, "out": 40, "cr": 0.8, "cw": 10, "long": {"in": 16, "out": 60, "cr": 1.6, "cw": 20}},
                    "until": "2026-11-21"},
  "gpt-5.6-terra": {"in": 2, "out": 12, "cr": 0.2, "cw": 2.5, "long": {"in": 4, "out": 18, "cr": 0.4, "cw": 5},
                    "fast": {"in": 4, "out": 24, "cr": 0.4, "cw": 5, "long": {"in": 8, "out": 36, "cr": 0.8, "cw": 10}}},
  "gpt-5.6-luna":  {"in": 0.2, "out": 1.2, "cr": 0.02, "cw": 0.25, "long": {"in": 0.4, "out": 1.8, "cr": 0.04, "cw": 0.5},
                    "fast": {"in": 0.4, "out": 2.4, "cr": 0.04, "cw": 0.5, "long": {"in": 0.8, "out": 3.6, "cr": 0.08, "cw": 1}}},
  "gpt-5.6-cyber": {"in": 12.5, "out": 75, "cr": 1.25, "cw": 15.625},
  "gpt-5.5":       {"in": 5, "out": 30, "cr": 0.5, "long": {"in": 10, "out": 45, "cr": 1}, "fast": {"in": 12.5, "out": 75, "cr": 1.25}},
  "gpt-5.4":       {"in": 2.5, "out": 15, "cr": 0.25, "long": {"in": 5, "out": 22.5, "cr": 0.5}, "fast": {"in": 5, "out": 30, "cr": 0.5}},
  "gpt-5.3-codex": {"in": 1.75, "out": 14, "cr": 0.175, "fast": {"in": 3.5, "out": 28, "cr": 0.35}},
  "gpt-5.2":       {"in": 1.75, "out": 14, "cr": 0.175, "fast": {"in": 3.5, "out": 28, "cr": 0.35}},
  "gpt-5.1":       {"in": 1.25, "out": 10, "cr": 0.125, "fast": {"in": 2.5, "out": 20, "cr": 0.25}},
  "gpt-5":         {"in": 1.25, "out": 10, "cr": 0.125, "fast": {"in": 2.5, "out": 20, "cr": 0.25}}}}
JSON
}

# jq helpers shared by the reports. pkey: longest key that is the id itself or the id less a date, @version or
# -vN suffix, so an unlisted newer model reports unpriced instead of borrowing a sibling's price
_TOK_JQ_DEFS='
    def r4: (. * 10000 + 0.5 | floor) / 10000;
    def usd: (. * 100 + 0.5 | floor) as $c
        | "\($c / 100 | floor).\(($c % 100) | tostring | if length == 1 then "0" + . else . end)";
    def pct: (. * 1000 + 0.5 | floor) as $t | "\($t / 10 | floor).\($t % 10)";
    def digits: length > 0 and (explode | all(. >= 48 and . <= 57));
    def idsuffix: . == "" or startswith("@")
        or (startswith("-v") and (.[2:3] | digits))
        or (startswith("-20") and ((length >= 9 and (.[1:9] | digits))
            or ((.[1:5] | digits) and .[5:6] == "-" and (.[6:8] | digits) and .[8:9] == "-" and (.[9:11] | digits))));
    def pkey($m; $tbl): ($m | if endswith("[1m]") then .[0:(length - 4)] else . end) as $s
        | ([$tbl | keys[]] | sort_by(length) | reverse
           | map(select(. as $k | ($s | startswith($k)) and ($s[($k | length):] | idsuffix))))
        | .[0];
    # [seconds, fraction] of a UTC "Z" timestamp, else null; fromdateiso8601 rejects fractions and normalizes Feb 30
    def epoch: if endswith("Z") and length >= 20 then
            (.[0:19] + "Z") as $w | (($w | fromdateiso8601?) // null) as $s
            | (if length == 20 then 0 elif .[19:20] == "." then (("0" + .[19:(length - 1)] | tonumber?) // null)
               else null end) as $f
            | if $s == null or ($s | todate) != $w or $f == null or $f >= 1 then null else [$s, $f] end
        else null end;
    def bucket($v; $tz): (.ts | epoch) as $e
        | if $e == null then "unknown"
          else ($e[0] | lfmt("%Y-%m-%d"; $tz)) as $d
            | if $v == "day" then $d
              elif $v == "week" then (($d + "T00:00:00Z" | fromdateiso8601) / 86400 | floor) as $n
                | ($n - (($n + 3) % 7)) * 86400 | strftime("%Y-%m-%d")
              else $d[0:7] end end;
    def slug: explode | map(if (. >= 48 and . <= 57) or (. >= 65 and . <= 90) or (. >= 97 and . <= 122) or . == 45
                            then . else 45 end) | implode;
    def series($v; $tz): if $v == "day" or $v == "week" or $v == "month"
        then {("by_" + $v): (map(. + {b: bucket($v; $tz)}) | group_by(.b)
              | map({key: .[0].b, sessions: ([.[].sk] | unique | length), turns: length,
                     cost_usd: ([.[].c] | add | r4)}))}
        else {} end;
    def topmodel: group_by(.model) | map({m: .[0].model, c: ([.[].c] | add)}) | max_by(.c) | .m;
'

# worker programs read "[k]" file markers, each file's grep-filtered lines and a closing "[-1]"; they print "k<TAB>row".
# One message's consecutive entries merge into one row; tss and parts let the report split a window straddler exactly
_TOK_JQ_CLAUDE_ROWS='
    def fin: if (.l | length) == 1 then .l[0]
        else .l as $l | ($l | min_by(.ts)) as $b | ($l | max_by(.ts)) as $e
          | {in: ([$l[].in] | max), cw5: ([$l[].cw5] | max), cw1h: ([$l[].cw1h] | max), cr: ([$l[].cr] | max),
             out: ([$l[].out] | max), th: ([$l[].th] | max)} as $mx
          | $b + $mx + {te: $e.ts, tss: ([$l[].ts] | unique)}
          + (if $e.in == $mx.in and $e.cw5 == $mx.cw5 and $e.cw1h == $mx.cw1h and $e.cr == $mx.cr
                and $e.out == $mx.out and $e.th == $mx.th then {}
             else {parts: [$l[] | [.ts, .in, .cw5, .cw1h, .cr, .out, .th]]} end) end;
    def row($k; $a): select((.message | type) == "object" and ((.timestamp // "") | type) == "string")
        | select(.type == "assistant"
            and ((.message.id // "") != "")
            and ((.message.usage | type) == "object")
            and (.message.model != "<synthetic>"))
        | .message.usage as $u
        | {id: .message.id, ts: (.timestamp // ""), file: $paths[$k], agent: $a,
           sid: (.sessionId // ""), cwd: (.cwd // "" | tostring),
           model: (.message.model // "unknown" | tostring),
           eff: (.effort // .perTurnEffort // "unset"),
           speed: ($u.speed // "standard"), geo: ($u.inference_geo // ""),
           in: ($u.input_tokens // 0), cr: ($u.cache_read_input_tokens // 0),
           out: ($u.output_tokens // 0),
           th: ($u.output_tokens_details.thinking_tokens // 0),
           cw5: (if ($u.cache_creation | type) == "object"
                 then ($u.cache_creation.ephemeral_5m_input_tokens // 0)
                 else ($u.cache_creation_input_tokens // 0) end),
           cw1h: (if ($u.cache_creation | type) == "object"
                  then ($u.cache_creation.ephemeral_1h_input_tokens // 0)
                  else 0 end)};
    foreach (inputs | fromjson?) as $x ({k: null, a: null, cur: null, emit: null};
        if ($x | type) == "array" and ($x | length) == 1 and ($x[0] | type) == "number" then {k: $x[0], a: null, cur: null, emit: .cur}
        elif ($x | type) == "array" and ($x | length) == 2 and $x[0] == "m" then
            .emit = null
            | .a = ($x[1] | if type == "object" then (.agentType // "unknown") | tostring else "unknown" end)
        elif ($x | type) == "object" and .k != null then
            . as $s | ([$x | row($s.k; $s.a)] | .[0]) as $r
            | if $r == null then .emit = null
              elif .cur != null and (.cur.l[0] | [.id, .model, .speed, .geo, .eff, .sid, .cwd, .agent])
                                      == ($r | [.id, .model, .speed, .geo, .eff, .sid, .cwd, .agent])
                then .emit = null | .cur.l += [$r]
              else .emit = .cur | .cur = {k: .k, l: [$r]} end
        else .emit = null end;
        .emit | select(. != null) | "\(.k)\t\(fin | tojson)")
'

_TOK_JQ_CODEX_DEFS='
    def n: if type == "number" and . > 0 then . else 0 end;
    def usage: {in: (.input_tokens | n), cr: (.cached_input_tokens | n), cw: (.cache_write_input_tokens | n),
                out: (.output_tokens | n), rs: (.reasoning_output_tokens | n)};
'

# one row per model response (sources and attribution: spec §4) plus {q: sample} quota rows; scope and window
# are the report's, so one entry serves any project and window
_TOK_JQ_CODEX_ROWS='
    reduce (inputs | fromjson?) as $x ([];
        if ($x | type) == "array" and ($x | length) == 1 and ($x[0] | type) == "number" then . + [{k: $x[0], l: []}]
        elif ($x | type) == "object" and length > 0 then .[length - 1].l += [$x]
        else . end)
    | .[] | .k as $k | .l as $l
    | ([$l[] | select(.type == "session_meta") | .payload | select(type == "object")] | .[0] // {}) as $m
    | (($m.source // {}) | if type == "object" then (.subagent // null) else null end
       | if type == "object" then (.thread_spawn.parent_thread_id // null) else null end) as $parent
    | (($m.source // "") | if type == "object" and has("subagent") then "sub" else "main" end) as $role
    | ([$l[] | select(.type == "token_usage_record")] | length > 0) as $per_response
    | (reduce ($l[] | select(.type == "turn_context" or .type == "token_usage_record"
                             or (.type == "event_msg" and (.payload | type) == "object"
                                 and (.payload.type == "thread_settings_applied" or .payload.type == "token_count")))) as $e
        ({model: "unknown", tier: "standard", effort: "unset",
          kind: (($m.source // "") | if type == "object" and .subagent == "review" then "review" else "other" end),
          prev: null, rows: []};
         if $e.type == "turn_context" then .model = ($e.payload.model // .model | tostring)
             | .effort = ($e.payload.effort // ($e.payload.collaboration_mode.settings.reasoning_effort)? // .effort
                          | tostring)
             | .kind = ((($e.payload.sandbox_policy.type)? // null
                         | if . == "read-only" then "review"
                           elif . == "workspace-write" or . == "danger-full-access" then "write" else null end) // .kind)
         elif $e.payload.type == "thread_settings_applied" then
             .model = ($e.payload.thread_settings.model // .model | tostring)
             | .tier = ($e.payload.thread_settings.service_tier // "standard" | tostring
                        | if . == "priority" or . == "fast" then "fast"
                          elif . == "standard" or . == "default" or . == "auto" or . == "" then "standard"
                          else . end)
         elif $e.type == "token_usage_record" then
             if ($e.payload.usage | type) == "object" then
                 .rows += [($e.payload.usage | usage)
                           + {rid: ($e.payload.response_id // null), ts: ($e.timestamp // "" | tostring),
                              model: .model, tier: .tier, effort: .effort, kind: .kind}]
             else . end
         elif $per_response or ($e.payload.info.total_token_usage | type) != "object" then .
         else ($e.payload.info.total_token_usage | usage) as $t
           | (if .prev == null or ($t.in + $t.out) < (.prev.in + .prev.out) then $t
              else {in: ($t.in - .prev.in | n), cr: ($t.cr - .prev.cr | n), cw: ($t.cw - .prev.cw | n),
                    out: ($t.out - .prev.out | n), rs: ($t.rs - .prev.rs | n)} end) as $d
           | .rows += [$d + {rid: null, ts: ($e.timestamp // "" | tostring), model: .model, tier: .tier,
                             effort: .effort, kind: .kind}]
           | .prev = $t
         end)
      | .rows[]
      | select(.in + .out > 0)
      | "\($k)\t\(. + {sid: ($m.id // "" | tostring), parent: $parent, cwd: ($m.cwd // "" | tostring),
                       role: $role, file: $paths[$k]} | tojson)"),
      ($l[] | select(.type == "event_msg" and (.payload | type) == "object" and .payload.type == "token_count"
                     and (.payload.rate_limits | type) == "object")
       | (.timestamp // "" | tostring) as $ts | .payload.rate_limits as $r
       | ($r.primary, $r.secondary) | select(type == "object" and (.window_minutes | type) == "number")
       | "\($k)\t\({q: {ts: $ts, win: .window_minutes, pct: (.used_percent // 0), resets: (.resets_at // 0),
                        plan: ($r.plan_type // null), reached: ($r.rate_limit_reached_type != null)}} | tojson)")
'

# _tok_window days since — sets _TOK_SINCE, _TOK_LOOKBACK and the mtime-prefilter ref file
_tok_window() {
    local days="$1" since="$2" e now ref
    if [ -n "$since" ]; then
        _TOK_SINCE="${since}T00:00:00Z"
        e="$(jq -n --arg s "$_TOK_SINCE" '$s | fromdateiso8601 | if (todate[0:10]) == ($s[0:10]) then . else error("date") end' 2>/dev/null)" || _tok_die "--since expects a valid YYYY-MM-DD date" 2  # jq error or normalized date (2026-02-30) → usage error
    else
        now="$(command date +%s)"
        e=$(( now - days * 86400 ))
        _TOK_SINCE="$(jq -nr --argjson e "$e" '$e | todate')"
    fi
    _TOK_LOOKBACK="$(jq -nr --argjson e "$(( e - _TOK_TTL_1H ))" '$e | todate')"
    ref="$(jq -nr --argjson e "$(( e - 86400 ))" '$e | strftime("%Y%m%d%H%M")')"
    command touch -t "$ref" "${_TOK_WORK}/ref"
}

# _tok_clock — stamp file 2 s in the past (a source newer than it after the read leaves its entry stale, even where
# -nt compares whole seconds) and _TOK_TZOFF, the local UTC offset in seconds
_tok_clock() {
    local t s z
    t=$(( $(command date +%s) - 2 ))
    s="$(command date -d "@${t}" '+%Y%m%d%H%M.%S' 2>/dev/null || command date -r "$t" '+%Y%m%d%H%M.%S')"  # GNU date, else BSD date
    command touch -t "$s" "${_TOK_WORK}/stamp"
    z="$(command date +%z)"
    case "$z" in
        [+-][0-9][0-9][0-9][0-9])
            _TOK_TZOFF=$(( 10#${z:1:2} * 3600 + 10#${z:3:2} * 60 ))
            [ "${z:0:1}" = "+" ] || _TOK_TZOFF=$(( 0 - _TOK_TZOFF ))
            ;;
    esac
}

# _tok_jobs — worker count: RDF_TOKENS_JOBS, else the online CPU count
_tok_jobs() {
    local n="${RDF_TOKENS_JOBS:-}"
    [ -n "$n" ] || n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '4')"  # getconf lacks the name → 4
    case "$n" in
        ''|*[!0-9]*|0) n=4 ;;
    esac
    printf '%s' "$n"
}

# _tok_cache_dir kind — entry root named by a checksum of the extraction program (a changed program never reads
# old entries; roots unused for a week are pruned); the work dir stands in when caching is off or impossible
_tok_cache_dir() {
    local kind="$1" prog sum d old
    if [ "$_TOK_NOCACHE" -eq 0 ]; then
        if [ "$kind" = codex ]; then prog="${_TOK_JQ_CODEX_DEFS}${_TOK_JQ_CODEX_ROWS}"; else prog="$_TOK_JQ_CLAUDE_ROWS"; fi
        sum="$(printf '%s%s' "$_TOK_CACHE_FMT" "$prog" | command cksum)"
        d="${RDF_TOKENS_CACHE}/${kind}-${sum%% *}"
        if ( command mkdir -p "$d" ) 2>/dev/null && [ -w "$d" ]; then  # subshell: bash 3.2 set -e exits on a failing command builtin; unwritable → work dir
            command touch "${d}/.rdf-tokens"
            for old in "${RDF_TOKENS_CACHE}/${kind}-"*; do
                if [ "$old" != "$d" ] && [ -f "${old}/.rdf-tokens" ] && [ -n "$(find "${old}/.rdf-tokens" -mtime +7)" ]; then
                    command rm -rf "$old"  # a root another version used this week stays
                fi
            done
            printf '%s' "$d"
            return 0
        fi
        printf 'rdf-tokens: warning: cache %s is not writable; reading without it\n' "$RDF_TOKENS_CACHE" >&2
    fi
    d="${_TOK_WORK}/cache/${kind}"
    command mkdir -p "$d"
    printf '%s' "$d"
}

# _tok_worker kind cdir stamp file... — extract each source file's rows into its cache entry (xargs runs batches)
_tok_worker() {
    local kind="$1" cdir="$2" stamp="$3" tmp k=0 f m meta prog="" e defs="" body
    local -a args
    shift 3
    args=()
    tmp="$(command mktemp -d "${cdir}/.w.XXXXXX")"
    _TOK_WORK="$tmp"
    for f in "$@"; do
        args+=(--arg "p${k}" "$f")
        prog="${prog}\$p${k},"
        : > "${tmp}/${k}"
        ( command touch -r "$f" "${tmp}/${k}.m" ) 2>/dev/null || true  # source gone → no mtime → entry stays stale
        m="${f%.jsonl}.meta.json"
        case "$f" in
            */subagents/*) [ ! -f "$m" ] || ( command touch -r "$m" "${tmp}/${k}.mm" ) 2>/dev/null || true ;;  # meta gone mid-run → no sidecar → stale
        esac
        k=$((k + 1))
    done
    if [ "$kind" = codex ]; then defs="$_TOK_JQ_CODEX_DEFS"; body="$_TOK_JQ_CODEX_ROWS"; else body="$_TOK_JQ_CLAUDE_ROWS"; fi
    k=0
    { for f in "$@"; do
        printf '[%s]\n' "$k"
        if [ "$kind" = codex ]; then
            LC_ALL=C grep -aF -e '"type":"session_meta"' -e '"type":"turn_context"' -e '"type":"token_usage_record"' \
                -e '"type":"thread_settings_applied"' -e '"type":"token_count"' -- "$f" || true  # no record lines, or the rollout vanished → no rows
        else
            case "$f" in
                */subagents/*)
                    m="${f%.jsonl}.meta.json"
                    if [ -f "$m" ]; then
                        meta=""
                        IFS= read -r -d '' meta < "$m" 2>/dev/null || true  # read ends at EOF, not a NUL; unreadable → agent unknown
                        printf '["m",%s]\n' "${meta//$'\n'/ }"
                    fi
                    ;;
            esac
            LC_ALL=C grep -aF '"usage"' -- "$f" || true  # no usage line, or the transcript vanished → no rows
        fi
        k=$((k + 1))
    done; printf '[-1]\n'; } | jq -nrR "${args[@]}" "${defs} [${prog%,}] as \$paths | ${body}" \
        | D="$tmp" command awk 'BEGIN { FS = "\t"; c = "-" }
            { if ($1 != c) { if (c != "-") close(ENVIRON["D"] "/" c); c = $1 }
              print substr($0, length($1) + 2) > (ENVIRON["D"] "/" c) }'
    k=0
    for f in "$@"; do
        e="${cdir}${f}.rows"
        m="${f%.jsonl}.meta.json"
        if [ -f "${tmp}/${k}.m" ] && ! [ "$f" -nt "$stamp" ] && { [ ! -f "$m" ] || ! [ "$m" -nt "$stamp" ]; }; then
            command touch -r "${tmp}/${k}.m" "${tmp}/${k}"
        else
            command touch -t 197001020000 "${tmp}/${k}"
        fi
        [ -d "${e%/*}" ] || command mkdir -p "${e%/*}"
        command mv -f "${tmp}/${k}" "$e"
        if [ -f "${tmp}/${k}.mm" ]; then
            command mv -f "${tmp}/${k}.mm" "${e}.meta"
        elif [ -e "${e}.meta" ]; then
            command rm -f "${e}.meta"
        fi
        k=$((k + 1))
    done
}

# _tok_fresh source entry — the entry's mtime equals the source's and, for a subagent, its meta's mtime equals the
# entry's .meta sidecar (no meta, no sidecar)
_tok_fresh() {
    local f="$1" e="$2" m
    [ -f "$e" ] && ! [ "$f" -nt "$e" ] && ! [ "$f" -ot "$e" ] || return 1
    case "$f" in
        */subagents/*)
            m="${f%.jsonl}.meta.json"
            if [ -f "$m" ]; then
                [ -f "${e}.meta" ] && ! [ "$m" -nt "${e}.meta" ] && ! [ "$m" -ot "${e}.meta" ]
            else
                [ ! -e "${e}.meta" ]
            fi
            return
            ;;
    esac
    return 0
}

# _tok_extract kind — ${_TOK_WORK}/rows from every listed source's cache entry, re-extracting stale ones in parallel
_tok_extract() {
    local kind="$1" cdir f e n=0 jobs batch
    cdir="$(_tok_cache_dir "$kind")"
    : > "${_TOK_WORK}/rows"
    [ -s "${_TOK_WORK}/files" ] || return 0
    {
        while IFS= read -r -d '' f; do
            e="${cdir}${f}.rows"
            printf '%s\0' "$e" >&3
            if ! _tok_fresh "$f" "$e"; then
                printf '%s\0' "$f"
                n=$((n + 1))
            fi
        done < "${_TOK_WORK}/files"
    } > "${_TOK_WORK}/miss" 3> "${_TOK_WORK}/entries"
    if [ "$n" -gt 0 ]; then
        jobs="$(_tok_jobs)"
        [ "$jobs" -le "$n" ] || jobs="$n"
        batch=$(( (n + jobs * 4 - 1) / (jobs * 4) ))
        [ "$batch" -le 64 ] || batch=64
        xargs -0 -n "$batch" -P "$jobs" bash "$_TOK_SELF" __worker "$kind" "$cdir" "${_TOK_WORK}/stamp" \
            < "${_TOK_WORK}/miss" || _tok_die "row extraction failed (see the errors above)" 1
    fi
    xargs -0 cat < "${_TOK_WORK}/entries" > "${_TOK_WORK}/rows"
}

# _tok_files tdir sid all — NUL list of transcript paths into ${_TOK_WORK}/files; --all reads each project dir
# once by its physical path, so a symlinked alias of another project is not read twice
_tok_files() {
    local tdir="$1" sid="$2" all="$3" out="${_TOK_WORK}/files" main="" f d seen=""
    local -a dirs
    if [ -n "$sid" ]; then
        for f in "${RDF_CLAUDE_PROJECTS}"/*/"${sid}.jsonl"; do
            [ -f "$f" ] && { main="$f"; break; }
        done
        [ -n "$main" ] || _tok_die "no transcript for session ${sid} under ${RDF_CLAUDE_PROJECTS}" 1
        case "$main" in /*) ;; *) main="${PWD}/${main}" ;; esac
        {
            printf '%s\0' "$main"
            if [ -d "${main%.jsonl}/subagents" ]; then
                find "${main%.jsonl}/subagents" -name 'agent-*.jsonl' -type f -print0
            fi
        } > "$out"
    elif [ "$all" -eq 1 ]; then
        dirs=()
        for f in "$tdir"/*/; do
            d="$(cd "$f" 2>/dev/null && pwd -P)" || continue  # dangling or unreadable project dir → skipped
            case "$seen" in *$'\034'"${d}"$'\034'*) continue ;; esac
            seen="${seen}"$'\034'"${d}"$'\034'
            dirs+=("$d")
        done
        : > "$out"
        if [ "${#dirs[@]}" -gt 0 ]; then
            {
                find "${dirs[@]}" -maxdepth 1 -name '*.jsonl' -type f -newer "${_TOK_WORK}/ref" -print0
                find "${dirs[@]}" -mindepth 3 -path '*/subagents/*' -name 'agent-*.jsonl' -type f -newer "${_TOK_WORK}/ref" -print0
            } > "$out"
        fi
    else
        {
            find -H "$tdir" -maxdepth 1 -name '*.jsonl' -type f -newer "${_TOK_WORK}/ref" -print0
            find -H "$tdir" -mindepth 3 -path '*/subagents/*' -name 'agent-*.jsonl' -type f -newer "${_TOK_WORK}/ref" -print0
        } > "$out"
    fi
}

# _tok_report label sid tdir root — dedup, price and aggregate Claude rows into one JSON object (root set: --all)
_tok_report() {
    local plabel="$1" sid="$2" tdir="$3" root="$4"
    jq -s -c --argjson prices "$(_tok_prices | jq -c .anthropic)" \
        --arg plabel "$plabel" --arg sid "$sid" --arg since "$_TOK_SINCE" --arg lookback "$_TOK_LOOKBACK" \
        --arg tdir "$tdir" --arg root "$root" --argjson ttl_1h "$_TOK_TTL_1H" \
        --arg view "$_TOK_VIEW" --argjson top "$_TOK_TOP" --argjson tz "$_TOK_TZOFF" "${_TOK_JQ_LOCAL}${_TOK_JQ_DEFS}"'
        def r1: (. * 10 + 0.5 | floor) / 10;
        def nr($p): length as $n
            | if $n == 0 then 0 else .[((0 - ((0 - ($p * $n)) | floor)) - 1)] end;
        def k: if . >= 1000 then (((. / 100) | floor) / 10 | tostring) + "K"
               else tostring end;
        # effective per-MTok rates for one turn: long-prompt tier, then fast mode (cache classes keep the
        # model ratios), then the 1.1x US data-residency multiplier
        def rates($p; $r): if ($r.speed != "fast" or $p.fast == null) and ($r.geo != "us" or $p.residency != true)
                               and $p.long == null then $p else
            ($r.in + $r.cw5 + $r.cw1h + $r.cr) as $prompt
            | (if $p.long != null and $prompt > $p.long.over then $p.long else $p end) as $b
            | (if $r.speed == "fast" and $p.fast != null
               then {in: $p.fast.in, out: $p.fast.out, cw5: ($p.fast.in * $b.cw5 / $b.in),
                     cw1h: ($p.fast.in * $b.cw1h / $b.in), cr: ($p.fast.in * $b.cr / $b.in)}
               else {in: $b.in, out: $b.out, cw5: $b.cw5, cw1h: $b.cw1h, cr: $b.cr} end) as $x
            | (if $r.geo == "us" and $p.residency == true then 1.1 else 1 end) as $g
            | {in: ($x.in * $g), out: ($x.out * $g), cw5: ($x.cw5 * $g), cw1h: ($x.cw1h * $g), cr: ($x.cr * $g)} end;
        def ttl_5m: 300;
        def rebuild_min_ctx: 50000;
        def rebuild_min_write_share: 0.5;
        def role_of: if contains("/subagents/") then "sub" else "main" end;
        def pdir: split("/subagents/") | .[0] | split("/") | .[0:(length - 1)] | join("/");
        # a merged message whose entries straddle the window or lookback start splits back into its entries
        def edge($t): $t != "" and (.ts[0:19]) < ($t[0:19]) and (.te[0:19]) >= ($t[0:19]);
        map(if .tss == null or ((edge($since) or edge($lookback)) | not) then .
            else . as $r
              | if .parts != null then (.parts[] | $r + {ts: .[0], in: .[1], cw5: .[2], cw1h: .[3], cr: .[4], out: .[5], th: .[6]})
                else (.tss[] | $r + {ts: .}) end end)
        | map(select((.ts[0:19]) >= ($lookback[0:19])) | . + {pre: ((.ts[0:19]) < ($since[0:19]))})
        | . as $raw
        | map(select(.pre != true))
        | group_by(.id)
        | map(if length == 1 then .[0]
              else sort_by(.ts) as $g
                | $g[0] + {in: ([$g[].in] | max), cw5: ([$g[].cw5] | max),
                           cw1h: ([$g[].cw1h] | max), cr: ([$g[].cr] | max),
                           out: ([$g[].out] | max), th: ([$g[].th] | max)} end)
        | (reduce ([.[].model] | unique)[] as $m ({}; .[$m] = pkey($m; $prices))) as $pks
        | map(. as $r
              | ($r.file | role_of) as $role
              | $pks[$r.model] as $pk
              | if $pk == null then
                  $r + {role: $role, sk: $r.sid, agent: (if $role == "main" then "main" else ($r.agent // "unknown") end),
                        priced: false, c_in: 0, c_cw: 0, c_cr: 0, c_out: 0, c: 0, c_rb: 0}
                else rates($prices[$pk]; $r) as $p
                  | ($r.in * $p.in / 1000000) as $ci
                  | (($r.cw5 * $p.cw5 + $r.cw1h * $p.cw1h) / 1000000) as $cw
                  | ($r.cr * $p.cr / 1000000) as $cr
                  | ($r.out * $p.out / 1000000) as $co
                  | $r + {role: $role, sk: $r.sid, agent: (if $role == "main" then "main" else ($r.agent // "unknown") end),
                          priced: true, c_in: $ci, c_cw: $cw, c_cr: $cr, c_out: $co, c: ($ci + $cw + $cr + $co),
                          c_rb: ($cw - ($r.cw5 + $r.cw1h) * $p.cr / 1000000)} end)
        | . as $rows
        | ([$rows[] | .c] | add // 0) as $total
        | (reduce $rows[] as $r ({}; .[$r.id | tostring] = $r)) as $byid
        # per-file sequences come from raw rows (window plus lookback): the shared dedup keeps a fork-copied turn in only one file
        | ([$raw | group_by(.file) | .[]
            | group_by(.id) | map(min_by(.ts)) | sort_by(.ts) as $f
            | range(1; $f | length) as $i
            | select($f[$i].pre != true)
            | $byid[$f[$i].id | tostring] as $c
            | ($c.cw5 + $c.cw1h) as $w | ($c.in + $w + $c.cr) as $n
            | ($f[$i - 1].ts | epoch) as $a | ($f[$i].ts | epoch) as $b
            | (if $a == null or $b == null then null else ($b[0] - $a[0]) + ($b[1] - $a[1]) end) as $gap
            | select($gap != null
                     and $gap > (if $c.cw1h > $c.cw5 then $ttl_1h else ttl_5m end)
                     and $n >= rebuild_min_ctx
                     and $w >= $n * rebuild_min_write_share)
            | {id: $c.id, file: $f[$i].file, role: ($f[$i].file | role_of), gap: $gap, w: $w, c: $c.c_rb}]
           | group_by(.id) | map(min_by([.role, .file]))) as $rb
        | ([$rows[] | select(.role == "main") | (.in + .cw5 + .cw1h + .cr)] | sort) as $ctx
        | ([$rows[] | select(.role == "sub")] | group_by(.file)
           | map(sort_by(.ts) | .[0] | (.cw5 + .cw1h)) | sort) as $boot
        | (if $root == "" then {}
           else ($rows | group_by(.file | pdir) | map((.[0].file | pdir) as $d | ($d | split("/") | last) as $dn
                 | [.[].cwd] as $cs
                 | {key: $d, value: (($cs | unique | map(split("/") as $p | [range(2; ($p | length) + 1) as $n
                                         | $p[0:$n] | join("/")][]) | unique | map(select(slug == $dn))
                                      | map(. as $a | {a: $a, n: ([$cs[] | select(. == $a or startswith($a + "/"))] | length)})
                                      | max_by(.n) | .a)
                                     // (group_by(.cwd) | max_by(length) | .[0].cwd))}) | from_entries) end) as $slugcwd
        | {scope: {project: $plabel, transcripts: (if $sid == "" then $tdir else null end),
                   since: (if $sid == "" then $since else null end),
                   session: (if $sid == "" then null else $sid end)},
           sessions: ([$rows[] | select(.role == "main") | .sid] | unique | length),
           api_turns: ($rows | length),
           main_turns: ([$rows[] | select(.role == "main")] | length),
           subagent_turns: ([$rows[] | select(.role == "sub")] | length),
           subagent_runs: ([$rows[] | select(.role == "sub") | .file] | unique | length),
           tokens: {input: ([$rows[].in] | add // 0), cache_write_5m: ([$rows[].cw5] | add // 0),
                    cache_write_1h: ([$rows[].cw1h] | add // 0), cache_read: ([$rows[].cr] | add // 0),
                    output: ([$rows[].out] | add // 0), thinking: ([$rows[].th] | add // 0)},
           cost_usd: ($total | r4),
           share: (if $total > 0 then
                     {input: (([$rows[].c_in] | add) / $total | r4),
                      cache_write: (([$rows[].c_cw] | add) / $total | r4),
                      cache_read: (([$rows[].c_cr] | add) / $total | r4),
                      output: (([$rows[].c_out] | add) / $total | r4)}
                   else {input: 0, cache_write: 0, cache_read: 0, output: 0} end),
           by_model: ($rows | group_by(.model)
                      | map({model: .[0].model, turns: length,
                             cost_usd: (if .[0].priced then ([.[].c] | add | r4) else null end)})
                      | sort_by(.cost_usd // -1) | reverse),
           by_agent: ($rows | group_by(.agent)
                      | map({agent: .[0].agent,
                             runs: (if .[0].agent == "main" then ([.[].sid] | unique | length)
                                    else ([.[].file] | unique | length) end),
                             turns: length, cost_usd: ([.[].c] | add | r4)})
                      | sort_by(.cost_usd) | reverse),
           main_context: {median: ($ctx | nr(0.5)), p90: ($ctx | nr(0.9)),
                          over_200k_pct: (if ($ctx | length) == 0 then 0
                                          else ([$ctx[] | select(. > 200000)] | length) * 100 / ($ctx | length) | r1 end)},
           subagent_boot: {median_cache_write: ($boot | nr(0.5)), runs: ($boot | length)},
           rebuilds: (([$rb[].c] | add // 0) as $rc
                      | {events: ($rb | length), tokens: ([$rb[].w] | add // 0), cost_usd: ($rc | r4),
                         share: (if $total > 0 then $rc / $total | r4 else 0 end),
                         median_gap_s: ([$rb[].gap] | sort | nr(0.5) | . + 0.5 | floor),
                         main: ([$rb[] | select(.role == "main")] | {events: length, cost_usd: ([.[].c] | add // 0 | r4)}),
                         sub: ([$rb[] | select(.role == "sub")] | {events: length, cost_usd: ([.[].c] | add // 0 | r4)})}),
           effort: ($rows | group_by(.eff) | map({key: .[0].eff, value: length}) | from_entries),
           unpriced_models: ([$rows[] | select(.priced | not) | .model] | unique),
           top_sessions: ($rows | group_by(.sk)
                          | map({tool: "claude", session: .[0].sk, start: ([.[].ts] | min), turns: length,
                                 cost_usd: ([.[].c] | add | r4), model: topmodel,
                                 cwd: (if $root == "" then null else $slugcwd[.[0].file | pdir] end),
                                 pdir: (if $root == "" then null else (.[0].file | pdir | split("/") | last) end)})
                          | sort_by(.cost_usd) | reverse | .[0:$top])}
        + (if $root == "" then {}
           else {by_project: ($rows | group_by(.file | pdir)
                 | map({cwd: $slugcwd[.[0].file | pdir], pdir: (.[0].file | pdir | split("/") | last),
                        sessions: ([.[] | select(.role == "main") | .sid] | unique | length),
                        turns: length, cost_usd: ([.[].c] | add | r4), _c: ([.[].c] | add)})
                 | sort_by(.cost_usd) | reverse)} end)
        + ($rows | series($view; $tz))
        | . as $R
        | . + {_total: $total,
               _head: (if $sid == "" then "rdf tokens — \($plabel) · since \($since) · list-price estimate"
                       else "rdf tokens — session \($sid) · list-price estimate" end),
               _sub: "sessions \($R.sessions) · api turns \($R.api_turns) (main \($R.main_turns) · subagents \($R.subagent_turns) in \($R.subagent_runs) runs)",
               _body: (if $R.api_turns == 0 then [] else [
                   "T\t\($total | usd)",
                   "S\tcache read\t\($R.share.cache_read | pct)\t\([$rows[].c_cr] | add | usd)",
                   "S\tcache write\t\($R.share.cache_write | pct)\t\([$rows[].c_cw] | add | usd)",
                   "S\toutput\t\($R.share.output | pct)\t\([$rows[].c_out] | add | usd)",
                   "S\tinput\t\($R.share.input | pct)\t\([$rows[].c_in] | add | usd)",
                   "B",
                   "MH",
                   ($R.by_model[] | "M\t\(.model)\t\(.turns)\t\(if .cost_usd == null then "unpriced" else (.cost_usd | usd) end)"),
                   "B",
                   "AH",
                   ($R.by_agent[] | "A\t\(.agent)\t\(.runs)\t\(.turns)\t\(.cost_usd | usd)"),
                   "B",
                   "H\tmain context/turn  median \($R.main_context.median | k) · p90 \($R.main_context.p90 | k) · >200K \($R.main_context.over_200k_pct)%",
                   "H\tsubagent boot      median \($R.subagent_boot.median_cache_write | k) cache-write tokens (\($R.subagent_boot.runs) runs)",
                   ($R.rebuilds | "H\tcache rebuilds     \(if .events == 0 then "none"
                       else "\(.events) (main \(.main.events) · sub \(.sub.events)) · $\(.cost_usd | usd) extra (\(.share | pct)% of spend) · median idle \(.median_gap_s / 60 | r1)m" end)"),
                   "H\teffort             \([$R.effort | to_entries | sort_by(.value) | reverse[] | "\(.key) \(.value)"] | join(" · "))",
                   (if ($R.unpriced_models | length) > 0 then "H\tunpriced models    \($R.unpriced_models | join(", "))" else empty end)
               ] end)}
    ' "${_TOK_WORK}/rows"
}

# _tok_codex_files sid — NUL list of rollouts naming sid, else every rollout in the window (the quota is
# account-wide; the report applies the project scope)
_tok_codex_files() {
    local sid="$1" r out="${_TOK_WORK}/files"
    : > "$out"
    for r in "${_TOK_CODEX}/sessions" "${_TOK_CODEX}/archived_sessions"; do
        [ -d "$r" ] || continue
        if [ -n "$sid" ]; then
            find -H "$r" -name 'rollout-*.jsonl' -type f \
                -exec grep -lF --null -e "\"id\":\"${sid}\"" -e "\"parent_thread_id\":\"${sid}\"" {} + >> "$out" || true  # grep exits 1 when no rollout names the id → empty list
        else
            find -H "$r" -name 'rollout-*.jsonl' -type f -newer "${_TOK_WORK}/ref" -print0 >> "$out"
        fi
    done
}

# _tok_codex_quota — plan quota from the samples of every rollout in the window (rate limits are per account); JSON or null
_tok_codex_quota() {
    jq -c --arg since "$_TOK_SINCE" 'select(.q != null) | .q | select(.ts[0:19] >= ($since[0:19]))' "${_TOK_WORK}/rows" \
        | jq -s -c '
            # resets_at jitters by seconds within one window; a re-login opens a second, overlapping window
            def windows: sort_by(.resets)
                | reduce .[] as $x ([];
                    if length > 0 and ($x.resets - .[length - 1].last) <= 3600
                    then (length - 1) as $i | .[$i].last = $x.resets | .[$i].peak = ([.[$i].peak, $x.pct] | max)
                    else . + [{last: $x.resets, peak: $x.pct}] end)
                | map({resets_at: (.last | todate), peak_pct: .peak});
            if length == 0 then null
            else sort_by(.ts) as $s
              | {scope: "account",
                 plan: ([$s[] | .plan | select(. != null)] | last),
                 limit_reached_events: ([$s[] | select(.reached) | .ts] | unique | length),
                 limits: ($s | group_by(.win)
                          | map({window_minutes: .[0].win, peak_pct: ([.[].pct] | max),
                                 latest_pct: (last | .pct), latest_at: (last | .ts), windows: windows}))}
            end'
}

# _tok_codex_report label sid logical physical all pinv ccwd quota — scope, dedup and price Codex rows into one JSON object
_tok_codex_report() {
    local plabel="$1" sid="$2" pl="$3" pp="$4" all=false pinv="$6" ccwd="$7" quota="$8"
    [ "$5" -eq 0 ] || all=true
    jq -s -c --argjson prices "$(_tok_prices | jq -c .openai)" \
        --argjson over "$(_tok_prices | jq -c .openai_long_over)" --argjson quota "$quota" \
        --arg plabel "$plabel" --arg sid "$sid" --arg pl "$pl" --arg pp "$pp" --argjson all "$all" \
        --argjson pinv "$pinv" --argjson ccwd "$ccwd" --arg since "$_TOK_SINCE" --arg root "${_TOK_CODEX}/sessions" \
        --arg view "$_TOK_VIEW" --argjson top "$_TOK_TOP" --argjson tz "$_TOK_TZOFF" "${_TOK_JQ_LOCAL}${_TOK_JQ_DEFS}"'
        def under($c; $p): $p != "" and ($c == $p or ($c | startswith($p + "/")));
        # tier rate (none for the tier → unpriced), then the per-request over-272K rate; absent cached/write rates bill at input
        def orates($p; $r): (if $r.tier == "standard" then $p elif $r.tier == "fast" then $p.fast else null end) as $t
            | if $t == null then null
              else (if $r.rid != null and $r.in > $over and $t.long != null then $t.long else $t end) as $x
                   | {in: $x.in, out: $x.out, cr: ($x.cr // $x.in), cw: ($x.cw // $x.in)} end;
        def wlabel: if . % 1440 == 0 then "\(. / 1440)-day" elif . % 60 == 0 then "\(. / 60)-hour"
                    else "\(.)-minute" end;
        ($pl | slug) as $sl | ($pp | slug) as $sp
        # project scope: the project dir or below it, or a path that names the project Claude Code slug (its scratchpads)
        | map(select(.q == null)
            | select(if $sid != "" then .sid == $sid or .parent == $sid
                     elif $all then true
                     else (.cwd as $c | under($c; $pl) or under($c; $pp)
                           or any($c | split("/")[]; . == $sl or . == $sp)) end)
            | select($sid != "" or ((.ts[0:19]) >= ($since[0:19]))))
        | ([.[] | select(.rid != null)] | group_by(.rid) | map(.[0])) + [.[] | select(.rid == null)]
        | (reduce ([.[].model] | unique)[] as $m ({}; .[$m] = pkey($m; $prices))) as $pks
        # in --all, a rollout belongs to its deepest ancestor that is a Claude Code project cwd in the window or whose
        # slug names a project dir, else to the project whose slug its path names (a scratchpad), else to its cwd
        | (if $all then (reduce ([.[].cwd] | unique)[] as $c ({};
               .[$c] = (($c | split("/")) as $p
                        | ([range(2; ($p | length) + 1) as $n | $p[0:$n] | join("/")
                            | select($ccwd[.] != null or $pinv[slug] != null)] | last) as $a
                        | if $a != null then {c: $a, d: ($ccwd[$a] // $pinv[$a | slug])}
                          else ([$p[] | select($pinv[.] != null)] | last) as $n
                            | if $n != null then {c: null, d: $pinv[$n]} else {c: $c, d: null} end end))) else {} end) as $pmap
        # cached and cache-write tokens are subsets of input_tokens; reasoning is a subset of output_tokens
        | map(. as $r
            | $pks[$r.model] as $pk
            | (if $pk == null then null else orates($prices[$pk]; $r) end) as $p
            | ([($r.in - $r.cr - $r.cw), 0] | max) as $u
            | $r + {unc: $u, priced: ($p != null), sk: ($r.parent // $r.sid),
                    c_in: (if $p == null then 0 else $u * $p.in / 1000000 end),
                    c_cr: (if $p == null then 0 else $r.cr * $p.cr / 1000000 end),
                    c_cw: (if $p == null then 0 else $r.cw * $p.cw / 1000000 end),
                    c_out: (if $p == null then 0 else $r.out * $p.out / 1000000 end)}
            | . + {c: (.c_in + .c_cr + .c_cw + .c_out)})
        | . as $rows
        | ([$rows[].c] | add // 0) as $total
        | {source: "codex",
           scope: {project: $plabel, sessions_dir: (if $sid == "" then $root else null end),
                   since: (if $sid == "" then $since else null end),
                   session: (if $sid == "" then null else $sid end)},
           sessions: ([$rows[] | select(.role == "main") | .sid] | unique | length),
           subagent_runs: ([$rows[] | select(.role == "sub") | .sid] | unique | length),
           api_turns: ($rows | length),
           tokens: {input: ([$rows[].unc] | add // 0), cached_input: ([$rows[].cr] | add // 0),
                    cache_write: ([$rows[].cw] | add // 0), output: ([$rows[].out] | add // 0),
                    reasoning: ([$rows[].rs] | add // 0)},
           cost_usd: ($total | r4),
           share: (if $total > 0 then
                     {input: (([$rows[].c_in] | add) / $total | r4),
                      cache_write: (([$rows[].c_cw] | add) / $total | r4),
                      cache_read: (([$rows[].c_cr] | add) / $total | r4),
                      output: (([$rows[].c_out] | add) / $total | r4)}
                   else {input: 0, cache_write: 0, cache_read: 0, output: 0} end),
           by_model: ($rows | group_by([.model, .tier])
                      | map({model: .[0].model, tier: .[0].tier, turns: length,
                             cost_usd: (if .[0].priced then ([.[].c] | add | r4) else null end)})
                      | sort_by(.cost_usd // -1) | reverse),
           # kind: review = read-only sandbox, write = workspace-write or full access; unpriced turns add $0
           by_kind: ($rows | group_by(.kind)
                     | map({kind: .[0].kind, runs: ([.[].sid] | unique | length), turns: length,
                            cost_usd: ([.[].c] | add | r4)})
                     | sort_by(.cost_usd) | reverse),
           by_effort: ($rows | group_by(.effort)
                       | map({effort: .[0].effort, turns: length, cost_usd: ([.[].c] | add | r4)})
                       | sort_by(.cost_usd) | reverse),
           quota: $quota,
           unpriced_models: ([$rows[] | select(.priced | not)
                              | if .tier == "standard" then .model else "\(.model) (\(.tier))" end] | unique),
           top_sessions: ($rows | group_by(.sk)
                          | map({tool: "codex", session: .[0].sk, start: ([.[].ts] | min), turns: length,
                                 cost_usd: ([.[].c] | add | r4), model: topmodel,
                                 cwd: (if $all then $pmap[.[0].cwd].c else null end),
                                 pdir: (if $all then $pmap[.[0].cwd].d else null end)})
                          | sort_by(.cost_usd) | reverse | .[0:$top])}
        + (if $all then {by_project: ($rows | group_by($pmap[.cwd] | .d // .c)
                 | map({cwd: $pmap[.[0].cwd].c, pdir: $pmap[.[0].cwd].d,
                        sessions: ([.[] | select(.role == "main") | .sid] | unique | length),
                        turns: length, cost_usd: ([.[].c] | add | r4), _c: ([.[].c] | add)})
                 | sort_by(.cost_usd) | reverse)} else {} end)
        + ($rows | series($view; $tz))
        | . as $R
        | . + {_total: $total,
               _head: (if $sid == "" then "rdf tokens — codex · \($plabel) · since \($since) · list-price estimate"
                       else "rdf tokens — codex session \($sid) · list-price estimate" end),
               _sub: "sessions \($R.sessions) · subagent runs \($R.subagent_runs) · api turns \($R.api_turns) · reasoning \($R.tokens.reasoning) of \($R.tokens.output) output tokens",
               _body: (if $R.api_turns == 0 then [] else [
                   "T\t\($total | usd)",
                   "S\tcache read\t\($R.share.cache_read | pct)\t\([$rows[].c_cr] | add | usd)",
                   "S\tcache write\t\($R.share.cache_write | pct)\t\([$rows[].c_cw] | add | usd)",
                   "S\toutput\t\($R.share.output | pct)\t\([$rows[].c_out] | add | usd)",
                   "S\tinput\t\($R.share.input | pct)\t\([$rows[].c_in] | add | usd)",
                   "B",
                   "MH",
                   ($R.by_model[] | "M\t\(.model)\(if .tier == "fast" then " (fast)" else "" end)\t\(.turns)\t\(if .cost_usd == null then "unpriced" else (.cost_usd | usd) end)"),
                   "B",
                   "KH",
                   ($R.by_kind[] | "A\t\(.kind)\t\(.runs)\t\(.turns)\t\(.cost_usd | usd)"),
                   "B",
                   "EH",
                   ($R.by_effort[] | "M\t\(.effort)\t\(.turns)\t\(.cost_usd | usd)"),
                   (if $quota == null then empty
                    else "B",
                         ($quota.limits[] | "H\tquota, \(.window_minutes | wlabel) window (account-wide): peak \(.peak_pct)% · latest \(.latest_pct)% at \(.latest_at[0:16]) · \(.windows | length) windows"),
                         "H\t  plan \($quota.plan // "unknown") · limit reached \($quota.limit_reached_events) times"
                    end),
                   (if ($R.unpriced_models | length) > 0 then "B", "H\tunpriced models    \($R.unpriced_models | join(", "))" else empty end)
               ] end)}
    ' "${_TOK_WORK}/rows"
}

# _tok_output mode combined plabel — render claude.json and codex.json (either may be empty) as text, JSON or summary
_tok_output() {
    local mode="$1" combined="$2" plabel="$3"
    jq -n -r --slurpfile c "${_TOK_WORK}/claude.json" --slurpfile x "${_TOK_WORK}/codex.json" \
        --arg mode "$mode" --argjson combined "$combined" --arg view "$_TOK_VIEW" --argjson top "$_TOK_TOP" \
        --argjson tz "$_TOK_TZOFF" --arg plabel "$plabel" --arg since "$_TOK_SINCE" --arg home "${HOME:-}" \
        "${_TOK_JQ_LOCAL}${_TOK_JQ_DEFS}"'
        def strip: if . == null then null
            else with_entries(select(.key | startswith("_") | not))
                 | if .by_project != null then .by_project |= map(del(._c)) else . end end;
        def used: . != null and .api_turns > 0;
        def csum: {session: .scope.session, cost_usd, api_turns,
                   cache_read_share: .share.cache_read, main_ctx_median: .main_context.median,
                   subagent_runs,
                   rebuild_events: .rebuilds.events, rebuild_cost_usd: .rebuilds.cost_usd,
                   by_model: ([.by_model[] | select(.cost_usd != null) | {key: .model, value: .cost_usd}] | from_entries)};
        def xsum: {source: "codex", session: .scope.session, cost_usd, api_turns,
                   cache_read_share: .share.cache_read, subagent_runs,
                   by_model: (reduce (.by_model[] | select(.cost_usd != null)) as $b ({}; .[$b.model] += $b.cost_usd)
                              | map_values(r4)),
                   quota: (if .quota == null then null
                           else [.quota.limits[] | {window_minutes, peak_pct, latest_pct}] end)};
        def cprefix: if length == 0 then []
            else .[0] as $f | reduce .[1:][] as $p ($f; . as $a
                | ([range(0; [($a | length), ($p | length)] | min) | select($a[.] != $p[.])] | .[0]
                   // ([($a | length), ($p | length)] | min)) as $n | $a[0:$n]) end;
        # project labels: below the common dir of the Claude Code projects (its parent when a project is that dir), else
        # the path with ~ for home
        def labels($base): map(select(. != null and . != "")) | unique as $cw
            | ($base | map(select(. != null and . != "")) | unique
               | (map(select($home != "" and startswith($home + "/"))) as $h | if ($h | length) > 0 then $h else . end)
               | map(split("/"))) as $bp
            | ($bp | cprefix) as $cp
            | (if ($bp | length) <= 1 or any($bp[]; . == $cp) then ($cp | length) - 1 else ($cp | length) end) as $d
            | ($cp[0:([$d, 0] | max)]) as $pre
            | reduce $cw[] as $c ({}; .[$c] = (($c | split("/")) as $p
                | if ($pre | length) > 1 and $p[0:($pre | length)] == $pre and ($p | length) > ($pre | length)
                  then $p[($pre | length):] | join("/")
                  elif $home != "" and ($c == $home or ($c | startswith($home + "/"))) then "~" + $c[($home | length):]
                  else $c end));
        def stamp: (epoch) as $e | if $e == null then .[0:16] else ($e[0] | lfmt("%Y-%m-%d %H:%M"; $tz)) end;
        def cost: if . == null then "-" else "$\(usd)" end;
        def fit($w): if length > $w then ".." + .[(length - $w + 2):] else . end;
        def gw: [26, ([.[] | length] | max // 0)] | max | [., 60] | min;
        def qrow($lab; $pcwd): ($pcwd[.pdir // ""] // .cwd) as $c
            | "Q\t\(.start | stamp)\t\(.tool)\t\(.session[0:8])\t\(.turns)\t\(.cost_usd | cost)"
            + (if $c == null and .pdir == null then "" else "\t\($lab[$c // ""] // .pdir // "-")" end);
        ($c[0] // null) as $C | ($x[0] // null) as $X
        | [$C, $X | select(. != null)] as $srcs
        | ([$srcs[] | ._total] | add // 0) as $total
        | ([($C.by_project // [])[] | select(.pdir != null and .cwd != null) | {key: .pdir, value: .cwd}] | from_entries) as $pcwd
        | ([$srcs[] | (.by_project // [])[], .top_sessions[] | ($pcwd[.pdir // ""] // .cwd)]
           | labels([($C.by_project // [])[].cwd])) as $lab
        | ([$srcs[] | .top_sessions[]] | sort_by(.cost_usd) | reverse | .[0:$top]) as $sessions
        | (reduce ($srcs[] | (if .source == "codex" then "codex" else "claude" end) as $t
                   | (.by_project // [])[] | {t: $t, p: (. + {cwd: ($pcwd[.pdir // ""] // .cwd)})}) as $e ({};
              .[$e.p.cwd // $e.p.pdir // ""] |= ((. // {cwd: $e.p.cwd, pdir: $e.p.pdir, sessions: 0, turns: 0, claude: null, codex: null})
                  | .sessions += $e.p.sessions | .turns += $e.p.turns | .[$e.t] = ((.[$e.t] // 0) + ($e.p._c // $e.p.cost_usd))))
           | [.[] | . + {project: ($lab[.cwd // ""] // .pdir // "(unknown)"), cost_usd: ((.claude // 0) + (.codex // 0) | r4),
                         claude: (if .claude == null then null else (.claude | r4) end),
                         codex: (if .codex == null then null else (.codex | r4) end)}]
           | sort_by(.cost_usd) | reverse) as $projects
        | ([$srcs[] | (if .source == "codex" then "codex" else "claude" end) as $t | (.["by_" + $view] // [])[] | . + {t: $t}]
           | group_by(.key)
           | map({key: .[0].key, sessions: ([.[].sessions] | add), turns: ([.[].turns] | add),
                  claude: ([.[] | select(.t == "claude") | .cost_usd] | add),
                  codex: ([.[] | select(.t == "codex") | .cost_usd] | add),
                  cost_usd: ([.[].cost_usd] | add | r4)})) as $series
        | ([$srcs[] | select(used)] | length) as $nused
        | ($combined == 1 and $nused == 2) as $both
        | (if $C | used then $C elif $X | used then $X elif $combined == 1 then null elif $C != null then $C else $X end) as $one
        | if $mode == "json" then
            (if $combined == 1 then
               {source: "all", scope: {project: $plabel, since: $since}, cost_usd: ($total | r4),
                claude: ($C | strip), codex: ($X | strip),
                top_sessions: ($sessions | map(($pcwd[.pdir // ""] // .cwd) as $c | . + {project: ($lab[$c // ""] // .pdir)}))}
               + (if ([$srcs[] | has("by_project")] | any) then {by_project: $projects} else {} end)
               + (if $view == "day" or $view == "week" or $view == "month" then {("by_" + $view): $series} else {} end)
             else ($srcs[0] | strip) end) | tojson
          elif $mode == "summary" then
            (if $combined == 1 then
               {source: "all", cost_usd: ($total | r4),
                claude: (if $C == null then null else ($C | csum) end),
                codex: (if $X == null then null else ($X | xsum) end)}
             elif $srcs[0].source == "codex" then ($srcs[0] | xsum)
             else ($srcs[0] | csum) end) | tojson
          elif $one == null then "X\tno usage in window"
          elif ($one | used | not) then
            (if $one.source == "codex" then "X\tno Codex usage in window" else "X\tno usage in window" end)
          else
            (if $both then
               "H\trdf tokens — \($plabel) · since \($since) · list-price estimate",
               "H\tspend  $\($total | usd)  (claude code $\($C._total | usd) · codex $\($X._total | usd))"
             else "H\t\($one._head)" end),
            (if $view != "" and ($both | not) then "T\t\($one._total | usd)" else empty end),
            (if $view == "" then
               (if $both then
                  "B", "H\tclaude code: \($C._sub)", $C._body[], "B", "H\tcodex: \($X._sub)", $X._body[]
                else "H\t\($one._sub)", "B", $one._body[] end),
               (if ($projects | length) > 1 then
                  ([$projects[0:$top][].project] | gw) as $w
                  | "B",
                  (if $both then "GH\tby project\tclaude\tcodex\ttotal\t\($w)" else "GH\tby project\tsessions\tturns\tcost\t\($w)" end),
                  ($projects[0:$top][] | (.project | fit($w)) as $l
                   | if $both then "G\t\($l)\t\(.claude | cost)\t\(.codex | cost)\t\(.cost_usd | cost)\t\($w)"
                     else "G\t\($l)\t\(.sessions)\t\(.turns)\t\(.cost_usd | cost)\t\($w)" end),
                  (if ($projects | length) > $top then "H\t  \(($projects | length) - $top) more (--top N or --json)" else empty end)
                else empty end),
               (if ($sessions | length) > 0 and $one.scope.session == null then
                  "B", (if ($projects | length) > 0 then "QH\tproject" else "QH" end),
                  ($sessions[0:5][] | qrow($lab; $pcwd))
                else empty end)
             elif $view == "session" then
               "B", (if ($projects | length) > 0 then "QH\tproject" else "QH" end),
               ($sessions[] | qrow($lab; $pcwd))
             elif $view == "project" then
               ([$projects[0:$top][].project] | gw) as $w
               | "B",
               (if $both then "GH\tby project\tclaude\tcodex\ttotal\t\($w)" else "GH\tby project\tsessions\tturns\tcost\t\($w)" end),
               ($projects[0:$top][] | (.project | fit($w)) as $l
                | if $both then "G\t\($l)\t\(.claude | cost)\t\(.codex | cost)\t\(.cost_usd | cost)\t\($w)"
                  else "G\t\($l)\t\(.sessions)\t\(.turns)\t\(.cost_usd | cost)\t\($w)" end),
               (if ($projects | length) > $top then "H\t  \(($projects | length) - $top) more (--top N or --json)" else empty end)
             else
               "B",
               (if $both then "GH\tby \($view)\tclaude\tcodex\ttotal\t26" else "GH\tby \($view)\tsessions\tturns\tcost\t26" end),
               ($series[] | if $both then "G\t\(.key)\t\(.claude | cost)\t\(.codex | cost)\t\(.cost_usd | cost)\t26"
                            else "G\t\(.key)\t\(.sessions)\t\(.turns)\t\(.cost_usd | cost)\t26" end)
             end)
          end
    '
}

# _tok_pricing mode — the embedded price table with its age and sources; text or json
_tok_pricing() {
    local mode="$1"
    if [ "$mode" = "json" ]; then
        _tok_prices | jq -c '. + {age_days: ((now - ((.as_of + "T00:00:00Z") | fromdateiso8601)) / 86400 | floor),
                                  expires: ([(.anthropic, .openai)[] | .until // empty] | min)}'
        return 0
    fi
    _tok_prices | jq -r '
        def num: if . == null then "-" else tostring end;
        ((now - ((.as_of + "T00:00:00Z") | fromdateiso8601)) / 86400 | floor) as $age
        | "H\trdf tokens pricing — list prices as of \(.as_of) (\($age) days old), USD per million tokens",
          (.sources | to_entries[] | "H\t  \(.key): \(.value)"),
          ([(.anthropic, .openai) | to_entries[] | select(.value.until) | "\(.key) until \(.value.until)"]
           | if length > 0 then "H\t  promotional prices: \(join(", "))" else empty end),
          "B",
          "PA\tanthropic\tinput\toutput\tcache 5m\tcache 1h\tcache read",
          (.anthropic | to_entries[]
           | "P\t\(.key)\t\(.value.in | num)\t\(.value.out | num)\t\(.value.cw5 | num)\t\(.value.cw1h | num)\t\(.value.cr | num)\t\(
                [(if .value.fast then "fast \(.value.fast.in)/\(.value.fast.out)" else empty end),
                 (if .value.long then "over \(.value.long.over / 1000)K prompt \(.value.long.in)/\(.value.long.out)" else empty end),
                 (if .value.residency then "us 1.1x" else empty end)] | join(" · "))"),
          "B",
          "PO\topenai (standard)\tinput\toutput\tcache write\tcached input",
          (.openai | to_entries[]
           | "P\t\(.key)\t\(.value.in | num)\t\(.value.out | num)\t\(.value.cw | num)\t\(.value.cr | num)\t\t")
    ' | while IFS=$'\t' read -r tag a b c d e f g; do
        case "$tag" in
            H)  printf '%s\n' "$a" ;;
            B)  printf '\n' ;;
            PA|PO|P) printf '  %-20s %7s %7s %10s %10s %10s  %s\n' "$a" "$b" "$c" "$d" "$e" "$f" "$g" ;;
        esac
    done
}

# _tok_render — format the tagged text lines from _tok_output
_tok_render() {
    local tag a b c d e f
    while IFS=$'\t' read -r tag a b c d e f; do
        case "$tag" in
            H|X) printf '%s\n' "$a" ;;
            B)   printf '\n' ;;
            T)   printf 'spend  $%s\n' "$a" ;;
            S)   printf '  %-12s %6s%%  %9s\n' "$a" "$b" "\$${c}" ;;
            MH)  printf '%-28s %6s %10s\n' "by model" "turns" "cost" ;;
            M)   printf '  %-26s %6s %10s\n' "$a" "$b" "$( [ "$c" = "unpriced" ] && printf 'unpriced' || printf '$%s' "$c")" ;;
            AH)  printf '%-28s %6s %6s %10s\n' "by agent" "runs" "turns" "cost" ;;
            KH)  printf '%-28s %6s %6s %10s\n' "by kind" "runs" "turns" "cost" ;;
            EH)  printf '%-28s %6s %10s\n' "by effort" "turns" "cost" ;;
            A)   printf '  %-26s %6s %6s %10s\n' "$a" "$b" "$c" "\$${d}" ;;
            GH)  printf '%-*s %10s %10s %10s\n' "$(( ${e:-26} + 2 ))" "$a" "$b" "$c" "$d" ;;
            G)   printf '  %-*s %10s %10s %10s\n' "${e:-26}" "$a" "$b" "$c" "$d" ;;
            QH)  printf '%-28s %-7s %-9s %6s %10s%s\n' "top sessions" "tool" "session" "turns" "cost" "${a:+  $a}" ;;
            Q)   printf '  %-26s %-7s %-9s %6s %10s%s\n' "$a" "$b" "$c" "$d" "$e" "${f:+  $f}" ;;
        esac
    done
}

main() {
    local project="" tdir="" sid="" sid_set=0 days="30" since="" mode="text" pricing=0
    local claude=0 codex=0 all=0 combined=0 d plabel logical="" physical="" reason="" root="" pinv="{}" ccwd="{}" quota top="" f fallback=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --project)     [ $# -ge 2 ] || _tok_die "--project needs a value" 2; project="$2"; shift 2 ;;
            --transcripts) [ $# -ge 2 ] || _tok_die "--transcripts needs a value" 2; tdir="$2"; shift 2 ;;
            --session)     [ $# -ge 2 ] || _tok_die "--session needs a value" 2; sid="$2"; sid_set=1; shift 2 ;;
            --days)        [ $# -ge 2 ] || _tok_die "--days needs a value" 2; days="$2"; shift 2 ;;
            --since)       [ $# -ge 2 ] || _tok_die "--since needs a value" 2; since="$2"; shift 2 ;;
            --by)          [ $# -ge 2 ] || _tok_die "--by needs a value" 2; _TOK_VIEW="$2"; shift 2 ;;
            --top)         [ $# -ge 2 ] || _tok_die "--top needs a value" 2; top="$2"; shift 2 ;;
            --json)        mode="json"; shift ;;
            --summary)     mode="summary"; shift ;;
            --claude)      claude=1; shift ;;
            --codex)       codex=1; shift ;;
            --all)         all=1; shift ;;
            --no-cache)    _TOK_NOCACHE=1; shift ;;
            --pricing)     pricing=1; shift ;;
            help|--help|-h) _tok_usage; return 0 ;;
            *) _tok_die "unknown option: $1 — run 'rdf tokens help'" 2 ;;
        esac
    done

    if [ "$pricing" -eq 1 ]; then
        command -v jq >/dev/null 2>&1 || _tok_die "jq is required (apt/dnf install jq, or brew install jq)" 1
        [ "$mode" = "summary" ] && _tok_die "--pricing takes --json or nothing" 2
        _tok_pricing "$mode"
        return 0
    fi
    [ "$codex" -eq 1 ] && [ -n "$tdir" ] && _tok_die "--codex reads Codex rollouts; it does not take --transcripts" 2
    [ -n "$tdir" ] && claude=1
    case "$_TOK_VIEW" in
        ''|day|week|month|session) ;;
        project) all=1 ;;
        *) _tok_die "--by expects day, week, month, session or project" 2 ;;
    esac
    if [ "$all" -eq 1 ] && { [ -n "$project" ] || [ -n "$tdir" ] || [ "$sid_set" -eq 1 ]; }; then
        _tok_die "--all covers every project; it does not take --project, --transcripts or --session" 2
    fi
    if [ -n "$top" ]; then
        case "$top" in
            ''|*[!0-9]*) _tok_die "--top expects a positive integer" 2 ;;
        esac
        _TOK_TOP=$((10#$top))
        [ "$_TOK_TOP" -gt 0 ] || _tok_die "--top expects a positive integer" 2
    fi
    if [ "$claude" -eq "$codex" ]; then
        claude=1; codex=1; combined=1
    fi

    case "$days" in
        ''|*[!0-9]*) _tok_die "--days expects a positive integer" 2 ;;
    esac
    days=$((10#$days))
    [ "$days" -gt 0 ] || _tok_die "--days expects a positive integer" 2
    if [ -n "$since" ]; then
        case "$since" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
            *) _tok_die "--since expects YYYY-MM-DD" 2 ;;
        esac
    fi
    if [ "$sid_set" -eq 1 ]; then
        case "$sid" in
            ''|*[!A-Za-z0-9-]*) _tok_die "--session expects an id of letters, digits and dashes" 2 ;;
        esac
    fi
    command -v jq >/dev/null 2>&1 || _tok_die "jq is required (apt/dnf install jq, or brew install jq)" 1
    if jq -n '0 | strflocaltime("%Y")' >/dev/null 2>&1; then  # jq 1.6+: each timestamp in its own local offset (DST); jq 1.5 → today's offset
        _TOK_JQ_LOCAL='def lfmt($f; $tz): strflocaltime($f);'
    fi

    case "$RDF_CLAUDE_PROJECTS" in /*) ;; *) RDF_CLAUDE_PROJECTS="${PWD}/${RDF_CLAUDE_PROJECTS}" ;; esac
    _TOK_CODEX="${CODEX_HOME:-${HOME}/.codex}"
    case "$_TOK_CODEX" in /*) ;; *) _TOK_CODEX="${PWD}/${_TOK_CODEX}" ;; esac
    umask 077
    _TOK_WORK="$(command mktemp -d "${TMPDIR:-/tmp}/rdf-tokens.XXXXXX")"
    _tok_clock
    : > "${_TOK_WORK}/claude.json"
    : > "${_TOK_WORK}/codex.json"

    # a session id belongs to one tool: Claude Code first, then Codex
    if [ "$sid_set" -eq 1 ]; then
        combined=0
        if [ "$claude" -eq 1 ] && [ "$codex" -eq 1 ]; then
            codex=0
            for f in "${RDF_CLAUDE_PROJECTS}"/*/"${sid}.jsonl"; do
                [ -f "$f" ] && break
                f=""
            done
            if [ -z "$f" ] && { [ -d "${_TOK_CODEX}/sessions" ] || [ -d "${_TOK_CODEX}/archived_sessions" ]; }; then
                claude=0; codex=1; fallback=1
            fi
        fi
        plabel="session"
    elif [ "$all" -eq 1 ]; then
        plabel="all projects"
        _tok_window "$days" "$since"
    else
        logical="$(cd "${project:-.}" 2>/dev/null && pwd)" || _tok_die "no such directory: ${project:-.}" 1  # unreadable dir reported as missing
        physical="$(cd "${project:-.}" && pwd -P)"
        plabel="$(command basename "$logical")"
        _tok_window "$days" "$since"
    fi

    if [ "$claude" -eq 1 ]; then
        if [ "$sid_set" -eq 1 ]; then
            tdir=""
        elif [ -n "$tdir" ]; then
            [ -d "$tdir" ] || _tok_die "transcripts directory not found: ${tdir}" 1
            plabel="$(command basename "$tdir")"
            case "$tdir" in /*) ;; *) tdir="${PWD}/${tdir}" ;; esac
            root="$(cd "$tdir" && pwd -P)"
        elif [ "$all" -eq 1 ]; then
            if [ -d "$RDF_CLAUDE_PROJECTS" ]; then
                tdir="$RDF_CLAUDE_PROJECTS"
                root="$(cd "$tdir" && pwd -P)"
            elif [ "$combined" -eq 0 ]; then
                _tok_die "no transcripts under ${RDF_CLAUDE_PROJECTS}" 1
            else
                claude=0; reason="no transcripts under ${RDF_CLAUDE_PROJECTS}"
            fi
        elif tdir="$(_tok_find_dir "${project:-.}")"; then
            root="$(cd "$tdir" && pwd -P)"
        elif [ "$combined" -eq 0 ]; then
            _tok_die "$tdir" 1
        else
            claude=0; reason="$tdir"
        fi
    fi
    if [ "$claude" -eq 1 ]; then
        _tok_files "$root" "$sid" "$all"
        _tok_extract claude
        if [ "$all" -eq 1 ]; then
            _tok_report "$plabel" "$sid" "$tdir" "$root" > "${_TOK_WORK}/claude.json"
        else
            _tok_report "$plabel" "$sid" "$tdir" "" > "${_TOK_WORK}/claude.json"
        fi
    fi

    if [ "$codex" -eq 1 ]; then
        if [ ! -d "${_TOK_CODEX}/sessions" ] && [ ! -d "${_TOK_CODEX}/archived_sessions" ]; then
            [ "$combined" -eq 1 ] || _tok_die "no Codex sessions under ${_TOK_CODEX}/sessions" 1
            codex=0
        else
            _TOK_CODEX="$(cd "$_TOK_CODEX" && pwd -P)"
        fi
    fi
    if [ "$codex" -eq 1 ]; then
        if [ "$all" -eq 1 ] && [ -d "$RDF_CLAUDE_PROJECTS" ]; then
            pinv="$(for f in "$RDF_CLAUDE_PROJECTS"/*/; do
                        d="$(cd "$f" 2>/dev/null && pwd -P)" || continue  # dangling alias → not a project
                        f="${f%/}"; printf '%s\t%s\n' "${f##*/}" "${d##*/}"
                    done | jq -R 'index("\t") as $i | select($i != null) | {(.[0:$i]): .[($i + 1):]}' | jq -s -c 'add // {}')"
            [ ! -s "${_TOK_WORK}/claude.json" ] \
                || ccwd="$(jq -c '[.by_project[] | select(.cwd != null) | {key: .cwd, value: .pdir}] | from_entries' "${_TOK_WORK}/claude.json")"
        fi
        _tok_codex_files "$sid"
        if [ "$fallback" -eq 1 ] && [ ! -s "${_TOK_WORK}/files" ]; then
            _tok_die "no transcript for session ${sid} under ${RDF_CLAUDE_PROJECTS} and no Codex rollout under ${_TOK_CODEX}" 1
        fi
        _tok_extract codex
        quota="null"
        [ "$sid_set" -eq 1 ] || quota="$(_tok_codex_quota)"
        _tok_codex_report "$plabel" "$sid" "$logical" "$physical" "$all" "$pinv" "$ccwd" "$quota" > "${_TOK_WORK}/codex.json"
    fi
    [ "$claude" -eq 1 ] || [ "$codex" -eq 1 ] || _tok_die "${reason:-no usage sources found}" 1
    if [ "$claude" -eq 0 ] && [ -n "$reason" ] && [ "$(jq '.api_turns' "${_TOK_WORK}/codex.json")" = "0" ]; then
        _tok_die "$reason" 1
    fi

    if [ "$mode" = "text" ]; then
        _tok_output text "$combined" "$plabel" | _tok_render
    else
        _tok_output "$mode" "$combined" "$plabel"
    fi
}

if [ "${1:-}" = "__worker" ]; then
    shift
    _tok_worker "$@"
else
    main "$@"
fi
