#!/usr/bin/env bash
# comment-metrics.sh — per-file comment cruft metrics for shell source
# Usage: comment-metrics.sh FILE [FILE...]
# Output: TSV with columns:
#   file total cmt_only cmt_pct banner tombstone hdr_ge4 hdr_max cat_block max_inline
#
# Definitions:
#   total       total line count
#   cmt_only    lines that are only a comment (no code)
#   cmt_pct     cmt_only / total as percent
#   banner      lines matching ^\s*#\s?[-=#_]{5,}\s*$ (separator-only comments)
#   tombstone   cmt_only lines matching "# (removed|was:|deprecated:|tombstone)"
#   hdr_ge4     count of consecutive cmt_only runs of length >= 4
#   hdr_max     longest consecutive cmt_only run
#   cat_block   longest cmt_only run starting within the first 120 lines
#               (heuristic for file-header prose catalogues)
#   max_inline  longest inline comment after code (character count)
#
# Deterministic: depends only on file contents; no timestamps, no locale.
set -u

if [[ $# -eq 0 ]]; then
    printf 'usage: %s FILE [FILE...]\n' "${0##*/}" >&2
    exit 2
fi

printf 'file\ttotal\tcmt_only\tcmt_pct\tbanner\ttombstone\thdr_ge4\thdr_max\tcat_block\tmax_inline\n'
for f in "$@"; do
    if [[ ! -r "$f" ]]; then
        printf '%s\tERROR\n' "$f" >&2
        continue
    fi
    awk -v fn="$f" '
    BEGIN {
        total=0; cmt_only=0; banner=0; tombstone=0
        in_hdr=0; hdr_lines=0; hdr_ge4=0; hdr_max=0
        max_inline=0; cat_total=0
    }
    {
        total++
        if ($0 ~ /^[[:space:]]*#/) {
            cmt_only++
            if ($0 ~ /^[[:space:]]*#[[:space:]]?[-=#_]{5,}[[:space:]]*$/) banner++
            if ($0 ~ /#[[:space:]]*(removed|was:|deprecated:|tombstone)/) tombstone++
            if (in_hdr==0) { in_hdr=1; hdr_lines=1 } else { hdr_lines++ }
            if (NR<=120 && hdr_lines>cat_total) cat_total=hdr_lines
            next
        }
        if (in_hdr) {
            if (hdr_lines>=4) hdr_ge4++
            if (hdr_lines>hdr_max) hdr_max=hdr_lines
        }
        in_hdr=0; hdr_lines=0
        idx=index($0,"#")
        if (idx>1) {
            tail=substr($0,idx)
            if (length(tail)>max_inline) max_inline=length(tail)
        }
    }
    END {
        if (in_hdr) {
            if (hdr_lines>=4) hdr_ge4++
            if (hdr_lines>hdr_max) hdr_max=hdr_lines
        }
        pct = (total>0) ? (cmt_only*100/total) : 0
        printf "%s\t%d\t%d\t%.1f\t%d\t%d\t%d\t%d\t%d\t%d\n", \
            fn, total, cmt_only, pct, banner, tombstone, hdr_ge4, hdr_max, cat_total, max_inline
    }' "$f"
done
