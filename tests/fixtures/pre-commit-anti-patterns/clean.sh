#!/usr/bin/env bash
# Fixture: all anti-pattern classes clean — should not trigger any block
set -euo pipefail

_sum="$(command sha256sum /etc/hostname)"   # command prefix present
_tmpfile="$(mktemp)"                         # no $$/$RANDOM in /tmp path
_check="$(command cat "$_tmpfile")" || true  # same-line justification comment
# command rm is used below — no tombstone phrases in this file
command rm -f "$_tmpfile"                    # command prefix; no local var=$(
