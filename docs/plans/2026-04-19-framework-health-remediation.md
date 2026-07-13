# Implementation Plan: RDF Framework Health Remediation

**Goal:** Eliminate /r-start hangs, stop unbounded file growth, close dogfooding gaps (tests/CI/gitattributes), and remove structural slop identified in the 2026-04-19 framework audit.

**Architecture:** 10 independent-ish fixes grouped into four tracks. Track A (perf/correctness) covers path discovery and timeouts — highest user-visible impact. Track B (hygiene) handles rotation, stale artifacts, packaging. Track C (adapter correctness) fixes `rdf doctor` false-OK and consolidates duplicate canonical content. Track D (dogfooding) adds CI and BATS adapter tests. A final regenerate phase verifies zero drift before push.

**Tech Stack:** Bash 4.1+ (CentOS 6 floor), markdown (canonical content), BATS (via batsman submodule pattern), GitHub Actions YAML. All edits respect the `command` prefix / `set -euo pipefail` / double-quote conventions from project CLAUDE.md.

**Spec:** N/A — remediation derived from audit findings in conversation 2026-04-19. Spec-less is acceptable because design decisions are straightforward (timeout values, rotation thresholds) and already agreed with user. If any phase hits a design ambiguity, stop and create a spec.

**Phases:** 11 (10 remediations + 1 regenerate/verify capstone)

**Timeout convention:** All git, python3, and fs-walk external calls in state scripts get `timeout 30` guards with `|| echo "<fallback>"` safe defaults. Rationale: healthy ops complete in milliseconds; 30s is wide enough to tolerate slow disks / cold cache / TLS handshake but narrow enough that a hang fails fast to the fallback rather than stalling session startup for minutes.

## Conventions

**Commit message format:** Free-form descriptive (RDF convention — no version prefix). Tag body lines:
```
Harden /r-start path discovery and rdf-state.sh timeouts

[Fix] deploy rdf-state.sh via generator so /r-start resolves it without find /
[New] 30s timeout guards on all git calls in rdf-state.sh
[Change] fall through to inline git fallback when canonical path missing
```

**Staging:** Stage files explicitly by name. Never `git add -A` or `git add .`. Force-add with `-f` only if `.git/info/exclude` blocks a genuinely committable file (docs/, canonical/, state/ are always committable).

**CHANGELOG / CHANGELOG.RELEASE:** Update on every code-changing commit per project rules. Phases that only touch canonical markdown or new files still count as code-changing for RDF.

## File Map

### New Files
| File | Lines | Purpose |
|------|-------|---------|
| `canonical/reference/progress-tracking.md` | ~40 | Extracted shared "Progress Tracking" block used by r-init/r-start/r-save |
| `state/rotate-work-output.sh` | ~80 | Age-based rotation for .rdf/work-output/ and agent-feed.log |
| `.gitattributes` | ~20 | `export-ignore` rules for release tarball exclusion |
| `.github/workflows/ci.yml` | ~50 | bash -n + shellcheck + rdf doctor on PR and push |
| `tests/adapter.bats` | ~60 | BATS: canonical → deployed round-trip verification |
| `tests/Makefile` | ~15 | `make test` entry for BATS execution |
| `docs/plans/2026-04-19-framework-health-remediation.md` | — | Committed copy of this plan |

### Modified Files
| File | Changes |
|------|---------|
| `canonical/commands/r-start.md` | Remove `find /` fallback risk; resolve `{RDF_HOME}` via explicit probe order; short-circuit to inline git fallback on miss |
| `state/rdf-state.sh` | Add `timeout 30` to 9 git calls (lines 76, 83, 86, 88, 94, 96, 98, 100, 104); guard python3 parser fallback |
| `state/context-audit.sh` | Add `timeout 30` to git-per-repo loop (line 232); guard python3 blocks (lines 211, 322); cap find-walk depth sanely; extract shared `_count_md_files` helper |
| `lib/cmd/generate.sh` | Deploy `state/rdf-state.sh` to `~/.rdf/state/rdf-state.sh` (not just the canonical adapters); same for `state/context-audit.sh` |
| `lib/cmd/doctor.sh` | Replace file-count drift check with per-file SHA or diff; FAIL (not OK) when canonical content differs from deployed |
| `canonical/commands/r-init.md` | Replace inline Progress Tracking block with reference link |
| `canonical/commands/r-start.md` | Same (on top of path-discovery changes) |
| `canonical/commands/r-save.md` | Same |
| `CHANGELOG` | Entries per commit |
| `CHANGELOG.RELEASE` | Entries per commit |

### Deleted Files
| File | Reason |
|------|--------|
| `/root/admin/work/proj/advanced-policy-firewall/.rdf/work-output/full-branch-diff.patch` | 521 KB, 34 days old, stale |
| `/root/admin/work/proj/s3perf/.rdf/memory/PLAN-tier0-909cbaa-239722c.md` | 60 KB plan misfiled under `memory/`; move to `docs/plans/` in target project or delete |
| `/root/admin/work/proj/rdf/.pytest_cache/` | RDF has no Python tests; stale artifact |
| `/root/admin/work/proj/rdf/canonical/reference/session-safety.md` | Unreferenced by any command/agent; confirm via grep, then delete |
| `/root/admin/work/proj/rdf/docs/superpowers/` | Unreferenced experimental branch from 2026-03-19 |

## Phase Dependencies

Phases 1–10 are **independently applicable** to the source tree. Phase 11 is a **serial capstone** that must run after all canonical or state-script changes land.

- Phase 1 (path discovery) is highest-value — land first so subsequent `/r-start` invocations during build don't hang.
- Phase 2 (rdf-state.sh timeouts) and Phase 3 (context-audit.sh timeouts) are sibling phases — can land in either order.
- Phases 4–10 are mutually independent.
- Phase 11 regenerates adapter output and verifies `rdf doctor` reports zero drift. MUST run last.

All phases: `mode: serial-context`. No worktree parallelism needed — changes are small and file overlap between phases is minimal but non-zero (e.g., Phase 1 and Phase 9 both touch `canonical/commands/r-start.md`).

---

### Phase 1: Fix /r-start path discovery and eliminate `find /` fallback

**Root cause recap:** `r-start.md:32` prescribes `bash state/rdf-state.sh --full .` with a relative path from CWD. The script exists only at `/root/admin/work/proj/rdf/state/rdf-state.sh`. When `/r-start` runs from any other project, the relative path fails, the documented `{RDF_HOME}/state/rdf-state.sh` fallback references an undefined var, and the agent degrades to `find / -name rdf-state.sh` which hits the 120s Bash sandbox timeout.

**Files:**
- Modify: `canonical/commands/r-start.md` (path resolution logic)
- Modify: `lib/cmd/generate.sh` (deploy state scripts to `~/.rdf/state/`)

- **Mode**: serial-context
- **Accept**: `/r-start` resolves `rdf-state.sh` in under 1 second from any project directory. `r-start.md` contains an explicit probe order: `~/.rdf/state/rdf-state.sh` → `/root/admin/work/proj/rdf/state/rdf-state.sh` → inline git fallback. The string `find /` does not appear in the command file. `lib/cmd/generate.sh` writes `rdf-state.sh` and `context-audit.sh` to `~/.rdf/state/` on `rdf generate claude-code`.
- **Test**:
  - `grep -c 'find /' canonical/commands/r-start.md` returns 0
  - `grep -c '~/.rdf/state/rdf-state.sh' canonical/commands/r-start.md` returns >= 1
  - After `rdf generate claude-code`: `ls -l ~/.rdf/state/rdf-state.sh` exists and is executable
  - Time `/r-start` from a non-rdf project: completes without hitting the 10+ minute hang
- **Edge cases**: Fresh install with no `~/.rdf/` — generator must create it. User deleted `~/.rdf/state/` — `/r-start` falls through to the canonical path, then inline git fallback. Non-RFXN workspace where canonical path doesn't exist — inline fallback triggers cleanly.

- [ ] **Step 1:** Update `canonical/commands/r-start.md` section "Gather State" — replace the current path-resolution prose with an explicit probe list and a hard "do not use `find`" constraint.
- [ ] **Step 2:** Update `lib/cmd/generate.sh` to copy `state/rdf-state.sh` and `state/context-audit.sh` to `~/.rdf/state/` during `claude-code` generation. Ensure executable bit.
- [ ] **Step 3:** Regenerate locally (`bin/rdf generate claude-code`) and verify `~/.rdf/state/rdf-state.sh` exists and is executable.
- [ ] **Step 4:** Manual test — invoke `/r-start` from an APF or LMD checkout; confirm state loads in under 5 seconds.
- [ ] **Step 5:** Commit.

---

### Phase 2: Add 30s timeouts to git calls in rdf-state.sh

Nine git invocations (lines 76, 83, 86, 88, 94, 96, 98, 100, 104) currently have no timeout. On a broken upstream (`HEAD...@{u}` with orphaned tracking branch), on a locked repo (`.git/index.lock`), or on a slow remote, any of these can stall indefinitely. The `2>/dev/null || echo "0"` silences errors but does not prevent hangs.

**Files:**
- Modify: `state/rdf-state.sh` (wrap git calls in `timeout 30`)

- **Mode**: serial-context
- **Accept**: All `git -C "$_project_path" <subcmd>` invocations in `rdf-state.sh` are wrapped in `timeout 30 git -C …`. Script still passes `bash -n` and `shellcheck`. Direct invocation (`bash state/rdf-state.sh --full .`) returns valid JSON in under 2 seconds on the RDF repo.
- **Test**:
  - `grep -c 'timeout 30 git ' state/rdf-state.sh` returns >= 9
  - `grep -cE '^\s*[_a-zA-Z]*=\"?\$\(git ' state/rdf-state.sh | grep -v 'timeout'` — zero bare-git assignments
  - `bash -n state/rdf-state.sh` passes
  - `shellcheck state/rdf-state.sh` passes (existing warnings acceptable; no new ones)
  - `time bash state/rdf-state.sh --full .` completes under 2s
  - Stress test: in a scratch repo with a broken upstream (`git remote set-url origin /tmp/nonexistent`), confirm rdf-state.sh completes in 30s max (not hang)
- **Edge cases**: Timeout binary missing on some minimal distros (coreutils-9+ has it everywhere in target OS matrix per CLAUDE.md — confirm CentOS 6 baseline). If `timeout` missing, script should still function but without guard — add a `command -v timeout` check early and set a `TIMEOUT_PREFIX` variable accordingly.

- [ ] **Step 1:** Add a `TIMEOUT_PREFIX` variable at the top of `rdf-state.sh` — set to `timeout 30` if `command -v timeout` succeeds, empty otherwise.
- [ ] **Step 2:** Wrap all 9 git calls with `$TIMEOUT_PREFIX git -C …`. Preserve existing `2>/dev/null || echo "…"` fallbacks.
- [ ] **Step 3:** Run `bash -n`, `shellcheck`, and a live invocation. Verify JSON output shape unchanged.
- [ ] **Step 4:** Commit.

---

### Phase 3: Add timeouts and guards to context-audit.sh

Same treatment for `context-audit.sh`, plus guards on python3 blocks and bounded find-walks. The per-repo loop at line 230-234 is the biggest risk: one corrupt repo's `git log` can stall the entire audit.

**Files:**
- Modify: `state/context-audit.sh`

- **Mode**: serial-context
- **Accept**: Git call in per-repo loop wrapped in `timeout 30`. Both python3 blocks (lines 211, 322) wrapped in `timeout 30` with error fallback. Find calls retain existing `-maxdepth` bounds (no change needed — they're already bounded). A helper function `_count_md_files()` replaces the 8 near-duplicate `command find … -name "*.md" ! -type d | wc -l` patterns.
- **Test**:
  - `grep -c 'timeout 30 git ' state/context-audit.sh` returns >= 1
  - `grep -c 'timeout 30 python3' state/context-audit.sh` returns >= 2
  - `bash -n` and `shellcheck` pass
  - Direct invocation completes in under 10s on RDF checkout
- **Edge cases**: python3 not installed — existing `command -v python3` guards handle this; adding timeout does not regress that path.

- [x] **Step 1:** Wrap git log in the per-repo loop (line 232) with `timeout 30`.
- [x] **Step 2:** Wrap both python3 invocations (lines 211-226, 322) with `timeout 30` and graceful fallback.
- [x] **Step 3:** Extract the repeating `command find … -name "*.md" ! -type d 2>/dev/null | wc -l` pattern into a helper function. Replace 8 call sites.
- [x] **Step 4:** `bash -n`, `shellcheck`, live invocation. Commit.

---

### Phase 4: Work-output rotation

`work-output/` directories in per-project `.rdf/` accumulate unboundedly (LMD has 236 files, BFD 178, etc.). `agent-feed.log` files grow past 290 KB without rotation. Adopt age-based pruning for files and size-based truncation for the event log.

**Files:**
- New: `state/rotate-work-output.sh`
- Modify: `lib/cmd/generate.sh` (install the rotator; wire a cron hint or manual-invocation doc)

- **Mode**: serial-context
- **Accept**:
  - `state/rotate-work-output.sh <project-root>` exists, executable, with `set -euo pipefail` and `command` prefix conventions.
  - Behavior: deletes `<project>/.rdf/work-output/*.md` files with mtime > 14 days and no reference in active PLAN.md. Truncates `<project>/.rdf/work-output/agent-feed.log` to last 1000 lines if size > 100 KB. Same treatment for `/root/admin/work/proj/.rdf/agent-feed.log` and `~/.rdf/work-output/` if present.
  - Dry-run mode: `--dry-run` prints what would change without modifying anything.
  - Generator deploys the rotator alongside `rdf-state.sh` to `~/.rdf/state/`.
- **Test**:
  - `bash -n state/rotate-work-output.sh` passes
  - `shellcheck` passes
  - `./state/rotate-work-output.sh --dry-run /root/admin/work/proj/linux-malware-detect` lists expected stale files without modifying
  - After live run: LMD work-output count drops, agent-feed.log stays under 100 KB
- **Edge cases**: No `.rdf/work-output/` directory exists — exit cleanly. Active PLAN.md references a file that's >14 days old — preserve (parse PLAN.md for referenced filenames before deletion).

- [ ] **Step 1:** Write `state/rotate-work-output.sh` with dry-run, size-threshold, age-threshold parameters (defaults hardcoded per spec above).
- [ ] **Step 2:** Update `lib/cmd/generate.sh` to deploy it to `~/.rdf/state/`.
- [ ] **Step 3:** Document manual invocation in `canonical/reference/` (or add a `/r-util-work-rotate` command — deferred; document for now).
- [ ] **Step 4:** Commit.

---

### Phase 5: Clean stale artifacts across projects

One-shot cleanup of specific stale files identified in the audit. This is separate from Phase 4 (automation) — Phase 4 prevents recurrence, Phase 5 deals with the backlog.

**Files:**
- Delete: `/root/admin/work/proj/advanced-policy-firewall/.rdf/work-output/full-branch-diff.patch` (521 KB)
- Delete or relocate: `/root/admin/work/proj/s3perf/.rdf/memory/PLAN-tier0-909cbaa-239722c.md` (60 KB — misplaced plan)
- Delete: `/root/admin/work/proj/rdf/.pytest_cache/`
- Delete: `/root/admin/work/proj/rdf/canonical/reference/session-safety.md` (verify unreferenced first)
- Delete: `/root/admin/work/proj/rdf/docs/superpowers/` (verify unreferenced first)
- Run `state/rotate-work-output.sh` once against each project with >100 files in work-output/.

- **Mode**: serial-context
- **Accept**: Each deletion verified (file no longer exists). Before deleting `session-safety.md` and `docs/superpowers/`, grep confirms zero incoming references in `canonical/`, `docs/`, `README.md`, or `lib/`. Work-output counts for LMD/BFD/sigforge/APF drop substantially.
- **Test**:
  - `grep -r 'session-safety' /root/admin/work/proj/rdf/{canonical,docs,README.md,lib} 2>/dev/null | wc -l` returns 0 before deletion
  - `grep -r 'superpowers' /root/admin/work/proj/rdf/{canonical,docs,README.md} 2>/dev/null | wc -l` returns 0 before deletion
  - Post-deletion: `ls` confirms files/dirs gone
  - Post-rotation: `find <project>/.rdf/work-output -name "*.md" | wc -l` dropped significantly for LMD, BFD, sigforge, APF
- **Edge cases**: `session-safety.md` turns out to be referenced — keep it and flag for Phase 9 or later. `docs/superpowers/` referenced — same.

- [ ] **Step 1:** Grep-verify `session-safety.md` and `docs/superpowers/` unreferenced.
- [ ] **Step 2:** Delete the specific files (use `/usr/bin/rm` per Bash-tool convention).
- [ ] **Step 3:** Run rotation script against LMD, BFD, sigforge, APF, and any other project with >100 work-output files.
- [ ] **Step 4:** Commit deletion of RDF-tree files (pytest_cache, session-safety, superpowers). Non-RDF-tree deletions do not produce an RDF commit.

---

### Phase 6: Add .gitattributes with export-ignore

RFXN CLAUDE.md mandates `.gitattributes` with `export-ignore` for release tarballs. RDF has none — release tarballs would ship `docs/`, `assets/`, archived plans, CLAUDE.md, PLAN.md, etc.

**Files:**
- New: `.gitattributes`

- **Mode**: serial-context
- **Accept**: `.gitattributes` at repo root contains `export-ignore` rules for `docs/`, `assets/`, `tests/`, `.github/`, `CLAUDE.md`, `PLAN.md`, `MEMORY.md`, `AUDIT.md`, `.pytest_cache/`, `.claude/`, `.rdf/`, `docs/plans/archived/`, `docs/superpowers/` (if still present). Also excludes working files per `.git/info/exclude`.
- **Test**:
  - `git check-attr export-ignore docs/README.md` reports set
  - `git archive --format=tar HEAD | tar -tvf - | grep -c docs/` returns 0 (after commit)
  - `git archive --format=tar HEAD | tar -tvf - | grep -c canonical/` returns >= 1 (canonical still shipped)
- **Edge cases**: N/A

- [ ] **Step 1:** Draft `.gitattributes` mirroring workspace CLAUDE.md spec. Cross-reference `.git/info/exclude` to catch any project-specific working files.
- [ ] **Step 2:** Verify with `git check-attr` and `git archive` dry-run.
- [ ] **Step 3:** Commit.

---

### Phase 7: Fix `rdf doctor` false-OK on content drift

Audit confirms: all 6 canonical agents differ from deployed copies, but `rdf doctor` reports OK because it counts files, not diffs content. This gives false confidence and lets drift ship.

**Files:**
- Modify: `lib/cmd/doctor.sh`

- **Mode**: serial-context
- **Accept**: `rdf doctor` computes a per-file hash (or runs `diff -q`) between canonical source and deployed output for commands, agents, scripts. Reports FAIL with specific file names when content differs — not OK. Existing file-count check retained as complementary (catches missing files).
- **Test**:
  - With current drifted state: `bin/rdf doctor` reports FAIL on 6 agent mismatches
  - After `rdf generate claude-code`: `bin/rdf doctor` reports OK on content
  - `bash -n` and `shellcheck` on modified script
- **Edge cases**: Canonical file has frontmatter-free markdown; deployed file has frontmatter added by adapter. Diff must compare the *post-frontmatter-strip* body OR the adapter must emit a canonical-hash sidecar the doctor can consult. Go with sidecar approach (simpler): generator writes `.rdf-hash` next to each deployed file, doctor compares canonical body hash to deployed `.rdf-hash`.

- [ ] **Step 1:** Read existing `doctor.sh` to understand current check structure.
- [ ] **Step 2:** Modify generator (in `lib/cmd/generate.sh`) to emit a `.rdf-hash` file next to each deployed markdown file containing the SHA of the canonical body (frontmatter-free).
- [ ] **Step 3:** Modify `doctor.sh` to compute the canonical body hash on the fly and compare to `.rdf-hash`. FAIL with file path on mismatch.
- [ ] **Step 4:** Regenerate, verify doctor reports OK; manually corrupt a deployed file, verify doctor reports FAIL.
- [ ] **Step 5:** Commit.

---

### Phase 8: Extract shared Progress Tracking block

The `## Progress Tracking` section (~30 lines describing TaskCreate conditional behavior) appears verbatim in `r-init.md`, `r-start.md`, and `r-save.md`. Extract to a single reference file and link from each command.

**Files:**
- New: `canonical/reference/progress-tracking.md`
- Modify: `canonical/commands/r-init.md`, `canonical/commands/r-start.md`, `canonical/commands/r-save.md`

- **Mode**: serial-context
- **Accept**: `canonical/reference/progress-tracking.md` contains the canonical Progress Tracking text. Each of the three commands replaces its inline block with a link (e.g., "See `reference/progress-tracking.md`"). Total canonical content reduced by approximately 60 lines.
- **Test**:
  - `grep -l '## Progress Tracking' canonical/commands/*.md` returns zero files (block removed from commands)
  - `canonical/reference/progress-tracking.md` exists and contains the TaskCreate conditional logic
  - Each of r-init.md, r-start.md, r-save.md contains a reference link to the new file
  - After `rdf generate claude-code`: deployed commands in `/root/.claude/commands/` still render the Progress Tracking guidance (adapter inlines references or preserves links — decide based on existing adapter behavior; if adapter does not inline, leave the reference link deployed)
- **Edge cases**: The three blocks are not byte-identical across commands — they have minor phrasing differences. Reconcile: pick the most complete version as the canonical reference; if differences are meaningful (e.g., r-start adds "before the dashboard"), preserve those as command-specific notes alongside the reference link.

- [ ] **Step 1:** Diff the three Progress Tracking blocks. Identify the superset and any command-specific clauses.
- [ ] **Step 2:** Write `canonical/reference/progress-tracking.md` with the superset text.
- [ ] **Step 3:** Replace each command's block with a reference link plus any command-specific clause.
- [ ] **Step 4:** Regenerate; spot-check deployed output.
- [ ] **Step 5:** Commit.

---

### Phase 9: Add CI workflow

No `.github/workflows/` exists. Add a minimal CI that runs on PR and push: `bash -n` + `shellcheck` on shell files, `bin/rdf doctor` (now strict after Phase 7), and BATS tests (added in Phase 10).

**Files:**
- New: `.github/workflows/ci.yml`

- **Mode**: serial-context
- **Accept**: Workflow triggers on pull_request and push to main. Jobs: `lint` (bash -n + shellcheck on `state/`, `lib/`, `bin/`, `canonical/scripts/`), `doctor` (runs `bin/rdf doctor`), `tests` (runs `make -C tests test` if tests/ exists — Phase 10 dependency). CI passes on current HEAD (once phases 1-8 land).
- **Test**:
  - `.github/workflows/ci.yml` valid YAML (`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` succeeds)
  - Optional: trigger CI via a dummy push to a feature branch, confirm jobs run
- **Edge cases**: Tests/ directory doesn't exist yet at time of Phase 9 commit — make the `tests` job conditional on `tests/Makefile` existence, or land Phase 10 before Phase 9.

- [ ] **Step 1:** Write `.github/workflows/ci.yml` with lint + doctor jobs (tests job stubbed, enabled after Phase 10).
- [ ] **Step 2:** Validate YAML locally.
- [ ] **Step 3:** Commit.

---

### Phase 10: BATS adapter tests

RDF's core value is the canonical → deployed adapter. It has zero test coverage. Add a minimal BATS suite that exercises `rdf generate claude-code` on a fixture canonical tree and asserts the expected output shape.

**Files:**
- New: `tests/Makefile`
- New: `tests/adapter.bats`
- New: `tests/fixtures/canonical/commands/r-example.md` (minimal canonical command)
- New: `tests/fixtures/canonical/agents/example.md` (minimal canonical agent)

- **Mode**: serial-context
- **Accept**: `make -C tests test` runs BATS; all tests pass. Coverage includes: (a) generator produces expected file tree under target dir, (b) frontmatter added correctly to deployed commands, (c) canonical body preserved in deployed output, (d) `.rdf-hash` sidecar created (from Phase 7), (e) re-running generator is idempotent.
- **Test**:
  - `make -C tests test` exits 0
  - BATS output shows >= 5 `ok` lines
  - Tests are hermetic (use `mktemp -d` for target, clean up on exit)
- **Edge cases**: batsman submodule not yet added to RDF — decide: (1) add batsman as submodule (consistent with APF/LMD/BFD pattern), or (2) use system `bats` binary if installed. Prefer (1) for consistency. If adding batsman submodule is out of scope, stub this phase with a shell-based test runner (`tests/test-adapter.sh`) and document the upgrade path.

- [ ] **Step 1:** Decide batsman submodule vs standalone. Document decision in plan comment.
- [ ] **Step 2:** Write `tests/adapter.bats` covering the 5 acceptance criteria.
- [ ] **Step 3:** Write `tests/Makefile` with `test:` target that invokes BATS with correct PATH.
- [ ] **Step 4:** Create minimal fixture canonical files under `tests/fixtures/canonical/`.
- [ ] **Step 5:** Run locally; confirm pass. Commit.
- [ ] **Step 6:** Enable the `tests` job in `.github/workflows/ci.yml` (Phase 9 follow-up).

---

### Phase 11: Regenerate, verify, push (capstone)

After all canonical and state-script changes land, regenerate deployed output and verify zero drift before push.

**Files:**
- No direct edits. Operational phase only.

- **Mode**: serial-context
- **Accept**:
  - `bin/rdf generate claude-code` runs clean
  - `bin/rdf doctor` reports zero FAIL (some WARN acceptable if pre-existing)
  - `git status` shows only expected modified/new files (no drift)
  - Commit list matches plan phases 1-10
  - CHANGELOG and CHANGELOG.RELEASE updated with consolidated entry for the remediation series
- **Test**:
  - `bin/rdf doctor` output captured; zero FAIL
  - `/r-start` from a non-rdf project completes in under 5 seconds
- **Edge cases**: Regeneration introduces unexpected diffs (generator bug) — stop, investigate, fix the generator before push.

- [ ] **Step 1:** Run `bin/rdf generate claude-code`.
- [ ] **Step 2:** Run `bin/rdf doctor --all`. Capture output.
- [ ] **Step 3:** Verify `git status` is clean relative to plan.
- [ ] **Step 4:** Update CHANGELOG and CHANGELOG.RELEASE with a consolidated 3.0.5 remediation entry.
- [ ] **Step 5:** Final commit + push.

---

## Success Criteria (end-to-end)

- `/r-start` from any project completes in under 5 seconds (no `find /` fallback)
- All git calls in `rdf-state.sh` and `context-audit.sh` bounded by 30s timeout
- `.rdf/work-output/` stays under 100 files per project; agent-feed.log stays under 100 KB
- `rdf doctor` FAILs on content drift (no more false-OK)
- Release tarball (`git archive`) ships only intended files
- CI runs on every PR (lint + doctor + adapter tests)
- BATS suite exercises the adapter round-trip
