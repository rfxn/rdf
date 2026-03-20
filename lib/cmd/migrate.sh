#!/usr/bin/env bash
# lib/cmd/migrate.sh — rdf migrate subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_migrate_usage() {
    cat <<'USAGE'
Usage: rdf migrate [options] [path]

Migrate project from .claude/governance/ + work-output/ to .rdf/

Arguments:
  path        Project directory (default: cwd)

Options:
  --dry-run   Show changes without modifying
  --all       Migrate all projects in workspace

Exit codes:
  0   Migration successful
  1   Migration failed (check /tmp/rdf-migrate-{project}.log)
  2   Nothing to migrate (already .rdf/ or fresh project)
  3   Conflict detected (both .claude/governance/ and .rdf/governance/ exist)
USAGE
}

# Convert absolute path to CC auto-memory path-encoded directory name
# /root/admin/work/proj/rdf → -root-admin-work-proj-rdf
_encode_project_path() {
    local abs_path="$1"
    local encoded="${abs_path//\//-}"
    echo "$encoded"
}

_migrate_governance() {
    local project_path="$1"
    local dry_run="$2"
    local log_file="$3"

    local src="${project_path}/.claude/governance"
    local dst="${project_path}/.rdf/governance"

    if [[ ! -d "$src" ]]; then
        rdf_log "  [—] no .claude/governance/ to migrate"
        return 0
    fi

    # Conflict check handled by _migrate_one() before this function is called

    local file_count
    file_count="$(find "$src" -type f 2>/dev/null | wc -l)"
    file_count="${file_count##* }"

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD MOVE: .claude/governance/ → .rdf/governance/ (${file_count} files)"
        return 0
    fi

    command mkdir -p "$dst"
    command cp -a "${src}/." "$dst/" 2>/dev/null || {
        echo "FAIL: cp governance" >> "$log_file"
        rdf_die "failed to copy governance files"
    }

    # Verify copy
    local dst_count
    dst_count="$(find "$dst" -type f 2>/dev/null | wc -l)"
    dst_count="${dst_count##* }"
    if [[ "$dst_count" -ne "$file_count" ]]; then
        echo "FAIL: governance count mismatch src=${file_count} dst=${dst_count}" >> "$log_file"
        rdf_die "governance copy verification failed: expected ${file_count} files, got ${dst_count}"
    fi

    command rm -rf "$src"
    echo "OK: governance ${file_count} files" >> "$log_file"
    rdf_log "  [✓] governance: .claude/governance/ → .rdf/governance/ (${file_count} files)"
}

_migrate_workoutput() {
    local project_path="$1"
    local dry_run="$2"
    local log_file="$3"

    local src="${project_path}/work-output"
    local dst="${project_path}/.rdf/work-output"

    if [[ ! -d "$src" ]]; then
        rdf_log "  [—] no work-output/ to migrate"
        return 0
    fi

    local file_count
    file_count="$(find "$src" -type f 2>/dev/null | wc -l)"
    file_count="${file_count##* }"

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD MOVE: work-output/ → .rdf/work-output/ (${file_count} files)"
        return 0
    fi

    command mkdir -p "$dst"
    if [[ "$file_count" -gt 0 ]]; then
        command cp -a "${src}/." "$dst/" 2>/dev/null || {
            echo "FAIL: cp work-output" >> "$log_file"
            rdf_die "failed to copy work-output files"
        }
    fi

    command rm -rf "$src"
    echo "OK: work-output ${file_count} files" >> "$log_file"
    rdf_log "  [✓] work-output: work-output/ → .rdf/work-output/ (${file_count} files)"
}

_setup_memory_symlink() {
    local project_path="$1"
    local dry_run="$2"
    local log_file="$3"

    local rdf_memory="${project_path}/.rdf/memory"
    local encoded
    encoded="$(_encode_project_path "$project_path")"
    local cc_memory="/root/.claude/projects/${encoded}/memory"

    if [[ -L "$rdf_memory" ]]; then
        rdf_log "  [—] .rdf/memory/ symlink already exists"
        return 0
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ -d "$cc_memory" ]]; then
            rdf_log "  WOULD SYMLINK: .rdf/memory/ → ${cc_memory}"
        else
            rdf_log "  WOULD CREATE: .rdf/memory/ (real directory — CC not detected)"
        fi
        return 0
    fi

    # Remove existing real directory if empty (from rdf init)
    if [[ -d "$rdf_memory" ]] && [[ ! "$(ls -A "$rdf_memory" 2>/dev/null)" ]]; then
        command rmdir "$rdf_memory"
    fi

    if [[ -d "$cc_memory" ]]; then
        command ln -s "$cc_memory" "$rdf_memory"
        echo "OK: memory symlink → ${cc_memory}" >> "$log_file"
        rdf_log "  [✓] memory: .rdf/memory/ → ${cc_memory}"
    else
        command mkdir -p "$rdf_memory"
        echo "OK: memory real dir (CC not detected)" >> "$log_file"
        rdf_log "  [✓] memory: .rdf/memory/ (real directory — CC not detected)"
    fi
}

_update_excludes() {
    local project_path="$1"
    local dry_run="$2"

    local exclude="${project_path}/.git/info/exclude"
    if [[ ! -f "$exclude" ]]; then
        rdf_log "  [—] no .git/info/exclude"
        return 0
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD UPDATE: .git/info/exclude"
        return 0
    fi

    # Remove old RDF entries, preserve everything else
    local old_entries=(".claude/" "work-output/" "audit-output/" "REGR.md")
    local tmp
    tmp="$(mktemp)"
    local removed=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        local skip=0
        for old in "${old_entries[@]}"; do
            if [[ "$line" == "$old" ]]; then
                skip=1
                removed=$((removed + 1))
                break
            fi
        done
        [[ "$skip" -eq 0 ]] && echo "$line" >> "$tmp"
    done < "$exclude"

    # Add .rdf/ if not present
    if ! grep -qxF '.rdf/' "$tmp"; then
        echo '.rdf/' >> "$tmp"
    fi

    command cp "$tmp" "$exclude"
    command rm "$tmp"
    rdf_log "  [✓] .git/info/exclude updated (removed ${removed} old entries)"
}

_migrate_one() {
    local project_path="$1"
    local dry_run="$2"
    local name
    name="$(basename "$project_path")"

    if [[ ! -d "${project_path}/.git" ]]; then
        rdf_warn "${name}: not a git repo — skipping"
        return 1
    fi

    # Check for conflict state (EC1)
    if [[ -d "${project_path}/.claude/governance" ]] && \
       [[ -d "${project_path}/.rdf/governance" ]] && \
       [[ "$(ls -A "${project_path}/.rdf/governance" 2>/dev/null)" ]]; then
        rdf_warn "${name}: conflict — both .claude/governance/ and .rdf/governance/ exist"
        return 3
    fi

    # Nothing to migrate? (EC10)
    if [[ ! -d "${project_path}/.claude/governance" ]] && \
       [[ ! -d "${project_path}/work-output" ]]; then
        if [[ -d "${project_path}/.rdf" ]]; then
            rdf_log "${name}: already migrated — nothing to do"
            return 2
        else
            rdf_log "${name}: fresh project — use 'rdf init' instead"
            return 2
        fi
    fi

    local log_file="/tmp/rdf-migrate-${name}.log"
    echo "=== rdf migrate: ${name} ===" > "$log_file"
    echo "timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$log_file"

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "[dry-run] would migrate ${name} to .rdf/ structure:"
    else
        rdf_log "migrating ${name} to .rdf/ structure..."
    fi

    # Ensure .rdf/ exists
    if [[ "$dry_run" -eq 0 ]]; then
        command mkdir -p "${project_path}/.rdf/governance" \
            "${project_path}/.rdf/work-output" \
            "${project_path}/.rdf/scopes"
        rdf_log "  [✓] .rdf/ created"
    else
        rdf_log "  WOULD CREATE: .rdf/"
    fi

    _migrate_governance "$project_path" "$dry_run" "$log_file"
    _migrate_workoutput "$project_path" "$dry_run" "$log_file"
    _setup_memory_symlink "$project_path" "$dry_run" "$log_file"
    _update_excludes "$project_path" "$dry_run"

    # Clean up empty .claude/ directory
    if [[ "$dry_run" -eq 0 ]] && [[ -d "${project_path}/.claude" ]]; then
        if [[ ! "$(ls -A "${project_path}/.claude" 2>/dev/null)" ]]; then
            command rmdir "${project_path}/.claude"
            rdf_log "  [✓] removed empty .claude/"
        fi
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "no files modified (dry run)"
    else
        rdf_log "migration complete — run 'rdf doctor' to verify"
    fi
}

cmd_migrate() {
    local path=""
    local dry_run=0
    local migrate_all=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)  dry_run=1; shift ;;
            --all)      migrate_all=1; shift ;;
            help|--help|-h) _migrate_usage; return 0 ;;
            -*)         rdf_die "unknown option: $1 — run 'rdf migrate help'" ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"; shift
                else
                    rdf_die "unexpected argument: $1"
                fi
                ;;
        esac
    done

    if [[ "$migrate_all" -eq 1 ]]; then
        local workspace="${path:-/root/admin/work/proj}"
        [[ -d "$workspace" ]] || rdf_die "workspace not found: $workspace"
        workspace="$(cd "$workspace" && pwd)" || exit 1

        local count=0
        local errors=0
        for subdir in "${workspace}"/*/; do
            [[ -d "$subdir" ]] || continue
            [[ -d "${subdir}/.git" ]] || continue
            local subname
            subname="$(basename "$subdir")"
            [[ "$subname" == .* ]] && continue

            _migrate_one "$subdir" "$dry_run" || {
                local rc=$?
                [[ $rc -eq 2 ]] || errors=$((errors + 1))
            }
            count=$((count + 1))
        done

        rdf_log "migration scan complete: ${count} projects, ${errors} errors"
    else
        path="${path:-$(pwd)}"
        [[ -d "$path" ]] || rdf_die "directory not found: $path"
        path="$(cd "$path" && pwd)" || exit 1
        _migrate_one "$path" "$dry_run"
    fi
}
