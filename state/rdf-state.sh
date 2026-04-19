#!/usr/bin/env bash
# state/rdf-state.sh — Deterministic project state snapshot
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Usage: rdf-state.sh [--full] [--no-insights] [project-path]
# Output: JSON to stdout
# --full: include extended fields for /r-start dashboard
# --no-insights: omit global insights array (caller reads once)
set -euo pipefail

# timeout wrapper — empty on systems without the binary (CentOS 6 minimal)
if command -v timeout >/dev/null 2>&1; then TIMEOUT_PREFIX="timeout 30"; else TIMEOUT_PREFIX=""; fi

_full_mode=0
_skip_insights=0
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --full) _full_mode=1; shift ;;
        --no-insights) _skip_insights=1; shift ;;
        *) break ;;
    esac
done

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
    s="${s//$'\n'/\\n}"
    echo -n "$s"
}

# Project name — directory basename
_project_name="$(basename "$_project_path")"

# Version — from VERSION file or project binary version variable
_version="unknown"
if [[ -f "${_project_path}/VERSION" ]]; then
    _version="$(< "${_project_path}/VERSION")"
    _version="${_version%%[[:space:]]}"
else
    if [[ -d "${_project_path}/files" ]]; then
        for _vf in "${_project_path}/files"/*; do
            [[ -f "$_vf" ]] || continue
            _v_line="$(grep -m1 -E '^(VERSION|VER|V|[a-z_]*_version)="?[0-9]+\.[0-9]' "$_vf" 2>/dev/null || true)"
            if [[ -n "$_v_line" ]]; then
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
_last_age_human=""
_commits_since_tag=0
_is_git="false"
_unpushed=0
_dirty_files="[]"
_recent_commits="[]"

if $TIMEOUT_PREFIX git -C "$_project_path" rev-parse --git-dir >/dev/null 2>&1; then
    _is_git="true"
    _branch="$($TIMEOUT_PREFIX git -C "$_project_path" branch --show-current 2>/dev/null || echo "")"

    if ! $TIMEOUT_PREFIX git -C "$_project_path" diff --quiet 2>/dev/null || \
       ! $TIMEOUT_PREFIX git -C "$_project_path" diff --cached --quiet 2>/dev/null; then
        _dirty="true"
    fi

    _uncommitted="$($TIMEOUT_PREFIX git -C "$_project_path" status --porcelain 2>/dev/null | wc -l)"
    _uncommitted="${_uncommitted##* }"

    _last_hash="$($TIMEOUT_PREFIX git -C "$_project_path" rev-parse --short HEAD 2>/dev/null || echo "")"

    local_epoch="$($TIMEOUT_PREFIX git -C "$_project_path" log -1 --format='%ct' 2>/dev/null || echo "0")"
    now_epoch="$(date +%s)"
    if [[ "$local_epoch" -gt 0 ]]; then
        _last_age_hours=$(( (now_epoch - local_epoch) / 3600 ))
    fi

    _last_age_human="$($TIMEOUT_PREFIX git -C "$_project_path" log -1 --format='%cr' 2>/dev/null || echo "unknown")"

    _tag="$($TIMEOUT_PREFIX git -C "$_project_path" describe --tags --abbrev=0 2>/dev/null || echo "")"
    if [[ -n "$_tag" ]]; then
        _commits_since_tag="$($TIMEOUT_PREFIX git -C "$_project_path" rev-list "${_tag}..HEAD" --count 2>/dev/null || echo "0")"
    else
        _commits_since_tag="$($TIMEOUT_PREFIX git -C "$_project_path" rev-list HEAD --count 2>/dev/null || echo "0")"
    fi

    # Upstream status
    _unpushed="$($TIMEOUT_PREFIX git -C "$_project_path" rev-list --count HEAD...@{u} 2>/dev/null || echo "0")"

    # Full mode: dirty file names, recent commits
    if [[ "$_full_mode" -eq 1 ]]; then
        # Dirty file names (max 5)
        _df_list=""
        while IFS= read -r _df; do
            [[ -z "$_df" ]] && continue
            _df="${_df:3}"  # strip status prefix
            _df_list="${_df_list}\"$(_json_str "$_df")\","
        done < <($TIMEOUT_PREFIX git -C "$_project_path" status --porcelain 2>/dev/null | head -5)
        _df_list="${_df_list%,}"
        _dirty_files="[${_df_list}]"

        # Recent commits (last 5)
        _rc_list=""
        while IFS= read -r _rc; do
            [[ -z "$_rc" ]] && continue
            _hash="${_rc%% *}"
            _msg="${_rc#* }"
            _rc_list="${_rc_list}{\"hash\":\"$(_json_str "$_hash")\",\"message\":\"$(_json_str "$_msg")\"},"
        done < <($TIMEOUT_PREFIX git -C "$_project_path" log --oneline -5 2>/dev/null)
        _rc_list="${_rc_list%,}"
        _recent_commits="[${_rc_list}]"
    fi
fi

# File existence checks
_memory_exists="false"
_memory_age_hours=0
_plan_exists="false"
_audit_exists="false"

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
_plan_total=0
_plan_completed=0
_plan_active=0
_plan_pending=0
if [[ "$_plan_exists" == "true" ]]; then
    _plan_total="$(grep -c -E -i '^(###|## ).*phase|^### Task' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    _plan_completed="$(grep -c -E -i 'COMPLETE|DONE' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    _plan_active="$(grep -c -E -i 'IN.PROGRESS|ACTIVE' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    _plan_pending="$(grep -c -i '^PENDING' "${_project_path}/PLAN.md" 2>/dev/null || true)"
    [[ -z "$_plan_total" ]] && _plan_total=0
    [[ -z "$_plan_completed" ]] && _plan_completed=0
    [[ -z "$_plan_active" ]] && _plan_active=0
    [[ -z "$_plan_pending" ]] && _plan_pending=0
fi

# Work output file count (filenames omitted — no consumers)
_work_output_count=0
if [[ -d "${_project_path}/.rdf/work-output" ]]; then
    _work_output_count="$(command find "${_project_path}/.rdf/work-output" -maxdepth 1 -name '*.md' ! -type d 2>/dev/null | wc -l)"
    _work_output_count="${_work_output_count##* }"
fi

# --- Full mode: extended fields ---

_governance_exists="false"
_governance_files=0
_governance_age_hours=0
_governance_mode="development"
_governance_project=""
_pipeline="idle"
_specs_count=0
_session_last=""
_in_flight="[]"
_insights="[]"

if [[ "$_full_mode" -eq 1 ]]; then

    # Governance index
    _gov_path=""
    if [[ -f "${_project_path}/.rdf/governance/index.md" ]]; then
        _gov_path="${_project_path}/.rdf/governance/index.md"
    elif [[ -f "${_project_path}/.claude/governance/index.md" ]]; then
        _gov_path="${_project_path}/.claude/governance/index.md"
    fi

    if [[ -n "$_gov_path" ]]; then
        _governance_exists="true"
        _gov_dir="$(dirname "$_gov_path")"
        _governance_files="$(command find "$_gov_dir" -maxdepth 1 -type f -name '*.md' | wc -l)"
        _governance_files="${_governance_files##* }"
        _gov_mtime="$(stat -c %Y "$_gov_path" 2>/dev/null || echo "0")"
        if [[ "$_gov_mtime" -gt 0 ]]; then
            _governance_age_hours=$(( ($(date +%s) - _gov_mtime) / 3600 ))
        fi
        _governance_mode="$(grep -m1 -i '^- Mode:' "$_gov_path" 2>/dev/null | sed 's/.*: *//' || echo "development")"
        _governance_project="$(grep -m1 -i '^- Name:' "$_gov_path" 2>/dev/null | sed 's/.*: *//' || echo "$_project_name")"
    fi

    # Specs count
    if [[ -d "${_project_path}/docs/specs" ]]; then
        _specs_count="$(command find "${_project_path}/docs/specs" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l)"
        _specs_count="${_specs_count##* }"
    fi

    # Pipeline position
    if [[ "$_plan_exists" == "true" ]]; then
        if [[ "$_plan_active" -gt 0 ]]; then
            _pipeline="build"
        elif [[ "$_plan_completed" -eq "$_plan_total" ]] && [[ "$_plan_total" -gt 0 ]]; then
            _pipeline="ship"
        else
            _pipeline="plan"
        fi
    elif [[ "$_specs_count" -gt 0 ]]; then
        _pipeline="spec"
    else
        _pipeline="idle"
    fi

    # Last session summary (extract only rendered fields, not raw JSONL)
    _session_file="${_project_path}/.rdf/work-output/session-log.jsonl"
    if [[ -f "$_session_file" ]]; then
        _raw_session="$(tail -1 "$_session_file" 2>/dev/null || echo "")"
        if [[ -n "$_raw_session" ]] && command -v python3 >/dev/null 2>&1; then
            _session_last="$(echo "$_raw_session" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    keep = ('timestamp','head_before','head_after','commits','diff_summary','pipeline','insight')
    out = {k: d[k] for k in keep if k in d}
    print(json.dumps(out, separators=(',',':')))
except: print('')
" 2>/dev/null || echo "$_raw_session")"
        else
            _session_last="$_raw_session"
        fi
    fi

    # In-flight signals
    _if_list=""
    if [[ -f "${_project_path}/HANDOFF.md" ]]; then
        _hf_title="$(head -1 "${_project_path}/HANDOFF.md" 2>/dev/null | sed 's/^# *//' || echo "unknown")"
        _if_list="${_if_list}{\"type\":\"handoff\",\"detail\":\"$(_json_str "$_hf_title")\"},"
    fi
    if [[ -f "${_project_path}/.rdf/work-output/spec-progress.md" ]]; then
        _sp_topic="$(grep -m1 '^TOPIC:' "${_project_path}/.rdf/work-output/spec-progress.md" 2>/dev/null | sed 's/TOPIC: *//' || echo "unknown")"
        _sp_phase="$(grep -m1 '^PHASE:' "${_project_path}/.rdf/work-output/spec-progress.md" 2>/dev/null | sed 's/PHASE: *//' || echo "unknown")"
        _if_list="${_if_list}{\"type\":\"spec\",\"detail\":\"$(_json_str "$_sp_topic — $_sp_phase")\"},"
    fi
    if [[ -f "${_project_path}/.rdf/work-output/ship-progress.md" ]]; then
        _sh_stage="$(grep -m1 '^STAGE:' "${_project_path}/.rdf/work-output/ship-progress.md" 2>/dev/null | sed 's/STAGE: *//' || echo "unknown")"
        _if_list="${_if_list}{\"type\":\"ship\",\"detail\":\"$(_json_str "$_sh_stage")\"},"
    fi
    _if_list="${_if_list%,}"
    _in_flight="[${_if_list}]"

    # Insights (last 5 from global insights file, skipped with --no-insights)
    if [[ "$_skip_insights" -eq 0 ]]; then
        _insights_file="${HOME}/.rdf/insights.jsonl"
        _ins_list=""
        if [[ -f "$_insights_file" ]]; then
            while IFS= read -r _ins_line; do
                [[ -z "$_ins_line" ]] && continue
                _ins_list="${_ins_list}${_ins_line},"
            done < <(tail -5 "$_insights_file" 2>/dev/null)
            _ins_list="${_ins_list%,}"
        fi
        _insights="[${_ins_list}]"
    fi
fi

# Output JSON
cat <<JSONEOF
{
  "project": "$(_json_str "${_governance_project:-$_project_name}")",
  "path": "$(_json_str "$_project_path")",
  "version": "$(_json_str "$_version")",
  "is_git": ${_is_git},
  "branch": "$(_json_str "$_branch")",
  "dirty": ${_dirty},
  "uncommitted_files": ${_uncommitted},
  "dirty_file_names": ${_dirty_files},
  "last_commit_hash": "$(_json_str "$_last_hash")",
  "last_commit_age_hours": ${_last_age_hours},
  "last_commit_age_human": "$(_json_str "$_last_age_human")",
  "commits_since_tag": ${_commits_since_tag},
  "unpushed": ${_unpushed},
  "recent_commits": ${_recent_commits},
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
  "work_output_count": ${_work_output_count},
  "governance_exists": ${_governance_exists},
  "governance_files": ${_governance_files},
  "governance_age_hours": ${_governance_age_hours},
  "governance_mode": "$(_json_str "$_governance_mode")",
  "pipeline": "$(_json_str "$_pipeline")",
  "specs_count": ${_specs_count},
  "session_last": "$(_json_str "$_session_last")",
  "in_flight": ${_in_flight},
  "insights": ${_insights}
}
JSONEOF
