#!/usr/bin/env bash
# state/rdf-overhead.sh — isolate RDF's per-session always-loaded token overhead
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Reports RDF's own always-loaded weight (the delta context-audit.sh does not
# isolate) as pure JSON. Tokens are a bytes/4 ESTIMATE (matches
# state/context-audit.sh) — a stable published figure guarded against drift, not
# an exact tokenizer count. hooks.json is EXCLUDED from every boot figure: it is
# runtime config that never enters model context. Scoped language rules are
# counted DORMANT (loaded only when a matching file is read), never in a boot
# figure. No jq dependency — degrades to plain arithmetic.
#
# Usage: rdf-overhead.sh [output_dir]
#   output_dir  claude-code adapter output to measure
#               (default: $RDF_HOME/adapters/claude-code/output)
set -euo pipefail

if [[ -n "${RDF_HOME:-}" ]]; then
    _rdf_home="$RDF_HOME"
else
    _rdf_home="$(cd "$(command dirname "$0")/.." && pwd)" || exit 1
fi
_out="${1:-${_rdf_home}/adapters/claude-code/output}"
_lite_src="${_rdf_home}/profiles/lite/governance-lite.md"

# session-start-inject.sh hard-caps the injected lessons-index at 400 bytes, so
# the default deploy's always-loaded RDF context is bounded to this regardless of
# how large ~/.rdf/lessons-index.md grows.
_LESSONS_CAP_B=400

_bytes() {
    [[ -f "$1" ]] || { echo 0; return 0; }   # missing file → 0 bytes
    wc -c < "$1" | tr -d ' '
}
_tok() { echo $(( ${1:-0} / 4 )); }

# Default-loaded RDF context: the lessons-index injection only. Measure the live
# index when it is smaller than the cap; otherwise report the cap (a fresh deploy
# with no index yet, or a full index the injector truncates to 400 bytes) — this
# keeps the published DEFAULT figure deterministic and machine-independent.
_live_idx_b="$(_bytes "${HOME:-/nonexistent}/.rdf/lessons-index.md")"
if [[ "${_live_idx_b:-0}" -gt 0 && "$_live_idx_b" -lt "$_LESSONS_CAP_B" ]]; then
    _lessons_idx_b="$_live_idx_b"
else
    _lessons_idx_b="$_LESSONS_CAP_B"
fi

_core_rule_b="$(_bytes "${_out}/rules/core.md")"   # loads only with --rules (opt-in)
_hooks_b="$(_bytes "${_out}/hooks.json")"          # EXCLUDED from boot (runtime config)

# Scoped language rules are dormant (load only on a matching-file read). *.md
# glob excludes the .rdf-hash integrity siblings by construction.
_dormant_b=0
if [[ -d "${_out}/rules" ]]; then
    for _f in "${_out}/rules"/*.md; do
        [[ -f "$_f" ]] || continue
        [[ "$(command basename "$_f")" == "core.md" ]] && continue
        _dormant_b=$(( _dormant_b + $(_bytes "$_f") ))
    done
fi

_default_boot_b=$(( _lessons_idx_b ))                 # lessons-index only (rules opt-in, off)
_rules_boot_b=$(( _lessons_idx_b + _core_rule_b ))    # opt-in --rules figure

# rdf-lite governance lands in Phase 7; until profiles/lite/governance-lite.md
# exists the lite figure is pending (null) rather than a misleading value equal
# to the default (which would understate lite's condensed-governance weight).
if [[ -f "$_lite_src" ]]; then
    _lite_core_b="$(_bytes "$_lite_src")"
    _lite_core_tok="$(_tok "$_lite_core_b")"
    _lite_boot_tok="$(_tok $(( _lessons_idx_b + _lite_core_b )))"
else
    _lite_core_tok="null"
    _lite_boot_tok="null"
fi

_commit="$(git -C "$_rdf_home" rev-parse --short HEAD 2>/dev/null || echo unknown)"  # non-git → unknown

command cat <<JSON
{
  "default_boot_tokens": $(_tok "$_default_boot_b"),
  "rules_boot_tokens": $(_tok "$_rules_boot_b"),
  "lite_boot_tokens": ${_lite_boot_tok},
  "breakdown": {
    "lessons_index": $(_tok "$_lessons_idx_b"),
    "core_governance_rule": $(_tok "$_core_rule_b"),
    "scoped_rules_dormant": $(_tok "$_dormant_b"),
    "lite_core_governance": ${_lite_core_tok}
  },
  "excluded": { "hooks_json_runtime_config": $(_tok "$_hooks_b") },
  "token_estimate": "bytes/4 heuristic (matches context-audit.sh)",
  "measured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "${_commit}"
}
JSON
