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

@test "generate deploys state helpers + pre-commit hook to ~/.rdf/state" {
    # RDF_HOME is the real source (helpers + git-hooks live there); HOME is a
    # throwaway so the deploy lands under a temp ~/.rdf/state, never the dev's.
    local home; home="$(mktemp -d)"
    run bash -c '
        set -euo pipefail
        rdf_src="$1"; fix_home="$2"
        HOME="$fix_home"
        RDF_HOME="$rdf_src"
        RDF_LIBDIR="${rdf_src}/lib"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/generate.sh"
        _generate_deploy_state_helpers
    ' -- "$RDF_SRC" "$home"
    [ "$status" -eq 0 ]
    [ -x "${home}/.rdf/state/rdf-bus.sh" ]
    [ -x "${home}/.rdf/state/rdf-overhead.sh" ]
    [ -x "${home}/.rdf/state/git-hooks/pre-commit" ]
    rm -rf "$home"
}
