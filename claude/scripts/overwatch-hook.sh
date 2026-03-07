#!/bin/bash
# overwatch-hook.sh — Capture subagent stop events to spool JSONL
# Added by Overwatch for real-time agent output visibility.
# Input: JSON on stdin with subagent details.
# Always exits 0 — async, non-blocking.
set -uo pipefail

SPOOL_DIR="${OVERWATCH_PROJ_ROOT:-/root/admin/work/proj}/work-output/spool"
mkdir -p "$SPOOL_DIR"

# Read subagent event from stdin
input=$(cat)

# Validate JSON input — exit silently on malformed data
if ! echo "$input" | jq empty 2>/dev/null; then
  exit 0
fi

# Extract fields from the actual SubagentStop payload
agent_id=$(echo "$input" | jq -r '.agent_id // "unknown"' 2>/dev/null)
agent_type=$(echo "$input" | jq -r '.agent_type // "unknown"' 2>/dev/null)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null)
last_msg=$(echo "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null | head -c 4000)
transcript=$(echo "$input" | jq -r '.agent_transcript_path // ""' 2>/dev/null)

# Skip conversation compaction agents (not real work agents)
if [[ "$agent_id" == acompact-* ]]; then
  exit 0
fi

# Derive project — multi-tier detection (don't trust cwd alone)
project=""
# Combine last_msg + transcript first-line for scanning
scan_text="$last_msg"
if [[ -n "$transcript" && -f "$transcript" ]]; then
  work_order=$(head -1 "$transcript" 2>/dev/null | jq -r '.message.content // ""' 2>/dev/null || true)
  scan_text="${scan_text} ${work_order}"
fi

# 1. PROJECT: marker in work order or message
explicit_proj=$(echo "$scan_text" | grep -oP 'PROJECT:\s*\K\S+' | head -1 || true)
if [[ -n "$explicit_proj" ]]; then
  project="$explicit_proj"
fi

# 2. Project path references (require trailing / to avoid matching file paths)
if [[ -z "$project" ]]; then
  path_proj=$(echo "$scan_text" | grep -oP '/root/admin/work/proj/\K[a-zA-Z0-9_-]+(?=/)' | head -1 || true)
  if [[ -n "$path_proj" ]]; then
    project="$path_proj"
  fi
fi

# 3. Known project name aliases
if [[ -z "$project" ]]; then
  if echo "$scan_text" | grep -qiE '\bBFD\b|brute.force.detection'; then
    project="bfd"
  elif echo "$scan_text" | grep -qiE '\bAPF\b|advanced.policy.firewall'; then
    project="apf"
  elif echo "$scan_text" | grep -qiE '\bpkg_lib\b'; then
    project="pkg_lib"
  elif echo "$scan_text" | grep -qiE '\belog_lib\b'; then
    project="elog_lib"
  elif echo "$scan_text" | grep -qiE '\balert_lib\b'; then
    project="alert_lib"
  elif echo "$scan_text" | grep -qiE '\btlog_lib\b'; then
    project="tlog_lib"
  elif echo "$scan_text" | grep -qiE '\boverwatch\b'; then
    project="overwatch"
  elif echo "$scan_text" | grep -qiE '\bbatsman\b'; then
    project="batsman"
  elif echo "$scan_text" | grep -qiE '\bLMD\b|linux.malware.detect|maldet'; then
    project="lmd"
  fi
fi

# 4. Fallback to cwd basename
if [[ -z "$project" && -n "$cwd" ]]; then
  project=$(basename "$cwd" 2>/dev/null || true)
fi

# Normalize directory names to short aliases
case "$project" in
  brute-force-detection) project="bfd" ;;
  advanced-policy-firewall) project="apf" ;;
  linux-malware-detect) project="lmd" ;;
esac

# Detect agent role from agent_type
agent_role=""
case "$agent_type" in
  rfxn-se|general-purpose) agent_role="SE" ;;
  rfxn-qa) agent_role="QA" ;;
  rfxn-planner|Plan) agent_role="Planner" ;;
  rfxn-uat) agent_role="UAT" ;;
  Explore) agent_role="Explorer" ;;
  *) agent_role="$agent_type" ;;
esac

# Generate spool filename from agent_id (sanitized)
spool_id=$(echo "$agent_id" | tr -cd 'a-zA-Z0-9_-')
if [[ -z "$spool_id" ]]; then
  spool_id="unknown-$(date +%s)"
fi

timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Append JSONL event
jq -nc \
  --arg ts "$timestamp" \
  --arg event "subagent_stop" \
  --arg agent_id "$agent_id" \
  --arg agent_type "$agent_type" \
  --arg agent_role "$agent_role" \
  --arg session_id "$session_id" \
  --arg project "$project" \
  --arg cwd "$cwd" \
  --arg preview "$last_msg" \
  --arg transcript "$transcript" \
  '{ts: $ts, event: $event, agent_id: $agent_id, agent_type: $agent_type, agent_role: $agent_role, session_id: $session_id, project: $project, cwd: $cwd, last_message_preview: $preview, transcript_path: $transcript}' \
  >> "${SPOOL_DIR}/${spool_id}.jsonl" 2>/dev/null  # best-effort: hook is non-blocking; server continues without spool entry

exit 0
