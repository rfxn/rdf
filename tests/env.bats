#!/usr/bin/env bats
# tests/env.bats — state/rdf-env.sh environment assessment and its rdf-state.sh embed
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: every run uses env -i with a PATH built from an allowlist of real tools, so a language
# server, shellcheck, curl or claude is present only when a test stubs it. HOME and the Claude config
# dir are temp dirs.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC
ENVSH="${RDF_SRC}/state/rdf-env.sh"
BASH_BIN="$(command -v bash)"

setup() {
    T="$(mktemp -d)"
    BIN="${T}/bin"; HOMEDIR="${T}/home"; CFG="${T}/cfg"
    mkdir -p "$BIN" "$HOMEDIR" "$CFG" "${T}/tmp"
    local tool path
    for tool in bash jq git awk sed grep sort head tail tr wc cksum uname mktemp rm cat cp mv mkdir \
        dirname basename date find env getconf df ls ln chmod touch stat cut xargs od; do
        path="$(command -v "$tool" 2>/dev/null)" || continue
        ln -s "$path" "${BIN}/${tool}"
    done
}

teardown() {
    rm -rf "$T"
}

# _stub name body — an executable stub on the test PATH; body is shell run with the stub's arguments
_stub() {
    printf '#!%s\n%s\n' "$BASH_BIN" "$2" > "${BIN}/$1"
    chmod +x "${BIN}/$1"
}

# _env [VAR=value ...] -- args... — run the helper hermetically
_env() {
    local -a vars=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do vars+=("$1"); shift; done
    shift
    env -i HOME="$HOMEDIR" PATH="$BIN" CLAUDE_CONFIG_DIR="$CFG" TMPDIR="${T}/tmp" "${vars[@]+"${vars[@]}"}" \
        "$BASH_BIN" "$ENVSH" "$@"
}

# _repo dir — a git repository whose index lists every file under dir
_repo() {
    git -C "$1" init -q
    git -C "$1" add -A
}

# _ts_project — a git TypeScript project (marker + 3 sources); prints its path
_ts_project() {
    local p="${T}/ts"
    mkdir -p "${p}/src"
    printf '{}\n' > "${p}/tsconfig.json"
    touch "${p}/src/a.ts" "${p}/src/b.ts" "${p}/src/c.ts"
    _repo "$p"
    printf '%s' "$p"
}

# _shell_project — a git shell project with 12 scripts; prints its path
_shell_project() {
    local p="${T}/sh" i
    mkdir -p "${p}/files"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do touch "${p}/files/s${i}.sh"; done
    _repo "$p"
    printf '%s' "$p"
}

@test "brief: a TypeScript project without its language server or plugin is a gap with both installs" {
    local p; p="$(_ts_project)"
    run _env CLAUDECODE=1 -- --brief --json "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.mode, .tool, .summary.gap]' <<< "$output")" = '["brief","claude",1]' ]
    [ "$(jq -r '.findings[0].id' <<< "$output")" = "lsp-typescript" ]
    [ "$(jq -c '.findings[0].fix' <<< "$output")" = "[\"npm install -g typescript-language-server typescript\",\"CLAUDE_CONFIG_DIR=${CFG} claude plugin install typescript-lsp@claude-plugins-official\"]" ]
}

@test "brief: server on PATH and plugin installed and enabled is no gap; disabled in project settings asks to enable" {
    local p; p="$(_ts_project)"
    _stub typescript-language-server 'exit 0'
    mkdir -p "${CFG}/plugins"
    printf '{"version":2,"plugins":{"typescript-lsp@claude-plugins-official":[]}}\n' > "${CFG}/plugins/installed_plugins.json"
    printf '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":true}}\n' > "${CFG}/settings.json"
    run _env CLAUDECODE=1 -- --brief --json "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.summary' <<< "$output")" = '{"gap":0,"warn":0,"info":0,"ignored":0}' ]
    mkdir -p "${p}/.claude"
    printf '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":false}}\n' > "${p}/.claude/settings.local.json"
    run _env CLAUDECODE=1 -- --brief --json "$p"
    [ "$(jq -c '.findings[0].fix' <<< "$output")" = "[\"CLAUDE_CONFIG_DIR=${CFG} claude plugin enable typescript-lsp@claude-plugins-official\"]" ]
}

@test "brief: samples, docs and vendored files never make a language primary; outside git a marker is required" {
    local p n i; p="$(_shell_project)"
    _stub shellcheck 'exit 0'; _stub bats 'exit 0'
    mkdir -p "${p}/docs/support" "${p}/tests/samples" "${p}/vendor"
    touch "${p}/docs/support/proto.js"
    for i in 1 2 3 4 5 6 7 8; do touch "${p}/tests/samples/m${i}.php"; done
    touch "${p}/vendor/lib.py"
    mkdir -p "${p}/docs/site"
    printf '{}\n' > "${p}/docs/site/package.json"
    touch "${p}/docs/site/a.js" "${p}/docs/site/b.js" "${p}/docs/site/c.js"
    git -C "$p" add -A
    run _env CLAUDECODE=1 -- --brief --json "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.facts.languages[] | select(.primary) | .lang]' <<< "$output")" = '["shell"]' ]
    [ "$(jq -c '.summary.gap' <<< "$output")" = "0" ]
    n="${T}/notes"; mkdir -p "$n"
    for i in $(seq 1 60); do touch "${n}/f${i}.py"; done
    run _env CLAUDECODE=1 -- --brief --json "$n"
    [ "$(jq -c '[.facts.languages[] | select(.primary) | .lang]' <<< "$output")" = '[]' ]
    touch "${n}/requirements.txt"
    run _env CLAUDECODE=1 -- --brief --json "$n"
    [ "$(jq -r '.findings[0].id' <<< "$output")" = "lsp-python" ]
}

@test "brief: a shell project without shellcheck or bats has gaps; a container test harness supplies bats" {
    local p; p="$(_shell_project)"
    run _env CLAUDECODE=1 -- --brief --json "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.findings[].id] | sort' <<< "$output")" = '["tool-bats","tool-shellcheck"]' ]
    mkdir -p "${p}/tests/infra"
    run _env CLAUDECODE=1 -- --brief --json "$p"
    [ "$(jq -c '[.findings[].id]' <<< "$output")" = '["tool-shellcheck"]' ]
}

@test "brief: Claude Code plugin checks run only for claude; the ignore list drops a finding and counts it" {
    local p; p="$(_ts_project)"
    run _env -- --brief --json --tool codex "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.tool, .summary.gap, .facts.lsp]' <<< "$output")" = '["codex",0,null]' ]
    mkdir -p "${HOMEDIR}/.rdf"
    printf '# not needed here\nlsp-typescript\n' > "${HOMEDIR}/.rdf/env-ignore"
    run _env CLAUDECODE=1 -- --brief --json "$p"
    [ "$(jq -c '[.summary.gap, .summary.ignored, (.findings | length)]' <<< "$output")" = '[0,1,0]' ]
}

@test "brief: a hard open-file limit under 4096 warns (Claude Code raises its soft limit to the hard one)" {
    local p; p="$(_shell_project)"
    _stub shellcheck 'exit 0'; _stub bats 'exit 0'
    run env -i HOME="$HOMEDIR" PATH="$BIN" CLAUDE_CONFIG_DIR="$CFG" TMPDIR="${T}/tmp" CLAUDECODE=1 \
        "$BASH_BIN" -c 'ulimit -n 1024 && exec "$0" "$1" --brief --json "$2"' "$BASH_BIN" "$ENVSH" "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.findings[] | select(.id == "limit-nofile") | .severity]' <<< "$output")" = '["warn"]' ]
    if [ "$(ulimit -Hn)" = "unlimited" ] || [ "$(ulimit -Hn)" -ge 4096 ]; then
        run env -i HOME="$HOMEDIR" PATH="$BIN" CLAUDE_CONFIG_DIR="$CFG" TMPDIR="${T}/tmp" CLAUDECODE=1 \
            "$BASH_BIN" -c 'ulimit -Sn 1024 && exec "$0" "$1" --brief --json "$2"' "$BASH_BIN" "$ENVSH" "$p"
        [ "$status" -eq 0 ]
        [ "$(jq -c '[.findings[] | select(.id == "limit-nofile")] | length' <<< "$output")" = "0" ]
    fi
}

@test "full --offline calls neither the npm registry nor claude doctor" {
    local p; p="$(_shell_project)"
    _stub curl 'echo curl "$@" >> "'"${T}"'/calls"; exit 1'
    _stub claude 'echo claude "$@" >> "'"${T}"'/calls"; [ "$1" = "--version" ] && echo "2.1.300 (Claude Code)"; exit 0'
    run _env CLAUDECODE=1 -- --json --offline "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.mode' <<< "$output")" = "full" ]
    [ "$(command cat "${T}/calls")" = "claude --version" ]
    [ "$(jq -c '[.facts.claude.version, .facts.claude.latest]' <<< "$output")" = '["2.1.300",null]' ]
}

@test "full online: a version behind the configured channel is info; claude doctor issues warn" {
    local p; p="$(_shell_project)"
    _stub curl 'printf "{\"latest\":\"2.1.310\",\"stable\":\"2.1.305\"}"'
    _stub claude 'case "$1" in --version) echo "2.1.300 (Claude Code)" ;; doctor) printf "Running: native (2.1.300)\nSearch: OK (bundled)\nWarning: settings.json has an invalid key\n" ;; esac'
    printf '{"autoUpdatesChannel":"stable"}\n' > "${CFG}/settings.json"
    run _env CLAUDECODE=1 -- --json "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.findings[] | select(.id == "claude-version") | "\(.severity)|\(.title)"' <<< "$output")" = "info|Claude Code 2.1.300; 2.1.305 is current on the stable channel" ]
    [ "$(jq -r '.findings[] | select(.id == "claude-doctor") | .severity' <<< "$output")" = "warn" ]
    [ "$(jq -c '[.facts.claude.channel, .facts.claude.releases_behind, .facts.claude.search]' <<< "$output")" = '["stable",5,"OK (bundled)"]' ]
}

@test "full: a promotional price past its date warns; a fresh table says nothing" {
    local p; p="$(_shell_project)"
    run _env CLAUDECODE=1 RDF_ENV_TODAY=2026-10-30 -- --json --offline "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '[.findings[] | select(.area == "pricing")] | length' <<< "$output")" = "0" ]
    [ "$(jq -r '.facts.pricing.age_days' <<< "$output")" = "6" ]
    run _env CLAUDECODE=1 RDF_ENV_TODAY=2027-01-15 -- --json --offline "$p"
    [ "$(jq -r '[.findings[] | select(.area == "pricing") | .id] | join(",")' <<< "$output")" = "pricing-expired" ]
}

@test "full: an auto-memory index past 200 lines warns; CLAUDE.md sizes are facts, not settings values" {
    local p slug; p="$(_shell_project)"
    slug="$(cd "$p" && pwd -P | sed 's/[^A-Za-z0-9-]/-/g')"
    mkdir -p "${CFG}/projects/${slug}/memory"
    seq 1 210 > "${CFG}/projects/${slug}/memory/MEMORY.md"
    printf '# rules\n' > "${p}/CLAUDE.md"
    printf '{"env":{"SECRET_TOKEN":"abc123","BASH_MAX_OUTPUT_LENGTH":"128000"}}\n' > "${CFG}/settings.json"
    run _env CLAUDECODE=1 -- --json --offline "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.findings[] | select(.id == "memory-index") | .severity' <<< "$output")" = "warn" ]
    [ "$(jq -c '[.facts.config.claude_md[] | select(.scope == "project") | .lines]' <<< "$output")" = "[1]" ]
    [ "$(jq -c '.facts.config.settings.env_names' <<< "$output")" = '["BASH_MAX_OUTPUT_LENGTH","SECRET_TOKEN"]' ]
    [[ "$output" != *"abc123"* ]]
    [ "$(jq -r '.findings[] | select(.id == "bash-output-length") | .severity' <<< "$output")" = "info" ]
}

@test "bad arguments exit 2; a missing project exits 1" {
    run _env -- --tool vim .
    [ "$status" -eq 2 ]
    run _env -- --bogus
    [ "$status" -eq 2 ]
    run _env RDF_ENV_TODAY=tomorrow -- --brief "$T"
    [ "$status" -eq 2 ]
    run _env -- --brief "${T}/missing"
    [ "$status" -eq 1 ]
}

@test "rdf-state.sh --full --env embeds the brief summary; without --env it is null" {
    local p; p="$(_ts_project)"
    run env -i HOME="$HOMEDIR" PATH="$BIN" CLAUDE_CONFIG_DIR="$CFG" TMPDIR="${T}/tmp" CLAUDECODE=1 \
        "$BASH_BIN" "${RDF_SRC}/state/rdf-state.sh" --full --env "$p"
    [ "$status" -eq 0 ]
    [ "$(jq -c '.env | [.gap, .warn, .top[0].id]' <<< "$output")" = '[1,0,"lsp-typescript"]' ]
    run env -i HOME="$HOMEDIR" PATH="$BIN" CLAUDE_CONFIG_DIR="$CFG" TMPDIR="${T}/tmp" \
        "$BASH_BIN" "${RDF_SRC}/state/rdf-state.sh" --full "$p"
    [ "$(jq -c '.env' <<< "$output")" = "null" ]
}
