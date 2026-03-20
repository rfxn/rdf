#!/bin/bash
# SubagentStop hook: log subagent completion to agent-feed.log.
# Appends timestamped entry for retrospective status tracking and
# crash recovery visibility.
# Input: JSON on stdin with subagent details.
# Always exits 0.

set -uo pipefail

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
last_msg=$(echo "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null | head -c 200)

# Derive project from cwd
project=""
if [[ -n "$cwd" ]]; then
    project=$(basename "$cwd" 2>/dev/null || true)
fi

# Determine the feed log location.
# Try project-level .rdf/work-output/ first, fall back to parent-level.
feed_dir=""
if [[ -d "./.rdf/work-output" ]]; then
    feed_dir="./.rdf/work-output"
elif [[ -d "/root/admin/work/proj/.rdf/work-output" ]]; then
    feed_dir="/root/admin/work/proj/.rdf/work-output"
else
    # Create parent-level .rdf/work-output if nothing exists
    feed_dir="/root/admin/work/proj/.rdf/work-output"
    mkdir -p "$feed_dir"
fi

feed_log="${feed_dir}/agent-feed.log"
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Build log entry
entry="${timestamp} | AGENT_STOP | type=${agent_type} | project=${project} | id=${agent_id} | session=${session_id}"
if [[ -n "${last_msg:-}" ]]; then
    # Sanitize: collapse newlines to spaces for single-line log
    clean_msg=$(echo "$last_msg" | tr '\n' ' ' | sed 's/  */ /g')
    entry="${entry} | preview=${clean_msg}"
fi

# Append to feed log
echo "$entry" >> "$feed_log"

exit 0
