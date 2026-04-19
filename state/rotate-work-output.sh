#!/usr/bin/env bash
# state/rotate-work-output.sh — Age-based pruning + log truncation for .rdf/work-output/
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Usage: rotate-work-output.sh [--dry-run] [--age <days>] [--size-cap <kb>] <project-root>
set -euo pipefail

_dry_run=0
_age_days=14
_size_cap_kb=100

# Parse flags
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --dry-run)
            _dry_run=1
            shift
            ;;
        --age)
            _age_days="${2:?--age requires a value}"
            shift 2
            ;;
        --size-cap)
            _size_cap_kb="${2:?--size-cap requires a value}"
            shift 2
            ;;
        *)
            printf 'rotate-work-output: unknown flag: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

_project_root="${1:?Usage: rotate-work-output.sh [--dry-run] [--age <days>] [--size-cap <kb>] <project-root>}"

_work_output="${_project_root}/.rdf/work-output"

# Silently succeed if work-output does not exist
if [[ ! -d "$_work_output" ]]; then
    exit 0
fi

# Resolve active basenames from PLAN.md to protect in-use result files
_active_basenames=""
_plan_file="${_project_root}/PLAN.md"
if [[ -f "$_plan_file" ]]; then
    # Extract bare filenames referenced in PLAN.md (no path, just basename)
    _active_basenames="$(grep -oE '[a-zA-Z0-9_-]+\.md' "$_plan_file" 2>/dev/null || true)" # grep exits 1 when no match; both outcomes are valid
fi

# _is_active_in_plan — return 0 if basename is listed in PLAN.md active set
_is_active_in_plan() {
    local base="$1"
    [[ -n "$_active_basenames" ]] || return 1
    echo "$_active_basenames" | grep -qxF "$base"
}

# Prune stale *.md files
_pruned=0
# Use find without -L to avoid following symlinks
while IFS= read -r _file; do
    _base="$(basename "$_file")"
    if _is_active_in_plan "$_base"; then
        if [[ $_dry_run -eq 1 ]]; then
            printf '[dry-run] KEEP (plan-active): %s\n' "$_file"
        fi
        continue
    fi
    if [[ $_dry_run -eq 1 ]]; then
        printf '[dry-run] DELETE (>%d days): %s\n' "$_age_days" "$_file"
    else
        command rm -f "$_file"
    fi
    _pruned=$((_pruned + 1))
done < <(command find "$_work_output" -maxdepth 1 -name '*.md' -not -type l -mtime "+${_age_days}" 2>/dev/null) # suppress permission errors on foreign filesystems

# Truncate agent-feed.log if over size cap
_log_file="${_work_output}/agent-feed.log"
if [[ -f "$_log_file" ]]; then
    _size_kb=$(( $(command wc -c < "$_log_file") / 1024 ))
    if [[ $_size_kb -gt $_size_cap_kb ]]; then
        if [[ $_dry_run -eq 1 ]]; then
            printf '[dry-run] TRUNCATE agent-feed.log (%d KB > %d KB cap, keep last 1000 lines)\n' \
                "$_size_kb" "$_size_cap_kb"
        else
            # Write last 1000 lines to a temp file, then replace atomically
            _tmp="$(command mktemp "${_work_output}/.agent-feed.tmp.XXXXXX")"
            tail -n 1000 "$_log_file" > "$_tmp"
            command mv "$_tmp" "$_log_file"
        fi
    fi
fi

if [[ $_dry_run -eq 0 && $_pruned -gt 0 ]]; then
    printf 'rotate-work-output: pruned %d file(s) from %s\n' "$_pruned" "$_work_output"
fi

exit 0
