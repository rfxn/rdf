#!/usr/bin/env bats
# tests/tokens.bats — rdf tokens (state/rdf-tokens.sh) and the session_last tokens pass-through
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: reads the committed fixture tree tests/fixtures/tokens/proj (dollar
# figures hand-computed in the spec §10a); every write goes to a mktemp dir.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC
TOK="${RDF_SRC}/state/rdf-tokens.sh"
FX="${RDF_SRC}/tests/fixtures/tokens/proj"

_tok() { bash "$TOK" "$@"; }

# every test gets its own row cache and no Codex home unless it sets CODEX_HOME
setup() {
    RDF_TOKENS_CACHE="$(mktemp -d)"
    export RDF_TOKENS_CACHE
    export CODEX_HOME="${RDF_TOKENS_CACHE}/no-codex"
}

teardown() {
    rm -rf "$RDF_TOKENS_CACHE"
}

@test "--json on the fixture reproduces the hand-computed report" {
    run _tok --transcripts "$FX" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    j="$output"
    [ "$(jq -c '[.sessions,.api_turns,.main_turns,.subagent_turns,.subagent_runs]' <<< "$j")" = "[2,6,3,3,2]" ]
    [ "$(jq -c '.tokens' <<< "$j")" = '{"input":121,"cache_write_5m":30000,"cache_write_1h":1000,"cache_read":420000,"output":4000,"thinking":500}' ]
    [ "$(jq -c '.cost_usd' <<< "$j")" = "0.3981" ]
    [ "$(jq -c '.share' <<< "$j")" = '{"input":0.0002,"cache_write":0.5853,"cache_read":0.211,"output":0.2035}' ]
    [ "$(jq -c '.by_model' <<< "$j")" = '[{"model":"claude-opus-5-5","turns":4,"cost_usd":0.2681},{"model":"claude-fable-5-1","turns":1,"cost_usd":0.13},{"model":"claude-mystery-9","turns":1,"cost_usd":null}]' ]
    [ "$(jq -c '.by_agent' <<< "$j")" = '[{"agent":"main","runs":2,"turns":3,"cost_usd":0.1481},{"agent":"general-purpose","runs":1,"turns":1,"cost_usd":0.13},{"agent":"rdf-engineer","runs":1,"turns":2,"cost_usd":0.12}]' ]
    [ "$(jq -c '.main_context' <<< "$j")" = '{"median":101010,"p90":300005,"over_200k_pct":33.3}' ]
    [ "$(jq -c '.subagent_boot' <<< "$j")" = '{"median_cache_write":10000,"runs":2}' ]
    [ "$(jq -c '.effort' <<< "$j")" = '{"high":1,"medium":2,"unset":1,"xhigh":2}' ]
}

@test "dedups repeated message.id entries (usage counted once)" {
    [ "$(grep -c '"msg_A"' "${FX}/s1.jsonl")" = "3" ]
    run _tok --transcripts "$FX" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.main_turns, .tokens.cache_write_1h, .tokens.thinking]' <<< "$output")" = "[3,1000,500]" ]
}

@test "labels subagents by meta agentType including workflow subagents" {
    run _tok --transcripts "$FX" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.by_agent[].agent] | sort | join(",")' <<< "$output")" = "general-purpose,main,rdf-engineer" ]
}

@test "skips synthetic, id-less and malformed entries" {
    run _tok --transcripts "$FX" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '[.by_model[].model] | index("<synthetic>")' <<< "$output")" = "null" ]
    [ "$(jq -c '[.api_turns, .tokens.input]' <<< "$output")" = "[6,121]" ]
}

@test "--since excludes older entries" {
    run _tok --transcripts "$FX" --since 2026-07-01 --json
    [ "$(jq -c '.api_turns' <<< "$output")" = "7" ]
    run _tok --transcripts "$FX" --since 2026-09-21 --json
    [ "$(jq -c '[.api_turns, .by_model[0].model]' <<< "$output")" = '[1,"claude-mystery-9"]' ]
}

@test "--session includes out-of-window rows and only that session" {
    RDF_CLAUDE_PROJECTS="${RDF_SRC}/tests/fixtures/tokens" run _tok --session s1 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.session, .api_turns, .cost_usd, .subagent_runs]' <<< "$output")" = '["s1",6,0.4001,2]' ]
}

@test "--summary emits the compact session object" {
    RDF_CLAUDE_PROJECTS="${RDF_SRC}/tests/fixtures/tokens" run _tok --session s1 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -r 'keys | join(",")' <<< "$output")" = "api_turns,by_model,cache_read_share,cost_usd,main_ctx_median,rebuild_cost_usd,rebuild_events,session,subagent_runs" ]
    [ "$(jq -c '.by_model' <<< "$output")" = '{"claude-opus-5-5":0.2701,"claude-fable-5-1":0.13}' ]
}

@test "unknown model is reported unpriced and excluded from shares" {
    run _tok --transcripts "$FX" --since 2026-09-01 --json
    [ "$(jq -c '.unpriced_models' <<< "$output")" = '["claude-mystery-9"]' ]
    [ "$(jq '[.share[]] | add' <<< "$output")" = "1" ]
}

@test "text output shows spend and by-agent rows" {
    run _tok --transcripts "$FX" --since 2026-09-01
    [ "$status" -eq 0 ]
    [[ "$output" == *'spend  $0.40'* ]]
    [[ "$output" == *'unpriced models    claude-mystery-9'* ]]
    echo "$output" | grep -qE '^  rdf-engineer +1 +2 +\$0\.12$'
}

@test "empty window prints no usage and exits 0" {
    run _tok --transcripts "$FX" --since 2030-01-01
    [ "$status" -eq 0 ]
    [ "$output" = "no usage in window" ]
}

@test "bad --days and bad --session exit 2; missing transcripts exit 1" {
    run _tok --days abc
    [ "$status" -eq 2 ]
    run _tok --session ../x
    [ "$status" -eq 2 ]
    run _tok --session ""
    [ "$status" -eq 2 ]
    local empty proj
    empty="$(mktemp -d)"; proj="$(mktemp -d)"
    RDF_CLAUDE_PROJECTS="$empty" run _tok --project "$proj"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no transcripts for"* ]]
    rm -rf "$empty" "$proj"
}

@test "rdf tokens wrapper forwards help and exit codes" {
    run "${RDF_SRC}/bin/rdf" tokens help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: rdf tokens"* ]]
    run "${RDF_SRC}/bin/rdf" tokens --days abc
    [ "$status" -eq 2 ]
}

# _tok_row sid id model ts — one assistant entry billing 1M input tokens
_tok_row() {
    printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"id":"%s","model":"%s","usage":{"input_tokens":1000000,"output_tokens":0}}}\n' "$4" "$1" "$2" "$3"
}

@test "prices [1m] and dated model ids, labels a meta-less subagent unknown, dedups across files, falls back to the physical slug" {
    local root cc tdir
    root="$(mktemp -d)"; cc="${root}/cc"
    mkdir -p "${root}/real"; ln -s real "${root}/link"
    tdir="${cc}/$(cd "${root}/real" && pwd -P | sed 's/[^A-Za-z0-9-]/-/g')"
    mkdir -p "${tdir}/s10/subagents"
    { _tok_row s9 msg_X 'claude-opus-5-5[1m]' 2026-09-10T00:00:00Z
      _tok_row s9 msg_Y claude-haiku-4-5-20251001 2026-09-10T00:01:00Z; } > "${tdir}/s9.jsonl"
    { _tok_row s10 msg_Y claude-haiku-4-5-20251001 2026-09-10T00:01:00Z
      _tok_row s10 msg_W claude-haiku-4-5-20251001 2026-09-10T00:02:00Z; } > "${tdir}/s10.jsonl"
    _tok_row s10 msg_Z claude-sonnet-5 2026-09-10T00:03:00Z > "${tdir}/s10/subagents/agent-z.jsonl"
    RDF_CLAUDE_PROJECTS="$cc" run _tok --claude --project "${root}/link" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.scope.transcripts' <<< "$output")" = "$tdir" ]
    [ "$(jq -c '[.api_turns, .sessions, .cost_usd, .unpriced_models]' <<< "$output")" = '[4,2,8,[]]' ]
    [ "$(jq -c '[.by_model[] | [.model, .turns, .cost_usd]] | sort' <<< "$output")" = '[["claude-haiku-4-5-20251001",2,2],["claude-opus-5-5[1m]",1,4],["claude-sonnet-5",1,2]]' ]
    [ "$(jq -c '[.by_agent[] | select(.agent == "unknown") | [.runs, .turns, .cost_usd]]' <<< "$output")" = '[[1,1,2]]' ]
    rm -rf "$root"
}

@test "dangling subagent symlinks are skipped and a symlinked transcripts dir is read" {
    local t; t="$(mktemp -d)"
    cp -R "$FX" "${t}/real"
    ln -s /nonexistent/agent-x.jsonl "${t}/real/s1/subagents/agent-zz.jsonl"
    ln -s real "${t}/link"
    run _tok --transcripts "${t}/link" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[6,0.3981]" ]
    RDF_CLAUDE_PROJECTS="$t" run _tok --session s1 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[6,0.4001]" ]
    rm -rf "$t"
}

@test "malformed subagent meta and non-object rows are skipped, not fatal" {
    local t; t="$(mktemp -d)"
    cp -R "$FX" "${t}/proj"
    printf '{"agentType":' > "${t}/proj/s1/subagents/agent-a1.meta.json"
    printf '"str"' > "${t}/proj/s1/subagents/workflows/wf_x/agent-w1.meta.json"
    printf '%s\n' '{"type":"assistant","message":"x","timestamp":"2026-09-20T00:00:00Z"}' \
        '{"type":"assistant","message":{"id":"msg_T","model":"claude-opus-5-5","usage":{"input_tokens":1}},"timestamp":42}' >> "${t}/proj/s2.jsonl"
    run _tok --transcripts "${t}/proj" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[6,0.3981]" ]
    [ "$(jq -r '[.by_agent[].agent] | sort | join(",")' <<< "$output")" = "main,unknown" ]
    rm -rf "$t"
}

@test "--days with leading zeros is decimal; zero days and impossible --since dates exit 2" {
    run _tok --transcripts "$FX" --days 010 --json
    [ "$status" -eq 0 ]
    local a; a="$(jq -r '.scope.since[0:10]' <<< "$output")"
    run _tok --transcripts "$FX" --days 10 --json
    [ "$(jq -r '.scope.since[0:10]' <<< "$output")" = "$a" ]
    run _tok --transcripts "$FX" --days 08 --json
    [ "$status" -eq 0 ]
    run _tok --transcripts "$FX" --days 00
    [ "$status" -eq 2 ]
    run _tok --transcripts "$FX" --since 2026-13-45
    [ "$status" -eq 2 ]
    [[ "$output" == *"--since expects a valid YYYY-MM-DD date"* ]]
    run _tok --transcripts "$FX" --since 2026-02-30
    [ "$status" -eq 2 ]
}

# _tok_turn id ts in cw5 cw1h cr [out] — one claude-opus-5-5 entry with split cache-write usage
_tok_turn() {
    printf '{"type":"assistant","timestamp":"%s","sessionId":"r1","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s}}}}\n' \
        "$2" "$1" "$3" "$(( $4 + $5 ))" "$6" "${7:-0}" "$4" "$5"
}

# _tok_rb dir — the rebuilds object for a transcripts dir
_tok_rb() {
    bash "$TOK" --transcripts "$1" --since 2026-09-01 --json | jq -c '.rebuilds'
}

@test "cache rebuild: a 5m write of half a 50K context after a 400 s idle counts at the write premium" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.250Z 1 20000 0 0
      _tok_turn m2 2026-09-10T00:06:40.900Z 1 25000 0 24999; } > "${t}/s.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$output" = '{"events":1,"tokens":25000,"cost_usd":0.12,"share":0.5217,"median_gap_s":401,"main":{"events":1,"cost_usd":0.12},"sub":{"events":0,"cost_usd":0}}' ]
    rm -rf "$t"
}

@test "cache rebuild: under half the context written, or a context under 50K, is not a rebuild" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 20000 0 0
      _tok_turn m2 2026-09-10T00:06:40.000Z 1 24999 0 25000; } > "${t}/half.jsonl"
    { _tok_turn n1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn n2 2026-09-10T00:06:40.000Z 1 49998 0 0; } > "${t}/small.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .cost_usd]' <<< "$output")" = "[0,0]" ]
    rm -rf "$t"
}

@test "cache rebuild: a large 5m write 100 s or exactly 300 s after the previous turn is not a rebuild" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:01:40.000Z 1 60000 0 0
      _tok_turn m3 2026-09-10T00:06:40.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.events' <<< "$output")" = "0" ]
    rm -rf "$t"
}

@test "cache rebuild: a large 5m write 301 s after the previous turn counts" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:05:01.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .median_gap_s]' <<< "$output")" = "[1,301]" ]
    rm -rf "$t"
}

@test "cache rebuild: fractional seconds count (300.9 s is a rebuild, 299.9 s is not)" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:05:00.900Z 1 60000 0 0; } > "${t}/over.jsonl"
    { _tok_turn n1 2026-09-10T00:00:00.500Z 1 1000 0 0
      _tok_turn n2 2026-09-10T00:05:00.400Z 1 60000 0 0; } > "${t}/under.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .median_gap_s]' <<< "$output")" = "[1,301]" ]
    rm -rf "$t"
}

@test "cache rebuild: a 1h write counts only past the 1h TTL (1,200 s no, 4,000 s yes)" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 0 1000 0
      _tok_turn m2 2026-09-10T00:20:00.000Z 1 0 60000 0
      _tok_turn m3 2026-09-10T01:26:40.000Z 1 0 60000 0; } > "${t}/s.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .tokens, .cost_usd, .median_gap_s]' <<< "$output")" = "[1,60000,0.468,4000]" ]
    rm -rf "$t"
}

@test "cache rebuild: a 1h write 3,600 s after the previous turn is not a rebuild, 3,601 s is" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 0 1000 0
      _tok_turn m2 2026-09-10T01:00:00.000Z 1 0 60000 0
      _tok_turn m3 2026-09-10T02:00:01.000Z 1 0 60000 0; } > "${t}/s.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .median_gap_s]' <<< "$output")" = "[1,3601]" ]
    rm -rf "$t"
}

@test "cache rebuild: equal 5m and 1h writes use the 5m TTL (400 s counts)" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:06:40.000Z 1 30000 30000 0; } > "${t}/s.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .tokens, .cost_usd]' <<< "$output")" = "[1,60000,0.378]" ]
    rm -rf "$t"
}

@test "cache rebuild: the TTL comes from the current turn's writes, not the previous turn's" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:20:00.000Z 1 0 60000 0; } > "${t}/to1h.jsonl"
    { _tok_turn n1 2026-09-10T00:00:00.000Z 1 0 1000 0
      _tok_turn n2 2026-09-10T00:06:40.000Z 1 60000 0 0; } > "${t}/to5m.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .median_gap_s]' <<< "$output")" = "[1,400]" ]
    rm -rf "$t"
}

@test "cache rebuild: a transcript's first turn never counts, even a large write long after another file's turn" {
    local t; t="$(mktemp -d)"
    mkdir -p "${t}/s/subagents"
    _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0 > "${t}/s.jsonl"
    { _tok_turn a1 2026-09-10T00:10:00.000Z 1 100000 0 0
      _tok_turn a2 2026-09-10T00:11:00.000Z 1 0 0 100000; } > "${t}/s/subagents/agent-a.jsonl"
    _tok_turn x1 2026-09-10T02:00:00.000Z 1 100000 0 0 > "${t}/x.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.events' <<< "$output")" = "0" ]
    rm -rf "$t"
}

@test "cache rebuild: a parent's rebuild copied into a fork counts once, whichever file is read first" {
    local t d parent fork
    t="$(mktemp -d)"
    for d in a b; do
        if [ "$d" = a ]; then parent=agent-p; fork=agent-f; else parent=agent-f; fork=agent-p; fi
        mkdir -p "${t}/${d}/s/subagents"
        _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0 > "${t}/${d}/s.jsonl"
        { _tok_turn p1 2026-09-10T00:00:10.000Z 1 5000 0 200000
          _tok_turn p2 2026-09-10T00:20:00.000Z 1 193169 0 17836; } > "${t}/${d}/s/subagents/${parent}.jsonl"
        { _tok_turn p2 2026-09-10T00:20:00.000Z 1 193169 0 17836
          _tok_turn f1 2026-09-10T00:20:05.000Z 1 1796 0 211005; } > "${t}/${d}/s/subagents/${fork}.jsonl"
        run _tok_rb "${t}/${d}"
        [ "$status" -eq 0 ]
        [ "$(jq -c '[.events, .tokens, .sub.events, .median_gap_s]' <<< "$output")" = "[1,193169,1,1190]" ]
    done
    rm -rf "$t"
}

@test "cache rebuild: a resumed transcript that copies a rebuild counts it once and counts its own" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:10:00.000Z 1 60000 0 0; } > "${t}/s1.jsonl"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:10:00.000Z 1 60000 0 0
      _tok_turn m3 2026-09-10T02:00:00.000Z 1 80000 0 0; } > "${t}/s2.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .tokens, .main.events]' <<< "$output")" = "[2,140000,2]" ]
    rm -rf "$t"
}

@test "cache rebuild: a turn up to an hour before the window is a predecessor only, never counted or priced" {
    local t; t="$(mktemp -d)"
    { _tok_turn a0 2026-09-09T23:20:00.000Z 1 1000 0 0
      _tok_turn a1 2026-09-09T23:50:00.000Z 1 60000 0 0
      _tok_turn b1 2026-09-10T00:01:00.000Z 1 60000 0 0; } > "${t}/near.jsonl"
    { _tok_turn c1 2026-09-09T22:00:00.000Z 1 1000 0 0
      _tok_turn d1 2026-09-10T00:30:00.000Z 1 60000 0 0; } > "${t}/far.jsonl"
    run _tok --transcripts "$t" --since 2026-09-10 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .tokens.cache_write_5m, .cost_usd]' <<< "$output")" = "[2,120000,0.6]" ]
    [ "$(jq -c '[.rebuilds.events, .rebuilds.tokens, .rebuilds.cost_usd, .rebuilds.median_gap_s]' <<< "$output")" = "[1,60000,0.288,660]" ]
    rm -rf "$t"
}

@test "cache rebuild: a turn that starts before the window is not counted even if it ends inside it" {
    local t; t="$(mktemp -d)"
    { _tok_turn p1 2026-09-09T23:50:00.000Z 1 1000 0 0
      _tok_turn m1 2026-09-09T23:59:59.000Z 1 60000 0 0
      _tok_turn m1 2026-09-10T00:00:01.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    run _tok --transcripts "$t" --since 2026-09-10 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .rebuilds.events]' <<< "$output")" = "[1,0]" ]
    rm -rf "$t"
}

@test "merged message entries: a message straddling the window start counts only its in-window entries, even when an earlier entry holds the larger usage" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-09T23:59:59.000Z 1 1000 0 0 900
      _tok_turn m1 2026-09-10T00:00:01.000Z 1 1000 0 0 10
      _tok_turn m2 2026-09-10T01:00:00.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    run _tok --transcripts "$t" --since 2026-09-10 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .tokens.output, .rebuilds.events, .rebuilds.median_gap_s, .cost_usd]' <<< "$output")" = "[2,10,1,3601,0.3052]" ]
    rm -rf "$t"
}

@test "merged message entries: entries of one message with different metadata are priced separately" {
    local t; t="$(mktemp -d)"
    printf '%s\n' '{"type":"assistant","timestamp":"2026-09-09T23:59:59.000Z","sessionId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":0,"speed":"standard"}}}' \
        '{"type":"assistant","timestamp":"2026-09-10T00:00:01.000Z","sessionId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":0,"speed":"fast"}}}' > "${t}/s.jsonl"
    run _tok --transcripts "$t" --since 2026-09-10 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[1,8]" ]
    rm -rf "$t"
}

@test "merged message entries: a message straddling the lookback start is timed from its first entry inside the lookback" {
    local t; t="$(mktemp -d)"
    { _tok_turn q1 2026-09-09T22:59:59.000Z 1 1000 0 0
      _tok_turn q1 2026-09-09T23:00:30.000Z 1 1000 0 0
      _tok_turn r1 2026-09-10T00:00:00.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    run _tok --transcripts "$t" --since 2026-09-10 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .rebuilds.events, .rebuilds.median_gap_s]' <<< "$output")" = "[1,1,3570]" ]
    rm -rf "$t"
}

@test "cache rebuild: main and subagent rebuilds are split, and text and --summary report them" {
    local t; t="$(mktemp -d)"
    mkdir -p "${t}/s/subagents"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2026-09-10T00:10:00.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    { _tok_turn a1 2026-09-10T00:20:00.000Z 1 1000 0 0
      _tok_turn a2 2026-09-10T00:26:00.000Z 1 60000 0 40000
      _tok_turn a3 2026-09-10T02:00:00.000Z 1 0 60000 0; } > "${t}/s/subagents/agent-a.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.events, .tokens, .median_gap_s, .main, .sub]' <<< "$output")" = '[3,180000,600,{"events":1,"cost_usd":0.288},{"events":2,"cost_usd":0.756}]' ]
    run _tok --transcripts "$t" --since 2026-09-01 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.rebuild_events, .rebuild_cost_usd]' <<< "$output")" = "[3,1.044]" ]
    run _tok --transcripts "$t" --since 2026-09-01
    [ "$status" -eq 0 ]
    [[ "$output" == *'cache rebuilds     3 (main 1 · sub 2) · $1.04 extra ('*'% of spend) · median idle 10m'* ]]
    rm -rf "$t"
}

@test "cache rebuild: partial then final entries for one message.id are one turn, timed from its first entry" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0 50
      _tok_turn m2 2026-09-10T00:06:40.000Z 1 60000 0 0 10
      _tok_turn m2 2026-09-10T00:13:20.000Z 1 60000 0 0 900
      _tok_turn m3 2026-09-10T00:16:40.000Z 1 70000 0 0; } > "${t}/s.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .tokens.output, .rebuilds.events, .rebuilds.tokens, .rebuilds.median_gap_s]' <<< "$output")" = "[3,950,2,130000,400]" ]
    rm -rf "$t"
}

@test "cache rebuild: an unparseable or non-Z timestamp is kept as a turn but forms no gap" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2026-09-10T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 zzzz 1 60000 0 0
      _tok_turn m3 2026-09-10T00:10:00.000 1 60000 0 0
      _tok_turn m4 2026-09-10T00:10:00.000+00:00 1 60000 0 0
      _tok_turn m5 2026-13-45T00:00:00.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .rebuilds.events]' <<< "$output")" = "[5,0]" ]
    rm -rf "$t"
}

@test "cache rebuild: an impossible date (Feb 30) forms no gap" {
    local t; t="$(mktemp -d)"
    { _tok_turn m1 2027-02-28T00:00:00.000Z 1 1000 0 0
      _tok_turn m2 2027-02-30T00:06:40.000Z 1 60000 0 0; } > "${t}/s.jsonl"
    run _tok_rb "$t"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.events' <<< "$output")" = "0" ]
    rm -rf "$t"
}

# ── pricing rules ────────────────────────────────────────────────────────────

# _tok_u sid id model ts usage-json — one assistant entry with an explicit usage object
_tok_u() {
    printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"id":"%s","model":"%s","usage":%s}}\n' "$4" "$1" "$2" "$3" "$5"
}

# _tok_models dir — sorted [model, turns, cost] triples for a transcripts dir
_tok_models() {
    bash "$TOK" --transcripts "$1" --since 2026-09-01 --json | jq -c '[.by_model[] | [.model, .turns, .cost_usd]] | sort'
}

@test "pricing: Sonnet 5.5 cache reads cost its own 0.05x rate, not Sonnet 5's" {
    local t; t="$(mktemp -d)"
    { _tok_u s1 a claude-sonnet-5-5 2026-09-10T00:00:00Z '{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":1000000}'
      _tok_u s1 b claude-sonnet-5 2026-09-10T00:01:00Z '{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":1000000}'; } > "${t}/s1.jsonl"
    run _tok_models "$t"
    [ "$status" -eq 0 ]
    [ "$output" = '[["claude-sonnet-5",1,0.2],["claude-sonnet-5-5",1,0.1]]' ]
    rm -rf "$t"
}

@test "pricing: a Haiku 5.5 prompt over 100K tokens, cache reads included, uses the long-prompt tier" {
    local t; t="$(mktemp -d)"
    { _tok_u s1 a claude-haiku-5-5 2026-09-10T00:00:00Z '{"input_tokens":100000,"output_tokens":0}'
      _tok_u s1 b claude-haiku-5-5 2026-09-10T00:01:00Z '{"input_tokens":50000,"output_tokens":0,"cache_read_input_tokens":60000}'; } > "${t}/s1.jsonl"
    run _tok_models "$t"
    [ "$status" -eq 0 ]
    [ "$output" = '[["claude-haiku-5-5",2,0.038]]' ]
    rm -rf "$t"
}

@test "pricing: fast mode scales every class from the fast input price; US residency adds 1.1x only on 4.6+ models" {
    local t; t="$(mktemp -d)"
    { _tok_u s1 a claude-opus-5-5 2026-09-10T00:00:00Z '{"input_tokens":1000000,"output_tokens":1000000,"cache_read_input_tokens":1000000,"speed":"fast"}'
      _tok_u s1 b claude-opus-5-5 2026-09-10T00:01:00Z '{"input_tokens":0,"output_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":1000000},"speed":"fast"}'
      _tok_u s1 c claude-opus-5-5 2026-09-10T00:02:00Z '{"input_tokens":1000000,"output_tokens":0,"inference_geo":"us"}'
      _tok_u s1 d claude-opus-5-5 2026-09-10T00:03:00Z '{"input_tokens":1000000,"output_tokens":0,"speed":"fast","inference_geo":"us"}'
      _tok_u s1 e claude-haiku-4-5 2026-09-10T00:04:00Z '{"input_tokens":1000000,"output_tokens":0,"inference_geo":"us"}'; } > "${t}/s1.jsonl"
    run _tok_models "$t"
    [ "$status" -eq 0 ]
    [ "$output" = '[["claude-haiku-4-5",1,1],["claude-opus-5-5",4,87.6]]' ]
    rm -rf "$t"
}

@test "pricing: an unlisted newer model id reports unpriced instead of borrowing a sibling's price" {
    local t; t="$(mktemp -d)"
    { _tok_row s1 a claude-opus-5-6 2026-09-10T00:00:00Z
      _tok_row s1 b claude-opus-4-1-20250805 2026-09-10T00:01:00Z
      _tok_row s1 c 'claude-opus-4-8@20260101' 2026-09-10T00:02:00Z; } > "${t}/s1.jsonl"
    run bash "$TOK" --transcripts "$t" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.cost_usd, .unpriced_models]' <<< "$output")" = '[20,["claude-opus-5-6"]]' ]
    rm -rf "$t"
}

@test "--pricing --json carries the date, its age, the source pages and both vendors' tables" {
    run _tok --pricing --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.as_of | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")' <<< "$output")" = "true" ]
    [ "$(jq -r '.age_days | type' <<< "$output")" = "number" ]
    [ "$(jq -r '.expires == null or .expires >= .as_of' <<< "$output")" = "true" ]
    [ "$(jq -r '.sources.anthropic' <<< "$output")" = "https://platform.claude.com/docs/en/about-claude/pricing" ]
    [ "$(jq -r '.sources.openai' <<< "$output")" = "https://developers.openai.com/api/docs/pricing" ]
    [ "$(jq -c '.anthropic["claude-sonnet-5-5"] | [.in, .cr, .cw5, .cw1h]' <<< "$output")" = "[2,0.1,2.5,4]" ]
    [ "$(jq -c '.openai["gpt-6-sol"] | [.in, .cr, .cw, .out]' <<< "$output")" = "[2,0.2,2.5,10]" ]
    run _tok --pricing
    [ "$status" -eq 0 ]
    [[ "$output" == *"https://platform.claude.com/docs/en/about-claude/pricing"* ]]
    [[ "$output" == *"claude-opus-5-5"*"fast 8/40"* ]]
    run _tok --pricing --summary
    [ "$status" -eq 2 ]
}

# ── Codex rollouts (--codex) ─────────────────────────────────────────────────

# _cx_meta ts id cwd / _cx_ctx ts model / _cx_tok ts in cached cw out reasoning — rollout records
_cx_meta() { printf '{"timestamp":"%s","type":"session_meta","payload":{"id":"%s","cwd":"%s"}}\n' "$1" "$2" "$3"; }
_cx_ctx() { printf '{"timestamp":"%s","type":"turn_context","payload":{"model":"%s"}}\n' "$1" "$2"; }
_cx_tok() {
    printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":%s,"cached_input_tokens":%s,"cache_write_input_tokens":%s,"output_tokens":%s,"reasoning_output_tokens":%s,"total_tokens":%s}}}}\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$(( $2 + $5 ))"
}

# _cx_home — a CODEX_HOME with one day directory; prints its path
_cx_home() {
    local h; h="$(mktemp -d)"
    mkdir -p "${h}/sessions/2026/10/02"
    printf '%s' "$h"
}

@test "codex: cumulative totals become per-turn deltas; a repeated event counts once; cached and cache-write split out of input" {
    local h p; h="$(_cx_home)"; p="$(mktemp -d)"
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"
      _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      _cx_tok 2026-10-02T10:00:10Z 1000000 600000 100000 100000 50000
      _cx_tok 2026-10-02T10:00:15Z 1000000 600000 100000 100000 50000
      _cx_tok 2026-10-02T10:01:00Z 2000000 1500000 100000 150000 60000; } > "${h}/sessions/2026/10/02/rollout-a.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.source, .sessions, .api_turns, .cost_usd]' <<< "$output")" = '["codex",1,2,2.85]' ]
    [ "$(jq -c '.tokens' <<< "$output")" = '{"input":400000,"cached_input":1500000,"cache_write":100000,"output":150000,"reasoning":60000}' ]
    rm -rf "$h" "$p"
}

@test "codex: a model switch re-attributes later deltas, an unknown model is unpriced, a dropped total restarts the sequence" {
    local h p; h="$(_cx_home)"; p="$(mktemp -d)"
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"
      _cx_ctx 2026-10-02T10:00:00Z gpt-5.6-sol
      _cx_tok 2026-10-02T10:00:10Z 100000 0 0 10000 0
      _cx_ctx 2026-10-02T10:01:00Z codex-auto-review
      _cx_tok 2026-10-02T10:01:10Z 150000 0 0 20000 0
      _cx_tok 2026-10-02T10:02:10Z 30000 0 0 1000 0; } > "${h}/sessions/2026/10/02/rollout-a.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .cost_usd, .unpriced_models]' <<< "$output")" = '[3,0.6,["codex-auto-review"]]' ]
    [ "$(jq -c '[.by_model[] | [.model, .turns, .cost_usd]] | sort' <<< "$output")" = '[["codex-auto-review",2,null],["gpt-5.6-sol",1,0.6]]' ]
    rm -rf "$h" "$p"
}

@test "codex: scope is the project's cwd or below it, not a sibling sharing its prefix; --session finds any project" {
    local h p d; h="$(_cx_home)"; p="$(mktemp -d)"; d="${h}/sessions/2026/10/02"
    mkdir -p "${p}/proj/sub" "${p}/proj-other"
    { _cx_meta 2026-10-02T10:00:00Z c1 "${p}/proj"; _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      _cx_tok 2026-10-02T10:00:10Z 1000000 0 0 0 0; } > "${d}/rollout-1.jsonl"
    { _cx_meta 2026-10-02T10:00:00Z c2 "${p}/proj/sub"; _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      _cx_tok 2026-10-02T10:00:10Z 1000000 0 0 0 0; } > "${d}/rollout-2.jsonl"
    { _cx_meta 2026-10-02T10:00:00Z c3 "${p}/proj-other"; _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      _cx_tok 2026-10-02T10:00:10Z 1000000 0 0 0 0; } > "${d}/rollout-3.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "${p}/proj" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.sessions, .api_turns, .cost_usd]' <<< "$output")" = '[2,2,4]' ]
    CODEX_HOME="$h" run _tok --codex --session c3 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.source, .session, .api_turns, .cost_usd]' <<< "$output")" = '["codex","c3",1,2]' ]
    rm -rf "$h" "$p"
}

@test "codex: a delta before the window is excluded but still serves as the baseline" {
    local h p; h="$(_cx_home)"; p="$(mktemp -d)"
    { _cx_meta 2026-08-01T10:00:00Z c1 "$p"
      _cx_ctx 2026-08-01T10:00:00Z gpt-6-sol
      _cx_tok 2026-08-01T10:00:10Z 1000000 0 0 0 0
      _cx_tok 2026-10-02T10:00:10Z 1500000 0 0 0 0; } > "${h}/sessions/2026/10/02/rollout-a.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .tokens.input, .cost_usd]' <<< "$output")" = '[1,500000,1]' ]
    rm -rf "$h" "$p"
}

# _cx_sub ts id cwd parent / _cx_set ts tier / _cx_tur ts response-id in cached cw out reasoning
_cx_sub() { printf '{"timestamp":"%s","type":"session_meta","payload":{"id":"%s","cwd":"%s","source":{"subagent":{"thread_spawn":{"parent_thread_id":"%s","depth":1}}}}}\n' "$1" "$2" "$3" "$4"; }
_cx_set() { printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"%s"}}}\n' "$1" "$2"; }
_cx_tur() {
    printf '{"timestamp":"%s","type":"token_usage_record","payload":{"response_id":"%s","usage":{"input_tokens":%s,"cached_input_tokens":%s,"cache_write_input_tokens":%s,"output_tokens":%s,"reasoning_output_tokens":%s}}}\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

@test "codex: per-response records win over token_count, dedup by response id across rollouts, and price Fast and over-272K requests" {
    local h p d; h="$(_cx_home)"; p="$(mktemp -d)"; d="${h}/sessions/2026/10/02"
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"
      _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      _cx_set 2026-10-02T10:00:01Z priority
      _cx_tur 2026-10-02T10:00:10Z r1 300000 0 0 0 0
      _cx_set 2026-10-02T10:01:00Z default
      _cx_tur 2026-10-02T10:01:10Z r2 100000 0 0 10000 0
      _cx_tok 2026-10-02T10:01:20Z 9000000 0 0 9000000 0; } > "${d}/rollout-a.jsonl"
    { _cx_sub 2026-10-02T10:02:00Z c2 "$p" c1
      _cx_meta 2026-10-02T10:02:00Z c1 "$p"
      _cx_ctx 2026-10-02T10:02:00Z gpt-6-sol
      _cx_tur 2026-10-02T10:01:10Z r2 100000 0 0 10000 0
      _cx_ctx 2026-10-02T10:03:00Z gpt-5.1-codex-max
      _cx_tur 2026-10-02T10:03:10Z r3 50000 0 0 0 0; } > "${d}/rollout-b.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.sessions, .subagent_runs, .api_turns, .cost_usd, .unpriced_models]' <<< "$output")" = '[1,1,3,2.7,["gpt-5.1-codex-max"]]' ]
    [ "$(jq -c '[.by_model[] | [.model, .tier, .turns, .cost_usd]] | sort' <<< "$output")" = '[["gpt-5.1-codex-max","standard",1,null],["gpt-6-sol","fast",1,2.4],["gpt-6-sol","standard",1,0.3]]' ]
    CODEX_HOME="$h" run _tok --codex --session c1 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .subagent_runs, .cost_usd]' <<< "$output")" = '[3,1,2.7]' ]
    rm -rf "$h" "$p"
}

@test "codex: a review subagent (source subagent \"review\", no turn_context) counts as a run with an unknown, unpriced model" {
    local h p; h="$(_cx_home)"; p="$(mktemp -d)"
    { printf '{"timestamp":"2026-10-02T10:00:00Z","type":"session_meta","payload":{"id":"rv1","cwd":"%s","source":{"subagent":"review"}}}\n' "$p"
      _cx_tok 2026-10-02T10:00:10Z 50000 0 0 1000 0; } > "${h}/sessions/2026/10/02/rollout-r.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.sessions, .subagent_runs, .api_turns, .cost_usd, .unpriced_models]' <<< "$output")" = '[0,1,1,0,["unknown"]]' ]
    rm -rf "$h" "$p"
}

# _cx_run ts model effort sandbox — turn_context with effort and sandbox / _cx_rl ts json — rate_limits only
_cx_run() { printf '{"timestamp":"%s","type":"turn_context","payload":{"model":"%s","effort":"%s","sandbox_policy":{"type":"%s"}}}\n' "$1" "$2" "$3" "$4"; }
_cx_rl() { printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":%s}}\n' "$1" "$2"; }

@test "codex: kind comes from the sandbox and effort from turn_context; by_kind and by_effort split the cost" {
    local h p d; h="$(_cx_home)"; p="$(mktemp -d)"; d="${h}/sessions/2026/10/02"
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"; _cx_run 2026-10-02T10:00:00Z gpt-6-sol medium read-only
      _cx_tok 2026-10-02T10:00:10Z 1000000 0 0 0 0; } > "${d}/rollout-1.jsonl"
    { _cx_meta 2026-10-02T10:00:00Z c2 "$p"; _cx_run 2026-10-02T10:00:00Z gpt-6-sol high workspace-write
      _cx_tok 2026-10-02T10:00:10Z 500000 0 0 200000 0; } > "${d}/rollout-2.jsonl"
    { _cx_meta 2026-10-02T10:00:00Z c3 "$p"
      printf '{"timestamp":"2026-10-02T10:00:00Z","type":"turn_context","payload":{"model":"gpt-6-sol","collaboration_mode":{"settings":{"reasoning_effort":"xhigh"}},"sandbox_policy":{"type":"danger-full-access"}}}\n'
      _cx_tok 2026-10-02T10:00:10Z 100000 0 0 0 0; } > "${d}/rollout-3.jsonl"
    { printf '{"timestamp":"2026-10-02T10:00:00Z","type":"session_meta","payload":{"id":"rv1","cwd":"%s","source":{"subagent":"review"}}}\n' "$p"
      _cx_tok 2026-10-02T10:00:10Z 50000 0 0 1000 0; } > "${d}/rollout-r.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '.by_kind' <<< "$output")" = '[{"kind":"write","runs":2,"turns":2,"cost_usd":3.2},{"kind":"review","runs":2,"turns":2,"cost_usd":2}]' ]
    [ "$(jq -c '[.by_effort[] | [.effort, .turns, .cost_usd]]' <<< "$output")" = '[["high",1,3],["medium",1,2],["xhigh",1,0.2],["unset",1,0]]' ]
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01
    [ "$status" -eq 0 ]
    [[ "$output" == *"by kind"*"write"*"by effort"*"high"* ]]
    rm -rf "$h" "$p"
}

@test "codex: quota is account-wide, peaks per reset window and per limit, ignores samples before the window, and is null with --session" {
    local h p o d; h="$(_cx_home)"; p="$(mktemp -d)"; o="$(mktemp -d)"; d="${h}/sessions/2026/10/02"
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"; _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      _cx_rl 2026-09-20T10:00:00Z '{"primary":{"used_percent":90,"window_minutes":10080,"resets_at":1790000000},"plan_type":"plus"}'
      _cx_tok 2026-10-02T10:00:10Z 1000000 0 0 0 0
      _cx_rl 2026-10-02T10:00:10Z '{"primary":{"used_percent":5,"window_minutes":10080,"resets_at":1791000000},"secondary":{"used_percent":40,"window_minutes":300,"resets_at":1791018000},"plan_type":"plus"}'
      _cx_rl 2026-10-02T11:00:00Z '{"primary":{"used_percent":12,"window_minutes":10080,"resets_at":1791000001},"plan_type":"plus","rate_limit_reached_type":"primary"}'
      _cx_rl 2026-10-04T10:00:00Z '{"primary":{"used_percent":3,"window_minutes":10080,"resets_at":1791604800},"plan_type":"pro"}'; } > "${d}/rollout-1.jsonl"
    { _cx_meta 2026-10-02T12:00:00Z c9 "$o"; _cx_ctx 2026-10-02T12:00:00Z gpt-6-sol
      _cx_rl 2026-10-02T12:00:00Z '{"primary":{"used_percent":20,"window_minutes":10080,"resets_at":1791000000},"plan_type":"plus"}'; } > "${d}/rollout-9.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .quota.scope, .quota.plan, .quota.limit_reached_events]' <<< "$output")" = '[1,"account","pro",1]' ]
    [ "$(jq -c '.quota.limits' <<< "$output")" = '[{"window_minutes":300,"peak_pct":40,"latest_pct":40,"latest_at":"2026-10-02T10:00:10Z","windows":[{"resets_at":"2026-10-03T09:00:00Z","peak_pct":40}]},{"window_minutes":10080,"peak_pct":20,"latest_pct":3,"latest_at":"2026-10-04T10:00:00Z","windows":[{"resets_at":"2026-10-03T04:00:01Z","peak_pct":20},{"resets_at":"2026-10-10T04:00:00Z","peak_pct":3}]}]' ]
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --summary
    [ "$(jq -c '.quota' <<< "$output")" = '[{"window_minutes":300,"peak_pct":40,"latest_pct":40},{"window_minutes":10080,"peak_pct":20,"latest_pct":3}]' ]
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01
    [[ "$output" == *"quota, 7-day window (account-wide): peak 20% · latest 3%"*"2 windows"* ]]
    [[ "$output" == *"quota, 5-hour window"*"plan pro · limit reached 1 times"* ]]
    CODEX_HOME="$h" run _tok --codex --session c1 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '.quota' <<< "$output")" = 'null' ]
    rm -rf "$h" "$p" "$o"
}

@test "codex: Fast uses the model's Fast rate; Fast without one, or an unknown tier, is unpriced, never Standard" {
    local h p d; h="$(_cx_home)"; p="$(mktemp -d)"; d="${h}/sessions/2026/10/02"
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"
      _cx_ctx 2026-10-02T10:00:00Z gpt-5.2
      _cx_set 2026-10-02T10:00:01Z priority
      _cx_tur 2026-10-02T10:00:10Z f1 1000000 0 0 0 0
      _cx_ctx 2026-10-02T10:01:00Z gpt-5.6-cyber
      _cx_tur 2026-10-02T10:01:10Z f2 1000000 0 0 0 0
      _cx_ctx 2026-10-02T10:02:00Z gpt-6-sol
      _cx_set 2026-10-02T10:02:01Z ultrafast
      _cx_tur 2026-10-02T10:02:10Z f3 1000000 0 0 0 0; } > "${d}/rollout-a.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.cost_usd, .unpriced_models]' <<< "$output")" = '[3.5,["gpt-5.6-cyber (fast)","gpt-6-sol (ultrafast)"]]' ]
    rm -rf "$h" "$p"
}

@test "codex: --transcripts is rejected; a missing Codex home exits 1; an empty window prints no usage" {
    local h p; h="$(_cx_home)"; p="$(mktemp -d)"
    run _tok --codex --transcripts "$p"
    [ "$status" -eq 2 ]
    CODEX_HOME="${p}/none" run _tok --codex --project "$p"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no Codex sessions"* ]]
    CODEX_HOME="$h" run _tok --codex --project "$p"
    [ "$status" -eq 0 ]
    [ "$output" = "no Codex usage in window" ]
    rm -rf "$h" "$p"
}

# _tok_cwd sid id ts cwd — one claude-opus-5-5 entry (1M input tokens, $4) recorded in cwd
_tok_cwd() {
    printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","cwd":"%s","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":0}}}\n' "$3" "$1" "$4" "$2"
}

# _tok_cx_one id cwd — a one-turn gpt-6-sol rollout ($2) recorded in cwd
_tok_cx_one() {
    _cx_meta 2026-09-10T10:00:00Z "$1" "$2"
    _cx_ctx 2026-09-10T10:00:00Z gpt-6-sol
    _cx_tok 2026-09-10T10:00:10Z 1000000 0 0 0 0
}

# _tok_both — RDF_CLAUDE_PROJECTS tree and CODEX_HOME for one project with $4 of Claude and $2 of Codex usage
_tok_both() {
    local root p cc h
    root="$(mktemp -d)"; p="${root}/work/alpha"; cc="${root}/cc"; h="${root}/codex"
    mkdir -p "$p" "${cc}/$(printf '%s' "$p" | sed 's/[^A-Za-z0-9-]/-/g')" "${h}/sessions/2026/09/10"
    _tok_cwd c1 m1 2026-09-10T20:00:00Z "$p" > "${cc}/$(printf '%s' "$p" | sed 's/[^A-Za-z0-9-]/-/g')/c1.jsonl"
    { _cx_meta 2026-09-10T10:00:00Z x1 "${p}/wt/feature"; _cx_ctx 2026-09-10T10:00:00Z gpt-6-sol
      _cx_tok 2026-09-10T10:00:10Z 1000000 0 0 0 0; } > "${h}/sessions/2026/09/10/rollout-x1.jsonl"
    printf '%s' "$root"
}

@test "default report adds Codex when the scope has Codex usage; --claude and --codex report one tool each" {
    local r; r="$(_tok_both)"
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" run _tok --project "${r}/work/alpha" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.source, .cost_usd, .claude.cost_usd, .codex.cost_usd, .codex.source]' <<< "$output")" = '["all",6,4,2,"codex"]' ]
    [ "$(jq -c '[.top_sessions[] | [.tool, .session, .cost_usd]]' <<< "$output")" = '[["claude","c1",4],["codex","x1",2]]' ]
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" run _tok --project "${r}/work/alpha" --since 2026-09-01
    [ "$status" -eq 0 ]
    [[ "$output" == *'spend  $6.00  (claude code $4.00 · codex $2.00)'* ]]
    [[ "$output" == *'claude code: sessions 1 · api turns 1'*'codex: sessions 1 · subagent runs 0 · api turns 1'* ]]
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" run _tok --project "${r}/work/alpha" --since 2026-09-01 --summary
    [ "$(jq -c '[.source, .cost_usd, .claude.cost_usd, .codex.source, .codex.cost_usd]' <<< "$output")" = '["all",6,4,"codex",2]' ]
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" run _tok --claude --project "${r}/work/alpha" --since 2026-09-01 --json
    [ "$(jq -c '[.source, .api_turns, .cost_usd]' <<< "$output")" = '[null,1,4]' ]
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" run _tok --codex --project "${r}/work/alpha" --since 2026-09-01 --json
    [ "$(jq -c '[.source, .api_turns, .cost_usd]' <<< "$output")" = '["codex",1,2]' ]
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/none" run _tok --project "${r}/work/alpha" --since 2026-09-01
    [ "$status" -eq 0 ]
    [[ "$output" == 'rdf tokens — alpha · since 2026-09-01T00:00:00Z'* ]]
    [[ "$output" != *'codex'* ]]
    rm -rf "$r"
}

@test "default report with Codex usage but no transcripts shows Codex; with neither it exits 1 with the transcripts reason" {
    local r; r="$(_tok_both)"
    rm -rf "${r}/cc"/*
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" run _tok --project "${r}/work/alpha" --since 2026-09-01
    [ "$status" -eq 0 ]
    [[ "$output" == 'rdf tokens — codex · alpha'* ]]
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" run _tok --project "${r}/work/alpha" --since 2026-10-01
    [ "$status" -eq 1 ]
    [[ "$output" == *"no transcripts for ${r}/work/alpha"* ]]
    rm -rf "$r"
}

@test "--all reports every project, follows a project dir symlinked from elsewhere, labels below the common directory, and folds Codex worktrees into their project" {
    local r cc b g; r="$(_tok_both)"; cc="${r}/cc"
    mkdir -p "${r}/work/beta" "${r}/work/gamma"
    b="${cc}/$(printf '%s' "${r}/work/beta" | sed 's/[^A-Za-z0-9-]/-/g')"
    mkdir -p "$b"
    { _tok_cwd c2 m2 2026-09-11T10:00:00Z "${r}/work/beta"; _tok_cwd c2 m3 2026-09-11T10:01:00Z "${r}/work/beta"; } > "${b}/c2.jsonl"
    ln -s "$b" "${cc}/-link-to-beta"
    g="${r}/moved/gamma"
    mkdir -p "$g"
    _tok_cwd c3 m4 2026-09-12T10:00:00Z "${r}/work/gamma" > "${g}/c3.jsonl"
    ln -s "$g" "${cc}/-gamma"
    ln -s "$b" "${cc}/$(printf '%s' "${r}/work/delta" | sed 's/[^A-Za-z0-9-]/-/g')"
    _tok_cx_one x3 "${r}/work/gamma/wt/x" > "${r}/codex/sessions/2026/09/10/rollout-x3.jsonl"
    _tok_cx_one x4 "${r}/work/delta/q" > "${r}/codex/sessions/2026/09/10/rollout-x4.jsonl"
    _tok_cx_one x5 "${r}/tmpx/$(printf '%s' "${r}/work/alpha" | sed 's/[^A-Za-z0-9-]/-/g')/s1/scratchpad/codex" \
        > "${r}/codex/sessions/2026/09/10/rollout-x5.jsonl"
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --all --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.claude.api_turns, .claude.cost_usd, .cost_usd]' <<< "$output")" = '[4,16,24]' ]
    [ "$(jq -c '[.by_project[] | [.project, .claude, .codex, .cost_usd]]' <<< "$output")" = '[["beta",8,2,10],["alpha",4,4,8],["gamma",4,2,6]]' ]
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --codex --project "${r}/work/alpha" --since 2026-09-01 --json
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = '[2,4]' ]
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --by project --since 2026-09-01
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^  alpha +\$4\.00 +\$4\.00 +\$8\.00$'
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --by project --top 1 --since 2026-09-01
    [[ "$output" == *"2 more (--top N or --json)"* ]]
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --all --since 2026-09-01
    echo "$output" | grep -qE '^top sessions +tool +session +turns +cost  project$'
    echo "$output" | grep -qE ' claude +c2 +2 +\$8\.00  beta$'
    rm -rf "$r"
}

@test "--all adds two project dirs that record the same cwd, and folds a Codex worktree into a project with no usage in the window" {
    local r cc d2; r="$(_tok_both)"; cc="${r}/cc"
    d2="${cc}/-elsewhere-alpha-copy"
    mkdir -p "$d2"
    _tok_cwd c5 m5 2026-09-12T10:00:00Z "${r}/work/alpha" > "${d2}/c5.jsonl"
    { _tok_cwd c6 m6 2026-09-12T11:00:00Z "${r}/work/alpha/sub"; _tok_cwd c6 m7 2026-09-12T11:01:00Z "${r}/work/alpha/sub"; } \
        > "${cc}/$(printf '%s' "${r}/work/alpha" | sed 's/[^A-Za-z0-9-]/-/g')/c6.jsonl"
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --all --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.by_project[] | [.project, .claude, .codex, .cost_usd, .sessions]]' <<< "$output")" = '[["alpha",16,2,18,4]]' ]
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --codex --all --since 2026-09-01 --json
    [ "$(jq -c '[.by_project[] | .cwd]' <<< "$output")" = "[\"${r}/work/alpha\"]" ]
    RDF_CLAUDE_PROJECTS="$cc" CODEX_HOME="${r}/codex" run _tok --all --since 2026-09-11 --json
    [ "$(jq -c '[.by_project[] | [.project, .claude, .codex]]' <<< "$output")" = '[["alpha",12,null]]' ]
    rm -rf "$r"
}

@test "--by day uses each timestamp's own UTC offset across a daylight-saving change" {
    local t; t="$(mktemp -d)"
    { _tok_cwd s1 m1 2026-01-15T05:30:00Z /w; _tok_cwd s2 m2 2026-07-15T05:30:00Z /w; } > "${t}/s.jsonl"
    TZ=America/Chicago run _tok --transcripts "$t" --since 2026-01-01 --by day --json
    [ "$status" -eq 0 ]
    if jq -n '0 | strflocaltime("%Y")' >/dev/null 2>&1 && [ "$(TZ=America/Chicago date -d @1768455000 +%z 2>/dev/null)" = "-0600" ]; then
        [ "$(jq -c '[.by_day[].key]' <<< "$output")" = '["2026-01-14","2026-07-15"]' ]
    fi
    rm -rf "$t"
}

@test "--by day, week and month bucket in local time; --by session ranks sessions; --top caps them" {
    local r; r="$(_tok_both)"
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" TZ=UTC run _tok --project "${r}/work/alpha" --since 2026-09-01 --by day --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.by_day[] | [.key, .claude, .codex, .cost_usd]]' <<< "$output")" = '[["2026-09-10",4,2,6]]' ]
    if [ "$(TZ=Asia/Tokyo date +%z)" = "+0900" ]; then
        RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" TZ=Asia/Tokyo run _tok --project "${r}/work/alpha" --since 2026-09-01 --by day --json
        [ "$(jq -c '[.by_day[] | [.key, .claude, .codex]]' <<< "$output")" = '[["2026-09-10",null,2],["2026-09-11",4,null]]' ]
    fi
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" TZ=UTC run _tok --claude --project "${r}/work/alpha" --since 2026-09-01 --by week --json
    [ "$(jq -c '.by_week' <<< "$output")" = '[{"key":"2026-09-07","sessions":1,"turns":1,"cost_usd":4}]' ]
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" TZ=UTC run _tok --project "${r}/work/alpha" --since 2026-09-01 --by month
    echo "$output" | grep -qE '^  2026-09 +\$4\.00 +\$2\.00 +\$6\.00$'
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" TZ=UTC run _tok --project "${r}/work/alpha" --since 2026-09-01 --by session --top 1
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^  2026-09-10 20:00 +claude +c1 +1 +\$4\.00$'
    ! grep -qE ' codex +x1 ' <<< "$output"
    { _cx_meta 2026-09-10T11:00:00Z x2 "${r}/work/alpha"; _cx_ctx 2026-09-10T11:00:00Z gpt-6-sol
      _cx_tok 2026-09-10T11:00:10Z 3000000 0 0 0 0; } > "${r}/codex/sessions/2026/09/10/rollout-x2.jsonl"
    RDF_CLAUDE_PROJECTS="${r}/cc" CODEX_HOME="${r}/codex" TZ=UTC run _tok --project "${r}/work/alpha" --since 2026-09-01 --by session --top 2
    [ "$(printf '%s\n' "$output" | grep -cE '^  2026-09-10 ')" = "2" ]
    printf '%s\n' "$output" | grep -E '^  2026-09-10 ' | head -1 | grep -qE ' codex +x2 +1 +\$6\.00$'
    rm -rf "$r"
}

@test "row cache: an unchanged source is read from its entry, a touched source is re-extracted, --no-cache bypasses it, and stale roots are pruned" {
    local t e
    t="$(mktemp -d)"
    { _tok_cwd s1 m1 2026-09-10T10:00:00Z /w; _tok_cwd s1 m1 2026-09-10T10:00:01Z /w; } > "${t}/s1.jsonl"
    touch -t 202609100000 "${t}/s1.jsonl"
    mkdir -p "${RDF_TOKENS_CACHE}/claude-1" "${RDF_TOKENS_CACHE}/claude-2" "${RDF_TOKENS_CACHE}/claude-3"
    touch -t 202601010000 "${RDF_TOKENS_CACHE}/claude-1/.rdf-tokens"
    touch "${RDF_TOKENS_CACHE}/claude-3/.rdf-tokens"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -c '.cost_usd' <<< "$output")" = "4" ]
    [ ! -d "${RDF_TOKENS_CACHE}/claude-1" ]
    [ -d "${RDF_TOKENS_CACHE}/claude-2" ]
    [ -d "${RDF_TOKENS_CACHE}/claude-3" ]
    e="$(find "$RDF_TOKENS_CACHE" -name 's1.jsonl.rows')"
    [ -n "$e" ]
    [ "$(grep -c . "$e")" = "1" ]
    sed 's/"in":1000000/"in":2000000/' "$e" > "${e}.new"
    touch -r "$e" "${e}.new"
    mv "${e}.new" "$e"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -c '.cost_usd' <<< "$output")" = "8" ]
    run _tok --transcripts "$t" --since 2026-09-01 --json --no-cache
    [ "$(jq -c '.cost_usd' <<< "$output")" = "4" ]
    grep -q '"in":2000000' "$e"
    touch "${t}/s1.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -c '.cost_usd' <<< "$output")" = "4" ]
    touch -t 202609100000 "${t}/s1.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    { _tok_cwd s1 m1 2026-09-10T10:00:00Z /w; _tok_cwd s1 m9 2026-09-10T10:05:00Z /w; } > "${t}/s1.jsonl"
    touch -t 202609090000 "${t}/s1.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -c '.cost_usd' <<< "$output")" = "8" ]
    rm -rf "$t"
}

@test "row cache: a transcript written moments before the run is re-read next time, even within the same second" {
    local t e; t="$(mktemp -d)"
    _tok_cwd s1 m1 2026-09-10T10:00:00Z /w > "${t}/s1.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -c '.cost_usd' <<< "$output")" = "4" ]
    e="$(find "$RDF_TOKENS_CACHE" -name 's1.jsonl.rows')"
    sed 's/"in":1000000/"in":2000000/' "$e" > "${e}.new"
    touch -r "$e" "${e}.new"
    mv "${e}.new" "$e"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -c '.cost_usd' <<< "$output")" = "4" ]
    rm -rf "$t"
}

@test "row cache: a subagent meta written after its transcript was cached relabels the agent" {
    local t; t="$(mktemp -d)"
    mkdir -p "${t}/s1/subagents"
    _tok_cwd s1 m1 2026-09-10T10:00:00Z /w > "${t}/s1/subagents/agent-a.jsonl"
    touch -t 202609100000 "${t}/s1/subagents/agent-a.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -r '[.by_agent[].agent] | join(",")' <<< "$output")" = "unknown" ]
    printf '{"agentType":"rdf-engineer"}' > "${t}/s1/subagents/agent-a.meta.json"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -r '[.by_agent[].agent] | join(",")' <<< "$output")" = "rdf-engineer" ]
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -r '[.by_agent[].agent] | join(",")' <<< "$output")" = "rdf-engineer" ]
    touch -t 202609090000 "${t}/s1/subagents/agent-a.meta.json"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    rm "${t}/s1/subagents/agent-a.meta.json"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -r '[.by_agent[].agent] | join(",")' <<< "$output")" = "unknown" ]
    printf '{"agentType":"rdf-qa"}' > "${t}/s1/subagents/agent-a.meta.json"
    touch -t 202609120000 "${t}/s1/subagents/agent-a.meta.json"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    { _tok_cwd s1 m1 2026-09-10T10:00:00Z /w; _tok_cwd s1 m2 2026-09-10T10:01:00Z /w; } > "${t}/s1/subagents/agent-a.jsonl"
    touch -t 202609110000 "${t}/s1/subagents/agent-a.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$(jq -c '[.cost_usd, [.by_agent[].agent]]' <<< "$output")" = '[8,["rdf-qa"]]' ]
    rm -rf "$t"
}

@test "--all labels a project by the cwd holding most of its rows when two paths share its slug, and sums fractions before rounding" {
    local r cc d; r="$(mktemp -d)"; cc="${r}/cc"
    d="${cc}/$(printf '%s' "${r}/a-b" | sed 's/[^A-Za-z0-9-]/-/g')"
    mkdir -p "$d" "${cc}/-copy"
    { _tok_cwd c1 m1 2026-09-10T10:00:00Z "${r}/a-b"; _tok_cwd c1 m2 2026-09-10T10:01:00Z "${r}/a-b"
      _tok_cwd c1 m3 2026-09-10T10:02:00Z "${r}/a/b"; } > "${d}/c1.jsonl"
    RDF_CLAUDE_PROJECTS="$cc" run _tok --claude --all --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -r '.by_project[0].cwd' <<< "$output")" = "${r}/a-b" ]
    rm -rf "$d"; mkdir -p "${cc}/-one"
    printf '{"type":"assistant","timestamp":"2026-09-10T10:00:00Z","sessionId":"%s","cwd":"/w","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":0}}}\n' s1 q1 > "${cc}/-one/s1.jsonl"
    printf '{"type":"assistant","timestamp":"2026-09-10T10:00:00Z","sessionId":"%s","cwd":"/w","message":{"id":"%s","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":0}}}\n' s2 q2 > "${cc}/-copy/s2.jsonl"
    RDF_CLAUDE_PROJECTS="$cc" run _tok --all --since 2026-09-01 --json
    [ "$(jq -c '[.cost_usd, (.by_project | length), .by_project[0].cost_usd]' <<< "$output")" = '[0.0001,1,0.0001]' ]
    rm -rf "$r"
}

@test "a transcript or rollout that grep would call binary still yields every row" {
    local t h p
    t="$(mktemp -d)"; h="$(_cx_home)"; p="$(mktemp -d)"
    { _tok_cwd s1 m1 2026-09-10T10:00:00Z /w
      printf '{"type":"user","message":"a\000b"}\n'
      _tok_cwd s1 m2 2026-09-10T10:01:00Z /w; } > "${t}/s1.jsonl"
    run _tok --transcripts "$t" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[2,8]" ]
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"; _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      printf '{"type":"event_msg","payload":{"type":"agent_message","message":"a\000b"}}\n'
      _cx_tok 2026-10-02T10:00:10Z 1000000 0 0 0 0; } > "${h}/sessions/2026/10/02/rollout-a.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[1,2]" ]
    rm -rf "$t" "$h" "$p"
}

@test "codex: archived_sessions rollouts count; --session falls back to a Codex thread when no transcript has the id" {
    local h p; h="$(_cx_home)"; p="$(mktemp -d)"
    mkdir -p "${h}/archived_sessions"
    { _cx_meta 2026-10-02T10:00:00Z c1 "$p"; _cx_ctx 2026-10-02T10:00:00Z gpt-6-sol
      _cx_tok 2026-10-02T10:00:10Z 1000000 0 0 0 0; } > "${h}/archived_sessions/rollout-old.jsonl"
    CODEX_HOME="$h" run _tok --codex --project "$p" --since 2026-10-01 --json
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[1,2]" ]
    RDF_CLAUDE_PROJECTS="${RDF_SRC}/tests/fixtures/tokens" CODEX_HOME="$h" run _tok --session c1 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.source, .session, .cost_usd]' <<< "$output")" = '["codex","c1",2]' ]
    RDF_CLAUDE_PROJECTS="${RDF_SRC}/tests/fixtures/tokens" CODEX_HOME="$h" run _tok --session s1 --summary
    [ "$(jq -c '[.source, .session, .api_turns]' <<< "$output")" = '[null,"s1",6]' ]
    RDF_CLAUDE_PROJECTS="${RDF_SRC}/tests/fixtures/tokens" CODEX_HOME="$h" run _tok --session nope --summary
    [ "$status" -eq 1 ]
    [[ "$output" == *"no transcript for session nope"* ]]
    RDF_CLAUDE_PROJECTS="${RDF_SRC}/tests/fixtures/tokens" CODEX_HOME="$h" run _tok --session c1
    [[ "$output" != *"top sessions"* ]]
    rm -rf "${h}/sessions"
    RDF_CLAUDE_PROJECTS="${RDF_SRC}/tests/fixtures/tokens" CODEX_HOME="$h" run _tok --session c1 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.source, .session]' <<< "$output")" = '["codex","c1"]' ]
    rm -rf "$h" "$p"
}

@test "CLAUDE_CONFIG_DIR sets the default transcript root" {
    local c; c="$(mktemp -d)"
    mkdir -p "${c}/projects"
    cp -R "$FX" "${c}/projects/proj"
    CLAUDE_CONFIG_DIR="$c" run env -u RDF_CLAUDE_PROJECTS bash "$TOK" --session s1 --summary
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.api_turns, .cost_usd]' <<< "$output")" = "[6,0.4001]" ]
    rm -rf "$c"
}

@test "one worker with several files per batch and many workers, and a transcript path holding a newline, give the same report" {
    local t a b i
    t="$(mktemp -d)"
    cp -R "$FX" "${t}/x
y"
    cp -R "$FX" "${t}/pad"
    for i in 1 2 3 4 5; do _tok_cwd "p${i}" "mp${i}" "2026-09-15T10:0${i}:00Z" /w > "${t}/pad/p${i}.jsonl"; done
    run env RDF_TOKENS_JOBS=1 bash "$TOK" --transcripts "${t}/pad" --since 2026-09-01 --json --no-cache
    a="$(jq -c 'del(.scope)' <<< "$output")"
    [ "$(jq -c '[.api_turns, .subagent_runs, .cost_usd, ([.by_agent[].agent] | sort)]' <<< "$a")" = '[11,2,20.3981,["general-purpose","main","rdf-engineer"]]' ]
    run env RDF_TOKENS_JOBS=7 bash "$TOK" --transcripts "${t}/pad" --since 2026-09-01 --json --no-cache
    [ "$(jq -c 'del(.scope)' <<< "$output")" = "$a" ]
    run _tok --transcripts "$FX" --since 2026-09-01 --json
    a="$(jq -c 'del(.scope)' <<< "$output")"
    run _tok --transcripts "${t}/x
y" --since 2026-09-01 --json
    [ "$status" -eq 0 ]
    b="$(jq -c 'del(.scope)' <<< "$output")"
    [ "$b" = "$a" ]
    rm -rf "$t"
}

@test "bad --by, --top and --all combinations exit 2" {
    run _tok --by year
    [ "$status" -eq 2 ]
    run _tok --top 0
    [ "$status" -eq 2 ]
    run _tok --top x
    [ "$status" -eq 2 ]
    run _tok --all --project .
    [ "$status" -eq 2 ]
    run _tok --by project --session s1
    [ "$status" -eq 2 ]
}

@test "rdf-tokens.sh uses no jq 1.6+ builtins or reserved-word variables" {
    run grep -nE '(^|[^a-z_])(round|ceil|abs|trim|ltrim|rtrim|pick|IN|INDEX|walk|halt_error|splits|test|match|capture|sub|gsub|scan)\(|\$ENV|[^a-z]env\.|--args|--jsonargs|--rawfile|strptime' "$TOK"
    [ "$status" -eq 1 ]
    run grep -nE '\$(label|import|include|def|if|then|elif|else|end|as|reduce|foreach|try|catch|and|or|not|__loc__)([^A-Za-z0-9_]|$)' "$TOK"
    [ "$status" -eq 1 ]
}

# ── session_last: rdf-state.sh keeps the /r-save tokens object ───────────────

# _state_last <lines…> — write a session-log with the given lines, print the
# rdf-state.sh session_last value (a JSON string, decoded)
_state_last() {
    local proj; proj="$(mktemp -d)"
    mkdir -p "${proj}/.rdf/work-output"
    printf '%s\n' "$@" > "${proj}/.rdf/work-output/session-log.jsonl"
    bash "${RDF_SRC}/state/rdf-state.sh" --full "$proj" | jq -r '.session_last'
    rm -rf "$proj"
}

SAVE='{"timestamp":"2026-09-23T10:00:00Z","head_after":"55e8473","commits":2,"diff_summary":"1 spec","pipeline":"spec","tokens":{"cost_usd":4.12,"api_turns":212}}'
HOOK='{"timestamp":"2026-09-23T10:05:00Z","head_after":"55e8473","branch":"main","dirty_files":0,"reason":"other","source":"session-end-hook","insight":null}'

@test "rdf-state.sh session_last preserves a tokens object" {
    run _state_last "$SAVE"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.tokens.cost_usd' <<< "$output")" = "4.12" ]
}

@test "session_last prefers the /r-save entry over a trailing same-state SessionEnd-hook entry" {
    run _state_last "$SAVE" "$HOOK"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.commits, .tokens.cost_usd]' <<< "$output")" = "[2,4.12]" ]
}

@test "session_last keeps a hook entry whose head_after differs" {
    run _state_last "$SAVE" "${HOOK/55e8473/abc1234}"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.head_after' <<< "$output")" = "abc1234" ]
    [ "$(jq -c '.tokens' <<< "$output")" = "null" ]
}

@test "session_last selects a pretty-spaced /r-save entry" {
    local spaced='{"timestamp": "2026-09-23T10:00:00Z", "head_after": "55e8473", "commits": 3, "tokens": {"cost_usd": 1.5}}'
    run _state_last "$spaced" "$HOOK"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.commits, .tokens.cost_usd]' <<< "$output")" = "[3,1.5]" ]
}

@test "session_last walks back over consecutive same-state SessionEnd-hook entries" {
    run _state_last "$SAVE" "$HOOK" "$HOOK"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.commits, .tokens.cost_usd]' <<< "$output")" = "[2,4.12]" ]
}

@test "session_last keeps an unterminated final /r-save line" {
    local proj; proj="$(mktemp -d)"
    mkdir -p "${proj}/.rdf/work-output"
    printf '%s\n%s' "$HOOK" "$SAVE" > "${proj}/.rdf/work-output/session-log.jsonl"
    run bash -c 'bash "$1/state/rdf-state.sh" --full "$2" | jq -r ".session_last"' _ "$RDF_SRC" "$proj"
    rm -rf "$proj"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.commits, .tokens.cost_usd]' <<< "$output")" = "[2,4.12]" ]
}
