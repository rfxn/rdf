# Spec: Comment Discipline Enforcement Across Shared Libraries

**Date:** 2026-04-10
**Scope:** alert_lib, elog_lib, tlog_lib (+ `tlog` CLI wrapper), pkg_lib, geoip_lib
**Out of scope:** APF, BFD, LMD binaries (consumers — separate follow-up plan)
**Plan:** `rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md`

## 1. Goal

Apply the comment-discipline primitives codified this session (parent
CLAUDE.md § Code Comments + RDF core profile § Code Comments + shell profile
anti-patterns + `reference/comment-discipline.md`) to all shared `*_lib`
projects. Produce a reproducible metrics pipeline that captures before/after
state so the delta can be measured.

## 2. Non-Goals

- Cleaning up consumer project source (APF `apf`, BFD `bfd`, LMD `maldet` and
  LMD internals). Those binaries are consumers of the libraries and will get
  a separate follow-up plan.
- Re-architecting library APIs. Cleanup is comment-only. Zero functional
  change, zero signature change, zero variable rename.
- Touching test suites. Tests are not affected by comment removal.
- Changing shellcheck directives (`# shellcheck disable=`) — these are
  load-bearing and stay.

## 3. Baseline Metrics (captured 2026-04-10)

Measured via `/tmp/comment-metrics.sh` prototype (to be productionized as
`rdf/canonical/scripts/comment-metrics.sh` in Phase 1 of the plan):

| File | Total | Cmt% | Banners | Hdr≥4 blocks | Max hdr | Cat block | Max inline |
|---|---:|---:|---:|---:|---:|---:|---:|
| `pkg_lib/files/pkg_lib.sh` | 3415 | 21.9% | 0 | **69** | 25 | 25 | 83 |
| `alert_lib/files/alert_lib.sh` | 1208 | 23.4% | 32 | 28 | 17 | 17 | 62 |
| `geoip_lib/files/geoip_lib.sh` | 961 | **27.8%** | **56** | 26 | 25 | 25 | 39 |
| `elog_lib/files/elog_lib.sh` | 1446 | 23.9% | 26 | 9 | **44** | **44** | 57 |
| `tlog_lib/files/tlog_lib.sh` | 800 | 24.2% | 8 | 11 | 17 | 17 | 54 |
| `tlog_lib/files/tlog` | 553 | 14.5% | 16 | 1 | 25 | 25 | 52 |

**Totals:** 8383 lines total, 1917 comment-only lines (22.9%), 144
multi-line header blocks ≥4 lines, 138 banner separator lines.

### Banner count methodology

A banner is a comment-only line matching the regex
`^[[:space:]]*#[[:space:]]?[-=#_]{5,}[[:space:]]*$` — i.e. a `#` followed by
five or more divider characters, no trailing text. Two dialects observed:
`##########` (tlog family) and `# -----` (geoip/alert/elog family). pkg_lib
uses blank-line separation and has zero banners.

### Triage

**Tier 1 — highest cruft absolute or relative:**
- **pkg_lib** — 69 multi-line function-header blocks (far more than any
  other file). Longest block 25 lines. Largest absolute cleanup target.
- **alert_lib** — 28 hdr≥4 blocks + 32 banners. High density combined with
  banner cruft.
- **geoip_lib** — Highest density at 27.8%, 56 banners (highest banner count
  of any file), 26 hdr≥4 blocks. Cruft-heavy on both axes.

**Tier 2 — moderate cleanup + specific concentrated targets:**
- **elog_lib** — 9 hdr≥4 blocks is low but includes the 44-line config
  variable catalogue at `elog_lib.sh:34-77` (the single worst prose catalogue
  in the codebase). 26 banner lines.
- **tlog_lib** — 11 hdr≥4 blocks + 8 banners. Moderate.

**Tier 3 — banner-only cleanup:**
- **tlog CLI wrapper (`tlog_lib/files/tlog`)** — 16 banner lines (highest
  banner count of any file), only 1 hdr≥4 block. Purely a banner cleanup.

## 4. Rules Applied

From `rdf/profiles/core/reference/comment-discipline.md` and parent
`CLAUDE.md § Code Comments`:

1. **Delete signature-restatement blocks** — multi-line `# Arguments:` /
   `# Args:` / `# Parameters:` headers above functions whose body begins
   `local x="$1"` are pure restatement. One-line headers only.
2. **Delete prose catalogues** of config variables in file headers. The
   `${FOO:-default}` line in code is the source of truth.
3. **Delete banner separators** (`# ----`, `##########`). Blank lines
   between sections instead.
4. **Preserve load-bearing comments**: platform quirks, language gotchas,
   suppression justifications (`2>/dev/null  # safe: ...`), ticket/CVE
   refs, non-obvious invariants, compat floors (`# bash 4.1: ...`).
5. **No tombstones** — git blame is the source of truth.

## 5. Vendor Integration Map

Each library is source-included by these consumers via
`internals/<lib>.sh`:

| Library | APF | BFD | LMD |
|---|:---:|:---:|:---:|
| pkg_lib | ✓ | ✓ | ✓ |
| elog_lib | ✓ | ✓ | ✓ |
| alert_lib | — | ✓ | ✓ |
| tlog_lib | — | ✓ | ✓ |
| geoip_lib | ✓ | ✓ | — |

Canonical → consumer sync is handled by `/r-util-lib-sync --sync` (existing
RDF command).

## 6. Release Strategy

Each library gets a **patch version bump** for the cleanup:
- `pkg_lib` 1.0.9 → 1.0.10
- `alert_lib` 1.0.6 → 1.0.7
- `elog_lib` 1.0.5 → 1.0.6
- `tlog_lib` 2.0.5 → 2.0.6
- `geoip_lib` 1.0.6 → 1.0.7

CHANGELOG body tag: `[Change]` — comment-only, non-functional.

After all 5 libraries are released, consumers (APF, BFD, LMD) get one
vendor-resync commit each, batching all applicable library bumps.

## 7. Verification per Library

1. `bash -n files/<lib>.sh` — syntax check. Exit 0.
2. `shellcheck files/<lib>.sh` — static analysis. No new findings.
3. `make -C tests test` — full BATS suite, Debian 12 default. All tests
   pass.
4. `make -C tests test-rocky9` — Rocky 9 (bash 5). All tests pass.
5. `make -C tests test-centos6` — CentOS 6 (bash 4.1 floor). All tests
   pass. **Mandatory for libraries** — bash 4.1 is the floor.
6. Grep: no new bare `cp`/`mv`/`rm`/`cat` or backslash bypasses introduced
   (defensive — cleanup shouldn't touch these but verify).
7. Grep: no load-bearing comments deleted. Load-bearing check is a
   whitelist grep against the pre-cleanup source: every `# safe:`, `# bash
   4.1:`, `# CVE-`, `# best-effort:`, `# compat:`, `# TLS:`, `# FreeBSD`
   line in the before-state must still exist in the after-state.

## 8. Edge Cases

| EC# | Case | Handling |
|---|---|---|
| EC1 | Line-range shift during cleanup as earlier deletions compact the file | Engineer processes deletions **bottom-up** (highest line first) OR uses function-name anchors (grep for `^funcname()` then delete N lines above) |
| EC2 | Load-bearing comment accidentally removed | Phase 8 after-state diff includes a load-bearing whitelist regrep. Any missing whitelist line is MUST-FIX |
| EC3 | BATS test regresses post-cleanup | Full test matrix (Debian 12 + Rocky 9 + CentOS 6) per library. Any red test blocks commit. Engineer rolls back the specific file and diagnoses |
| EC4 | Consumer vendor-resync conflicts with an open PR | APF has open PR #52 per MEMORY.md (2026-04-08). Pre-flight of Phase 9 greps `gh pr list` for each consumer; if an open PR touches `internals/<lib>.sh`, the engineer halts and escalates |
| EC5 | pkg_lib already on 1.0.9 in APF (ahead of BFD/LMD) | APF will get pkg_lib 1.0.10 via the resync; BFD/LMD will jump 1.0.8 → 1.0.10. Vendor version refs updated in each consumer |
| EC6 | Long inline comment (>60 chars) that IS load-bearing (e.g., `# -n prevents following existing symlink-to-directory (classic ln -sf gotcha)` at `pkg_lib.sh:964` = 77 chars) | Preserved. The length guideline is not a hard cap; load-bearing wins. Reference doc table row "Non-obvious invariant" applies |
| EC7 | Cleanup phase finds a real bug (e.g., stale function-header claim reveals drift from implementation) | Out of scope. Engineer files an issue and leaves the code untouched. This plan is comment-only |
| EC8 | Metrics pipeline produces different numbers on re-run | Pipeline must be deterministic. Phase 1 produces a fully committed script with pinned awk logic; Phase 8 re-runs the same script against the post-cleanup files |

## 9. Success Criteria

- Total multi-line header blocks ≥4 across the 6 files drops from 144 to
  ≤15 (≥90% reduction). Remaining blocks are out-parameter contracts,
  side-effect documentation, or caller-precondition notes — deliberately
  kept under the rule.
- Total banner separator lines drops from 138 to 0.
- 44-line config catalogue at `elog_lib.sh:34-77` replaced with ≤3 lines
  of cross-reference to README (or deleted outright if README covers it).
- All library test suites green on Debian 12 + Rocky 9 + CentOS 6.
- Consumer test suites (APF, BFD, LMD) green post-resync on their
  supported OS matrix.
- `rdf/canonical/scripts/comment-metrics.sh` is a committed, runnable
  script. Anyone can rerun it later and get comparable numbers.
- Delta report at `rdf/docs/specs/support/2026-04-10-comment-delta.md`
  documents before/after per file as a table.
