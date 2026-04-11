#!/usr/bin/env bash
# comment-snapshot.sh — run comment-metrics.sh against the shared library set
# Usage: comment-snapshot.sh [OUTPUT_TSV]
#   Default output: stdout
# Exits non-zero if any target file is missing.
set -u

WORKSPACE="${WORKSPACE:-/root/admin/work/proj}"
METRICS="$(command dirname "$0")/comment-metrics.sh"

if [[ ! -x "$METRICS" ]]; then
    printf 'comment-snapshot: metrics script not found or not executable: %s\n' "$METRICS" >&2
    exit 2
fi

TARGETS=(
    "$WORKSPACE/pkg_lib/files/pkg_lib.sh"
    "$WORKSPACE/alert_lib/files/alert_lib.sh"
    "$WORKSPACE/geoip_lib/files/geoip_lib.sh"
    "$WORKSPACE/elog_lib/files/elog_lib.sh"
    "$WORKSPACE/tlog_lib/files/tlog_lib.sh"
    "$WORKSPACE/tlog_lib/files/tlog"
)

for t in "${TARGETS[@]}"; do
    if [[ ! -r "$t" ]]; then
        printf 'comment-snapshot: missing target: %s\n' "$t" >&2
        exit 3
    fi
done

if [[ $# -ge 1 ]]; then
    "$METRICS" "${TARGETS[@]}" > "$1"
    printf 'wrote %s\n' "$1" >&2
else
    "$METRICS" "${TARGETS[@]}"
fi
