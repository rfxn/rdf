#!/usr/bin/env bash
# state/rdf-state.sh — Deterministic project state snapshot
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Usage: rdf-state.sh [project-path]
# Output: JSON to stdout
set -euo pipefail

_project_path="${1:-.}"

# Resolve to absolute path
_project_path="$(cd "$_project_path" && pwd)" || {
    echo '{"error": "invalid path"}' >&2
    exit 1
}

# Helper: escape string for JSON
_json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    echo -n "$s"
}

# Project name — directory basename
_project_name="$(basename "$_project_path")"

# Version — from VERSION file or project binary version variable
# rfxn projects use: VERSION=, VER=, V=, lmd_version=, etc.
_version="unknown"
if [[ -f "${_project_path}/VERSION" ]]; then
    _version="$(< "${_project_path}/VERSION")"
    _version="${_version%%[[:space:]]}"
else
    # Search for version assignment patterns in project binaries under files/
    if [[ -d "${_project_path}/files" ]]; then
        for _vf in "${_project_path}/files"/*; do
            [[ -f "$_vf" ]] || continue
            # Match common rfxn version patterns with semver-like values
            # Requires at least N.N to avoid matching config toggles like ="1"
            _v_line="$(grep -m1 -E '^(VERSION|VER|V|[a-z_]*_version)="?[0-9]+\.[0-9]' "$_vf" 2>/dev/null || true)"
            if [[ -n "$_v_line" ]]; then
                # Strip key name up to first =
                _version="${_v_line#*=}"
                _version="${_version//\"/}"
                _version="${_version//\'/}"
                break
            fi
        done
    fi
fi

# Git state
_branch=""
_dirty="false"
_uncommitted=0
_last_hash=""
_last_age_hours=0
_commits_since_tag=0
_is_git="false"

if git -C "$_project_path" rev-parse --git-dir >/dev/null 2>&1; then
    _is_git="true"
    _branch="$(git -C "$_project_path" branch --show-current 2>/dev/null || echo "")"

    if ! git -C "$_project_path" diff --quiet 2>/dev/null || \
       ! git -C "$_project_path" diff --cached --quiet 2>/dev/null; then
        _dirty="true"
    fi

    _uncommitted="$(git -C "$_project_path" status --porcelain 2>/dev/null | wc -l)"
    _uncommitted="${_uncommitted##* }"

    _last_hash="$(git -C "$_project_path" rev-parse --short HEAD 2>/dev/null || echo "")"

    local_epoch="$(git -C "$_project_path" log -1 --format='%ct' 2>/dev/null || echo "0")"
    now_epoch="$(date +%s)"
    if [[ "$local_epoch" -gt 0 ]]; then
        _last_age_hours=$(( (now_epoch - local_epoch) / 3600 ))
    fi

    _tag="$(git -C "$_project_path" describe --tags --abbrev=0 2>/dev/null || echo "")"
    if [[ -n "$_tag" ]]; then
        _commits_since_tag="$(git -C "$_project_path" rev-list "${_tag}..HEAD" --count 2>/dev/null || echo "0")"
    else
        _commits_since_tag="$(git -C "$_project_path" rev-list HEAD --count 2>/dev/null || echo "0")"
    fi
fi

# File existence checks
_memory_exists="false"
_memory_age_hours=0
_plan_exists="false"
_audit_exists="false"

# Check for MEMORY.md in project directory
if [[ -f "${_project_path}/MEMORY.md" ]]; then
    _memory_exists="true"
    _mem_mtime="$(stat -c %Y "${_project_path}/MEMORY.md" 2>/dev/null || echo "0")"
    if [[ "$_mem_mtime" -gt 0 ]]; then
        _memory_age_hours=$(( ($(date +%s) - _mem_mtime) / 3600 ))
    fi
fi

[[ -f "${_project_path}/PLAN.md" ]] && _plan_exists="true"
[[ -f "${_project_path}/AUDIT.md" ]] && _audit_exists="true"

# Plan phase counts
# Note: grep -c exits 1 when count is 0 but still outputs "0" —
# using || true to suppress the exit code without doubling the output
_plan_total=0
_plan_completed=0
_plan_active=0
_plan_pending=0
if [[ "$_plan_exists" == "true" ]]; then
    _plan_total="$(grep -c -E -i '^(###|## ).*phase|^### Task' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    _plan_completed="$(grep -c -E -i 'COMPLETE|DONE' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    _plan_active="$(grep -c -E -i 'IN.PROGRESS|ACTIVE' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    _plan_pending="$(grep -c -i '^PENDING' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    # Ensure numeric — fallback if grep produced empty output
    [[ -z "$_plan_total" ]] && _plan_total=0
    [[ -z "$_plan_completed" ]] && _plan_completed=0
    [[ -z "$_plan_active" ]] && _plan_active=0
    [[ -z "$_plan_pending" ]] && _plan_pending=0
fi

# Work output files
_work_output_files="[]"
if [[ -d "${_project_path}/work-output" ]]; then
    _wo_list="$(find "${_project_path}/work-output" -maxdepth 1 -type f -name '*.md' -printf '"%f",' 2>/dev/null | sed 's/,$//' || echo "")"
    _work_output_files="[${_wo_list}]"
fi

# Output JSON
cat <<JSONEOF
{
  "project": "$(_json_str "$_project_name")",
  "path": "$(_json_str "$_project_path")",
  "version": "$(_json_str "$_version")",
  "is_git": ${_is_git},
  "branch": "$(_json_str "$_branch")",
  "dirty": ${_dirty},
  "uncommitted_files": ${_uncommitted},
  "last_commit_hash": "$(_json_str "$_last_hash")",
  "last_commit_age_hours": ${_last_age_hours},
  "commits_since_tag": ${_commits_since_tag},
  "memory_exists": ${_memory_exists},
  "memory_age_hours": ${_memory_age_hours},
  "plan_exists": ${_plan_exists},
  "plan_phases": {
    "total": ${_plan_total},
    "completed": ${_plan_completed},
    "active": ${_plan_active},
    "pending": ${_plan_pending}
  },
  "audit_exists": ${_audit_exists},
  "work_output_files": ${_work_output_files}
}
JSONEOF
