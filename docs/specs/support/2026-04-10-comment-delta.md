# Comment Discipline Enforcement — Before/After Delta

**Date:** 2026-04-11
**Plan:** `rdf/docs/plans/2026-04-10-comment-discipline-enforcement.md`
**Spec:** `rdf/docs/specs/2026-04-10-comment-discipline-enforcement.md`
**Baseline TSV:** `rdf/docs/specs/support/2026-04-10-comment-baseline.tsv`
**After TSV:** `rdf/docs/specs/support/2026-04-10-comment-after.tsv`

## Per-File Delta

| File | Total (before→after) | Cmt% (before→after) | Hdr≥4 (before→after) | Banner (before→after) | Lines removed |
|---|---|---|---:|---:|---:|
| `pkg_lib/files/pkg_lib.sh` | 3415 → 3209 | 21.9% → 16.9% | 69 → 27 | 0 → 0 | **-206** |
| `alert_lib/files/alert_lib.sh` | 1208 → 1175 | 23.4% → 21.4% | 28 → 28 | 32 → 0 | -33 |
| `geoip_lib/files/geoip_lib.sh` | 961 → 839 | 27.8% → 17.3% | 26 → 11 | 56 → 0 | **-122** |
| `elog_lib/files/elog_lib.sh` | 1446 → 1353 | 23.9% → 19.6% | 9 → 8 | 26 → 0 | -93 |
| `tlog_lib/files/tlog_lib.sh` | 800 → 784 | 24.2% → 23.2% | 11 → 11 | 8 → 0 | -16 |
| `tlog_lib/files/tlog` | 553 → 522 | 14.5% → 10.9% | 1 → 1 | 16 → 0 | -31 |

## Aggregate

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| Total lines | 8383 | 7882 | **-501** |
| Comment-only lines | 1917 | 1442 | **-475** |
| Comment % (weighted) | 22.9% | 18.3% | -4.6 pp |
| Multi-line header blocks (≥4 lines) | 144 | 86 | **-58** (40% reduction) |
| Banner separator lines | 138 | 0 | **-138** (100% eliminated) |
| Tombstone comments | 0 | 0 | 0 |

## Per-Library Notes

### pkg_lib v1.0.9 → v1.0.10 (commit `229e74f`)
Largest absolute cleanup. Removed 206 restatement lines across 42 fully cleared header blocks (`# Arguments:` / `#   $N — name` / default `# Returns`). Kept 27 blocks as load-bearing: OS-cascade ordering for service management, config-merge safety rationale, AWK-injection escape vector, bash 4.1 indirect-expansion compat notes, FHS symlink-farm backward-compat. Also corrected an inherited stale `1.0.8` version string in the file docstring header. Tests 502/502 × 3 OSes.

### alert_lib v1.0.6 → v1.0.7 (commit `f031620`)
All 32 banners removed. All 28 multi-line headers preserved — every one carried load-bearing content: CVE refs, CR/LF header injection protection, bash 5.2 `&` backreference compat, `chmod 600` token-from-ps hardening, flock-based digest concurrency, out-parameter contracts (`_ALERT_CHANNEL_IDX`, `_ALERT_TPL_RESOLVED`). Tests 260/260 × 3 OSes.

### geoip_lib v1.0.6 → v1.0.7 (commit `d9ef7dd`)
Biggest density drop (27.8% → 17.5%). Removed 56 banners plus 43 `# Args:` / `# Returns:` / `# Prints:` / `# Input:` / `# Output:` restatement lines. TLS/security rationale preserved: strict-TLS default, `GEOIP_TLS_INSECURE` legacy escape hatch, curl/wget preference logic, mawk-compat explainers, IPv6 lookup complexity notes. Out-parameter contracts preserved as one-line `# Sets _GEOIP_<var>` comments (restored post-sentinel-review for `geoip_build_ipdb` and `geoip_build_ip6db`). Also corrected an inherited stale `1.0.5` file-header version. Tests 251/251 × 3 OSes. Pre-existing SC2016 info-level shellcheck findings on AWK bodies intentionally preserved.

### elog_lib v1.0.5 → v1.0.6 (commit `54ded9e`)
Replaced the 44-line ELOG_* configuration variable prose catalogue at `elog_lib.sh:34-77` with a 3-line cross-reference to `README.md § 3. Configuration`. All 33 ELOG_* variables verified present in README before deletion — single source of truth now lives in README, not duplicated in source. Also removed 26 banner separator lines. 8 remaining multi-line headers are all SIEM/CEF/GELF/ECS contract documentation (dispatch semantics, module registry, severity mapping, symlink-guard rationale). Tests 189/189 × 3 OSes.

### tlog_lib v2.0.5 → v2.0.6 (commit `7f6c3bb`)
Removed all 24 banner lines (8 in `tlog_lib.sh` + 16 in `tlog` CLI wrapper). Zero header blocks removed — every one of the 11 multi-line headers in `tlog_lib.sh` is load-bearing: `_tlog_cursor_value` / `_tlog_cursor_mode` out-parameter contracts, rotation-semantics documentation, `$jfilter` intentional-unquote invariant, return-code tables, `declare -A` source-from-function scope trap. `tlog` CLI had 1 multi-line file-level header with usage synopsis + GPL license — preserved intact. Tests 206/206 × 3 OSes.

## Why hdr_ge4 did not drop to the spec target (~15)

The spec's success criterion was `hdr_ge4` total ≤15 across all files (~90% reduction). The actual result is 86 (40% reduction). This is a **spec overshoot, not a cleanup shortfall**.

The `hdr_ge4` metric counts any run of ≥4 consecutive comment lines, regardless of whether those lines are restatement or load-bearing content. The spec assumed the dominant pattern would be signature-restatement docstrings (which it was for pkg_lib's 42-of-69 cleared blocks), but in practice most of the *other* libraries' multi-line headers turned out to be load-bearing:

- Out-parameter contracts (`# Sets _foo_out on success`)
- Security rationale (injection vectors, TLS handling, symlink guards)
- Platform/compat notes (bash 4.1, FreeBSD, CentOS 6)
- Return-code tables for non-default semantics
- OS-family cascade orderings
- Backward-compat explainers for deprecated paths

These all count toward `hdr_ge4` but must never be deleted under the rule. The engineer subagents (appropriately) preserved them — every phase's load-bearing whitelist diff returned zero deletions.

**The headline win is the 100% banner elimination (-138 lines) and the 206 restatement lines pulled out of pkg_lib.** The `hdr_ge4` reduction of 58 blocks represents real restatement cleanup, not blanket deletion.

## Reproducibility

Re-run the snapshot at any future point:
```bash
/root/admin/work/proj/rdf/canonical/scripts/comment-snapshot.sh
```
Output is deterministic; re-running produces an identical TSV given identical source files. The metrics script is committed as `rdf/canonical/scripts/comment-metrics.sh`.

## Commits (not yet pushed — pending sentinel review)

| Library | Version | Commit | Repo |
|---|---|---|---|
| pkg_lib | 1.0.9 → 1.0.10 | `229e74f` | rfxn/pkg_lib |
| alert_lib | 1.0.6 → 1.0.7 | `f031620` | rfxn/alert_lib |
| geoip_lib | 1.0.6 → 1.0.7 | `d9ef7dd` | rfxn/geoip_lib |
| elog_lib | 1.0.5 → 1.0.6 | `54ded9e` | rfxn/elog_lib |
| tlog_lib | 2.0.5 → 2.0.6 | `7f6c3bb` | rfxn/tlog_lib |

## Test Matrix Summary

All 5 libraries: full test matrix green on Debian 12 + Rocky 9 + CentOS 6 (bash 4.1 floor). Aggregate test count: 1408 tests passing (pkg_lib 502 + alert_lib 260 + geoip_lib 251 + elog_lib 189 + tlog_lib 206).
