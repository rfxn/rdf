#!/usr/bin/env bats
# tests/deploy.bats — RDF Reach: deploy/sync install-surface coverage (audit M6)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: fresh temp RDF home + temp HOME per test. Harness mirrors
# tests/rules-deploy.bats:1-64 — deploy.sh is sourced against a temp
# HOME/RDF_HOME so a real symlink deploy proceeds without touching the
# developer's ~/.claude. The sync round-trip sources lib/cmd/sync.sh
# directly (tests/adapter.bats style) rather than bin/rdf.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2088

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

# Usage: _make_deploy_skeleton <fix_home> — minimal claude-code output tree so
# a real deploy proceeds past the pre-flight (cc output is local-only, absent on
# a CI checkout).
_make_deploy_skeleton() {
    local fix_home="$1"
    local out="${fix_home}/adapters/claude-code/output"
    mkdir -p "${out}/agents" "${out}/commands" "${out}/scripts" \
             "${out}/governance" "${out}/rules"
    touch "${out}/commands/x.md" "${out}/governance/core-governance.md" \
          "${out}/rules/core.md"
}

# Usage: _run_deploy <fix_home> [extra cmd_deploy args...] — default target is
# claude-code; a trailing target token (agent-skills, codex, ...) overrides it.
_run_deploy() {
    local fix_home="$1"; shift
    local has_target=0 a
    for a in "$@"; do
        case "$a" in
            claude-code|gemini-cli|codex|agent-skills) has_target=1 ;;
        esac
    done
    bash -c '
        set -euo pipefail
        rdf_src="$1"; fix_home="$2"; has_target="$3"; shift 3
        HOME="$fix_home"
        RDF_HOME="$fix_home"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/deploy.sh"
        if [ "$has_target" -eq 1 ]; then
            cmd_deploy "$@"
        else
            cmd_deploy "$@" claude-code
        fi
    ' -- "$RDF_SRC" "$fix_home" "$has_target" "$@"
}

setup() { FIX_HOME="$(mktemp -d)"; export FIX_HOME; _make_deploy_skeleton "$FIX_HOME"; }
teardown() { rm -rf "$FIX_HOME" 2>/dev/null || true; }  # cleanup, ignore errors

@test "deploy claude-code symlink create/replace/skip/force" {
    local out="${FIX_HOME}/adapters/claude-code/output"
    # 1) fresh create → commands is a symlink to the output
    run _run_deploy "$FIX_HOME"
    [ "$status" -eq 0 ]
    [ -L "${FIX_HOME}/.claude/commands" ]
    [ "$(readlink "${FIX_HOME}/.claude/commands")" = "${out}/commands" ]
    # 2) second run → still a symlink (replaced, not skipped)
    run _run_deploy "$FIX_HOME"
    [ -L "${FIX_HOME}/.claude/commands" ]
    # 3) a REAL dir where the symlink would go, no --force → skipped, dir intact
    rm -f "${FIX_HOME}/.claude/governance"; mkdir -p "${FIX_HOME}/.claude/governance"
    touch "${FIX_HOME}/.claude/governance/keep.md"
    run _run_deploy "$FIX_HOME"
    [ ! -L "${FIX_HOME}/.claude/governance" ]            # untouched real dir
    [ -f "${FIX_HOME}/.claude/governance/keep.md" ]
    echo "$output" | grep -q 'not a symlink'
    # 4) --force → backs up the real dir and symlinks
    run _run_deploy "$FIX_HOME" --force
    [ -L "${FIX_HOME}/.claude/governance" ]
    ls -d "${FIX_HOME}/.claude/governance".bak-* >/dev/null   # backup exists
}

@test "deploy claude-code honors RDF_TARGET override" {
    local out="${FIX_HOME}/adapters/claude-code/output"
    local target; target="$(mktemp -d)"
    run bash -c '
        set -euo pipefail
        rdf_src="$1"; fix_home="$2"; target="$3"
        HOME="$fix_home"
        RDF_HOME="$fix_home"
        RDF_TARGET="$target"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/deploy.sh"
        cmd_deploy claude-code
    ' -- "$RDF_SRC" "$FIX_HOME" "$target"
    [ "$status" -eq 0 ]
    # Symlinks land under RDF_TARGET, not ~/.claude
    [ -L "${target}/commands" ]
    [ "$(readlink "${target}/commands")" = "${out}/commands" ]
    [ ! -e "${FIX_HOME}/.claude/commands" ]
    rm -rf "$target"
}

@test "deploy claude-code skips hooks.json" {
    run _run_deploy "$FIX_HOME"
    [ ! -e "${FIX_HOME}/.claude/hooks.json" ]           # never symlinked (manual merge)
    echo "$output" | grep -q 'skipped: hooks.json'
}

@test "deploy agent-skills symlinks .agents/skills into project root" {
    local out="${FIX_HOME}/adapters/agent-skills/output"
    mkdir -p "${out}/.agents/skills/r-spec"
    printf -- '---\nname: r-spec\n---\nbody\n' > "${out}/.agents/skills/r-spec/SKILL.md"
    local proj; proj="$(mktemp -d)"
    run _run_deploy "$FIX_HOME" --project-root "$proj" agent-skills
    [ "$status" -eq 0 ]
    [ -L "${proj}/.agents/skills" ]
    [ -f "${proj}/.agents/skills/r-spec/SKILL.md" ]
    rm -rf "$proj"
}

@test "sync strips frontmatter from a COMMAND on the reverse flow (BLOCKER 2)" {
    # A deployed command carries frontmatter + a body --- rule; sync must write
    # back the STRIPPED body to canonical, never the frontmatter.
    local home; home="$(mktemp -d)"
    mkdir -p "${home}/canonical/commands" "${home}/adapters/claude-code/output/commands"
    printf 'orig body\n---\nrule\n' > "${home}/canonical/commands/x.md"
    printf -- '---\ndescription: >\n  trigger\n---\n\nEDITED body\n---\nrule\n' \
        > "${home}/adapters/claude-code/output/commands/x.md"
    run bash -c '
        set -euo pipefail
        RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
        source "$2/lib/rdf_common.sh"; rdf_init
        source "$2/lib/cmd/sync.sh"; cmd_sync
    ' -- "$home" "$RDF_SRC"
    [ "$status" -eq 0 ]
    [ "$(head -1 "${home}/canonical/commands/x.md")" != "---" ]   # NO frontmatter
    grep -q '^EDITED body$' "${home}/canonical/commands/x.md"     # edit landed
    grep -q '^---$' "${home}/canonical/commands/x.md"             # body --- rule preserved
    run grep -q 'description: >' "${home}/canonical/commands/x.md"
    [ "$status" -ne 0 ]                                           # trigger stripped (absent)
    rm -rf "$home"
}

@test "deploy claude-code symlinks state helpers per-file (glob)" {
    local home; home="$(mktemp -d)"
    _make_deploy_skeleton "$home"
    cp -R "$RDF_SRC/state" "$home/state"
    run _run_deploy "$home"
    [ "$status" -eq 0 ]
    [ -L "${home}/.rdf/state/rdf-bus.sh" ]
    [ -L "${home}/.rdf/state/rdf-overhead.sh" ]
    [ -L "${home}/.rdf/state/git-hooks/pre-commit" ]
    [ "$(find "${home}/.rdf/state" -maxdepth 1 -type l | wc -l | tr -d ' ')" = "7" ]
    rm -rf "$home"
}

@test "deploy migrates byte-identical helper copies to symlinks; differing copy skipped" {
    local home; home="$(mktemp -d)"
    _make_deploy_skeleton "$home"; cp -R "$RDF_SRC/state" "$home/state"
    mkdir -p "${home}/.rdf/state"
    cp "$home/state/rdf-bus.sh" "${home}/.rdf/state/rdf-bus.sh"          # identical → migrate
    printf 'locally modified\n' > "${home}/.rdf/state/rdf-state.sh"      # differs → skip
    run _run_deploy "$home"
    [ -L "${home}/.rdf/state/rdf-bus.sh" ]
    [ ! -L "${home}/.rdf/state/rdf-state.sh" ]
    grep -q '^locally modified$' "${home}/.rdf/state/rdf-state.sh"
    echo "$output" | grep -q 'not a symlink'
    rm -rf "$home"
}

@test "generate claude-code writes nothing under HOME" {
    # A REAL generation run against a fixture checkout: the contract is that
    # cmd_generate touches only adapters/<t>/output, never $HOME.
    local fix home; fix="$(mktemp -d)"; home="$(mktemp -d)"
    mkdir -p "${fix}/canonical/agents" "${fix}/canonical/commands" \
             "${fix}/canonical/scripts" "${fix}/adapters/claude-code/hooks" \
             "${fix}/adapters/agent-skills" "${fix}/profiles"
    printf 'body\n' > "${fix}/canonical/agents/ghost.md"
    printf 'desc\n' > "${fix}/canonical/commands/r-x.md"
    printf '{"ghost":{"name":"g","description":"d","model":"sonnet"}}\n' \
        > "${fix}/adapters/claude-code/agent-meta.json"
    printf '{}\n' > "${fix}/adapters/agent-skills/skill-meta.json"
    printf '{"hooks":{}}\n' > "${fix}/adapters/claude-code/hooks/hooks.json"
    cp "$RDF_SRC/adapters/claude-code/adapter.sh" "${fix}/adapters/claude-code/"
    run bash -c '
        set -euo pipefail
        rdf_src="$1"; fix="$2"; fix_home="$3"
        HOME="$fix_home"
        RDF_HOME="$fix"; RDF_LIBDIR="${rdf_src}/lib"; RDF_VERSION="0.0.0-test"
        source "${rdf_src}/lib/rdf_common.sh"; rdf_init
        source "${rdf_src}/lib/cmd/generate.sh"
        cmd_generate claude-code
    ' -- "$RDF_SRC" "$fix" "$home"
    [ "$status" -eq 0 ]
    [ -f "${fix}/adapters/claude-code/output/agents/ghost.md" ]   # generation actually ran
    [ -z "$(find "$home" -mindepth 1 2>/dev/null)" ]              # HOME untouched
    [ "$(grep -c '^_generate_deploy_state_helpers()' "$RDF_SRC/lib/cmd/generate.sh")" = "0" ]
    rm -rf "$fix" "$home"
}

@test "deploy --dry-run logs helper symlinks without writing" {
    local home; home="$(mktemp -d)"
    _make_deploy_skeleton "$home"; cp -R "$RDF_SRC/state" "$home/state"
    run _run_deploy "$home" --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'would symlink.*rdf-bus.sh'
    [ ! -e "${home}/.rdf/state/rdf-bus.sh" ]
    rm -rf "$home"
}

@test "generate claude-code fails listing agents missing from agent-meta" {
    home="$(mktemp -d)"
    mkdir -p "${home}/canonical/agents" "${home}/canonical/commands" \
             "${home}/canonical/scripts" "${home}/adapters/claude-code/hooks" \
             "${home}/adapters/agent-skills" "${home}/profiles"
    printf 'body\n' > "${home}/canonical/agents/ghost.md"
    printf '{}\n' > "${home}/adapters/claude-code/agent-meta.json"
    printf '{}\n' > "${home}/adapters/claude-code/command-meta-v3.json"
    printf '{}\n' > "${home}/adapters/agent-skills/skill-meta.json"
    printf '{"hooks":{}}\n' > "${home}/adapters/claude-code/hooks/hooks.json"
    run bash -c '
        set -euo pipefail
        RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
        source "$2/lib/rdf_common.sh"; rdf_init
        source "$2/adapters/claude-code/adapter.sh"
        cc_generate_all
    ' -- "$home" "$RDF_SRC"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q 'agents missing from agent-meta.json: ghost'
    rm -rf "$home"
}

@test "generate claude-plugin fails on same missing agent-meta" {
    home="$(mktemp -d)"
    mkdir -p "${home}/canonical/agents" "${home}/canonical/commands" \
             "${home}/canonical/scripts" "${home}/adapters/claude-code/hooks" \
             "${home}/adapters/claude-plugin" "${home}/adapters/agent-skills" \
             "${home}/.claude-plugin"
    printf 'body\n' > "${home}/canonical/agents/ghost.md"
    printf '{}\n' > "${home}/adapters/claude-code/agent-meta.json"
    printf '{}\n' > "${home}/adapters/agent-skills/skill-meta.json"
    printf '{"hooks":{}}\n' > "${home}/adapters/claude-code/hooks/hooks.json"
    printf '{"name":"rdf"}\n' > "${home}/.claude-plugin/plugin.json"
    run bash -c '
        set -euo pipefail
        RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
        source "$2/lib/rdf_common.sh"; rdf_init
        source "$2/adapters/claude-plugin/adapter.sh"
        RDF_ADAPTERS="$1/adapters" _CPL_OUTPUT_DIR="$1/adapters/claude-plugin/output" cpl_generate_all
    ' -- "$home" "$RDF_SRC"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q 'agents missing from agent-meta.json: ghost'
    rm -rf "$home"
}
