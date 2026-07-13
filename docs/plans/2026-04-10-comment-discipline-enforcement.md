# Implementation Plan: Comment Discipline Enforcement Across Shared Libraries

**Goal:** Apply the new comment-discipline rule (parent `CLAUDE.md § Code Comments`, RDF core profile § Code Comments, `reference/comment-discipline.md`) to all 5 shared `*_lib` projects with before/after metrics captured via a reproducible pipeline, then vendor-resync into the 3 consumer projects (APF, BFD, LMD).

**Architecture:** Comment-only cleanup, zero functional change. New `rdf/canonical/scripts/comment-metrics.sh` measures cruft across shell files; per-library cleanup phases execute the cleanup and bump patch versions; consumer phase resyncs canonical files into `internals/` directories. Libraries are processed in parallel (independent files/projects); consumer resync is one parallel-agent phase with one track per consumer.

**Tech Stack:** Bash (4.1+ floor, CentOS 6), BATS for tests, existing `/r-util-lib-sync` and `/r-util-lib-release` RDF commands.

**Spec:** `rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md`

**Phases:** 9

**Scope note (2026-04-10):** Consumer-project (APF/BFD/LMD) vendor resync is **deferred** to a separate follow-up plan per user direction. This plan covers the 5 shared libraries end-to-end including upstream git-tag and push, and stops at the library level. Final Phase 9 is the upstream publication step, not consumer sync.

---

## Conventions

**Commit message format per library (APF/BFD-style versioned libs):**
- `pkg_lib`: `v1.0.10 | [Change] comment discipline: ...`
- `alert_lib`: `1.0.7 | [Change] comment discipline: ...`
- `elog_lib`: `1.0.6 | [Change] comment discipline: ...`
- `tlog_lib`: `2.0.6 | [Change] comment discipline: ...`
- `geoip_lib`: `geoip_lib 1.0.7 | [Change] comment discipline: ...`

**Commit message format for RDF phases (Phase 1, 2, 8):** free-form descriptive, no version prefix, tag body lines `[New]` `[Change]` `[Fix]`.

**Consumer commit format (Phase 9 — APF/BFD/LMD):**
- APF: `2.0.2 | [Change] vendor: <libs> comment cleanup resync`
- BFD: `2.0.2 | [Change] vendor: <libs> comment cleanup resync`
- LMD: `[Change] vendor: <libs> comment cleanup resync`

**Staging:** explicit `git add <file>` — never `git add -A` or `git add .`.

**Cleanup processing order:** **bottom-up** within each file (highest line number first) to prevent line-range shift from invalidating later deletions. When a function header restatement block is removed, verify the immediately-following function signature still matches the intended target before proceeding.

**Load-bearing preservation whitelist:** before any cleanup edit, the engineer runs a whitelist grep against the current file:
```bash
grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' <file>
```
These lines are load-bearing per `rdf/profiles/core/reference/comment-discipline.md` and MUST survive the cleanup. The post-cleanup re-grep must return a strict superset (same lines present; new additions OK, none missing).

**CRITICAL:**
- Never commit a cleanup that fails any of `bash -n`, `shellcheck`, or the test matrix
- Each library phase is self-contained — version bump + source edit + CHANGELOG update + test run + commit, all in one atomic unit
- When an edit spans hundreds of lines across dozens of blocks, use the Edit tool per-block rather than Write — preserves diff auditability

---

## File Map

### New Files
| File | Lines | Purpose | Test File |
|---|---|---|---|
| `rdf/canonical/scripts/comment-metrics.sh` | ~60 | Per-file comment cruft metrics as TSV | N/A (utility script, tested by execution in Phase 2) |
| `rdf/canonical/scripts/comment-snapshot.sh` | ~40 | Runs metrics against a list of library paths, writes timestamped TSV | N/A (wrapper) |
| `rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md` | (already written) | Spec and triage | N/A (docs) |
| `rdf/docs/specs/support/2026-04-10-comment-baseline.tsv` | 7 | Before-state snapshot TSV | N/A (data) |
| `rdf/docs/specs/support/2026-04-10-comment-after.tsv` | 7 | After-state snapshot TSV | N/A (data) |
| `rdf/docs/specs/support/2026-04-10-comment-delta.md` | ~50 | Before/after delta report | N/A (docs) |

### Modified Files
| File | Changes | Test File |
|---|---|---|
| `rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md` | This file | N/A (plan) |
| `pkg_lib/files/pkg_lib.sh` | Remove 69 multi-line headers + inline restatements; preserve load-bearing | `pkg_lib/tests/*.bats` (14 files, unchanged) |
| `pkg_lib/files/VERSION` | 1.0.9 → 1.0.10 | N/A |
| `pkg_lib/CHANGELOG` | Prepend v1.0.10 entry | N/A |
| `pkg_lib/CHANGELOG.RELEASE` | Prepend v1.0.10 entry | N/A |
| `alert_lib/files/alert_lib.sh` | Remove 28 headers + 32 banners; preserve load-bearing | `alert_lib/tests/*.bats` (8 files, unchanged) |
| `alert_lib/files/VERSION` | 1.0.6 → 1.0.7 | N/A |
| `alert_lib/CHANGELOG`, `alert_lib/CHANGELOG.RELEASE` | Prepend v1.0.7 entry | N/A |
| `geoip_lib/files/geoip_lib.sh` | Remove 26 headers + 56 banners + signature restatements; preserve load-bearing | `geoip_lib/tests/*.bats` (4 files, unchanged) |
| `geoip_lib/files/VERSION` | 1.0.6 → 1.0.7 | N/A |
| `geoip_lib/CHANGELOG`, `geoip_lib/CHANGELOG.RELEASE` | Prepend v1.0.7 entry | N/A |
| `elog_lib/files/elog_lib.sh` | Collapse 44-line config catalogue at lines 34-77; remove 9 headers + 26 banners; preserve load-bearing | `elog_lib/tests/*.bats` (11 files, unchanged) |
| `elog_lib/files/VERSION` | 1.0.5 → 1.0.6 | N/A |
| `elog_lib/CHANGELOG`, `elog_lib/CHANGELOG.RELEASE` | Prepend v1.0.6 entry | N/A |
| `tlog_lib/files/tlog_lib.sh` | Remove 11 headers + 8 banners; preserve load-bearing | `tlog_lib/tests/*.bats` (3 files, unchanged) |
| `tlog_lib/files/tlog` | Remove 16 banners (CLI wrapper — banner-only cleanup) | — (tested via `tlog_lib/tests/`) |
| `tlog_lib/files/VERSION` | 2.0.5 → 2.0.6 | N/A |
| `tlog_lib/CHANGELOG`, `tlog_lib/CHANGELOG.RELEASE` | Prepend v2.0.6 entry | N/A |
| `advanced-policy-firewall/files/internals/pkg_lib.sh` | Resync from canonical pkg_lib 1.0.10 | `advanced-policy-firewall/tests/*.bats` |
| `advanced-policy-firewall/files/internals/elog_lib.sh` | Resync from canonical elog_lib 1.0.6 | — |
| `advanced-policy-firewall/files/internals/geoip_lib.sh` | Resync from canonical geoip_lib 1.0.7 | — |
| `advanced-policy-firewall/CHANGELOG`, `advanced-policy-firewall/CHANGELOG.RELEASE` | Vendor bump entry | — |
| `brute-force-detection/files/internals/pkg_lib.sh` | Resync pkg_lib 1.0.10 | `brute-force-detection/tests/*.bats` |
| `brute-force-detection/files/internals/elog_lib.sh` | Resync elog_lib 1.0.6 | — |
| `brute-force-detection/files/internals/alert_lib.sh` | Resync alert_lib 1.0.7 | — |
| `brute-force-detection/files/internals/tlog_lib.sh` | Resync tlog_lib 2.0.6 | — |
| `brute-force-detection/files/internals/geoip_lib.sh` | Resync geoip_lib 1.0.7 | — |
| `brute-force-detection/CHANGELOG`, `brute-force-detection/CHANGELOG.RELEASE` | Vendor bump entry | — |
| `linux-malware-detect/files/internals/pkg_lib.sh` | Resync pkg_lib 1.0.10 | `linux-malware-detect/tests/*.bats` |
| `linux-malware-detect/files/internals/elog_lib.sh` | Resync elog_lib 1.0.6 | — |
| `linux-malware-detect/files/internals/alert_lib.sh` | Resync alert_lib 1.0.7 | — |
| `linux-malware-detect/files/internals/tlog_lib.sh` | Resync tlog_lib 2.0.6 | — |
| `linux-malware-detect/CHANGELOG`, `linux-malware-detect/CHANGELOG.RELEASE` | Vendor bump entry | — |

### Deleted Files
None. Cleanup is edit-only.

---

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [2]
- Phase 4: [2]
- Phase 5: [2]
- Phase 6: [2]
- Phase 7: [2]
- Phase 8: [3, 4, 5, 6, 7]
- Phase 9: [8]

Phases 3-7 (per-library cleanups) depend only on Phase 2 (baseline captured) and are independent of each other. **Execution decision (2026-04-10):** despite parallel eligibility, Phases 3-7 run **serial** via individual engineer subagent dispatches to make failure diagnosis tractable in the autonomous run. Phase 9 (publication) runs as 5 parallel tracks since each is just `git push` + tag on an independent repo.

---

## Pre-flight (run once before Phase 1)

Verify working trees clean, no upstream conflicts, and all library test suites currently green. This protects against commingling the comment-discipline change with unrelated in-flight work.

1. Working tree clean per library:
   ```bash
   for lib in alert_lib elog_lib tlog_lib pkg_lib geoip_lib; do
     printf '%-12s ' "$lib"
     git -C /root/admin/work/proj/$lib status --short | wc -l
   done
   # expect: 0 for every lib
   ```
   If any lib is non-zero: inspect, resolve, or halt.

2. Branch verification:
   ```bash
   for lib in alert_lib elog_lib tlog_lib pkg_lib geoip_lib; do
     printf '%-12s ' "$lib"
     git -C /root/admin/work/proj/$lib branch --show-current
   done
   # expect: master for every lib
   ```

3. Consumer working trees clean + no in-flight PRs touching `internals/<lib>.sh`:
   ```bash
   for c in advanced-policy-firewall brute-force-detection linux-malware-detect; do
     printf '%-30s ' "$c"
     git -C /root/admin/work/proj/$c status --short | wc -l
     git -C /root/admin/work/proj/$c branch --show-current
   done
   # expect: 0 and the current release branch (2.0.2 for APF/BFD, 2.0.1 for LMD)

   gh pr list -R rfxn/advanced-policy-firewall --state open --json number,headRefName,files -q \
     '.[] | select(.files[].path | test("internals/.*_lib\\.sh"))'
   gh pr list -R rfxn/brute-force-detection --state open --json number,headRefName,files -q \
     '.[] | select(.files[].path | test("internals/.*_lib\\.sh"))'
   gh pr list -R rfxn/linux-malware-detect --state open --json number,headRefName,files -q \
     '.[] | select(.files[].path | test("internals/.*_lib\\.sh"))'
   # expect: empty output from each (no open PRs touching vendored libs)
   ```
   **If any consumer PR touches `internals/*_lib.sh`, HALT and escalate.** Per MEMORY.md (2026-04-08) APF PR #52 was open on the 2.0.2 branch — verify it is merged or that it does not touch `internals/pkg_lib.sh`, otherwise Phase 9 will conflict.

4. Baseline test pass per library (establishes green trunk before any edit):
   ```bash
   for lib in alert_lib elog_lib tlog_lib pkg_lib geoip_lib; do
     echo "=== $lib ==="
     make -C /root/admin/work/proj/$lib/tests test 2>&1 | tee /tmp/preflight-${lib}.log | tail -5
     grep -c "^not ok" /tmp/preflight-${lib}.log
   done
   # expect: "not ok" count == 0 for every lib
   ```
   Any red test halts the plan — debug and land the fix before starting comment cleanup.

> **Pre-flight GO** — only after all four checks pass cleanly.

---

### Phase 1: Metrics pipeline scaffold

Productionize the prototype `/tmp/comment-metrics.sh` as a committed, reusable RDF script. This is the reproducible measurement tool the plan and all future audits will rely on.

**Files:**
- Create: `rdf/canonical/scripts/comment-metrics.sh` (test: N/A, smoke-tested by Phase 2)
- Create: `rdf/canonical/scripts/comment-snapshot.sh` (test: N/A, smoke-tested by Phase 2)

- **Mode**: serial-context
- **Accept**: both scripts exist, are executable, and pass `bash -n` + `shellcheck`; running `comment-snapshot.sh` against the 6 target files produces a TSV matching the baseline recorded in the spec
- **Test**: `bash -n` + `shellcheck` on both new files; execution smoke test (Phase 2 Step 2)
- **Edge cases**: EC8 (pipeline must be deterministic)

- [ ] **Step 1: Create `rdf/canonical/scripts/comment-metrics.sh`**

  ```bash
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
  # Deterministic: depends only on the file contents; no timestamps, no sorting
  # non-determinism, no locale sensitivity.
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
  ```

  Make executable: `command chmod +x /root/admin/work/proj/rdf/canonical/scripts/comment-metrics.sh`

- [ ] **Step 2: Create `rdf/canonical/scripts/comment-snapshot.sh`**

  ```bash
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
  ```

  Make executable: `command chmod +x /root/admin/work/proj/rdf/canonical/scripts/comment-snapshot.sh`

- [ ] **Step 3: Verify syntax and static analysis**

  ```bash
  bash -n /root/admin/work/proj/rdf/canonical/scripts/comment-metrics.sh
  bash -n /root/admin/work/proj/rdf/canonical/scripts/comment-snapshot.sh
  # expect: exit 0, no output

  shellcheck /root/admin/work/proj/rdf/canonical/scripts/comment-metrics.sh
  shellcheck /root/admin/work/proj/rdf/canonical/scripts/comment-snapshot.sh
  # expect: exit 0, no findings
  ```

- [ ] **Step 4: Regenerate Claude Code adapter output**

  ```bash
  cd /root/admin/work/proj/rdf && /root/admin/work/proj/rdf/bin/rdf generate claude-code
  # expect: "CC generation complete: 6 agents, 31 commands, 11 scripts" (script count increments by 1)
  ```

  Verify the new scripts landed in `/root/.claude/scripts/`:
  ```bash
  ls /root/.claude/scripts/comment-*.sh
  # expect: both files present
  ```

- [ ] **Step 5: Commit**

  ```bash
  cd /root/admin/work/proj/rdf
  git add canonical/scripts/comment-metrics.sh canonical/scripts/comment-snapshot.sh
  # NOTE: do NOT stage generated adapter output (/root/.claude/) — that's not in the rdf repo
  git commit -m "$(cat <<'EOF'
  Add comment-metrics pipeline for library cruft measurement

  [New] canonical/scripts/comment-metrics.sh — per-file comment cruft metrics
        emitting TSV (total, cmt_only, banner, tombstone, hdr_ge4, hdr_max,
        cat_block, max_inline). Deterministic, awk-based, no locale sensitivity.
  [New] canonical/scripts/comment-snapshot.sh — wrapper running metrics against
        the shared library set (pkg_lib, alert_lib, geoip_lib, elog_lib,
        tlog_lib, tlog CLI). Supports stdout or file output.

  Supports the comment-discipline enforcement plan at
  rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md.
  EOF
  )"
  git log --oneline -1
  # expect: new commit with the above subject
  ```

---

### Phase 2: Baseline snapshot + delta-support tree

Capture the authoritative before-state TSV that Phase 8 will compare against. Also create the `rdf/docs/specs/support/` directory if it does not exist (per RDF plan-file organization convention).

**Files:**
- Create: `rdf/docs/specs/support/2026-04-10-comment-baseline.tsv`

- **Mode**: serial-context
- **Accept**: TSV file exists, has exactly 7 lines (1 header + 6 data rows), and the row for `pkg_lib.sh` shows `hdr_ge4=69`
- **Test**: diff against spec metrics table (manual; row counts checked automatically)
- **Edge cases**: EC8

- [ ] **Step 1: Create support directory if missing**

  ```bash
  command mkdir -p /root/admin/work/proj/rdf/docs/specs/support
  ls -d /root/admin/work/proj/rdf/docs/specs/support
  # expect: directory listed (no error)
  ```

- [ ] **Step 2: Run baseline snapshot**

  ```bash
  /root/admin/work/proj/rdf/canonical/scripts/comment-snapshot.sh \
      /root/admin/work/proj/rdf/docs/specs/support/2026-04-10-comment-baseline.tsv
  # expect: "wrote .../2026-04-10-comment-baseline.tsv" on stderr
  ```

- [ ] **Step 3: Verify baseline matches spec metrics**

  ```bash
  wc -l /root/admin/work/proj/rdf/docs/specs/support/2026-04-10-comment-baseline.tsv
  # expect: 7 (header + 6 data rows)

  grep 'pkg_lib\.sh' /root/admin/work/proj/rdf/docs/specs/support/2026-04-10-comment-baseline.tsv | awk -F'\t' '{print $7}'
  # expect: 69

  grep 'geoip_lib\.sh' /root/admin/work/proj/rdf/docs/specs/support/2026-04-10-comment-baseline.tsv | awk -F'\t' '{print $5}'
  # expect: 56

  grep '/tlog$' /root/admin/work/proj/rdf/docs/specs/support/2026-04-10-comment-baseline.tsv | awk -F'\t' '{print $5}'
  # expect: 16
  ```

  If any row diverges from spec: STOP. Either the metrics pipeline is broken (investigate `comment-metrics.sh`) or the library state drifted since spec (re-measure and update spec).

- [ ] **Step 4: Commit baseline + spec**

  ```bash
  cd /root/admin/work/proj/rdf
  git add docs/specs/2026-04-10-comment-discipline-enforcement.md \
          docs/plans/2026-04-10-comment-discipline-enforcement.md \
          docs/specs/support/2026-04-10-comment-baseline.tsv
  git commit -m "$(cat <<'EOF'
  Add comment-discipline enforcement spec, plan, and baseline snapshot

  [New] docs/specs/2026-04-10-comment-discipline-enforcement.md — scope,
        triage (3-tier severity), rules applied, vendor integration map,
        release strategy, verification, edge cases, success criteria.
  [New] docs/plans/2026-04-10-comment-discipline-enforcement.md — 9-phase
        execution-grade plan: pipeline scaffold, baseline snapshot, 5
        parallel library cleanups, after snapshot, consumer vendor resync.
  [New] docs/specs/support/2026-04-10-comment-baseline.tsv — authoritative
        before-state metrics: 8383 total lines, 1917 comment-only (22.9%),
        144 multi-line headers >=4 lines, 138 banner separator lines
        across pkg_lib / alert_lib / geoip_lib / elog_lib / tlog_lib / tlog.
  EOF
  )"
  git log --oneline -1
  ```

---

### Phase 3: pkg_lib cleanup (v1.0.10)

Remove 69 multi-line function-header blocks (the largest concentration in the library set). pkg_lib has zero banner separators — cleanup is signature-restatement focused. The majority of blocks are 4-9 lines; the longest is 25 lines.

**Files:**
- Modify: `pkg_lib/files/pkg_lib.sh` (comment cleanup + `PKG_LIB_VERSION` bump)
- Modify: `pkg_lib/files/VERSION` (1.0.9 → 1.0.10)
- Modify: `pkg_lib/CHANGELOG`
- Modify: `pkg_lib/CHANGELOG.RELEASE`

- **Mode**: serial-agent
- **Accept**:
  - `grep -c '^PKG_LIB_VERSION=' pkg_lib/files/pkg_lib.sh` == 1 AND value is `"1.0.10"`
  - `comment-metrics.sh pkg_lib/files/pkg_lib.sh | awk -F'\t' 'NR==2 {print $7}'` returns ≤3 (down from 69)
  - `bash -n pkg_lib/files/pkg_lib.sh` exits 0
  - `shellcheck pkg_lib/files/pkg_lib.sh` reports no NEW findings vs. baseline
  - `make -C pkg_lib/tests test` full matrix (Debian 12 + Rocky 9 + CentOS 6) all green
  - Load-bearing whitelist grep count AFTER ≥ count BEFORE for all whitelist patterns
- **Test**: `make -C tests test` (Debian 12), `make -C tests test-rocky9`, `make -C tests test-centos6`; verify via `/tmp/test-pkglib-<os>.log | grep -c '^not ok'` == 0
- **Edge cases**: EC1 (bottom-up processing), EC2 (load-bearing preserved), EC3 (test regression), EC6 (long inline load-bearing kept), EC7 (discovered bugs filed separately)

- [ ] **Step 1: Capture load-bearing whitelist baseline**

  ```bash
  cd /root/admin/work/proj/pkg_lib
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/pkg_lib.sh > /tmp/pkglib-loadbearing-before.txt
  wc -l /tmp/pkglib-loadbearing-before.txt
  # expect: a positive count; record it for Step 7 comparison
  ```

- [ ] **Step 2: Identify deletion targets (bottom-up)**

  ```bash
  awk '/^[[:space:]]*#/ {if(!in_hdr){start=NR;in_hdr=1;n=1}else{n++};next}
  {if(in_hdr && n>=4) print start"-"(NR-1)" ("n" lines)"; in_hdr=0;n=0}' \
      /root/admin/work/proj/pkg_lib/files/pkg_lib.sh | sort -t- -k1 -n -r > /tmp/pkglib-targets.txt
  wc -l /tmp/pkglib-targets.txt
  # expect: 69 (one line per header block >=4 lines)
  head -5 /tmp/pkglib-targets.txt
  # expect: 5 largest line-numbered blocks first (bottom-up order)
  ```

- [ ] **Step 3: Process each deletion target bottom-up**

  For each entry in `/tmp/pkglib-targets.txt` (highest line numbers first):
  1. Read the target range with `Read file_path offset=$start limit=$n+2` (include 2 lines of following context to see the function signature).
  2. Verify the block is a signature-restatement pattern. Signature restatement = the block mentions `$1`, `$2`, `Arguments:`, `Args:`, `Parameters:`, `Returns`, `Out:`, or parameter names that also appear in the immediately-following `local var="$1"` lines.
  3. If the block is one-line prose describing function purpose, **keep only the first line** — that is the valid one-line header.
  4. If the block is multi-line restatement, **delete all but the first line**. The first line (e.g., `# pkg_service_restart name — restart service now`) is the one-line header the rule permits.
  5. If the block is load-bearing (explains WHY, documents out-parameters, notes a side effect, or is a compat/platform quirk), **keep it intact**. Err on the side of keeping.
  6. Apply the edit via Edit tool, using the old block as `old_string` and the trimmed first line as `new_string`. Never `replace_all`.

  **Concrete example — `pkg_lib.sh:1450-1459`:**
  ```
  # pkg_service_restart name — restart service now
  # Arguments:
  #   $1 — service name
  pkg_service_restart() {
      local name="$1"
  ```
  becomes:
  ```
  # pkg_service_restart name — restart service now
  pkg_service_restart() {
      local name="$1"
  ```
  Three lines cut (`# Arguments:`, `#   $1 — service name`, and typically a `# Returns 0 on success, 1 on error.` line).

  **Concrete example — `pkg_lib.sh:2640-2643`:**
  ```
  # Shell-escape old_val for sourcing safety: the AWK raw reader returns literal
  # file bytes between quotes — single-quoted originals lack escape sequences,
  # so writing them inside double quotes without escaping creates injection vectors.
  # Escape \, ", $, ` for double-quote context (backslash first to avoid double-escaping).
  ```
  This is **load-bearing** (explains *why* and notes an injection vector). **Keep intact.**

- [ ] **Step 4: Bump version**

  ```bash
  cd /root/admin/work/proj/pkg_lib
  ```
  Edit `files/pkg_lib.sh`:
  ```
  - PKG_LIB_VERSION="1.0.9"
  + PKG_LIB_VERSION="1.0.10"
  ```
  Edit `files/VERSION`:
  ```
  - 1.0.9
  + 1.0.10
  ```
  Verify:
  ```bash
  grep '^PKG_LIB_VERSION=' files/pkg_lib.sh
  cat files/VERSION
  # expect: "1.0.10" in both
  ```

- [ ] **Step 5: Update CHANGELOG + CHANGELOG.RELEASE**

  Prepend to `CHANGELOG` and replace the top of `CHANGELOG.RELEASE`:
  ```
  - 1.0.10 | Apr 10 2026:

    [Change] Comment discipline: removed N multi-line function-header blocks that restated
        signatures (# Arguments: / #   $1 — ... above local var="$1"); converted to
        one-line headers per core profile comment-discipline rule. Zero functional
        change, zero signature change. See rdf/docs/specs/2026-04-10-comment-discipline-
        enforcement.md. Cruft reduction: N→≤3 multi-line header blocks (M lines removed
        from file).
  ```
  Substitute `N` and `M` with the actual counts after Step 3 completes. Compute via:
  ```bash
  /root/admin/work/proj/rdf/canonical/scripts/comment-metrics.sh files/pkg_lib.sh | awk -F'\t' 'NR==2 {printf "hdr_ge4=%d\n", $7}'
  ```

- [ ] **Step 6: Syntax + static analysis**

  ```bash
  bash -n files/pkg_lib.sh
  # expect: exit 0, no output
  shellcheck files/pkg_lib.sh
  # expect: exit 0, no findings (or same findings as pre-cleanup)
  ```

- [ ] **Step 7: Load-bearing whitelist preservation check**

  ```bash
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/pkg_lib.sh > /tmp/pkglib-loadbearing-after.txt
  diff /tmp/pkglib-loadbearing-before.txt /tmp/pkglib-loadbearing-after.txt
  # expect: no "<" lines (nothing deleted); ">" lines allowed (only additions)
  ```
  Any `<` line indicates a load-bearing comment was removed — STOP, restore the line, re-verify.

- [ ] **Step 8: Test matrix**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-pkglib-debian12.log | tail -30
  grep -c '^not ok' /tmp/test-pkglib-debian12.log
  # expect: 0

  make -C tests test-rocky9 2>&1 | tee /tmp/test-pkglib-rocky9.log | tail -30
  grep -c '^not ok' /tmp/test-pkglib-rocky9.log
  # expect: 0

  make -C tests test-centos6 2>&1 | tee /tmp/test-pkglib-centos6.log | tail -30
  grep -c '^not ok' /tmp/test-pkglib-centos6.log
  # expect: 0
  ```
  Any red test: STOP, roll back the specific file, diagnose the regression, never commit a broken library.

- [ ] **Step 9: Commit**

  ```bash
  cd /root/admin/work/proj/pkg_lib
  git add files/pkg_lib.sh files/VERSION CHANGELOG CHANGELOG.RELEASE
  git status --short
  # expect: 4 staged files, no untracked

  git commit -m "$(cat <<'EOF'
  v1.0.10 | Comment discipline enforcement

  [Change] files/pkg_lib.sh: removed N multi-line function-header blocks that
      restated signatures (# Arguments: / #   $1 — ... above local var="$1");
      converted to one-line headers per core profile comment-discipline rule.
      Zero functional change, zero signature change.
  [Change] files/VERSION: 1.0.9 → 1.0.10
  [Change] CHANGELOG, CHANGELOG.RELEASE: v1.0.10 entry

  Rationale and taxonomy: rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md
  Plan: rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md
  EOF
  )"
  git log --oneline -1
  # expect: new commit starting with "v1.0.10 |"
  ```

---

### Phase 4: alert_lib cleanup (v1.0.7)

Remove 28 multi-line function-header blocks AND 32 banner separator lines. alert_lib mixes both cruft patterns. Longest header block is 17 lines.

**Files:**
- Modify: `alert_lib/files/alert_lib.sh`
- Modify: `alert_lib/files/VERSION` (1.0.6 → 1.0.7)
- Modify: `alert_lib/CHANGELOG`, `alert_lib/CHANGELOG.RELEASE`

- **Mode**: serial-agent
- **Accept**:
  - `grep '^ALERT_LIB_VERSION=' alert_lib/files/alert_lib.sh` == `"1.0.7"`
  - `hdr_ge4` drops from 28 to ≤3 AND `banner` drops from 32 to 0
  - Full test matrix green
  - Load-bearing whitelist preserved
- **Test**: `make -C tests test{,-rocky9,-centos6}`; `grep -c '^not ok'` == 0 per OS
- **Edge cases**: EC1, EC2, EC3, EC6

- [ ] **Step 1: Load-bearing whitelist baseline**

  ```bash
  cd /root/admin/work/proj/alert_lib
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/alert_lib.sh > /tmp/alertlib-loadbearing-before.txt
  wc -l /tmp/alertlib-loadbearing-before.txt
  ```

- [ ] **Step 2: Identify header block targets (bottom-up)**

  ```bash
  awk '/^[[:space:]]*#/ {if(!in_hdr){start=NR;in_hdr=1;n=1}else{n++};next}
  {if(in_hdr && n>=4) print start"-"(NR-1)" ("n" lines)"; in_hdr=0;n=0}' \
      /root/admin/work/proj/alert_lib/files/alert_lib.sh | sort -t- -k1 -n -r > /tmp/alertlib-header-targets.txt
  wc -l /tmp/alertlib-header-targets.txt
  # expect: 28
  ```

- [ ] **Step 3: Identify banner targets**

  ```bash
  grep -nE '^[[:space:]]*#[[:space:]]?[-=#_]{5,}[[:space:]]*$' /root/admin/work/proj/alert_lib/files/alert_lib.sh | sort -t: -k1 -n -r > /tmp/alertlib-banner-targets.txt
  wc -l /tmp/alertlib-banner-targets.txt
  # expect: 32
  ```

- [ ] **Step 4: Delete banner lines (bottom-up via Edit tool)**

  For each line in `/tmp/alertlib-banner-targets.txt` (highest line number first):
  - Read 1 line of context via Read at that offset
  - Apply Edit with the banner line as `old_string` and empty string as `new_string` — when the banner is on its own, remove the line entirely (including its newline)
  - When two banners bracket a section heading, delete both but keep the heading as a plain comment line

- [ ] **Step 5: Delete signature-restatement blocks (bottom-up)**

  Apply the same pattern as Phase 3 Step 3. alert_lib's blocks are typically 4-7 lines each. Preserve any block whose lines include `_ret` out-parameters, slack/email channel setup preconditions, or CVE/bash-compat refs.

- [ ] **Step 6: Bump version**

  Edit `files/alert_lib.sh`: `ALERT_LIB_VERSION="1.0.6"` → `"1.0.7"`
  Edit `files/VERSION`: `1.0.6` → `1.0.7`

  ```bash
  grep '^ALERT_LIB_VERSION=' files/alert_lib.sh
  cat files/VERSION
  # expect: 1.0.7 in both
  ```

- [ ] **Step 7: CHANGELOG + CHANGELOG.RELEASE**

  Prepend v1.0.7 entry with same structure as Phase 3 Step 5, replacing N and M with actual counts.

- [ ] **Step 8: Syntax + static analysis**

  ```bash
  bash -n files/alert_lib.sh
  shellcheck files/alert_lib.sh
  # expect: clean
  ```

- [ ] **Step 9: Load-bearing whitelist preservation**

  ```bash
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/alert_lib.sh > /tmp/alertlib-loadbearing-after.txt
  diff /tmp/alertlib-loadbearing-before.txt /tmp/alertlib-loadbearing-after.txt
  # expect: no "<" lines
  ```

- [ ] **Step 10: Test matrix**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-alertlib-debian12.log | tail -30
  grep -c '^not ok' /tmp/test-alertlib-debian12.log
  make -C tests test-rocky9 2>&1 | tee /tmp/test-alertlib-rocky9.log | tail -30
  grep -c '^not ok' /tmp/test-alertlib-rocky9.log
  make -C tests test-centos6 2>&1 | tee /tmp/test-alertlib-centos6.log | tail -30
  grep -c '^not ok' /tmp/test-alertlib-centos6.log
  # expect: 0 for each
  ```

- [ ] **Step 11: Commit**

  ```bash
  cd /root/admin/work/proj/alert_lib
  git add files/alert_lib.sh files/VERSION CHANGELOG CHANGELOG.RELEASE
  git commit -m "$(cat <<'EOF'
  1.0.7 | Comment discipline enforcement

  [Change] files/alert_lib.sh: removed 28 multi-line function-header blocks
      (signature restatement) and 32 banner separator lines (# ----- style);
      converted to one-line headers and blank-line section separation per
      core profile comment-discipline rule. Zero functional change.
  [Change] files/VERSION: 1.0.6 → 1.0.7
  [Change] CHANGELOG, CHANGELOG.RELEASE: v1.0.7 entry

  Rationale: rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md
  Plan: rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md
  EOF
  )"
  git log --oneline -1
  ```

---

### Phase 5: geoip_lib cleanup (v1.0.7)

Highest density cruft at 27.8%. Remove 26 multi-line function-header blocks AND 56 banner separator lines. Longest header 25 lines. geoip_lib is also notable for using `# Args:` / `# Returns:` docstring-style headers throughout (see example at `geoip_lib.sh:250-257`).

**Files:**
- Modify: `geoip_lib/files/geoip_lib.sh`
- Modify: `geoip_lib/files/VERSION` (1.0.6 → 1.0.7)
- Modify: `geoip_lib/CHANGELOG`, `geoip_lib/CHANGELOG.RELEASE`

- **Mode**: serial-agent
- **Accept**:
  - `grep '^GEOIP_LIB_VERSION=' geoip_lib/files/geoip_lib.sh` == `"1.0.7"`
  - `hdr_ge4` drops from 26 to ≤3 AND `banner` drops from 56 to 0
  - Test matrix green
  - Load-bearing whitelist preserved (**critical:** geoip_lib has `# Strict TLS`, `# TLS_INSECURE`, `# FreeBSD` lines — all load-bearing)
- **Test**: `make -C tests test{,-rocky9,-centos6}`
- **Edge cases**: EC1, EC2, EC3, EC6

- [ ] **Step 1: Load-bearing whitelist baseline**

  ```bash
  cd /root/admin/work/proj/geoip_lib
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|[Ss]trict TLS|[Ii]nsecure|gotcha|race|deadlock|shellcheck disable|workaround):' files/geoip_lib.sh > /tmp/geoiplib-loadbearing-before.txt
  wc -l /tmp/geoiplib-loadbearing-before.txt
  ```

- [ ] **Step 2: Identify header targets**

  ```bash
  awk '/^[[:space:]]*#/ {if(!in_hdr){start=NR;in_hdr=1;n=1}else{n++};next}
  {if(in_hdr && n>=4) print start"-"(NR-1)" ("n" lines)"; in_hdr=0;n=0}' \
      /root/admin/work/proj/geoip_lib/files/geoip_lib.sh | sort -t- -k1 -n -r > /tmp/geoiplib-header-targets.txt
  wc -l /tmp/geoiplib-header-targets.txt
  # expect: 26
  ```

- [ ] **Step 3: Identify banner targets**

  ```bash
  grep -nE '^[[:space:]]*#[[:space:]]?[-=#_]{5,}[[:space:]]*$' /root/admin/work/proj/geoip_lib/files/geoip_lib.sh | sort -t: -k1 -n -r > /tmp/geoiplib-banner-targets.txt
  wc -l /tmp/geoiplib-banner-targets.txt
  # expect: 56
  ```

- [ ] **Step 4: Delete banner lines bottom-up**

  Same method as Phase 4 Step 4. geoip_lib banners are `# ------...-` style.

- [ ] **Step 5: Delete signature-restatement blocks bottom-up**

  geoip_lib's dominant pattern is:
  ```
  # _geoip_download_cmd — download URL to file via curl or wget.
  # Internal helper. Strict TLS by default. Set GEOIP_TLS_INSECURE=1 to allow
  # insecure fallback (analogous to curl --insecure) for legacy systems with
  # untrusted CA bundles or expired certificates.
  # Args: URL OUTPUT
  # Returns: 0 on success, 1 on failure (OUTPUT removed on failure)
  ```

  The first line is a valid one-line header. The "Internal helper. Strict TLS..." block is **load-bearing** (documents default TLS behavior and escape hatch — non-obvious). **Keep it.** The `# Args: URL OUTPUT` and `# Returns: 0 on success...` lines ARE signature restatement. **Delete those two lines only.**

  This is the most delicate cleanup in the plan because the blocks mix load-bearing prose with restatement. When in doubt: keep. The win comes from the next function, not from this one.

- [ ] **Step 6: Bump version**

  Edit `files/geoip_lib.sh`: `GEOIP_LIB_VERSION="1.0.6"` → `"1.0.7"`
  Edit `files/VERSION`: `1.0.6` → `1.0.7`

- [ ] **Step 7: CHANGELOG + CHANGELOG.RELEASE**

  Prepend v1.0.7 entry. Note in the entry that "Args:" and "Returns:" docstring lines were removed but load-bearing TLS/security rationale was preserved.

- [ ] **Step 8: Syntax + static analysis**

  ```bash
  bash -n files/geoip_lib.sh
  shellcheck files/geoip_lib.sh
  ```

- [ ] **Step 9: Load-bearing whitelist preservation**

  ```bash
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|[Ss]trict TLS|[Ii]nsecure|gotcha|race|deadlock|shellcheck disable|workaround):' files/geoip_lib.sh > /tmp/geoiplib-loadbearing-after.txt
  diff /tmp/geoiplib-loadbearing-before.txt /tmp/geoiplib-loadbearing-after.txt
  # expect: no "<" lines
  ```

- [ ] **Step 10: Test matrix**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-geoiplib-debian12.log | tail -30
  grep -c '^not ok' /tmp/test-geoiplib-debian12.log
  make -C tests test-rocky9 2>&1 | tee /tmp/test-geoiplib-rocky9.log | tail -30
  grep -c '^not ok' /tmp/test-geoiplib-rocky9.log
  make -C tests test-centos6 2>&1 | tee /tmp/test-geoiplib-centos6.log | tail -30
  grep -c '^not ok' /tmp/test-geoiplib-centos6.log
  # expect: 0 each
  ```

- [ ] **Step 11: Commit**

  ```bash
  cd /root/admin/work/proj/geoip_lib
  git add files/geoip_lib.sh files/VERSION CHANGELOG CHANGELOG.RELEASE
  git commit -m "$(cat <<'EOF'
  geoip_lib 1.0.7 | Comment discipline enforcement

  [Change] files/geoip_lib.sh: removed 26 multi-line function-header blocks
      (# Args: / # Returns: signature restatement) and 56 banner separator
      lines (# ----- style); converted to one-line headers and blank-line
      section separation per core profile comment-discipline rule. Preserved
      all load-bearing TLS/security/FreeBSD compat comments.
      Zero functional change.
  [Change] files/VERSION: 1.0.6 → 1.0.7
  [Change] CHANGELOG, CHANGELOG.RELEASE: v1.0.7 entry

  Rationale: rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md
  Plan: rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md
  EOF
  )"
  git log --oneline -1
  ```

---

### Phase 6: elog_lib cleanup (v1.0.6)

Moderate header cleanup (9 blocks) PLUS the single worst prose catalogue in the codebase: the 44-line ELOG_* configuration variable catalogue at `elog_lib.sh:34-77`. Also 26 banner lines.

**Files:**
- Modify: `elog_lib/files/elog_lib.sh`
- Modify: `elog_lib/files/VERSION` (1.0.5 → 1.0.6)
- Modify: `elog_lib/CHANGELOG`, `elog_lib/CHANGELOG.RELEASE`
- Potentially modify: `elog_lib/README.md` (if the catalogue content is not already there, it must be moved)

- **Mode**: serial-agent
- **Accept**:
  - `grep '^ELOG_LIB_VERSION=' elog_lib/files/elog_lib.sh` == `"1.0.6"`
  - `hdr_ge4` drops from 9 to ≤3 AND `banner` drops from 26 to 0 AND `cat_block` drops from 44 to ≤3
  - Test matrix green
  - README contains the ELOG_* variable reference table (either pre-existing or added by this phase)
  - Load-bearing whitelist preserved
- **Test**: `make -C tests test{,-rocky9,-centos6}`
- **Edge cases**: EC1, EC2, EC3, EC6, EC7 (if the catalogue documents a variable that the code no longer supports, file an issue — do not fix in this plan)

- [ ] **Step 1: Load-bearing whitelist baseline**

  ```bash
  cd /root/admin/work/proj/elog_lib
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/elog_lib.sh > /tmp/eloglib-loadbearing-before.txt
  wc -l /tmp/eloglib-loadbearing-before.txt
  ```

- [ ] **Step 2: Audit README for the ELOG_* variable reference**

  ```bash
  grep -c '^##.*Config\|^##.*Variable\|ELOG_LOG_DIR' README.md
  # expect: >= 1
  ```
  If README lacks a config variable table: before deleting the catalogue from `elog_lib.sh:34-77`, extract its content and add it as a `## Configuration Variables` section to `README.md`. Use a table with columns: Variable | Default | Purpose. This preserves the reference without bloating source.

  If README already has the table: proceed to delete the catalogue. Verify every variable named in `elog_lib.sh:34-77` is also documented in the README.

- [ ] **Step 3: Delete the 44-line config catalogue at `elog_lib.sh:34-77`**

  Read the block first:
  ```bash
  sed -n '34,77p' files/elog_lib.sh
  ```
  Then via Edit tool, replace the 44-line block with a 2-line cross-reference:
  ```
  # Configuration: all ELOG_* variables consulted via ${VAR:-default} at use site.
  # See README.md § Configuration Variables for the full reference table.
  ```

  Verify:
  ```bash
  awk 'NR>=34 && NR<=36' files/elog_lib.sh
  # expect: the 2-line cross-reference plus the line below it
  ```

- [ ] **Step 4: Identify and delete remaining header blocks**

  ```bash
  awk '/^[[:space:]]*#/ {if(!in_hdr){start=NR;in_hdr=1;n=1}else{n++};next}
  {if(in_hdr && n>=4) print start"-"(NR-1)" ("n" lines)"; in_hdr=0;n=0}' \
      /root/admin/work/proj/elog_lib/files/elog_lib.sh | sort -t- -k1 -n -r > /tmp/eloglib-header-targets.txt
  wc -l /tmp/eloglib-header-targets.txt
  # expect: ~8 (9 minus the catalogue already replaced)
  ```

  Delete signature-restatement blocks bottom-up per Phase 3 Step 3 method.

- [ ] **Step 5: Delete banner separator lines**

  ```bash
  grep -nE '^[[:space:]]*#[[:space:]]?[-=#_]{5,}[[:space:]]*$' files/elog_lib.sh | sort -t: -k1 -n -r > /tmp/eloglib-banner-targets.txt
  wc -l /tmp/eloglib-banner-targets.txt
  # expect: ~26
  ```

  Delete bottom-up via Edit tool.

- [ ] **Step 6: Bump version**

  Edit `files/elog_lib.sh`: `ELOG_LIB_VERSION="1.0.5"` → `"1.0.6"`
  Edit `files/VERSION`: `1.0.5` → `1.0.6`

- [ ] **Step 7: CHANGELOG + CHANGELOG.RELEASE**

  Prepend v1.0.6 entry, noting: (a) 44-line config catalogue replaced with 2-line README cross-reference, (b) N multi-line headers removed, (c) 26 banners removed.

- [ ] **Step 8: Syntax + static analysis**

  ```bash
  bash -n files/elog_lib.sh
  shellcheck files/elog_lib.sh
  ```

- [ ] **Step 9: Load-bearing whitelist preservation**

  ```bash
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/elog_lib.sh > /tmp/eloglib-loadbearing-after.txt
  diff /tmp/eloglib-loadbearing-before.txt /tmp/eloglib-loadbearing-after.txt
  # expect: no "<" lines
  ```

- [ ] **Step 10: Test matrix**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-eloglib-debian12.log | tail -30
  grep -c '^not ok' /tmp/test-eloglib-debian12.log
  make -C tests test-rocky9 2>&1 | tee /tmp/test-eloglib-rocky9.log | tail -30
  grep -c '^not ok' /tmp/test-eloglib-rocky9.log
  make -C tests test-centos6 2>&1 | tee /tmp/test-eloglib-centos6.log | tail -30
  grep -c '^not ok' /tmp/test-eloglib-centos6.log
  # expect: 0 each
  ```

- [ ] **Step 11: Commit**

  ```bash
  cd /root/admin/work/proj/elog_lib
  git add files/elog_lib.sh files/VERSION CHANGELOG CHANGELOG.RELEASE
  # Also stage README.md if modified in Step 2:
  # git add README.md
  git commit -m "$(cat <<'EOF'
  1.0.6 | Comment discipline enforcement

  [Change] files/elog_lib.sh: collapsed 44-line ELOG_* configuration variable
      prose catalogue at lines 34-77 into a 2-line cross-reference to
      README.md § Configuration Variables. The declaration at each use site
      (${ELOG_VAR:-default}) is now the source of truth.
  [Change] files/elog_lib.sh: removed N multi-line function-header blocks
      (signature restatement) and 26 banner separator lines (# ----- style).
  [Change] files/VERSION: 1.0.5 → 1.0.6
  [Change] CHANGELOG, CHANGELOG.RELEASE: v1.0.6 entry

  Zero functional change. Rationale:
  rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md
  EOF
  )"
  git log --oneline -1
  ```

---

### Phase 7: tlog_lib + tlog CLI cleanup (v2.0.6)

Two files in one library. `tlog_lib.sh` has 11 header blocks + 8 banners. The `tlog` CLI wrapper has 16 banner lines (highest count of any file) but only 1 header block — purely a banner cleanup.

**Files:**
- Modify: `tlog_lib/files/tlog_lib.sh`
- Modify: `tlog_lib/files/tlog` (CLI wrapper)
- Modify: `tlog_lib/files/VERSION` (2.0.5 → 2.0.6)
- Modify: `tlog_lib/CHANGELOG`, `tlog_lib/CHANGELOG.RELEASE`

- **Mode**: serial-agent
- **Accept**:
  - `grep '^TLOG_LIB_VERSION=' tlog_lib/files/tlog_lib.sh` == `"2.0.6"`
  - For `tlog_lib.sh`: `hdr_ge4` drops from 11 to ≤3 AND `banner` drops from 8 to 0
  - For `tlog`: `banner` drops from 16 to 0 (headers unchanged)
  - Test matrix green
  - Load-bearing whitelist preserved on both files
- **Test**: `make -C tests test{,-rocky9,-centos6}`
- **Edge cases**: EC1, EC2, EC3

- [ ] **Step 1: Load-bearing whitelist baseline (both files)**

  ```bash
  cd /root/admin/work/proj/tlog_lib
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/tlog_lib.sh > /tmp/tloglib-lb-before.txt
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/tlog > /tmp/tlog-lb-before.txt
  wc -l /tmp/tloglib-lb-before.txt /tmp/tlog-lb-before.txt
  ```

- [ ] **Step 2: Delete banner lines in both files (bottom-up)**

  ```bash
  grep -nE '^[[:space:]]*#[[:space:]]?[-=#_]{5,}[[:space:]]*$' files/tlog_lib.sh | sort -t: -k1 -n -r > /tmp/tloglib-banner-targets.txt
  wc -l /tmp/tloglib-banner-targets.txt
  # expect: 8

  grep -nE '^[[:space:]]*#[[:space:]]?[-=#_]{5,}[[:space:]]*$' files/tlog | sort -t: -k1 -n -r > /tmp/tlog-banner-targets.txt
  wc -l /tmp/tlog-banner-targets.txt
  # expect: 16
  ```

  Delete via Edit tool, bottom-up, one banner at a time. When a banner bracket sandwiches a section heading (common tlog pattern), delete both banners but keep the heading as a plain comment line.

- [ ] **Step 3: Delete signature-restatement header blocks in `tlog_lib.sh`**

  ```bash
  awk '/^[[:space:]]*#/ {if(!in_hdr){start=NR;in_hdr=1;n=1}else{n++};next}
  {if(in_hdr && n>=4) print start"-"(NR-1)" ("n" lines)"; in_hdr=0;n=0}' \
      files/tlog_lib.sh | sort -t- -k1 -n -r > /tmp/tloglib-header-targets.txt
  wc -l /tmp/tloglib-header-targets.txt
  # expect: 11 initially; after Step 2 banner deletion some blocks may have merged/split — re-measure if needed
  ```

  Process bottom-up. **Important:** tlog_lib uses out-parameter globals (`_tlog_cursor_value`, `_tlog_cursor_mode`) — multi-line headers documenting out-parameter contracts are **load-bearing**. Keep any header block that mentions `_tlog_*` return values.

- [ ] **Step 4: Delete any remaining single-line banners in `tlog`**

  The CLI wrapper has no signature-restatement (only 1 hdr≥4 block). After Step 2, `tlog` should be compliant. Verify:
  ```bash
  /root/admin/work/proj/rdf/canonical/scripts/comment-metrics.sh files/tlog | awk -F'\t' 'NR==2 {print "banner="$5, "hdr_ge4="$7}'
  # expect: banner=0 hdr_ge4<=1
  ```

- [ ] **Step 5: Bump version**

  Edit `files/tlog_lib.sh`: `TLOG_LIB_VERSION="2.0.5"` → `"2.0.6"`
  Edit `files/VERSION`: `2.0.5` → `2.0.6`

  Check whether `tlog` also carries a version constant:
  ```bash
  grep -E 'VERSION=|version=' files/tlog | head -5
  ```
  If so, bump it to match.

- [ ] **Step 6: CHANGELOG + CHANGELOG.RELEASE**

  Prepend v2.0.6 entry covering both file cleanups.

- [ ] **Step 7: Syntax + static analysis**

  ```bash
  bash -n files/tlog_lib.sh files/tlog
  shellcheck files/tlog_lib.sh files/tlog
  ```

- [ ] **Step 8: Load-bearing whitelist preservation (both files)**

  ```bash
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/tlog_lib.sh > /tmp/tloglib-lb-after.txt
  grep -nE '# (safe|best-effort|bash 4\.1|compat|CVE-|FreeBSD|BSD|TLS|gotcha|race|deadlock|shellcheck disable|workaround):' files/tlog > /tmp/tlog-lb-after.txt
  diff /tmp/tloglib-lb-before.txt /tmp/tloglib-lb-after.txt
  diff /tmp/tlog-lb-before.txt /tmp/tlog-lb-after.txt
  # expect: no "<" lines in either diff
  ```

- [ ] **Step 9: Test matrix**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-tloglib-debian12.log | tail -30
  grep -c '^not ok' /tmp/test-tloglib-debian12.log
  make -C tests test-rocky9 2>&1 | tee /tmp/test-tloglib-rocky9.log | tail -30
  grep -c '^not ok' /tmp/test-tloglib-rocky9.log
  make -C tests test-centos6 2>&1 | tee /tmp/test-tloglib-centos6.log | tail -30
  grep -c '^not ok' /tmp/test-tloglib-centos6.log
  # expect: 0 each
  ```

- [ ] **Step 10: Commit**

  ```bash
  cd /root/admin/work/proj/tlog_lib
  git add files/tlog_lib.sh files/tlog files/VERSION CHANGELOG CHANGELOG.RELEASE
  git commit -m "$(cat <<'EOF'
  2.0.6 | Comment discipline enforcement

  [Change] files/tlog_lib.sh: removed N multi-line function-header blocks
      (signature restatement, out-parameter docs preserved) and 8 banner
      separator lines (##### style).
  [Change] files/tlog: removed 16 banner separator lines (##### style).
      CLI wrapper cleanup only; no header-block changes.
  [Change] files/VERSION: 2.0.5 → 2.0.6
  [Change] CHANGELOG, CHANGELOG.RELEASE: v2.0.6 entry

  Zero functional change. Rationale:
  rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md
  EOF
  )"
  git log --oneline -1
  ```

---

### Phase 8: After-state snapshot + delta report

Re-run the metrics pipeline against all 6 files, produce an after-state TSV, and generate a side-by-side delta markdown report.

**Files:**
- Create: `rdf/docs/specs/support/2026-04-10-comment-after.tsv`
- Create: `rdf/docs/specs/support/2026-04-10-comment-delta.md`

- **Mode**: serial-context
- **Accept**:
  - After TSV has 7 lines and shows `hdr_ge4` totals ≤15 (down from 144), `banner` totals == 0 (down from 138)
  - Delta report renders as markdown with per-file before/after table
  - Delta report is committed to rdf repo
- **Test**: `wc -l <tsv>` == 7; `awk` sum of `hdr_ge4` column ≤ 15
- **Edge cases**: EC8

- [ ] **Step 1: Run after-state snapshot**

  ```bash
  /root/admin/work/proj/rdf/canonical/scripts/comment-snapshot.sh \
      /root/admin/work/proj/rdf/docs/specs/support/2026-04-10-comment-after.tsv
  # expect: "wrote ..." on stderr
  ```

- [ ] **Step 2: Verify aggregate success criteria**

  ```bash
  awk -F'\t' 'NR>1 {hdr+=$7; banner+=$5} END {print "hdr_ge4_total="hdr, "banner_total="banner}' \
      /root/admin/work/proj/rdf/docs/specs/support/2026-04-10-comment-after.tsv
  # expect: hdr_ge4_total <= 15, banner_total == 0
  ```

  If either exceeds threshold: STOP, identify which library's cleanup was incomplete, return to that phase and re-run.

- [ ] **Step 3: Generate delta report**

  Read both TSVs and write a markdown report at `rdf/docs/specs/support/2026-04-10-comment-delta.md`. Required structure:

  ```markdown
  # Comment Discipline Enforcement — Before/After Delta

  **Date:** 2026-04-10
  **Plan:** `rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md`
  **Spec:** `rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md`

  ## Per-File Delta

  | File | Total (before→after) | Cmt% (before→after) | Hdr≥4 (before→after) | Banner (before→after) | Lines removed |
  |---|---|---|---|---|---|
  | `pkg_lib/files/pkg_lib.sh` | 3415→X | 21.9%→X% | 69→X | 0→0 | Y |
  | ... one row per file ... |

  ## Aggregate

  | Metric | Before | After | Delta |
  |---|---:|---:|---:|
  | Total lines | 8383 | X | -Y |
  | Comment-only lines | 1917 | X | -Y |
  | Comment % | 22.9% | X% | -Y pp |
  | Multi-line header blocks (≥4 lines) | 144 | X | -Y |
  | Banner separator lines | 138 | 0 | -138 |

  ## Reproducibility

  Re-run the snapshot:
  ```
  rdf/canonical/scripts/comment-snapshot.sh
  ```
  Output is deterministic; re-running produces the same TSV.
  ```

  Populate from the two TSVs via `awk` or by reading and computing inline.

- [ ] **Step 4: Commit**

  ```bash
  cd /root/admin/work/proj/rdf
  git add docs/specs/support/2026-04-10-comment-after.tsv \
          docs/specs/support/2026-04-10-comment-delta.md
  git commit -m "$(cat <<'EOF'
  Add comment-discipline after-state snapshot and delta report

  [New] docs/specs/support/2026-04-10-comment-after.tsv — post-cleanup metrics
        for all 6 target files.
  [New] docs/specs/support/2026-04-10-comment-delta.md — per-file before/after
        table and aggregate delta. Hdr>=4 dropped 144→X, banners 138→0, total
        comment-only lines dropped from 1917 to X (-Y lines, -Z pp).

  Closes the measurement loop for the plan at
  rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md.
  EOF
  )"
  git log --oneline -1
  ```

---

### Phase 9 (ORIGINAL — DEFERRED): Consumer vendor resync

> **Deferred per user direction (2026-04-10).** The consumer-project vendor
> resync (APF/BFD/LMD) is out of scope for this plan's execution pass. It
> will be handled by a separate follow-up plan after the library-level
> work lands upstream. The original Phase 9 content is retained below for
> reference but is not executed by `/r-build`.

### Phase 9: Push + tag libraries upstream

Publish the cleaned-up library versions upstream. Each library gets:
- A `git push origin master` to publish the commit from its Phase 3-7 cleanup
- An annotated git tag at the new version (`v1.0.10`, `1.0.7`, `geoip_lib-1.0.7`, etc. — **match each library's existing tag convention**, do NOT invent a format)
- A `git push origin <tag>` to publish the tag

**Files:** None modified in the workspace. This phase publishes git state only.

- **Mode**: parallel-agent (5 tracks, one per library, independent repositories)
- **Accept**:
  - Per library: `git status --short` empty; HEAD matches the Phase 3-7 cleanup commit SHA
  - Per library: `git ls-remote origin refs/tags/<tag>` returns the new tag SHA
  - Per library: `git push origin master` returns non-error status
  - Per library: `git log origin/master..HEAD` is empty (remote is up to date)
- **Test**: N/A — publication step
- **Edge cases**:
  - **EC9** (new): Library's existing tag convention varies — check `git tag --list | tail -5` per lib and match exactly. For example, pkg_lib historical tags are `v1.0.9` style; geoip_lib may use `geoip_lib-1.0.6` or a different pattern. Never guess.
  - **EC10** (new): Push is rejected because upstream has diverged — STOP, investigate, never `--force`. This would indicate someone else pushed while the plan was running.
  - **EC4** (existing): No conflicting open PR — pre-flighted.

File ownership boundaries:
- Track A — `pkg_lib` (one repo, one track)
- Track B — `alert_lib` (one repo, one track)
- Track C — `geoip_lib` (one repo, one track)
- Track D — `elog_lib` (one repo, one track)
- Track E — `tlog_lib` (one repo, one track)

No file overlap. Repositories are independent.

**Per-library procedure (identical across tracks, substitute library name and tag):**

- [ ] **Step 1: Verify clean state**

  ```bash
  cd /root/admin/work/proj/<lib>
  git status --short
  # expect: empty
  git log --oneline -3
  # expect: HEAD is the cleanup commit from Phase 3/4/5/6/7
  git rev-parse HEAD
  # record the SHA for the tag step
  ```

- [ ] **Step 2: Inspect existing tag convention**

  ```bash
  git tag --list | tail -5
  # record the format — e.g. "v1.0.9", "1.0.6", "geoip_lib-1.0.5"
  # new tag MUST match this format exactly
  ```

- [ ] **Step 3: Push commit to origin**

  ```bash
  git push origin master
  # expect: non-error, "* master -> master" in output
  ```

  If the push is rejected (remote diverged), STOP. Do NOT force-push. Investigate: `git fetch origin && git log HEAD..origin/master --oneline` shows what diverged.

- [ ] **Step 4: Create annotated tag**

  ```bash
  git tag -a <tag-matching-convention> -m "v<version> — comment discipline cleanup"
  # example for pkg_lib: git tag -a v1.0.10 -m "v1.0.10 — comment discipline cleanup"
  # example for tlog_lib: git tag -a 2.0.6 -m "2.0.6 — comment discipline cleanup"
  git tag --list | tail -3
  # expect: new tag visible
  ```

- [ ] **Step 5: Push tag to origin**

  ```bash
  git push origin <tag>
  # expect: "* [new tag] <tag> -> <tag>" in output
  git ls-remote origin refs/tags/<tag>
  # expect: non-empty line with the tag SHA
  ```

---

## Completion Handoff

> **Plan ready** — `rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md` (9 phases)
> Execution: Phases 1-2 serial, Phases 3-7 serial-agent dispatched via engineer subagents, Phase 8 serial, Phase 9 publishes all 5 libraries.
> Consumer resync (APF/BFD/LMD) is deferred — handled by a separate follow-up plan.

