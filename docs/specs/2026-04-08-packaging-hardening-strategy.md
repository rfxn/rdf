# Cross-Project Packaging Hardening — Strategy

**Date:** 2026-04-08
**Scope:** APF, BFD, LMD, pkg_lib
**Status:** Spec complete, Phase 0 ready for `/r-plan`

## Context

On 2026-04-07 an APF packaging hotfix cascade (`bbdf048` → `2057bca` → `07c067a` → `58b0fd6` → `b0e54f0`) exposed a class of brittleness shared across APF, BFD, and LMD RPM/DEB packaging. BFD shipped defensive cleanup (`8bbe0b7`, `912b2d7`, `a25b6ea`). LMD mirrored APF's dir-vs-symlink fix (`cde510b`, `4fe368c`). The firefighting was not five independent bugs — it was one shared test-coverage gap plus four latent architectural issues.

Full analysis lives in `HANDOFF-packaging-hardening.md` at the workspace root. This strategy doc converts that analysis into five discrete specs and a phased execution plan, with a release-impact decision for each.

## The five brittleness classes

1. **Migration-path test blindness** (all 3) — tests start from empty containers; no scenario pre-stages a source `install.sh` tree before `rpm -ivh` / `dpkg -i`. APF's dir-vs-symlink P0 survived sentinel + QA + UAT + 36/36 install tests because of this.
2. **Scriptlet phase-ordering traps** (APF) — `%pretrans` move in `2057bca` was a correctness fix, not polish. RPM locks `%config(noreplace)` dispositions before `%pre` runs; APF's `/etc/apf/` legacy path makes this load-bearing.
3. **Orphan enumeration drift** (BFD 7-list, LMD 9-list) — hardcoded directory lists in preinst/`%pre` with no coupling to `install.sh`.
4. **RPM/DEB logic divergence** (APF, BFD) — duplicated post-install scriptlets. LMD already retired this via `pkg/scripts/pkg-postinst.sh`.
5. **pkg_lib vendoring lag** — `pkg_config_merge` fix (APF `b0e54f0`) not yet vendored to BFD or LMD. **Currently active drift.**

## Current release state

| Project | Branch | PR | Tree | pkg_lib vendored | Hotfixes landed |
|---|---|---|---|---|---|
| APF | `2.0.2` | rfxn/advanced-policy-firewall#52 | clean, CI green | **1.0.9** (in-sync with master fix) | 5/5 ✓ |
| BFD | `2.0.2` | rfxn/brute-force-detection#7 | clean, CI green | 1.0.8 (**behind**) | 3/3 ✓ |
| LMD | `2.0.1` | rfxn/linux-malware-detect#478 | clean, CI green | 1.0.8 (**behind**) | 5/5 ✓ |
| pkg_lib | `master` | — | **dirty** (1.0.9 staged, uncommitted) | canonical | N/A |

BFD #7 and LMD #478 currently ship pkg_lib 1.0.8 — a version known to corrupt conditional expressions in `importconf` on upgrade. This is the single ship-blocker driving the in-tree decision below.

## Scoping decisions

### In-tree to 2.0.x PRs

**Phase 0 / Action A only.** Minimum viable fix to keep the 2.0.x release honest.

- `rfxn/pkg_lib` master: commit staged dirty state as v1.0.9, tag, push
- `rfxn/brute-force-detection#7`: vendor-sync `files/internals/pkg_lib.sh` → 1.0.9 in a single commit
- `rfxn/linux-malware-detect#478`: vendor-sync `files/internals/pkg_lib.sh` → 1.0.9 in a single commit
- `rfxn/advanced-policy-firewall#52`: **no action** — already on 1.0.9

**Rationale:** bug fix, one-file vendor bump per consumer, CI currently green on all three, zero refactor surface. Cost of deferral is shipping BFD/LMD 2.0.x with a known importconf corruption regression.

### Out-of-tree, new branches

**Phases 1–3.** None of these may touch the open 2.0.x PRs — they are refactors or test infrastructure, not bug fixes, and folding them in would delay the release for coverage or cleanup that does not affect shipped bits.

| Phase | Action | Spec | Target release | Depends on |
|---|---|---|---|---|
| 1 | B: migration-path test fixtures (all 3) | `2026-04-08-migration-path-test-fixtures.md` | 2.0.3 or 2.1.0 per project | none — can start immediately |
| 2 | D: APF/BFD postinst consolidation | `2026-04-08-postinst-script-consolidation.md` | APF 2.1.0, BFD 2.1.0 | **hard-blocked on Phase 1 green** |
| 3 | C: pkg_lib manifest-driven orphan cleanup | `2026-04-08-pkg-lib-install-manifest-primitive.md` | pkg_lib v1.0.10 → BFD/LMD 2.0.3+ | structurally independent; benefits from Phase 1 for meaningful test signal |

### Documented debt

**Phase 4 / Action E** — APF `/etc/apf/` → `/usr/local/apf/` migration. **Do not do this.** 20+ years of documentation, blog posts, Stack Overflow answers, and sysadmin muscle memory reference `/etc/apf/conf.apf`. The breaking-change cost outweighs the architectural cleanliness.

The `%pretrans` requirement, conffile-scan interaction, and full wipe-and-restore migration strategy are all consequences of the path choice. Future APF maintainers need to understand the hazard is paid for by the path, not by bad engineering.

**Action:** add a note to `advanced-policy-firewall/CLAUDE.md` or a permanent entry in APF's project memory explaining *why* APF's packaging is more elaborate than BFD's and LMD's. One-paragraph memory entry, no spec, no plan, no commit.

## Dependency chain

```
Phase 0 (in-tree, urgent)
  ├── pkg_lib v1.0.9 release
  ├── BFD #7 vendor sync
  └── LMD #478 vendor sync
         │
         │  (release ships)
         ▼
Phase 1 (out-of-tree)                    Phase 3 (out-of-tree)
  migration-path fixtures                  pkg_lib v1.0.10 primitive
  3 parallel per-project plans             + BFD/LMD integration
         │                                          │
         │  (green on APF+BFD)                      │
         ▼                                          │
Phase 2 (out-of-tree)                               │
  APF + BFD postinst consolidation   ◄──────────────┘
  (hard dependency on Phase 1)         (benefits from Phase 1 test signal)
```

Phase 1 unblocks Phase 2. Phase 3 is independent structurally but should not land before Phase 1 because its acceptance criteria will be shaky without migration test coverage.

## Spec inventory

| File | Phase | Action | Scope |
|---|---|---|---|
| `2026-04-08-packaging-hardening-strategy.md` | — | umbrella | this doc |
| `2026-04-08-pkg-lib-1.0.9-vendor-fanout.md` | 0 | A | pkg_lib release + BFD/LMD in-tree vendor sync |
| `2026-04-08-migration-path-test-fixtures.md` | 1 | B | shared helper design + per-project fixture suites |
| `2026-04-08-postinst-script-consolidation.md` | 2 | D | LMD pattern fanout to APF and BFD |
| `2026-04-08-pkg-lib-install-manifest-primitive.md` | 3 | C | new pkg_lib primitives + BFD/LMD integration |

## Plan kick-off

Only Phase 0 has an accompanying plan as of this spec. The plan file is at:

- `rdf/docs/plans/2026-04-08-pkg-lib-1.0.9-vendor-fanout.md`

Phases 1–3 will each get their own `/r-plan` cycle after the 2.0.x release ships. They are scoped independently enough that they can be picked up in any order, subject to the Phase 2 → Phase 1 dependency.

## Verification gates

- **Phase 0 in-tree commits must not change CI status** — BFD #7 and LMD #478 are currently green. Any regression is a hard abort.
- **Each consumer's config-merge regression test must run** — BFD and LMD must have `tests/09-config.bats` or equivalent covering `pkg_config_merge` conditional-expression passthrough. If the test does not exist in the consumer (it's new in pkg_lib v1.0.9), the vendor sync commit must include a minimal smoke test that exercises importconf on a conditional-heavy fixture.
- **Phase 0 may not be squashed across projects** — one commit per project (pkg_lib, BFD, LMD), one commit per branch, preserving the release cadence discipline from parent CLAUDE.md §Commit Protocol.

## Out of scope for this strategy

- Any changes to `/etc/apf/` path choice (Phase 4, documented debt)
- Folding Phase 3's pkg_lib v1.0.10 primitives into the v1.0.9 release (explicitly rejected to keep v1.0.9 unblocked)
- Refactoring LMD's `pkg-postinst.sh` reference implementation (Phase 2 targets APF and BFD only)
- Broader batsman enhancements beyond the Phase 1 helper (per-project helpers first, promote later)

## References

- `HANDOFF-packaging-hardening.md` — full analysis and file/line citations
- `linux-malware-detect/pkg/scripts/pkg-postinst.sh` lines 48-146 — Phase 2 reference implementation
- `pkg_lib/files/pkg_lib.sh` — canonical location of Phase 3 primitives
- APF commit `b0e54f0`, `2057bca`, `07c067a`, `bbdf048`, `58b0fd6` — Phase 0 reference bug fix chain
- BFD commit `8bbe0b7`, `912b2d7`, `a25b6ea` — Phase 1 BFD regression retro-target
- LMD commit `cde510b`, `4fe368c` — Phase 1 LMD regression retro-target
