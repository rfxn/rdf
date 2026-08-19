#!/usr/bin/env bash
# lib/cmd/deploy.sh — rdf deploy subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_deploy_usage() {
    cat <<'USAGE'
Usage: rdf deploy [options] <target>

Deploy generated adapter output to its tool-specific destination.

Targets:
  claude-code    Deploy to ~/.claude/ (agents, commands, scripts, governance) + ~/.rdf/state helpers
  gemini-cli     Deploy to ~/.gemini/ (agents, commands, GEMINI.md)
  codex          Deploy to ~/.codex/ + project root (requires --project-root)
  agent-skills   Deploy .agents/skills/ into a workspace root (--project-root, default CWD)

Options:
  --dry-run        Show what would happen without making changes
  --force          Back up real dirs/files and replace with symlinks
  --rules          Also symlink scoped governance rules/ (claude-code; opt-in)
  --lite           rdf-lite deploy: symlink rules/ as governance, skip hooks
  --project-root   Project root for Codex AGENTS.md deployment

Hooks merge (claude-code symlink deploy only; plugin installs auto-register):
  hooks.json is never symlinked. From the RDF checkout root, merge it into
  ~/.claude/settings.json (settings.json controls what your agent executes —
  stage through mktemp, never a predictable /tmp path):
    t=$(mktemp) && jq -s '.[0] * .[1]' ~/.claude/settings.json adapters/claude-code/hooks/hooks.json > "$t" && cp "$t" ~/.claude/settings.json && rm -f "$t"
  Review the result: '*' merges objects recursively but REPLACES arrays —
  if you already define hooks for the same event, merge those manually.

Exit status: 0 all items deployed; 1 if any item was skipped.

Symlinked directories allow 'rdf generate' to update deployed files in place.
Files that require manual merge (e.g., hooks.json) are reported with a
notice and do not affect the exit status.

Examples:
  rdf deploy claude-code
  rdf deploy --dry-run gemini-cli
  rdf deploy --force claude-code
  rdf deploy --project-root /path/to/proj codex
USAGE
}

# Counters for summary reporting
_DEPLOY_OK=0
_DEPLOY_SKIPPED=0

# Symlink a source to a destination (works for both dirs and files)
# Args: $1=source (absolute), $2=destination, $3=dry_run, $4=force
# The source type (-d or -f) is auto-detected.
_deploy_symlink() {
    local src="$1"
    local dst="$2"
    local dry_run="$3"
    local force="${4:-0}"

    # Validate source exists
    if [[ ! -e "$src" ]]; then
        rdf_warn "source not found: ${src}"
        _DEPLOY_SKIPPED=$((_DEPLOY_SKIPPED + 1))
        return 1
    fi

    # Ensure parent directory exists
    local parent
    parent="$(dirname "$dst")"
    if [[ ! -d "$parent" ]]; then
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would create directory: ${parent}"
        else
            command mkdir -p "$parent"
        fi
    fi

    if [[ -L "$dst" ]]; then
        # Already a symlink — replace
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would replace symlink: ${dst} -> ${src}"
        else
            command ln -snf "$src" "$dst"
            rdf_log "replaced symlink: ${dst} -> ${src}"
        fi
        _DEPLOY_OK=$((_DEPLOY_OK + 1))
    elif [[ -e "$dst" ]]; then
        # Real file or directory exists
        if [[ $force -eq 1 ]]; then
            local backup
            backup="${dst}.bak-$(date +%Y%m%d%H%M%S)"
            if [[ $dry_run -eq 1 ]]; then
                rdf_log "[dry-run] would back up ${dst} to ${backup}"
                rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
            else
                command mv "$dst" "$backup"
                command ln -snf "$src" "$dst"
                rdf_log "backed up ${dst} to ${backup}"
                rdf_log "symlinked: ${dst} -> ${src}"
            fi
            _DEPLOY_OK=$((_DEPLOY_OK + 1))
        else
            rdf_warn "${dst} exists (not a symlink). Back it up and re-run, or use --force."
            _DEPLOY_SKIPPED=$((_DEPLOY_SKIPPED + 1))
        fi
    else
        # Absent — create
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
        else
            command ln -snf "$src" "$dst"
            rdf_log "symlinked: ${dst} -> ${src}"
        fi
        _DEPLOY_OK=$((_DEPLOY_OK + 1))
    fi
}

# Copy a file, skip if destination already exists and matches
# Args: $1=source, $2=destination, $3=dry_run, $4=force
_deploy_copy_skip() {
    local src="$1"
    local dst="$2"
    local dry_run="$3"
    local force="${4:-0}"

    if [[ ! -f "$src" ]]; then
        rdf_warn "source file not found: ${src}"
        _DEPLOY_SKIPPED=$((_DEPLOY_SKIPPED + 1))
        return 1
    fi

    # Ensure parent exists
    local parent
    parent="$(dirname "$dst")"
    if [[ ! -d "$parent" ]]; then
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would create directory: ${parent}"
        else
            command mkdir -p "$parent"
        fi
    fi

    if [[ -f "$dst" ]]; then
        if diff -q "$src" "$dst" >/dev/null 2>&1; then
            rdf_log "unchanged: ${dst}"
            _DEPLOY_OK=$((_DEPLOY_OK + 1))
        elif [[ $force -eq 1 ]]; then
            local backup
            backup="${dst}.bak-$(date +%Y%m%d%H%M%S)"
            if [[ $dry_run -eq 1 ]]; then
                rdf_log "[dry-run] would back up ${dst} to ${backup}"
                rdf_log "[dry-run] would copy: ${src} -> ${dst}"
            else
                command cp "$dst" "$backup"
                command cp "$src" "$dst"
                rdf_log "backed up ${dst} to ${backup}"
                rdf_log "copied: ${src} -> ${dst}"
            fi
            _DEPLOY_OK=$((_DEPLOY_OK + 1))
        else
            rdf_warn "${dst} already exists and differs from source. Use --force to overwrite."
            _DEPLOY_SKIPPED=$((_DEPLOY_SKIPPED + 1))
        fi
    else
        # Absent — copy
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would copy: ${src} -> ${dst}"
        else
            command cp "$src" "$dst"
            rdf_log "copied: ${src} -> ${dst}"
        fi
        _DEPLOY_OK=$((_DEPLOY_OK + 1))
    fi
}

# Deploy state helpers as per-file symlinks into ~/.rdf/state/ (glob-driven —
# no hard-coded list). The dir itself stays real: handoff/ inside it is a
# runtime write target. Helpers are per-user, so the destination is always
# $HOME-scoped and does not follow RDF_TARGET.
# Symlink one helper, migrating a byte-identical legacy copy without --force;
# differing real files keep _deploy_symlink's skip-with-warn (--force to replace).
_deploy_state_link() {
    local src="$1" dst="$2" dry_run="$3" force="$4"
    if [[ -f "$dst" && ! -L "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then  # identical = machine-managed copy, safe to replace
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would migrate identical copy: ${dst} -> ${src}"
            _DEPLOY_OK=$((_DEPLOY_OK + 1))
            return 0
        fi
        command rm -f "$dst"
    fi
    _deploy_symlink "$src" "$dst" "$dry_run" "$force"
}

_deploy_state_helpers() {
    local dry_run="$1"
    local force="$2"
    local state_dst="${HOME}/.rdf/state"
    local src
    for src in "${RDF_HOME}/state/"*.sh; do
        [[ -f "$src" ]] || continue
        _deploy_state_link "$src" "${state_dst}/$(command basename "$src")" "$dry_run" "$force"
    done
    src="${RDF_HOME}/state/git-hooks/pre-commit"
    if [[ -f "$src" ]]; then
        _deploy_state_link "$src" "${state_dst}/git-hooks/pre-commit" "$dry_run" "$force"
    fi
    # Symlink delivery supersedes plugin-bootstrap copies — retire the stamps.
    [[ $dry_run -eq 1 ]] || command rm -f "${state_dst}/.rdf-version" "${state_dst}/.rdf-source"
    return 0
}

# Deploy Claude Code adapter output to ~/.claude/
_deploy_claude_code() {
    local dry_run="$1"
    local force="$2"
    local deploy_rules="${3:-0}"   # opt-in scoped rules/ symlink (default off)
    local output_dir="${RDF_ADAPTERS}/claude-code/output"
    local dest_base="${RDF_TARGET:-${HOME}/.claude}"

    # Pre-flight: output must exist and be non-empty
    if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then
        rdf_die "output not found — run 'rdf generate claude-code' first"
    fi

    local plugin_manifest="${HOME}/.claude/plugins/installed_plugins.json"
    if command -v jq >/dev/null 2>&1 \
        && [[ -f "$plugin_manifest" ]] \
        && jq -e '.plugins | has("rdf@rdf")' "$plugin_manifest" >/dev/null 2>&1; then  # no jq / no manifest = skip advisory silently
        rdf_warn "plugin install detected (rdf@rdf) — symlink deploy will duplicate commands as /r-* and /rdf:r-*"
    fi

    rdf_log "deploying Claude Code adapter to ${dest_base}..."

    _deploy_symlink "${output_dir}/agents" "${dest_base}/agents" "$dry_run" "$force"
    _deploy_symlink "${output_dir}/commands" "${dest_base}/commands" "$dry_run" "$force"
    _deploy_symlink "${output_dir}/scripts" "${dest_base}/scripts" "$dry_run" "$force"
    _deploy_symlink "${output_dir}/governance" "${dest_base}/governance" "$dry_run" "$force"
    _deploy_symlink "${output_dir}/reference" "${dest_base}/reference" "$dry_run" "$force"

    # Scoped rules/ are opt-in (--rules): default keeps existing symlink users unchanged.
    if [[ "$deploy_rules" -eq 1 && -d "${output_dir}/rules" ]]; then
        _deploy_symlink "${output_dir}/rules" "${dest_base}/rules" "$dry_run" "$force"
    fi

    _deploy_state_helpers "$dry_run" "$force"

    # Skip hooks.json — requires manual merge
    rdf_log "manual merge required: hooks.json (see 'rdf deploy help'; does not affect exit status)"
}

# Deploy Gemini CLI adapter output to ~/.gemini/
_deploy_gemini_cli() {
    local dry_run="$1"
    local force="$2"
    local output_dir="${RDF_ADAPTERS}/gemini-cli/output"
    local dest_base="${HOME}/.gemini"

    # Pre-flight: output must exist and be non-empty
    if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then
        rdf_die "output not found — run 'rdf generate gemini-cli' first"
    fi

    rdf_log "deploying Gemini CLI adapter to ${dest_base}..."

    _deploy_symlink "${output_dir}/.gemini/agents" "${dest_base}/agents" "$dry_run" "$force"
    _deploy_symlink "${output_dir}/.gemini/commands" "${dest_base}/commands" "$dry_run" "$force"
    _deploy_symlink "${output_dir}/.gemini/GEMINI.md" "${dest_base}/GEMINI.md" "$dry_run" "$force"
    _deploy_symlink "${output_dir}/scripts" "${dest_base}/scripts" "$dry_run" "$force"
}

# Deploy Codex adapter output to ~/.codex/ + project root
_deploy_codex() {
    local dry_run="$1"
    local force="$2"
    local project_root="$3"
    local output_dir="${RDF_ADAPTERS}/codex/output"
    local dest_base="${HOME}/.codex"

    # Pre-flight: output must exist and be non-empty
    if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then
        rdf_die "output not found — run 'rdf generate codex' first"
    fi

    # Pre-flight: --project-root must be provided and valid
    if [[ -z "$project_root" ]]; then
        rdf_die "codex deploy requires --project-root <path>"
    fi
    if [[ ! -d "$project_root" ]]; then
        rdf_die "project root not a directory: ${project_root}"
    fi

    rdf_log "deploying Codex adapter to ${dest_base} and ${project_root}..."

    _deploy_copy_skip "${output_dir}/AGENTS.md" "${project_root}/AGENTS.md" "$dry_run" "$force"
    _deploy_copy_skip "${output_dir}/.codex/config.toml" "${dest_base}/config.toml" "$dry_run" "$force"
}

# Deploy agent-skills output (.agents/skills/) into a workspace root
_deploy_agent_skills() {
    local dry_run="$1"
    local force="$2"
    local project_root="$3"
    local output_dir="${RDF_ADAPTERS}/agent-skills/output"

    if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then  # 2>/dev/null: empty-on-missing is the intended empties→rdf_die value
        rdf_die "output not found — run 'rdf generate agent-skills' first"
    fi
    [[ -n "$project_root" ]] || project_root="$PWD"
    if [[ ! -d "$project_root" ]]; then
        rdf_die "project root not a directory: ${project_root}"
    fi

    rdf_log "deploying agent-skills to ${project_root}/.agents/skills..."
    _deploy_symlink "${output_dir}/.agents/skills" "${project_root}/.agents/skills" "$dry_run" "$force"
}

cmd_deploy() {
    local dry_run=0
    local force=0
    local deploy_rules=0
    local project_root=""
    local target=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)      dry_run=1; shift ;;
            --force)        force=1; shift ;;
            --rules)        deploy_rules=1; shift ;;
            --lite)         deploy_rules=1; shift ;;   # rdf-lite: rules ARE the governance; hooks skipped as always
            --project-root)
                if [[ $# -lt 2 ]]; then
                    rdf_die "--project-root requires a value"
                fi
                project_root="$2"; shift 2
                ;;
            help|--help|-h) _deploy_usage; return 0 ;;
            -*)             rdf_die "unknown option: $1 — run 'rdf deploy help' for usage" ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                    shift
                else
                    rdf_die "unexpected argument: $1 — run 'rdf deploy help' for usage"
                fi
                ;;
        esac
    done

    if [[ -z "$target" ]]; then
        rdf_die "missing target — run 'rdf deploy help' for usage"
    fi

    # Reset counters
    _DEPLOY_OK=0
    _DEPLOY_SKIPPED=0

    # jq preflight — hooks and the statusline degrade without it (non-fatal)
    if ! command -v jq >/dev/null 2>&1; then
        rdf_warn "jq not found on PATH — deployed hooks and statusline degrade until installed (apt/dnf install jq, or brew install jq)"
    fi

    case "$target" in
        claude-code) _deploy_claude_code "$dry_run" "$force" "$deploy_rules" ;;
        gemini-cli)  _deploy_gemini_cli "$dry_run" "$force" ;;
        codex)       _deploy_codex "$dry_run" "$force" "$project_root" ;;
        agent-skills) _deploy_agent_skills "$dry_run" "$force" "$project_root" ;;
        *)           rdf_die "unknown target: ${target} — run 'rdf deploy help' for usage" ;;
    esac

    # Summary with skip reporting
    if [[ $_DEPLOY_SKIPPED -gt 0 ]]; then
        rdf_warn "deploy complete: ${_DEPLOY_OK} deployed, ${_DEPLOY_SKIPPED} skipped (use --force to override)"
        return 1
    fi
    rdf_log "deploy complete: ${_DEPLOY_OK} items deployed"
}
