#!/usr/bin/env bash
# lib/cmd/generate.sh — rdf generate subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_generate_usage() {
    cat <<'USAGE'
Usage: rdf generate [--deploy] <target>

Build tool-specific output from canonical sources.

Targets:
  claude-code    Generate Claude Code adapter output
  gemini-cli     Generate Gemini CLI adapter output
  codex          Generate Codex adapter output (AGENTS.md + config)
  agents-md      Generate cross-tool AGENTS.md
  all            Generate all available adapters

Options:
  --deploy       Run 'rdf deploy <target>' after generation completes

The generated output is written to adapters/<target>/output/.

Examples:
  rdf generate claude-code
  rdf generate --deploy claude-code
  rdf generate gemini-cli
  rdf generate codex
  rdf generate agents-md
  rdf generate all
USAGE
}

# Source and run a single adapter
# Args: $1 = adapter script relative to RDF_ADAPTERS, $2 = generation function name
_generate_adapter() {
    local script="${RDF_ADAPTERS}/$1"
    local func="$2"

    if [[ ! -f "$script" ]]; then
        rdf_die "adapter not found: ${script}"
    fi

    # shellcheck disable=SC1090
    source "$script"
    "$func"
}

cmd_generate() {
    rdf_profile_init
    local deploy_after=0

    # Parse --deploy flag if present
    if [[ "${1:-}" == "--deploy" ]]; then
        deploy_after=1
        shift
    fi

    case "${1:-}" in
        claude-code)
            _generate_adapter "claude-code/adapter.sh" "cc_generate_all"
            if [[ $deploy_after -eq 1 ]]; then
                # shellcheck disable=SC1090,SC1091
                source "${RDF_LIBDIR}/cmd/deploy.sh"
                cmd_deploy claude-code
            fi
            ;;
        gemini-cli)
            _generate_adapter "gemini-cli/adapter.sh" "gem_generate_all"
            if [[ $deploy_after -eq 1 ]]; then
                # shellcheck disable=SC1090,SC1091
                source "${RDF_LIBDIR}/cmd/deploy.sh"
                cmd_deploy gemini-cli
            fi
            ;;
        codex)
            _generate_adapter "codex/adapter.sh" "cdx_generate_all"
            if [[ $deploy_after -eq 1 ]]; then
                rdf_warn "--deploy for codex requires manual 'rdf deploy --project-root <path> codex'"
            fi
            ;;
        agents-md)
            _generate_adapter "agents-md/adapter.sh" "amd_generate_all"
            if [[ $deploy_after -eq 1 ]]; then
                rdf_warn "--deploy not applicable to agents-md target"
            fi
            ;;
        all)
            rdf_log "generating all adapters..."
            local failed=0

            # Claude Code
            if [[ -f "${RDF_ADAPTERS}/claude-code/adapter.sh" ]]; then
                _generate_adapter "claude-code/adapter.sh" "cc_generate_all" || failed=$((failed + 1))
            fi

            # Gemini CLI
            if [[ -f "${RDF_ADAPTERS}/gemini-cli/adapter.sh" ]]; then
                _generate_adapter "gemini-cli/adapter.sh" "gem_generate_all" || failed=$((failed + 1))
            fi

            # Codex
            if [[ -f "${RDF_ADAPTERS}/codex/adapter.sh" ]]; then
                _generate_adapter "codex/adapter.sh" "cdx_generate_all" || failed=$((failed + 1))
            fi

            # AGENTS.md
            if [[ -f "${RDF_ADAPTERS}/agents-md/adapter.sh" ]]; then
                _generate_adapter "agents-md/adapter.sh" "amd_generate_all" || failed=$((failed + 1))
            fi

            if [[ $failed -gt 0 ]]; then
                rdf_warn "${failed} adapter(s) failed"
            else
                rdf_log "all adapters generated successfully"
            fi

            if [[ $deploy_after -eq 1 ]]; then
                rdf_warn "--deploy with 'all' is not supported — deploy each target individually"
            fi
            ;;
        help|--help|-h)
            _generate_usage
            ;;
        "")
            rdf_die "missing target — run 'rdf generate help' for usage"
            ;;
        *)
            rdf_die "unknown target: $1 — run 'rdf generate help' for usage"
            ;;
    esac
}
