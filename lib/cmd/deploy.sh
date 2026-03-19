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
  claude-code    Deploy to ~/.claude/ (agents, commands, scripts, governance)
  gemini-cli     Deploy to ~/.gemini/ (agents, commands, GEMINI.md)
  codex          Deploy to ~/.codex/ + project root (requires --project-root)

Options:
  --dry-run        Show what would happen without making changes
  --force          Back up real dirs/files and replace with symlinks
  --project-root   Project root for Codex AGENTS.md deployment

Symlinked directories allow 'rdf generate' to update deployed files in place.
Files that require manual merge (e.g., hooks.json) are skipped with a notice.

Examples:
  rdf deploy claude-code
  rdf deploy --dry-run gemini-cli
  rdf deploy --force claude-code
  rdf deploy --project-root /path/to/proj codex
USAGE
}

# Symlink a directory
# Args: $1=source (absolute), $2=destination, $3=dry_run, $4=force
_deploy_symlink_dir() {
    local src="$1"
    local dst="$2"
    local dry_run="$3"
    local force="${4:-0}"

    if [[ ! -d "$src" ]]; then
        rdf_warn "source directory not found: ${src}"
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

    if [[ -L "$dst" ]]; then
        # Already a symlink — replace
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would replace symlink: ${dst} -> ${src}"
        else
            ln -snf "$src" "$dst"
            rdf_log "replaced symlink: ${dst} -> ${src}"
        fi
    elif [[ -d "$dst" ]]; then
        # Real directory
        if [[ $force -eq 1 ]]; then
            local backup
            backup="${dst}.bak-$(date +%Y%m%d%H%M%S)"
            if [[ $dry_run -eq 1 ]]; then
                rdf_log "[dry-run] would back up ${dst} to ${backup}"
                rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
            else
                command mv "$dst" "$backup"
                ln -snf "$src" "$dst"
                rdf_log "backed up ${dst} to ${backup}"
                rdf_log "symlinked: ${dst} -> ${src}"
            fi
        else
            rdf_warn "${dst} exists as a regular directory, not a symlink. Back it up and re-run, or use --force."
        fi
    elif [[ -e "$dst" ]]; then
        # Some other file type at this path
        if [[ $force -eq 1 ]]; then
            local backup
            backup="${dst}.bak-$(date +%Y%m%d%H%M%S)"
            if [[ $dry_run -eq 1 ]]; then
                rdf_log "[dry-run] would back up ${dst} to ${backup}"
                rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
            else
                command mv "$dst" "$backup"
                ln -snf "$src" "$dst"
                rdf_log "backed up ${dst} to ${backup}"
                rdf_log "symlinked: ${dst} -> ${src}"
            fi
        else
            rdf_warn "${dst} exists as a regular file, not a symlink. Back it up and re-run, or use --force."
        fi
    else
        # Absent — create
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
        else
            ln -snf "$src" "$dst"
            rdf_log "symlinked: ${dst} -> ${src}"
        fi
    fi
}

# Symlink a file
# Args: $1=source (absolute), $2=destination, $3=dry_run, $4=force
_deploy_symlink_file() {
    local src="$1"
    local dst="$2"
    local dry_run="$3"
    local force="${4:-0}"

    if [[ ! -f "$src" ]]; then
        rdf_warn "source file not found: ${src}"
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

    if [[ -L "$dst" ]]; then
        # Already a symlink — replace
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would replace symlink: ${dst} -> ${src}"
        else
            ln -snf "$src" "$dst"
            rdf_log "replaced symlink: ${dst} -> ${src}"
        fi
    elif [[ -f "$dst" ]]; then
        # Real file
        if [[ $force -eq 1 ]]; then
            local backup
            backup="${dst}.bak-$(date +%Y%m%d%H%M%S)"
            if [[ $dry_run -eq 1 ]]; then
                rdf_log "[dry-run] would back up ${dst} to ${backup}"
                rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
            else
                command mv "$dst" "$backup"
                ln -snf "$src" "$dst"
                rdf_log "backed up ${dst} to ${backup}"
                rdf_log "symlinked: ${dst} -> ${src}"
            fi
        else
            rdf_warn "${dst} exists as a regular file, not a symlink. Back it up and re-run, or use --force."
        fi
    elif [[ -e "$dst" ]]; then
        # Some other type (directory, etc.)
        if [[ $force -eq 1 ]]; then
            local backup
            backup="${dst}.bak-$(date +%Y%m%d%H%M%S)"
            if [[ $dry_run -eq 1 ]]; then
                rdf_log "[dry-run] would back up ${dst} to ${backup}"
                rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
            else
                command mv "$dst" "$backup"
                ln -snf "$src" "$dst"
                rdf_log "backed up ${dst} to ${backup}"
                rdf_log "symlinked: ${dst} -> ${src}"
            fi
        else
            rdf_warn "${dst} exists as a regular directory, not a symlink. Back it up and re-run, or use --force."
        fi
    else
        # Absent — create
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would symlink: ${dst} -> ${src}"
        else
            ln -snf "$src" "$dst"
            rdf_log "symlinked: ${dst} -> ${src}"
        fi
    fi
}

# Copy a file, skip if destination already exists
# Args: $1=source, $2=destination, $3=dry_run, $4=force
_deploy_copy_skip() {
    local src="$1"
    local dst="$2"
    local dry_run="$3"
    local force="${4:-0}"

    if [[ ! -f "$src" ]]; then
        rdf_warn "source file not found: ${src}"
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
        else
            rdf_warn "${dst} already exists and differs from source. Use --force to overwrite."
        fi
    else
        # Absent — copy
        if [[ $dry_run -eq 1 ]]; then
            rdf_log "[dry-run] would copy: ${src} -> ${dst}"
        else
            command cp "$src" "$dst"
            rdf_log "copied: ${src} -> ${dst}"
        fi
    fi
}

# Deploy Claude Code adapter output to ~/.claude/
_deploy_claude_code() {
    local dry_run="$1"
    local force="$2"
    local output_dir="${RDF_ADAPTERS}/claude-code/output"
    local dest_base="${HOME}/.claude"

    # Pre-flight: output must exist and be non-empty
    if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then
        rdf_die "output not found — run 'rdf generate claude-code' first"
    fi

    rdf_log "deploying Claude Code adapter to ${dest_base}..."

    # Symlink directories
    _deploy_symlink_dir "${output_dir}/agents" "${dest_base}/agents" "$dry_run" "$force"
    _deploy_symlink_dir "${output_dir}/commands" "${dest_base}/commands" "$dry_run" "$force"
    _deploy_symlink_dir "${output_dir}/scripts" "${dest_base}/scripts" "$dry_run" "$force"
    _deploy_symlink_dir "${output_dir}/governance" "${dest_base}/governance" "$dry_run" "$force"

    # Skip hooks.json — requires manual merge
    rdf_log "skipped: hooks.json (manual merge — see 'rdf deploy help')"

    rdf_log "Claude Code deploy complete"
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

    # Symlink directories
    _deploy_symlink_dir "${output_dir}/.gemini/agents" "${dest_base}/agents" "$dry_run" "$force"
    _deploy_symlink_dir "${output_dir}/.gemini/commands" "${dest_base}/commands" "$dry_run" "$force"

    # Symlink GEMINI.md
    _deploy_symlink_file "${output_dir}/.gemini/GEMINI.md" "${dest_base}/GEMINI.md" "$dry_run" "$force"

    rdf_log "Gemini CLI deploy complete"
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

    # Copy AGENTS.md to project root
    _deploy_copy_skip "${output_dir}/AGENTS.md" "${project_root}/AGENTS.md" "$dry_run" "$force"

    # Copy config.toml — skip if exists, warn if differs
    _deploy_copy_skip "${output_dir}/.codex/config.toml" "${dest_base}/config.toml" "$dry_run" "$force"

    rdf_log "Codex deploy complete"
}

cmd_deploy() {
    local dry_run=0
    local force=0
    local project_root=""
    local target=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)      dry_run=1; shift ;;
            --force)        force=1; shift ;;
            --project-root) project_root="$2"; shift 2 ;;
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

    case "$target" in
        claude-code) _deploy_claude_code "$dry_run" "$force" ;;
        gemini-cli)  _deploy_gemini_cli "$dry_run" "$force" ;;
        codex)       _deploy_codex "$dry_run" "$force" "$project_root" ;;
        *)           rdf_die "unknown target: ${target} — run 'rdf deploy help' for usage" ;;
    esac
}
