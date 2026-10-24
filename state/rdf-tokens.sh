#!/usr/bin/env bash
# state/rdf-tokens.sh — local token usage report from Claude Code transcripts and Codex rollouts
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# shellcheck disable=SC2016  # literal $ in single-quoted jq programs
set -euo pipefail

RDF_CLAUDE_PROJECTS="${RDF_CLAUDE_PROJECTS:-${HOME}/.claude/projects}"
_TOK_WORK=""
_TOK_SINCE=""
_TOK_LOOKBACK=""
_TOK_TTL_1H=3600  # 1h cache TTL; also how far before the window rebuild detection looks for a predecessor
trap '[ -z "$_TOK_WORK" ] || command rm -rf "$_TOK_WORK"' EXIT

_tok_usage() {
    cat <<'USAGE'
Usage: rdf tokens [options]

Local token usage report from Claude Code transcripts (or, with --codex,
Codex CLI rollouts): deduplicated usage, list-price cost, and breakdowns by
cost class, model, agent, context depth, subagent boot cost, cache rebuilds,
and effort.

Options:
  --project DIR      project directory (default: current directory)
  --transcripts DIR  transcript directory (overrides --project resolution)
  --session ID       one session and its subagents, found under any project
                     (ignores the window)
  --days N           window: last N days (default 30)
  --since YYYY-MM-DD window start (overrides --days)
  --json             full JSON report
  --summary          compact JSON object for session logs
  --codex            report Codex CLI sessions (rollouts whose cwd is the
                     project or below it) instead of Claude Code transcripts,
                     split by kind (review = read-only sandbox, write) and
                     effort, plus the account's plan quota peak per window
  --pricing          print the embedded price table, its date and sources
  help               this text

Environment:
  RDF_CLAUDE_PROJECTS  transcript root (default: ~/.claude/projects)
  CODEX_HOME           Codex home for --codex (default: ~/.codex)

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

# _tok_resolve_dir project — transcripts dir for a project, logical path first
_tok_resolve_dir() {
    local project="$1" logical physical a b
    logical="$(cd "$project" 2>/dev/null && pwd)" || _tok_die "no such directory: ${project}" 1  # unreadable dir reported as missing
    physical="$(cd "$project" && pwd -P)" || _tok_die "no such directory: ${project}" 1
    a="${RDF_CLAUDE_PROJECTS}/$(_tok_slug "$logical")"
    b="${RDF_CLAUDE_PROJECTS}/$(_tok_slug "$physical")"
    if [ -d "$a" ]; then
        printf '%s' "$a"
    elif [ -d "$b" ]; then
        printf '%s' "$b"
    else
        _tok_die "no transcripts for ${logical} (looked in ${a} and ${b})" 1
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

# jq helpers shared by the Claude and Codex reports. pkey: longest key that is the id itself or the id less
# a date, @version or -vN suffix, so an unlisted newer model reports unpriced instead of borrowing a sibling's price
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

# _tok_files tdir sid — NUL list of transcript paths into ${_TOK_WORK}/files
_tok_files() {
    local tdir="$1" sid="$2" out="${_TOK_WORK}/files" main="" f
    if [ -n "$sid" ]; then
        for f in "${RDF_CLAUDE_PROJECTS}"/*/"${sid}.jsonl"; do
            [ -f "$f" ] && { main="$f"; break; }
        done
        [ -n "$main" ] || _tok_die "no transcript for session ${sid} under ${RDF_CLAUDE_PROJECTS}" 1
        {
            printf '%s\0' "$main"
            if [ -d "${main%.jsonl}/subagents" ]; then
                find "${main%.jsonl}/subagents" -name 'agent-*.jsonl' -type f -print0
            fi
        } > "$out"
    else
        {
            find -H "$tdir" -maxdepth 1 -name '*.jsonl' -type f -newer "${_TOK_WORK}/ref" -print0
            find -H "$tdir" -mindepth 3 -path '*/subagents/*' -name 'agent-*.jsonl' -type f -newer "${_TOK_WORK}/ref" -print0
        } > "$out"
    fi
}

# _tok_agent_map — merged {meta path: agentType} into ${_TOK_WORK}/agents.json
_tok_agent_map() {
    local f m metas="${_TOK_WORK}/metas"
    : > "$metas"
    while IFS= read -r -d '' f; do
        case "$f" in
            */subagents/*)
                m="${f%.jsonl}.meta.json"
                [ -f "$m" ] && printf '%s\0' "$m" >> "$metas"
                ;;
        esac
    done < "${_TOK_WORK}/files"
    if [ -s "$metas" ]; then
        # one "path<TAB>json" line per meta: CC writes metas without a trailing newline, and a bad one must not abort the map
        while IFS= read -r -d '' m; do
            printf '%s\t' "$m"
            command tr -d '\n' < "$m" 2>/dev/null || true  # meta removed mid-run → empty → agent unknown
            printf '\n'
        done < "$metas" \
            | jq -cR 'index("\t") as $i | select($i != null)
                | {(.[0:$i]): (.[($i + 1):] | fromjson? | select(type == "object") | (.agentType // "unknown") | tostring)}' \
            | jq -s 'add // {}' > "${_TOK_WORK}/agents.json"
    else
        printf '{}\n' > "${_TOK_WORK}/agents.json"
    fi
}

# _tok_rows — one compact row per kept assistant entry into ${_TOK_WORK}/rows
_tok_rows() {
    if [ ! -s "${_TOK_WORK}/files" ]; then
        : > "${_TOK_WORK}/rows"
        return 0
    fi
    xargs -0 jq -cR --arg since "$_TOK_SINCE" --arg lookback "$_TOK_LOOKBACK" '
        fromjson? | select(type == "object")
        | select((.message | type) == "object" and ((.timestamp // "") | type) == "string")
        | select(.type == "assistant"
            and ((.message.id // "") != "")
            and ((.message.usage | type) == "object")
            and (.message.model != "<synthetic>")
            and (((.timestamp // "")[0:19]) >= ($lookback[0:19])))
        | .message.usage as $u
        | {id: .message.id, ts: (.timestamp // ""), file: input_filename,
           pre: (((.timestamp // "")[0:19]) < ($since[0:19])),
           sid: (.sessionId // ""), model: (.message.model // "unknown"),
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
                  else 0 end)}
    ' < "${_TOK_WORK}/files" > "${_TOK_WORK}/rows"
}

# _tok_report mode label sid — dedup, price, aggregate; render text|json|summary
_tok_report() {
    local mode="$1" plabel="$2" sid="$3" tdir="$4"
    jq -s -r --slurpfile agents "${_TOK_WORK}/agents.json" \
        --argjson prices "$(_tok_prices | jq -c .anthropic)" \
        --arg mode "$mode" --arg plabel "$plabel" --arg sid "$sid" \
        --arg since "$_TOK_SINCE" --arg tdir "$tdir" --argjson ttl_1h "$_TOK_TTL_1H" "${_TOK_JQ_DEFS}"'
        def r1: (. * 10 + 0.5 | floor) / 10;
        def nr($p): length as $n
            | if $n == 0 then 0 else .[((0 - ((0 - ($p * $n)) | floor)) - 1)] end;
        def k: if . >= 1000 then (((. / 100) | floor) / 10 | tostring) + "K"
               else tostring end;
        # effective per-MTok rates for one turn: long-prompt tier, then fast mode (cache classes keep the
        # model ratios), then the 1.1x US data-residency multiplier
        def rates($p; $r): ($r.in + $r.cw5 + $r.cw1h + $r.cr) as $prompt
            | (if $p.long != null and $prompt > $p.long.over then $p.long else $p end) as $b
            | (if $r.speed == "fast" and $p.fast != null
               then {in: $p.fast.in, out: $p.fast.out, cw5: ($p.fast.in * $b.cw5 / $b.in),
                     cw1h: ($p.fast.in * $b.cw1h / $b.in), cr: ($p.fast.in * $b.cr / $b.in)}
               else {in: $b.in, out: $b.out, cw5: $b.cw5, cw1h: $b.cw1h, cr: $b.cr} end) as $x
            | (if $r.geo == "us" and $p.residency == true then 1.1 else 1 end) as $g
            | {in: ($x.in * $g), out: ($x.out * $g), cw5: ($x.cw5 * $g), cw1h: ($x.cw1h * $g), cr: ($x.cr * $g)};
        def ttl_5m: 300;
        def rebuild_min_ctx: 50000;
        def rebuild_min_write_share: 0.5;
        def role_of: if contains("/subagents/") then "sub" else "main" end;
        # [seconds, fraction] of a UTC "Z" timestamp, else null; fromdateiso8601 rejects fractions and normalizes Feb 30
        def epoch: if endswith("Z") and length >= 20 then
                (.[0:19] + "Z") as $w | (($w | fromdateiso8601?) // null) as $s
                | (if length == 20 then 0 elif .[19:20] == "." then (("0" + .[19:(length - 1)] | tonumber?) // null)
                   else null end) as $f
                | if $s == null or ($s | todate) != $w or $f == null or $f >= 1 then null else [$s, $f] end
            else null end;
        ($agents[0] // {}) as $amap
        | . as $raw
        | map(select(.pre != true))
        | group_by(.id)
        | map(sort_by(.ts) as $g
              | $g[0] + {in: ([$g[].in] | max), cw5: ([$g[].cw5] | max),
                         cw1h: ([$g[].cw1h] | max), cr: ([$g[].cr] | max),
                         out: ([$g[].out] | max), th: ([$g[].th] | max)})
        | map(. as $r
              | ($r.file | role_of) as $role
              | pkey($r.model; $prices) as $pk
              | (if $pk == null then null else rates($prices[$pk]; $r) end) as $p
              | $r + {role: $role,
                      agent: (if $role == "main" then "main"
                              else ($amap[($r.file | rtrimstr(".jsonl")) + ".meta.json"] // "unknown") end),
                      priced: ($p != null),
                      c_in: (if $p == null then 0 else $r.in * $p.in / 1000000 end),
                      c_cw: (if $p == null then 0 else ($r.cw5 * $p.cw5 + $r.cw1h * $p.cw1h) / 1000000 end),
                      c_cr: (if $p == null then 0 else $r.cr * $p.cr / 1000000 end),
                      c_out: (if $p == null then 0 else $r.out * $p.out / 1000000 end)}
              | . + {c: (.c_in + .c_cw + .c_cr + .c_out),
                     c_rb: (if $p == null then 0 else .c_cw - (.cw5 + .cw1h) * $p.cr / 1000000 end)})
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
           unpriced_models: ([$rows[] | select(.priced | not) | .model] | unique)}
        | . as $R
        | if $mode == "json" then $R | tojson
          elif $mode == "summary" then
            {session: $R.scope.session, cost_usd: $R.cost_usd, api_turns: $R.api_turns,
             cache_read_share: $R.share.cache_read, main_ctx_median: $R.main_context.median,
             subagent_runs: $R.subagent_runs,
             rebuild_events: $R.rebuilds.events, rebuild_cost_usd: $R.rebuilds.cost_usd,
             by_model: ([$R.by_model[] | select(.cost_usd != null) | {key: .model, value: .cost_usd}] | from_entries)}
            | tojson
          elif $R.api_turns == 0 then "X\tno usage in window"
          else
            (if $sid == "" then "H\trdf tokens — \($plabel) · since \($since) · list-price estimate"
             else "H\trdf tokens — session \($sid) · list-price estimate" end),
            "H\tsessions \($R.sessions) · api turns \($R.api_turns) (main \($R.main_turns) · subagents \($R.subagent_turns) in \($R.subagent_runs) runs)",
            "B",
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
          end
    ' "${_TOK_WORK}/rows"
}

# _tok_codex_files sid logical physical — NUL list of candidate rollouts into ${_TOK_WORK}/files; the
# grep pre-filter only narrows (a cwd string under another path still reaches the exact check in jq)
_tok_codex_files() {
    local sid="$1" pl="$2" pp="$3" root out="${_TOK_WORK}/files"
    root="${CODEX_HOME:-${HOME}/.codex}/sessions"
    [ -d "$root" ] || _tok_die "no Codex sessions under ${root}" 1
    if [ -n "$sid" ]; then
        find -H "$root" -name 'rollout-*.jsonl' -type f \
            -exec grep -lF --null -e "\"id\":\"${sid}\"" -e "\"parent_thread_id\":\"${sid}\"" {} + > "$out" || true  # grep exits 1 when no rollout names the id → empty list
    else
        find -H "$root" -name 'rollout-*.jsonl' -type f -newer "${_TOK_WORK}/ref" \
            -exec grep -lF --null -e "\"cwd\":\"${pl}" -e "\"cwd\":\"${pp}" {} + > "$out" || true  # grep exits 1 when no rollout in the window ran here → empty list
    fi
}

# _tok_codex_rows logical physical sid — one row per model response into ${_TOK_WORK}/rows (sources and attribution: spec §4)
_tok_codex_rows() {
    local pl="$1" pp="$2" sid="$3" f
    local records='"type":"(session_meta|turn_context|token_usage_record|thread_settings_applied|token_count)"'
    : > "${_TOK_WORK}/rows"
    while IFS= read -r -d '' f; do
        grep -E "$records" "$f" > "${_TOK_WORK}/rollout" 2>/dev/null || true  # no record lines or an unreadable rollout → empty input
        jq -R -s -c --arg since "$_TOK_SINCE" --arg pl "$pl" --arg pp "$pp" --arg sid "$sid" --arg file "$f" '
            def n: if type == "number" and . > 0 then . else 0 end;
            def under($c; $p): $p != "" and ($c == $p or ($c | startswith($p + "/")));
            def usage: {in: (.input_tokens | n), cr: (.cached_input_tokens | n), cw: (.cache_write_input_tokens | n),
                        out: (.output_tokens | n), rs: (.reasoning_output_tokens | n)};
            [split("\n")[] | fromjson? | select(type == "object")] as $l
            | ([$l[] | select(.type == "session_meta") | .payload | select(type == "object")] | .[0] // {}) as $m
            | (($m.source // {}) | if type == "object" then (.subagent // null) else null end
               | if type == "object" then (.thread_spawn.parent_thread_id // null) else null end) as $parent
            | (($m.source // "") | if type == "object" and has("subagent") then "sub" else "main" end) as $role
            | select(if $sid != "" then ($m.id // "") == $sid or $parent == $sid
                     else (($m.cwd // "") as $c | under($c; $pl) or under($c; $pp)) end)
            | ([$l[] | select(.type == "token_usage_record")] | length > 0) as $per_response
            | reduce ($l[] | select(.type == "turn_context" or .type == "token_usage_record"
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
            | select($sid != "" or ((.ts[0:19]) >= ($since[0:19])))
            | . + {sid: ($m.id // "" | tostring), role: $role, file: $file}
        ' < "${_TOK_WORK}/rollout" >> "${_TOK_WORK}/rows" || true  # malformed rollout → skipped, like a malformed transcript line
    done < "${_TOK_WORK}/files"
}

# _tok_codex_quota root — plan quota from every rollout in the window (rate limits are per account); JSON or null
_tok_codex_quota() {
    local root="$1"
    find -H "$root" -name 'rollout-*.jsonl' -type f -newer "${_TOK_WORK}/ref" \
        -exec grep -hF '"rate_limits"' {} + > "${_TOK_WORK}/quota" || true  # grep exits 1 when no rollout in the window recorded a quota → no samples
    jq -R -c --arg since "$_TOK_SINCE" '
            fromjson? | select(type == "object" and .type == "event_msg" and (.payload | type) == "object"
                               and .payload.type == "token_count" and (.payload.rate_limits | type) == "object")
            | (.timestamp // "" | tostring) as $ts | select($ts[0:19] >= ($since[0:19]))
            | .payload.rate_limits as $r
            | ($r.primary, $r.secondary) | select(type == "object" and (.window_minutes | type) == "number")
            | {ts: $ts, win: .window_minutes, pct: (.used_percent // 0), resets: (.resets_at // 0),
               plan: ($r.plan_type // null), reached: ($r.rate_limit_reached_type != null)}' < "${_TOK_WORK}/quota" \
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

# _tok_codex_report mode label sid root quota — price Codex rows; render text|json|summary
_tok_codex_report() {
    local mode="$1" plabel="$2" sid="$3" root="$4" quota="$5"
    jq -s -r --argjson prices "$(_tok_prices | jq -c .openai)" \
        --argjson over "$(_tok_prices | jq -c .openai_long_over)" --argjson quota "$quota" \
        --arg mode "$mode" --arg plabel "$plabel" --arg sid "$sid" \
        --arg since "$_TOK_SINCE" --arg root "$root" "${_TOK_JQ_DEFS}"'
        # tier rate (none for the tier → unpriced), then the per-request over-272K rate; absent cached/write rates bill at input
        def orates($p; $r): (if $r.tier == "standard" then $p elif $r.tier == "fast" then $p.fast else null end) as $t
            | if $t == null then null
              else (if $r.rid != null and $r.in > $over and $t.long != null then $t.long else $t end) as $x
                   | {in: $x.in, out: $x.out, cr: ($x.cr // $x.in), cw: ($x.cw // $x.in)} end;
        ([.[] | select(.rid != null)] | group_by(.rid) | map(.[0])) + [.[] | select(.rid == null)]
        # cached and cache-write tokens are subsets of input_tokens; reasoning is a subset of output_tokens
        | map(. as $r
            | pkey($r.model; $prices) as $pk
            | (if $pk == null then null else orates($prices[$pk]; $r) end) as $p
            | ([($r.in - $r.cr - $r.cw), 0] | max) as $u
            | $r + {unc: $u, priced: ($p != null),
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
                              | if .tier == "standard" then .model else "\(.model) (\(.tier))" end] | unique)}
        | . as $R
        | def wlabel: if . % 1440 == 0 then "\(. / 1440)-day" elif . % 60 == 0 then "\(. / 60)-hour"
                      else "\(.)-minute" end;
          if $mode == "json" then $R | tojson
          elif $mode == "summary" then
            {source: "codex", session: $R.scope.session, cost_usd: $R.cost_usd, api_turns: $R.api_turns,
             cache_read_share: $R.share.cache_read, subagent_runs: $R.subagent_runs,
             by_model: (reduce ($R.by_model[] | select(.cost_usd != null)) as $b ({}; .[$b.model] += $b.cost_usd)
                        | map_values(r4)),
             quota: (if $quota == null then null
                     else [$quota.limits[] | {window_minutes, peak_pct, latest_pct}] end)}
            | tojson
          elif $R.api_turns == 0 then "X\tno Codex usage in window"
          else
            (if $sid == "" then "H\trdf tokens — codex · \($plabel) · since \($since) · list-price estimate"
             else "H\trdf tokens — codex session \($sid) · list-price estimate" end),
            "H\tsessions \($R.sessions) · subagent runs \($R.subagent_runs) · api turns \($R.api_turns) · reasoning \($R.tokens.reasoning) of \($R.tokens.output) output tokens",
            "B",
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
          end
    ' "${_TOK_WORK}/rows"
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

# _tok_render — format the tagged text lines from _tok_report
_tok_render() {
    local tag a b c d
    while IFS=$'\t' read -r tag a b c d; do
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
        esac
    done
}

main() {
    local project="" tdir="" sid="" sid_set=0 days="30" since="" mode="text" plabel codex=0 pricing=0
    local logical physical croot quota

    while [ $# -gt 0 ]; do
        case "$1" in
            --project)     [ $# -ge 2 ] || _tok_die "--project needs a value" 2; project="$2"; shift 2 ;;
            --transcripts) [ $# -ge 2 ] || _tok_die "--transcripts needs a value" 2; tdir="$2"; shift 2 ;;
            --session)     [ $# -ge 2 ] || _tok_die "--session needs a value" 2; sid="$2"; sid_set=1; shift 2 ;;
            --days)        [ $# -ge 2 ] || _tok_die "--days needs a value" 2; days="$2"; shift 2 ;;
            --since)       [ $# -ge 2 ] || _tok_die "--since needs a value" 2; since="$2"; shift 2 ;;
            --json)        mode="json"; shift ;;
            --summary)     mode="summary"; shift ;;
            --codex)       codex=1; shift ;;
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

    _TOK_WORK="$(command mktemp -d "${TMPDIR:-/tmp}/rdf-tokens.XXXXXX")"

    if [ "$codex" -eq 1 ]; then
        if [ "$sid_set" -eq 1 ]; then
            plabel="session"
        else
            logical="$(cd "${project:-.}" 2>/dev/null && pwd)" || _tok_die "no such directory: ${project:-.}" 1  # unreadable dir reported as missing
            physical="$(cd "${project:-.}" && pwd -P)"
            plabel="$(command basename "$logical")"
            _tok_window "$days" "$since"
        fi
        croot="${CODEX_HOME:-${HOME}/.codex}/sessions"
        _tok_codex_files "$sid" "${logical:-}" "${physical:-}"
        _tok_codex_rows "${logical:-}" "${physical:-}" "$sid"
        quota="null"
        [ "$sid_set" -eq 1 ] || quota="$(_tok_codex_quota "$croot")"
        if [ "$mode" = "text" ]; then
            _tok_codex_report text "$plabel" "$sid" "$croot" "$quota" | _tok_render
        else
            _tok_codex_report "$mode" "$plabel" "$sid" "$croot" "$quota"
        fi
        return 0
    fi

    if [ "$sid_set" -eq 1 ]; then
        plabel="session"
    else
        if [ -n "$tdir" ]; then
            [ -d "$tdir" ] || _tok_die "transcripts directory not found: ${tdir}" 1
            plabel="$(command basename "$tdir")"
        else
            tdir="$(_tok_resolve_dir "${project:-.}")"
            plabel="$(command basename "$(cd "${project:-.}" && pwd)")"
        fi
        _tok_window "$days" "$since"
    fi

    _tok_files "$tdir" "$sid"
    _tok_agent_map
    _tok_rows

    if [ "$mode" = "text" ]; then
        _tok_report text "$plabel" "$sid" "$tdir" | _tok_render
    else
        _tok_report "$mode" "$plabel" "$sid" "$tdir"
    fi
}

main "$@"
