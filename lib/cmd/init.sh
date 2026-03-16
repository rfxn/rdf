#!/usr/bin/env bash
# lib/cmd/init.sh — rdf init subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_init_usage() {
    cat <<'USAGE'
Usage: rdf init <path> [options]

Initialize a project with RDF conventions. Creates CLAUDE.md from profile
templates, sets up .git/info/exclude, creates work-output/ directory.

Arguments:
  path                  Project directory to initialize

Options:
  --type TYPE           Force project type: shell|lib|frontend|security|minimal
                        (default: auto-detect)
  --tools TOOLS         Comma-separated tool targets (default: claude-code)
  --version X.Y.Z       Initial version string (default: from VERSION file or 0.1.0)
  --no-memory           Skip MEMORY.md placeholder creation
  --github              Create labels + repo project board via gh CLI
  --batch               Process multiple directories (path is parent dir)
  --dry-run             Show what would be created without writing

Examples:
  rdf init /root/admin/work/proj/my-project
  rdf init /root/admin/work/proj/my-project --type shell --github
  rdf init /root/admin/work/proj --batch --type minimal
  rdf init /root/admin/work/proj/inactive --batch --dry-run
USAGE
}

# Project type detection heuristic
# Priority: files/ dir -> shell, lib/ dir -> lib, package.json -> frontend, else -> minimal
# Security type is never auto-detected — must be explicit --type security
_detect_project_type() {
    local path="$1"
    if [[ -d "${path}/files" ]]; then
        # Distinguish shell project from lib by checking for a main executable
        # Libraries have files/<name>.sh (single .sh file), shell projects have
        # files/<name> (executable without extension) or files/internals/
        local name
        name="$(basename "$path")"
        if [[ -f "${path}/files/${name}.sh" ]] && [[ ! -f "${path}/files/${name}" ]]; then
            echo "lib"
        else
            echo "shell"
        fi
    elif [[ -d "${path}/lib" ]]; then
        echo "lib"
    elif [[ -f "${path}/package.json" ]]; then
        echo "frontend"
    else
        echo "minimal"
    fi
}

# Map project type to profile name for template lookup
_type_to_profile() {
    local type="$1"
    case "$type" in
        shell)    echo "systems-engineering" ;;
        lib)      echo "systems-engineering" ;;
        frontend) echo "frontend" ;;
        security) echo "security" ;;
        minimal)  echo "core" ;;
        *)        echo "core" ;;
    esac
}

# Map project type to template filename
_type_to_template() {
    local type="$1"
    case "$type" in
        shell)    echo "claude-shell.md.tmpl" ;;
        lib)      echo "claude-lib.md.tmpl" ;;
        frontend) echo "claude-frontend.md.tmpl" ;;
        security) echo "claude-security.md.tmpl" ;;
        minimal)  echo "claude-minimal.md.tmpl" ;;
        *)        echo "claude-minimal.md.tmpl" ;;
    esac
}

# Resolve version from project directory
_resolve_version() {
    local path="$1"
    local explicit="${2:-}"

    # Explicit --version wins
    if [[ -n "$explicit" ]]; then
        echo "$explicit"
        return 0
    fi

    # VERSION file
    if [[ -f "${path}/VERSION" ]]; then
        local v
        v="$(< "${path}/VERSION")"
        v="${v%%[[:space:]]}"
        echo "$v"
        return 0
    fi

    # files/<project-name> VERSION= line
    local name
    name="$(basename "$path")"
    if [[ -f "${path}/files/${name}" ]]; then
        local v
        # grep may exit 1 if no match — safe to ignore here
        v="$(grep -m1 '^VERSION=' "${path}/files/${name}" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
        if [[ -n "$v" ]]; then
            echo "$v"
            return 0
        fi
    fi

    echo "0.1.0"
}

# Standard .git/info/exclude entries for rfxn projects
_GIT_EXCLUDE_ENTRIES=(
    "# RDF working files (managed by rdf init)"
    "CLAUDE.md"
    "PLAN*.md"
    "AUDIT.md"
    "REGR.md"
    "MEMORY.md"
    ".claude/"
    "audit-output/"
    "work-output/"
)

# Ensure .git/info/exclude has all required entries
_setup_git_exclude() {
    local path="$1"
    local dry_run="$2"

    local exclude_file="${path}/.git/info/exclude"
    if [[ ! -d "${path}/.git" ]]; then
        rdf_warn "not a git repo — skipping .git/info/exclude: ${path}"
        return 0
    fi

    # Ensure directory exists
    if [[ ! -d "${path}/.git/info" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD CREATE: .git/info/"
        else
            command mkdir -p "${path}/.git/info"
        fi
    fi

    local existing=""
    if [[ -f "$exclude_file" ]]; then
        existing="$(< "$exclude_file")"
    fi

    local added=0
    local to_append=""
    for entry in "${_GIT_EXCLUDE_ENTRIES[@]}"; do
        # Skip comment lines for matching purposes
        if [[ "$entry" == "#"* ]]; then
            # Add the comment header only if the block hasn't been added before
            if [[ "$existing" != *"RDF working files"* ]] && [[ $added -eq 0 ]]; then
                to_append="${to_append}${entry}"$'\n'
            fi
            continue
        fi
        # Check if entry already present (exact line match)
        if ! echo "$existing" | grep -qxF "$entry"; then
            to_append="${to_append}${entry}"$'\n'
            added=$((added + 1))
        fi
    done

    if [[ $added -gt 0 ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD ADD ${added} entries to .git/info/exclude"
        else
            # Append with a blank line separator if file is non-empty
            if [[ -n "$existing" ]] && [[ "${existing: -1}" != $'\n' ]]; then
                echo "" >> "$exclude_file"
            fi
            echo "" >> "$exclude_file"
            printf '%s' "$to_append" >> "$exclude_file"
            rdf_log "  added ${added} entries to .git/info/exclude"
        fi
    else
        rdf_log "  .git/info/exclude already complete"
    fi
}

# Generate CLAUDE.md from profile template
_generate_claude_md() {
    local path="$1"
    local type="$2"
    local version="$3"
    local dry_run="$4"

    local profile
    profile="$(_type_to_profile "$type")"
    local template_name
    template_name="$(_type_to_template "$type")"
    local template_file="${RDF_HOME}/profiles/${profile}/templates/${template_name}"

    local name
    name="$(basename "$path")"

    if [[ ! -f "$template_file" ]]; then
        # Fallback: generate a minimal CLAUDE.md inline
        rdf_warn "template not found: ${template_file} — generating minimal CLAUDE.md"
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD CREATE: CLAUDE.md (minimal, type=${type})"
            return 0
        fi
        cat > "${path}/CLAUDE.md" <<MINIMAL
# ${name} — Project CLAUDE.md

> **Inherits all shared conventions from parent CLAUDE.md** (\`/root/admin/work/proj/CLAUDE.md\`).
> This file covers ${name}-specific architecture, constraints, and testing only.

## Project Overview

${name} version ${version}. Type: ${type}.

## Project Structure

\`\`\`
(TODO: document project structure)
\`\`\`
MINIMAL
        rdf_log "  created CLAUDE.md (minimal fallback)"
        return 0
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD CREATE: CLAUDE.md (template=${template_name}, type=${type})"
        return 0
    fi

    # Template variable substitution
    # Supported variables: {{PROJECT_NAME}}, {{VERSION}}, {{TYPE}},
    # {{PARENT_CLAUDE_PATH}}, {{YEAR}}
    local year
    year="$(date +%Y)"
    local parent_path="/root/admin/work/proj/CLAUDE.md"

    sed \
        -e "s|{{PROJECT_NAME}}|${name}|g" \
        -e "s|{{VERSION}}|${version}|g" \
        -e "s|{{TYPE}}|${type}|g" \
        -e "s|{{PARENT_CLAUDE_PATH}}|${parent_path}|g" \
        -e "s|{{YEAR}}|${year}|g" \
        "$template_file" > "${path}/CLAUDE.md"

    rdf_log "  created CLAUDE.md (template=${template_name})"
}

# Initialize a single project
_init_one() {
    local path="$1"
    local type="$2"
    local version="$3"
    local no_memory="$4"
    local do_github="$5"
    local dry_run="$6"

    local name
    name="$(basename "$path")"

    rdf_log "initializing: ${name} (type=${type}, version=${version})"

    # 1. CLAUDE.md from template
    if [[ -f "${path}/CLAUDE.md" ]]; then
        rdf_log "  CLAUDE.md already exists — skipping (use rdf doctor to check drift)"
    else
        _generate_claude_md "$path" "$type" "$version" "$dry_run"
    fi

    # 2. .git/info/exclude
    _setup_git_exclude "$path" "$dry_run"

    # 3. work-output/ directory
    if [[ ! -d "${path}/work-output" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD CREATE: work-output/"
        else
            command mkdir -p "${path}/work-output"
            rdf_log "  created work-output/"
        fi
    fi

    # 4. MEMORY.md placeholder (unless --no-memory)
    if [[ "$no_memory" -eq 0 ]] && [[ ! -f "${path}/MEMORY.md" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD CREATE: MEMORY.md (placeholder)"
        else
            cat > "${path}/MEMORY.md" <<MEMEOF
# ${name} — Project Memory

## Project Status
- **Version:** ${version}
- **Type:** ${type}
- **Status:** initialized via rdf init

## Session Log
MEMEOF
            rdf_log "  created MEMORY.md placeholder"
        fi
    fi

    # 5. GitHub scaffolding (labels + project board)
    if [[ "$do_github" -eq 1 ]]; then
        if ! command -v gh >/dev/null 2>&1; then
            rdf_warn "gh CLI not found — skipping GitHub scaffolding"
        elif [[ ! -d "${path}/.git" ]]; then
            rdf_warn "not a git repo — skipping GitHub scaffolding"
        else
            local repo
            repo="$(git -C "$path" remote get-url origin 2>/dev/null \
                | sed 's|.*github.com[:/]||; s|\.git$||' || echo "")"
            if [[ -z "$repo" ]]; then
                rdf_warn "cannot detect GitHub repo from origin — skipping"
            elif [[ "$dry_run" -eq 1 ]]; then
                rdf_log "  WOULD RUN: rdf github setup --repo ${repo}"
            else
                # Source github.sh and call setup
                # shellcheck disable=SC1090,SC1091
                source "${RDF_LIBDIR}/cmd/github.sh"
                _github_setup --repo "$repo"
            fi
        fi
    fi

    rdf_log "init complete: ${name}"
}

# shellcheck disable=SC2034  # tools reserved for Phase 8
cmd_init() {
    local path=""
    local type=""
    local tools="claude-code"  # reserved for Phase 8 multi-tool support
    local version=""
    local no_memory=0
    local do_github=0
    local batch=0
    local dry_run=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)      type="$2"; shift 2 ;;
            --tools)     tools="$2"; shift 2 ;;
            --version)   version="$2"; shift 2 ;;
            --no-memory) no_memory=1; shift ;;
            --github)    do_github=1; shift ;;
            --batch)     batch=1; shift ;;
            --dry-run)   dry_run=1; shift ;;
            help|--help|-h) _init_usage; return 0 ;;
            -*)          rdf_die "unknown option: $1 — run 'rdf init help'" ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"; shift
                else
                    rdf_die "unexpected argument: $1 — run 'rdf init help'"
                fi
                ;;
        esac
    done

    [[ -z "$path" ]] && rdf_die "missing path — run 'rdf init help'"

    # Resolve to absolute path
    if [[ ! -d "$path" ]]; then
        rdf_die "directory not found: $path"
    fi
    path="$(cd "$path" && pwd)" || rdf_die "cannot resolve path: $path"

    # Validate --type if explicit
    if [[ -n "$type" ]]; then
        case "$type" in
            shell|lib|frontend|security|minimal) ;;
            *) rdf_die "invalid type: $type — must be shell|lib|frontend|security|minimal" ;;
        esac
    fi

    if [[ "$batch" -eq 1 ]]; then
        # Batch mode: iterate subdirectories
        rdf_log "batch init: scanning ${path}..."
        local count=0

        for subdir in "${path}"/*/; do
            [[ -d "$subdir" ]] || continue
            local subname
            subname="$(basename "$subdir")"

            # Skip hidden directories and non-project dirs
            [[ "$subname" == .* ]] && continue

            # Auto-detect type per project unless --type forced
            local proj_type="$type"
            if [[ -z "$proj_type" ]]; then
                proj_type="$(_detect_project_type "$subdir")"
            fi

            local proj_version
            proj_version="$(_resolve_version "$subdir" "$version")"

            _init_one "$subdir" "$proj_type" "$proj_version" "$no_memory" "$do_github" "$dry_run"
            count=$((count + 1))
        done

        rdf_log "batch init complete: ${count} projects processed"
    else
        # Single project mode
        if [[ -z "$type" ]]; then
            type="$(_detect_project_type "$path")"
            rdf_log "auto-detected type: ${type}"
        fi

        local resolved_version
        resolved_version="$(_resolve_version "$path" "$version")"

        _init_one "$path" "$type" "$resolved_version" "$no_memory" "$do_github" "$dry_run"
    fi
}
