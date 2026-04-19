#!/usr/bin/env bash
# state/context-audit.sh — Measure Claude Code context weight
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Usage: context-audit.sh [--baseline FILE] [workspace-path]
# Output: JSON to stdout
# --baseline FILE: compare against a prior snapshot and emit deltas
set -euo pipefail

# timeout wrapper — empty on systems without the binary (CentOS 6 minimal)
if command -v timeout >/dev/null 2>&1; then TIMEOUT_PREFIX="timeout 30"; else TIMEOUT_PREFIX=""; fi

_baseline_file=""
if [[ "${1:-}" == "--baseline" ]]; then
    _baseline_file="${2:-}"
    shift 2
fi

_workspace="${1:-/root/admin/work/proj}"
_claude_home="${HOME}/.claude"
_rdf_home="${HOME}/.rdf"
_project_slug="$(echo "$_workspace" | sed 's|/|-|g; s|^-||')"
_project_memory="${_claude_home}/projects/-${_project_slug}/memory"
_project_settings="${_claude_home}/projects/-${_project_slug}"

# Helper: file size in bytes (0 if missing)
_fsize() { stat -c %s "$1" 2>/dev/null || echo 0; }

# Helper: line count (0 if missing)
_flines() { wc -l < "$1" 2>/dev/null || echo 0; }

# Helper: escape string for JSON
_json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    echo -n "$s"
}

# Helper: count *.md files in a directory (maxdepth 1, no symlinked dirs)
# _count_md_files dir — prints integer count, 0 if dir missing or empty
_count_md_files() {
    local dir="$1"
    local n
    n="$(command find "$dir" -maxdepth 1 -name "*.md" ! -type d 2>/dev/null | wc -l)"
    echo "${n##* }"
}

# --- Section 1: CLAUDE.md files (always-loaded) ---

_global_claude="${_claude_home}/CLAUDE.md"
_global_claude_bytes=$(_fsize "$_global_claude")
_global_claude_lines=$(_flines "$_global_claude")

_workspace_claude="${_workspace}/CLAUDE.md"
_workspace_claude_bytes=$(_fsize "$_workspace_claude")
_workspace_claude_lines=$(_flines "$_workspace_claude")

# Per-project CLAUDE.md files (loaded when entering a project)
_subproject_claude_total_bytes=0
_subproject_claude_total_lines=0
_subproject_claude_count=0
_subproject_claude_list=""
while IFS= read -r _cf; do
    [[ -z "$_cf" ]] && continue
    [[ "$_cf" == "$_workspace_claude" ]] && continue
    _cb=$(_fsize "$_cf")
    _cl=$(_flines "$_cf")
    _subproject_claude_total_bytes=$((_subproject_claude_total_bytes + _cb))
    _subproject_claude_total_lines=$((_subproject_claude_total_lines + _cl))
    _subproject_claude_count=$((_subproject_claude_count + 1))
    _rel="${_cf#$_workspace/}"
    _subproject_claude_list="${_subproject_claude_list}{\"path\":\"$(_json_str "$_rel")\",\"bytes\":${_cb},\"lines\":${_cl}},"
done < <(command find "$_workspace" -maxdepth 3 -name "CLAUDE.md" ! -type d 2>/dev/null | sort)
_subproject_claude_list="${_subproject_claude_list%,}"

# --- Section 2: Memory system ---

_memory_index="${_project_memory}/MEMORY.md"
_memory_index_bytes=$(_fsize "$_memory_index")
_memory_index_lines=$(_flines "$_memory_index")

_memory_satellite_bytes=0
_memory_satellite_lines=0
_memory_satellite_count=0
_memory_archive_bytes=0
_memory_archive_lines=0
_memory_archive_count=0
_memory_satellite_list=""
if [[ -d "$_project_memory" ]]; then
    _memory_satellite_count="$(_count_md_files "$_project_memory")"
    # MEMORY.md itself is in the directory; subtract it from satellite count
    [[ -f "$_memory_index" ]] && _memory_satellite_count=$((_memory_satellite_count - 1))
    while IFS= read -r _mf; do
        [[ -z "$_mf" ]] && continue
        [[ "$_mf" == "$_memory_index" ]] && continue
        _mb=$(_fsize "$_mf")
        _ml=$(_flines "$_mf")
        _mname="$(basename "$_mf")"
        if [[ "$_mname" == archive-* ]]; then
            _memory_archive_bytes=$((_memory_archive_bytes + _mb))
            _memory_archive_lines=$((_memory_archive_lines + _ml))
            _memory_archive_count=$((_memory_archive_count + 1))
        fi
        _memory_satellite_bytes=$((_memory_satellite_bytes + _mb))
        _memory_satellite_lines=$((_memory_satellite_lines + _ml))
        _memory_satellite_list="${_memory_satellite_list}{\"name\":\"$(_json_str "$_mname")\",\"bytes\":${_mb},\"lines\":${_ml}},"
    done < <(command find "$_project_memory" -maxdepth 1 -name "*.md" ! -type d 2>/dev/null | sort)
fi
_memory_satellite_list="${_memory_satellite_list%,}"
_memory_total_bytes=$((_memory_index_bytes + _memory_satellite_bytes))
_memory_total_lines=$((_memory_index_lines + _memory_satellite_lines))

# --- Section 3: Settings files ---

_global_settings="${_claude_home}/settings.json"
_global_settings_bytes=$(_fsize "$_global_settings")
_global_settings_lines=$(_flines "$_global_settings")
_global_settings_allow_count=0
_global_settings_hook_count=0
if [[ -f "$_global_settings" ]]; then
    _global_settings_allow_count=$(grep -c '"Bash' "$_global_settings" 2>/dev/null || true)
    _global_settings_hook_count=$(grep -c '"command"' "$_global_settings" 2>/dev/null || true)
fi

_local_settings="${_project_settings}/settings.json"
if [[ ! -f "$_local_settings" ]]; then
    _local_settings="${_project_settings}/settings.local.json"
fi
_local_settings_bytes=$(_fsize "$_local_settings")
_local_settings_lines=$(_flines "$_local_settings")

_local_settings2="${_workspace}/.claude/settings.local.json"
_local_settings2_bytes=$(_fsize "$_local_settings2")
_local_settings2_lines=$(_flines "$_local_settings2")

_settings_total_bytes=$((_global_settings_bytes + _local_settings_bytes + _local_settings2_bytes))

# --- Section 4: Skills inventory ---

_global_commands="${_claude_home}/commands/"
_project_commands="${_project_settings}/commands/"
_canonical_commands="${_workspace}/rdf/canonical/commands/"

_skill_global_count=0
_skill_global_bytes=0
_skill_project_count=0
_skill_project_bytes=0
_skill_canonical_count=0
_skill_canonical_bytes=0

if [[ -d "$_global_commands" ]]; then
    _skill_global_count="$(_count_md_files "$_global_commands")"
    while IFS= read -r _sf; do
        [[ -z "$_sf" ]] && continue
        _skill_global_bytes=$((_skill_global_bytes + $(_fsize "$_sf")))
    done < <(command find "$_global_commands" -maxdepth 1 -name "*.md" ! -type d 2>/dev/null)
fi

if [[ -d "$_project_commands" ]]; then
    _skill_project_count="$(_count_md_files "$_project_commands")"
    while IFS= read -r _sf; do
        [[ -z "$_sf" ]] && continue
        _skill_project_bytes=$((_skill_project_bytes + $(_fsize "$_sf")))
    done < <(command find "$_project_commands" -maxdepth 1 -name "*.md" ! -type d 2>/dev/null)
fi

if [[ -d "$_canonical_commands" ]]; then
    _skill_canonical_count="$(_count_md_files "$_canonical_commands")"
    while IFS= read -r _sf; do
        [[ -z "$_sf" ]] && continue
        _skill_canonical_bytes=$((_skill_canonical_bytes + $(_fsize "$_sf")))
    done < <(command find "$_canonical_commands" -maxdepth 1 -name "*.md" ! -type d 2>/dev/null)
fi

_skill_deployed_count=$((_skill_global_count + _skill_project_count))
_skill_deployed_bytes=$((_skill_global_bytes + _skill_project_bytes))

# Skill listing overhead (names + descriptions in system prompt)
# ~65 bytes per skill name+description line
_skill_listing_est_bytes=$((_skill_deployed_count * 65))

# --- Section 5: Agent definitions ---

_agents_dir="${_claude_home}/agents"
_agents_count=0
_agents_bytes=0
_agents_canonical_count=0
_canonical_agents="${_workspace}/rdf/canonical/agents/"
if [[ -d "$_agents_dir" ]]; then
    _agents_count="$(_count_md_files "$_agents_dir")"
    while IFS= read -r _af; do
        [[ -z "$_af" ]] && continue
        _agents_bytes=$((_agents_bytes + $(_fsize "$_af")))
    done < <(command find "$_agents_dir" -maxdepth 1 -name "*.md" ! -type d 2>/dev/null)
fi
_agents_canonical_count="$(_count_md_files "$_canonical_agents")"

# --- Section 6: Lessons learned ---

_lessons="${_rdf_home}/lessons-learned.md"
_lessons_bytes=$(_fsize "$_lessons")
_lessons_lines=$(_flines "$_lessons")
_rdf_md_count="$(_count_md_files "$_rdf_home")"

# --- Section 7: rdf-state.sh output analysis ---

_rdf_state="${_workspace}/rdf/state/rdf-state.sh"
_state_total_bytes=0
_state_repos_measured=0
_state_work_output_bytes=0
_state_insights_bytes=0
_state_session_bytes=0
if [[ -x "$_rdf_state" ]] || [[ -f "$_rdf_state" ]]; then
    # Measure top 5 repos by recency
    _repo_sizes=""
    while IFS= read -r _rd; do
        [[ -z "$_rd" ]] && continue
        _rdir="${_rd%/.git}"
        _rname="$(basename "$_rdir")"
        _sout="$(bash "$_rdf_state" --full "$_rdir" 2>/dev/null || echo "{}")"
        _sbytes="${#_sout}"
        _state_total_bytes=$((_state_total_bytes + _sbytes))
        _state_repos_measured=$((_state_repos_measured + 1))

        # Field breakdown via python3 (if available)
        if command -v python3 >/dev/null 2>&1; then
            _field_sizes="$($TIMEOUT_PREFIX python3 -c "
import sys, json
try:
    d = json.loads('''$_sout''')
    wo = len(json.dumps(d.get('work_output_files', [])))
    ins = len(json.dumps(d.get('insights', [])))
    sl = len(json.dumps(d.get('session_last', '')))
    print(f'{wo} {ins} {sl}')
except: print('0 0 0')
" 2>/dev/null || echo "0 0 0")"
            read -r _wo _in _sl <<< "$_field_sizes"
            _state_work_output_bytes=$((_state_work_output_bytes + _wo))
            _state_insights_bytes=$((_state_insights_bytes + _in))
            _state_session_bytes=$((_state_session_bytes + _sl))
        fi

        _repo_sizes="${_repo_sizes}{\"repo\":\"$(_json_str "$_rname")\",\"bytes\":${_sbytes}},"
        [[ "$_state_repos_measured" -ge 5 ]] && break
    done < <(command find "$_workspace" -maxdepth 2 -name ".git" -type d 2>/dev/null | while read -r g; do
        _gd="${g%/.git}"
        _gt="$($TIMEOUT_PREFIX git -C "$_gd" log -1 --format=%ct 2>/dev/null || echo 0)"
        echo "$_gt $g"
    done | sort -rn | awk '{print $2}')
    _repo_sizes="${_repo_sizes%,}"
fi

# Count all repos for extrapolation
_total_repos="$(command find "$_workspace" -maxdepth 2 -name ".git" -type d 2>/dev/null | wc -l)"
_total_repos="${_total_repos##* }"

# Work-output file counts per project
_wo_total_files=0
_wo_heaviest_repo=""
_wo_heaviest_count=0
while IFS= read -r _wod; do
    [[ -z "$_wod" ]] && continue
    _woc="$(_count_md_files "$_wod")"
    _wo_total_files=$((_wo_total_files + _woc))
    _worepo="$(basename "$(dirname "$(dirname "$_wod")")")"
    if [[ "$_woc" -gt "$_wo_heaviest_count" ]]; then
        _wo_heaviest_count="$_woc"
        _wo_heaviest_repo="$_worepo"
    fi
done < <(command find "$_workspace" -maxdepth 3 -type d -name "work-output" 2>/dev/null)

# --- Section 8: Session history ---

_session_db="${_claude_home}/sessions.db"
_session_db_bytes=$(_fsize "$_session_db")
_jsonl_total_bytes=0
_jsonl_count=0
if [[ -d "${_claude_home}/projects" ]]; then
    # Use find -printf for byte sum: avoids per-file stat calls over thousands of JSONL files
    _jsonl_count="$(command find "${_claude_home}/projects" -name "*.jsonl" ! -type d 2>/dev/null | wc -l)"
    _jsonl_count="${_jsonl_count##* }"
    _jsonl_total_bytes="$(command find "${_claude_home}/projects" -name "*.jsonl" ! -type d -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')"
fi

_history_file="${_claude_home}/history.jsonl"
_history_bytes=$(_fsize "$_history_file")
_history_lines=$(_flines "$_history_file")

# --- Section 9: Totals and scoring ---

# Always-loaded context (every session start)
_always_loaded_bytes=$((_global_claude_bytes + _workspace_claude_bytes + _memory_total_bytes + _settings_total_bytes + _skill_listing_est_bytes))
_always_loaded_tokens=$((_always_loaded_bytes / 4))

# /r-start additional cost (workspace mode, 5 repos)
_rstart_cost_bytes=$((_state_total_bytes + 6400))  # state output + skill prompt ~6400 bytes
_rstart_cost_tokens=$((_rstart_cost_bytes / 4))

# Boot total (session + /r-start)
_boot_total_tokens=$((_always_loaded_tokens + _rstart_cost_tokens))

# Score: 100 base, deductions for bloat
_score=100

# Memory satellite penalty
[[ "$_memory_satellite_count" -gt 15 ]] && _score=$((_score - 10))
[[ "$_memory_archive_bytes" -gt 10000 ]] && _score=$((_score - 10))
[[ "$_memory_index_lines" -ge 180 ]] && _score=$((_score - 5))
[[ "$_memory_index_lines" -ge 200 ]] && _score=$((_score - 10))

# CLAUDE.md size penalty
[[ "$_workspace_claude_lines" -gt 200 ]] && _score=$((_score - 10))
[[ "$_workspace_claude_lines" -gt 400 ]] && _score=$((_score - 10))

# State output waste
[[ "$_state_work_output_bytes" -gt 5000 ]] && _score=$((_score - 10))
[[ "$_state_insights_bytes" -gt 5000 ]] && _score=$((_score - 5))

# Boot tokens penalty
[[ "$_boot_total_tokens" -gt 40000 ]] && _score=$((_score - 10))
[[ "$_boot_total_tokens" -gt 60000 ]] && _score=$((_score - 10))

# Floor at 0
[[ "$_score" -lt 0 ]] && _score=0

# Grade
_grade="CLEAN"
[[ "$_score" -lt 90 ]] && _grade="NEEDS_WORK"
[[ "$_score" -lt 70 ]] && _grade="BLOATED"
[[ "$_score" -lt 50 ]] && _grade="CRITICAL"

# --- Baseline comparison ---
_delta_json=""
if [[ -n "$_baseline_file" ]] && [[ -f "$_baseline_file" ]] && command -v python3 >/dev/null 2>&1; then
    _delta_json="$($TIMEOUT_PREFIX python3 -c "
import json, sys
try:
    with open('$_baseline_file') as f:
        base = json.load(f)
    cur = {
        'always_loaded_tokens': $_always_loaded_tokens,
        'boot_total_tokens': $_boot_total_tokens,
        'memory_satellite_count': $_memory_satellite_count,
        'memory_total_bytes': $_memory_total_bytes,
        'workspace_claude_lines': $_workspace_claude_lines,
        'state_output_bytes': $_state_total_bytes,
        'score': $_score
    }
    delta = {}
    for k in cur:
        bv = base.get('totals', {}).get(k, base.get(k, 0))
        if bv and cur[k] != bv:
            delta[k] = {'was': bv, 'now': cur[k], 'change': cur[k] - bv}
    json.dump(delta, sys.stdout)
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo "{}")"
fi

# --- Output JSON ---
cat <<JSONEOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace": "$(_json_str "$_workspace")",
  "claude_md": {
    "global": {"bytes": ${_global_claude_bytes}, "lines": ${_global_claude_lines}},
    "workspace": {"bytes": ${_workspace_claude_bytes}, "lines": ${_workspace_claude_lines}},
    "subprojects": {"count": ${_subproject_claude_count}, "bytes": ${_subproject_claude_total_bytes}, "lines": ${_subproject_claude_total_lines}, "files": [${_subproject_claude_list}]}
  },
  "memory": {
    "index": {"bytes": ${_memory_index_bytes}, "lines": ${_memory_index_lines}},
    "satellites": {"count": ${_memory_satellite_count}, "bytes": ${_memory_satellite_bytes}, "lines": ${_memory_satellite_lines}},
    "archives": {"count": ${_memory_archive_count}, "bytes": ${_memory_archive_bytes}, "lines": ${_memory_archive_lines}},
    "total": {"bytes": ${_memory_total_bytes}, "lines": ${_memory_total_lines}},
    "files": [${_memory_satellite_list}]
  },
  "settings": {
    "global": {"bytes": ${_global_settings_bytes}, "lines": ${_global_settings_lines}, "allow_rules": ${_global_settings_allow_count}, "hooks": ${_global_settings_hook_count}},
    "local": {"bytes": ${_local_settings_bytes}, "lines": ${_local_settings_lines}},
    "local2": {"bytes": ${_local_settings2_bytes}, "lines": ${_local_settings2_lines}},
    "total_bytes": ${_settings_total_bytes}
  },
  "skills": {
    "deployed": {"count": ${_skill_deployed_count}, "bytes": ${_skill_deployed_bytes}},
    "global": {"count": ${_skill_global_count}, "bytes": ${_skill_global_bytes}},
    "project": {"count": ${_skill_project_count}, "bytes": ${_skill_project_bytes}},
    "canonical": {"count": ${_skill_canonical_count}, "bytes": ${_skill_canonical_bytes}},
    "listing_overhead_est": ${_skill_listing_est_bytes}
  },
  "agents": {
    "count": ${_agents_count},
    "bytes": ${_agents_bytes},
    "canonical_count": ${_agents_canonical_count}
  },
  "lessons": {
    "bytes": ${_lessons_bytes},
    "lines": ${_lessons_lines},
    "rdf_md_files": ${_rdf_md_count}
  },
  "state_output": {
    "repos_measured": ${_state_repos_measured},
    "total_repos": ${_total_repos},
    "measured_bytes": ${_state_total_bytes},
    "field_breakdown": {
      "work_output_files": ${_state_work_output_bytes},
      "insights": ${_state_insights_bytes},
      "session_last": ${_state_session_bytes}
    },
    "work_output_files_total": ${_wo_total_files},
    "work_output_heaviest": {"repo": "$(_json_str "$_wo_heaviest_repo")", "count": ${_wo_heaviest_count}},
    "repos": [${_repo_sizes}]
  },
  "session_history": {
    "db_bytes": ${_session_db_bytes},
    "jsonl_files": ${_jsonl_count},
    "jsonl_total_bytes": ${_jsonl_total_bytes},
    "history_entries": ${_history_lines},
    "history_bytes": ${_history_bytes}
  },
  "totals": {
    "always_loaded_bytes": ${_always_loaded_bytes},
    "always_loaded_tokens": ${_always_loaded_tokens},
    "rstart_additional_tokens": ${_rstart_cost_tokens},
    "boot_total_tokens": ${_boot_total_tokens},
    "memory_satellite_count": ${_memory_satellite_count},
    "memory_total_bytes": ${_memory_total_bytes},
    "workspace_claude_lines": ${_workspace_claude_lines},
    "state_output_bytes": ${_state_total_bytes},
    "context_200k_percent": $(( (_boot_total_tokens * 100) / 200000 )),
    "score": ${_score},
    "grade": "$_grade"
  }$(if [[ -n "$_delta_json" ]] && [[ "$_delta_json" != "{}" ]]; then echo ",
  \"delta\": $_delta_json"; fi)
}
JSONEOF
