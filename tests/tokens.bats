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
    [ "$(jq -r 'keys | join(",")' <<< "$output")" = "api_turns,by_model,cache_read_share,cost_usd,main_ctx_median,session,subagent_runs" ]
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
    RDF_CLAUDE_PROJECTS="$cc" run _tok --project "${root}/link" --since 2026-09-01 --json
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
