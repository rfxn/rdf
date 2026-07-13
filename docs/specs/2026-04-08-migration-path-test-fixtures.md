# Migration-Path Test Fixtures — APF / BFD / LMD

> Cross-project design spec for Phase 1 (Action B) of the packaging hardening
> initiative. Parent strategy doc: `2026-04-08-packaging-hardening-strategy.md`.
> Source analysis: `/root/admin/work/proj/HANDOFF-packaging-hardening.md` (lines
> 90-115, plus Architecture baseline lines 17-41).

---

## 1. Problem Statement

Packaging test fixtures for APF, BFD, and LMD start every run from an empty
container. A clean `rpm -ivh` or `dpkg -i` exercises the **fresh install**
code path only — it cannot exercise the **migration-from-source-install**
code path, because no legacy tree exists to migrate from.

This is a structural blind spot, not a coverage oversight. APF's `/etc/apf/doc`
dir-vs-symlink P0 (commit `bbdf048`) survived sentinel review, QA, UAT, and
36/36 packaging install tests for exactly this reason: every test container was
empty when `rpm -ivh` ran, so the `%pretrans` collision between an existing
real directory and a new symlink could not manifest. LMD mirrored the same
class of fix defensively in `cde510b` (9-dir conflict detection). BFD shipped
its own variant in `8bbe0b7` (real-file sentinel discriminator on
`internals/bfd.lib.sh`). Three projects, one test blindness class.

**Goal:** make migration-from-`install.sh` a first-class packaging test
scenario. The next dir-vs-symlink P0 should fail in CI, not production.

---

## 2. Current State

All three projects ship a `pkg/test/test-pkg-install.sh` verifier and a
`pkg/docker/Dockerfile.test-{rpm,deb}` harness. The harness is driven from
`pkg/Makefile` targets `test-rpm-rocky9` / `test-deb-debian12`.

### 2.1 Reference call sites

| Project | Verifier | Harness (RPM) | Makefile target |
|---|---|---|---|
| APF | `advanced-policy-firewall/pkg/test/test-pkg-install.sh` | `pkg/docker/Dockerfile.test-rpm` lines 1-22 | `test-rpm-rocky9` — `pkg/Makefile` lines 104-108 |
| BFD | `brute-force-detection/pkg/test/test-pkg-install.sh` | `pkg/test/Dockerfile.test-rpm-rocky9` | (same shape in `pkg/Makefile`) |
| LMD | `linux-malware-detect/pkg/test/test-pkg-install.sh` | `pkg/docker/Dockerfile.test-rpm` | (same shape in `pkg/Makefile`) |

### 2.2 Current flow (pattern — APF, lines from `pkg/docker/Dockerfile.test-rpm`)

```dockerfile
FROM rockylinux:9
RUN dnf install -y ... && dnf clean all
COPY apf-*el9*.rpm /tmp/
COPY test-pkg-install.sh /test/test-pkg-install.sh
RUN rpm -ivh /tmp/apf-*el9*.rpm      # <-- empty container, no prior install
CMD ["/test/test-pkg-install.sh", "rpm"]
```

At no point does the harness populate `/etc/apf/` (APF), `/usr/local/bfd/`
(BFD), or `/usr/local/maldetect/` (LMD) with a prior source-install tree
before `rpm -ivh` runs. The verifier only asserts **post-install end-state**,
not **migration behavior**.

### 2.3 Why the existing BATS suites do not cover this

The main BATS suites (`tests/*.bats`) exercise runtime behavior against a
fresh `install.sh` target inside a Docker container. They do not load an RPM
or DEB package. The gap is specific to `pkg/test/` — the packaging-install
path, not the runtime-behavior path.

---

## 3. Design — Shared Fixture Helper

### 3.1 Decision: per-project first, promote to batsman later

**Location:** each project owns its fixture helper under
`<project>/pkg/test/helpers/` (new subdirectory). Do **not** land in batsman
for the first iteration.

Rationale:
1. Batsman v1.4.2 was released recently. Adding a packaging-test primitive now
   means a coordinated version bump + consumer pin bump across four repos for
   a capability that has not yet been exercised in anger.
2. The fixture content (source-install tree) is intrinsically per-project —
   batsman cannot own the legacy path layout of APF or the 9-dir LMD tree.
   Only the *invocation convention* is shareable, and that convention is a
   single bash function plus a tarball loader.
3. Per-project helpers land today. A shared batsman promotion can be done
   later without blocking this phase.

Promotion criterion (out of scope for this spec): once all three projects
have the helper in place and one round of fixture-regeneration has been
exercised, extract the common shape to `batsman/lib/pkg-fixtures.sh` and
vendor down.

**Batsman sanity check (performed):** `batsman/lib/` contains only
`run-tests-core.sh` and `uat-helpers.bash` — no existing packaging-test
helper surface to extend, confirming there is no sunk convention to match.

### 3.2 Helper surface (per project)

New file: `<project>/pkg/test/helpers/pre-stage-source-install.sh`

```
pre_stage_source_install <legacy_path>
```

Contract:
- Populates `<legacy_path>` with a representative source-install tree (real
  files, not symlinks; real subdirectories).
- Idempotent — safe to call twice (second call overwrites cleanly).
- Must not depend on host network access, package managers, or `install.sh`.
- Exits non-zero with a clear error if the fixture tarball is missing.

The helper is sourced by Dockerfile.test-* harnesses before the
`rpm -ivh` / `dpkg -i` invocation.

### 3.3 Decision: frozen tarball fixture (not live install.sh)

**Chosen:** each project commits a frozen minimal fixture tarball under
`<project>/pkg/test/fixtures/source-install-<project>.tar.gz`, regenerated by
an explicit `make` target when `install.sh` changes.

Rationale:
- **Deterministic.** A fixture tarball has a known content hash; a live
  `install.sh --test-mode` invocation can hit network resources (GeoIP
  download, sig update, `update-ipcountry.sh`) and produce a different tree
  on every run.
- **Fast.** Docker build context stays small (<1MB budget); fixture unpack is
  sub-second.
- **Side-effect-free.** Live `install.sh` seeds cron, writes to
  `/etc/cron.d/`, touches `/var/log/`, and (for APF) invokes iptables. None
  of that belongs in a fixture population step.
- **Versioned alongside code.** A regression on the migration path produces
  a diff against the committed fixture — the review surface is visible.

Drawbacks accepted:
- **Drift.** When `install.sh` changes the set of files/directories it
  writes, the fixture must be regenerated. Mitigation: Section 3.5.
- **Representativeness.** A minimal fixture may omit files that trigger
  real-world collisions. Mitigation: Scenario 3 retro-validation
  (Section 5) is the explicit gate — if the fixture doesn't reproduce the
  pre-fix bug, the fixture is wrong and must be expanded.

### 3.4 Fixture contents (per project)

The fixture must be large enough to exercise every defensive cleanup path in
the current `%pre` / `%pretrans` / `preinst`, but small enough to stay under
the 1MB budget. Minimum population per project:

| Project | Legacy root | Fixture must contain |
|---|---|---|
| APF | `/etc/apf/` | `apf` (real file), `internals/apf.lib.sh`, `internals/apf_*.sh` (all 7 core sub-libs, real files), `internals/internals.conf`, `conf.apf`, `allow_hosts.rules`, `deny_hosts.rules`, `doc/` **real directory with at least one file** (drives `bbdf048` retro), `vnet/` dir, `log/` dir |
| BFD | `/usr/local/bfd/` | `bfd` (real file), `internals/bfd.lib.sh` (**real file, not symlink — drives `8bbe0b7` retro**), `internals/bfd_*.sh`, `internals/internals.conf`, `conf.bfd`, `rules/` dir (at least 2 rule files), `alert/`, `data/`, `tmp/`, `stats/`, `ipcountry.dat` |
| LMD | `/usr/local/maldetect/` | `maldet` (real file), `internals/lmd.lib.sh`, `internals/lmd_*.sh`, `internals/internals.conf`, `conf.maldet`, and **all 9 orphan-enum dirs (drives `cde510b` retro):** `sigs/`, `quarantine/`, `sess/`, `tmp/`, `pub/`, `clean/`, `logs/`, `cron/`, `internals/alert/` — each with at least one real file so they are not empty |

Empty directories do **not** exercise dir-vs-symlink collision logic on all
packaging tools — populate every listed subdirectory with at least a single
placeholder file.

### 3.5 Fixture regeneration target

New Makefile target per project: `make -C pkg regen-fixture`. Steps:

1. `mktemp -d` a staging dir
2. Run `INSTALL_PATH=<staging>/<legacy> ./install.sh` (APF) or equivalent
3. **Prune** network-dependent artifacts before tarring: geoip data, remote
   deny lists, fetched sigs, log files, cron remnants
4. `tar czf pkg/test/fixtures/source-install-<project>.tar.gz -C <staging> .`
5. Emit a size check: fail target if tarball exceeds 1MB

Checked-in fixture drift detection (optional): a `make verify-fixture` target
that regenerates to a temp location and compares against the committed file.
Defer until Phase 1 lands.

---

## 4. Per-Project Test Deliverables

Each project delivers three scenarios. Scenarios live in the existing
`test-pkg-install.sh` verifier with a new mode argument, or in parallel
Dockerfiles that source the fixture helper before package install. Per-project
implementation plans pick the shape — the scenarios themselves are binding.

### 4.1 Scenario 1 — Migrate from full source install

Setup:
1. Harness container boots empty
2. Harness unpacks fixture tarball into legacy path
3. Harness runs `rpm -ivh <pkg>` (or `dpkg -i`)

Assertions:
- Binary executes (`<bin> --version` exits 0, version matches package)
- User-editable config preserved (modified conf file from fixture survives
  intact — conffile contract)
- No orphan files left under the legacy path that should have been cleaned
- `pkg_fhs_verify_farm()` passes: manifest at
  `/usr/lib/<proj>/internals/.symlink-manifest` is valid and all symlinks
  resolve

Validation command: extend `test-pkg-install.sh` with a `--mode=migrate-full`
flag that runs this assertion set.

### 4.2 Scenario 2 — Migrate from partial uninstall

Setup:
1. Container boots empty
2. Harness unpacks fixture tarball into legacy path
3. Harness removes the main binary (`rm /etc/apf/apf` etc.) but leaves
   subdirs intact, simulating a half-uninstalled source install
4. Harness runs `rpm -ivh` / `dpkg -i`

Assertions:
- Install succeeds (no scriptlet failure)
- Cleanup ran: subdirs that conflict with package layout are either moved
  into backup or converted to symlink farm
- `pkg_fhs_verify_farm()` passes
- Binary is present and functional post-install

Validation command: `test-pkg-install.sh --mode=migrate-partial`.

### 4.3 Scenario 3 — Project-specific regression (retro-target)

This scenario is the **acceptance gate** for the entire phase. Each project's
Scenario 3 test **must fail against the pre-fix commit and pass against
current HEAD**.

#### 4.3.1 APF — `/etc/apf/doc` dir-vs-symlink collision

- Retro-target commit: `bbdf048` (`/root/admin/work/proj/advanced-policy-firewall`)
- Mechanism: fixture must contain `/etc/apf/doc/` as a real directory with at
  least one file. Package install expects `doc` to become a symlink into
  `/usr/share/apf/`. Pre-fix: `%pretrans` did not wipe the legacy path, so
  RPM hit a cpio conflict on `doc` being both directory and symlink.
- Assertion: `rpm -ivh` exits 0 and `/etc/apf/doc` resolves via `readlink` to
  `/usr/share/apf/doc` (or equivalent).
- Validation: check out pre-fix parent commit, rebuild RPM, run Scenario 3 —
  **must fail** (cpio conflict or scriptlet error). Check out current HEAD
  — **must pass**.

#### 4.3.2 BFD — `internals/bfd.lib.sh` real-file sentinel discriminator

- Retro-target commit: `8bbe0b7` (`/root/admin/work/proj/brute-force-detection`)
- Mechanism: fixture must place `internals/bfd.lib.sh` as a **real file**
  (not a symlink). Pre-fix: `%pre` detection sentinel used a weaker check
  that false-negatived when `bfd.lib.sh` was present but not real-vs-symlink
  discriminated, so cleanup did not run.
- Assertion: post-install, `/usr/local/bfd/internals/bfd.lib.sh` resolves
  via `readlink -f` to `/usr/lib/bfd/internals/bfd.lib.sh`, and the RPM
  scriptlet log shows the detection sentinel fired.
- Validation: pre-fix parent commit — **must fail**. Current HEAD — **must
  pass**.

#### 4.3.3 LMD — 9-dir conflict detection

- Retro-target commit: `cde510b` (`/root/admin/work/proj/linux-malware-detect`)
- Mechanism: fixture populates all 9 orphan-enum directories (`sigs/`,
  `quarantine/`, `sess/`, `tmp/`, `pub/`, `clean/`, `logs/`, `cron/`,
  `internals/alert/`) as real directories with content. Pre-fix: `%pre`
  defensive detection missed at least one directory, producing a cpio
  conflict or orphan on install.
- Assertion: `rpm -ivh` exits 0, all 9 legacy directories now resolve as
  symlinks into the FHS tree, no orphaned real directories remain.
- Validation: pre-fix parent commit — **must fail**. Current HEAD — **must
  pass**.

---

## 5. Acceptance Criterion

The validation gate for this entire phase is **retro-reproduction**. For
each project:

1. Check out the pre-fix parent commit of the Scenario 3 retro-target
2. Build the package at that commit
3. Run the Scenario 3 test against that package
4. **The test must fail.**
5. Check out current HEAD
6. Rebuild the package
7. Run the Scenario 3 test against the new package
8. **The test must pass.**

If step 4 does not fail, the fixture is not representative — the bug cannot
be reproduced, so the test cannot guard against regression. The fixture
must be expanded until step 4 fails.

This is the only reliable way to prove the fixture is doing its job. Lint
passes and clean-install tests are already green against both commits; they
give no signal here.

**Retro-validation CI hook (defer):** wire the retro-check into CI as a
quarterly job that pins the pre-fix commit hash per project and runs
Scenario 3 against it. If CI ever reports the pre-fix commit passing,
the fixture has regressed. Out of scope for the initial landing — capture
as a follow-up.

---

## 6. Implementation Strategy

### 6.1 Per-project plans in parallel worktrees

Three independent implementation plans: APF, BFD, LMD. Each owns exclusively
its own `pkg/test/`, `pkg/test/fixtures/`, `pkg/test/helpers/`, and
`pkg/Makefile` edits. **No shared file ownership.** CHANGELOG ownership is
per-project as usual.

Parallel dispatch is safe because:
- No cross-project code sharing inside the test harness
- Per-project fixtures are per-project files
- Each project's existing pkg test infrastructure is standalone

### 6.2 Dependencies

None. This phase can begin immediately after spec approval. It does not
depend on Phase 0 (pkg_lib vendor sync) because the fixture helper operates
entirely on the legacy tree — it never touches pkg_lib primitives.

### 6.3 Disk budget / CI footprint

Anvil Docker cache budget is the constraint. Per-project fixture budget:

| Project | Expected tarball size | Rationale |
|---|---|---|
| APF | ~200-400 KB | 7 sub-libs, doc dir placeholder, small rules fixtures |
| BFD | ~150-300 KB | Sub-libs + rules dir, no signature data |
| LMD | ~300-600 KB | 9 dirs including `sigs/` and `clean/` placeholders |

Hard cap: 1MB per project. `make regen-fixture` fails if exceeded. Total
cross-project ceiling: ~3MB in-tree. Negligible vs existing test images.

Runtime cost: fixture unpack adds ~1-2 seconds per Dockerfile.test-* build.
Per-project pkg test total runtime stays under current budget.

### 6.4 Test integration

Each project wires fixture-aware harnesses into its existing
`pkg/Makefile`:

- New targets: `test-rpm-rocky9-migrate`, `test-deb-debian12-migrate`
- Existing clean-install targets (`test-rpm-rocky9`, `test-deb-debian12`)
  remain unchanged — they cover the fresh-install path
- CI matrix adds the new migrate targets as additional jobs (not
  replacements)

### 6.5 Target release

Out of tree from the current 2.0.x PRs. New branches per project. Target
**2.0.3 or 2.1.0** per each project's release judgment — not blocking
the 2.0.x stream.

---

## 7. Risks

1. **Fixture drift.** `install.sh` changes the set of files or directories
   it writes; the committed fixture is no longer representative. Mitigation:
   `make regen-fixture` Makefile target per project + 1MB budget check.
   Escalation mitigation: cross-reference with `install.sh` mtime in
   CI — out of scope for this phase, note as follow-up.
2. **False negative on Scenario 3.** Fixture passes retro-validation once
   (fails pre-fix, passes HEAD) but later fixture edits silently break the
   retro assertion. Mitigation: the retro-validation CI hook in Section 5.
3. **DEB vs RPM divergence.** A fixture may trigger the retro bug on RPM
   but not DEB (or vice versa) because the two packaging tools handle
   dir-vs-symlink differently. Mitigation: run Scenario 3 on both RPM and
   DEB harnesses, require both to fail against pre-fix.
4. **`install.sh` side-effects during regeneration.** Running `install.sh`
   at fixture-regen time seeds cron and touches `/var/log/`. Mitigation:
   `make regen-fixture` runs in a `mktemp -d` staging root with explicit
   post-run pruning before `tar`. Never invoke `install.sh` against a
   developer's real `/etc/` or `/usr/local/`.
5. **Anvil vs freedom parity.** If the fixture tarball is in the Docker
   build context but the `.dockerignore` excludes `pkg/test/fixtures/`,
   harness builds will silently fall back to empty trees. Mitigation: every
   project's fixture helper must assert the tarball is present and fail
   loudly if missing.

---

## 8. Out of Scope

- **Refactor of packaging scriptlets** — that is Phase 2/D (consolidate
  APF/BFD scriptlets via the LMD `pkg-postinst.sh` pattern). This phase
  adds tests only.
- **Manifest-driven orphan cleanup** — Phase 3/C. Scenario 3 retro tests
  intentionally cover the current hardcoded-enum cleanup logic, not the
  future manifest-driven version.
- **Batsman integration of fixture helper** — promotion to batsman is a
  follow-up after per-project landing stabilizes.
- **Upgrade-path testing beyond migration from source install** — e.g.,
  package-to-package upgrade, package downgrade, `rpm -U` vs `rpm -ivh`
  contrast. Valuable but distinct blind spots; scope separately.
- **APF legacy path move** — Phase 4/E is explicitly deferred in the parent
  handoff and out of scope here.

---

## 9. Target Release

| Project | Branch | Target | Blocking 2.0.x? |
|---|---|---|---|
| APF | `2.0.3-fixtures` or `2.1.0-fixtures` | 2.0.3 / 2.1.0 | No |
| BFD | `2.0.3-fixtures` or `2.1.0-fixtures` | 2.0.3 / 2.1.0 | No |
| LMD | `2.0.2-fixtures` or `2.1.0-fixtures` | 2.0.2 / 2.1.0 | No |

Per-project release decision belongs to the implementation plan.

---

## 10. Open Questions — Deferred to Implementation

1. **Fixture tarball build context inclusion.** Dockerfile.test-rpm builds
   from `$(BUILDDIR)/rpms` — the fixture tarball needs to be copied there
   alongside the built RPM, or the Docker build context needs to switch to
   a superset. Implementation plans decide which approach: copy-into-context
   (simple, matches current `cp test-pkg-install.sh` pattern) vs context
   superset (cleaner, but touches Makefile structure).
2. **Retro-validation automation.** Section 5 describes the acceptance gate
   as a manual two-commit checkout. Can it be automated inside the pkg
   Makefile as `make retro-validate PRE_FIX=<sha>`? Depends on how cleanly
   `git worktree add` composes with the pkg build flow. Defer.
3. **Shared Dockerfile.test-migrate-rpm vs per-scenario Dockerfiles.**
   Option A: single Dockerfile.test-migrate-rpm that takes a mode flag and
   runs all three scenarios in sequence. Option B: three separate
   Dockerfiles. A is cheaper on Docker layer cache but harder to debug
   failures; B is chattier but surfaces scenario-level failures cleanly.
   Per-project plan decides.
4. **BFD `internals/bfd.lib.sh` real-vs-symlink discriminator assertion**
   needs to interrogate scriptlet logs for the sentinel firing, which is
   fragile. Alternative: stronger post-state assertion that proves the
   `8bbe0b7` code path ran without relying on log output. Implementation
   plan designs the robust assertion.
5. **LMD fixture for `sigs/` dir population.** Real LMD signatures are
   large and non-redistributable under some mirrors. Decision: use dummy
   placeholder files in `sigs/`, not real signatures. Confirm during
   implementation that this is sufficient to trigger the `cde510b` code
   path — if not, expand to include minimal real sig stubs.
6. **CI job ordering.** Should migrate-test jobs run in the same matrix as
   clean-install tests, or as a separate "packaging deep-check" workflow?
   Affects PR feedback latency. Implementation plan decides per project.
7. **Fixture format: single tar.gz vs per-scenario tarballs.** Scenario 1,
   2, and 3 all need slightly different tree shapes (Scenario 2 is
   Scenario 1 minus the binary; Scenario 3 is the retro-targeted fixture).
   Option A: one tarball + scenario-specific pruning in the helper. Option
   B: three separate fixtures. A keeps disk budget low, B keeps scenarios
   isolated. Defer to implementation.

---

## 11. Summary

| Dimension | Decision |
|---|---|
| Helper location | Per-project `pkg/test/helpers/` (first iteration) |
| Fixture format | Frozen tarball under `pkg/test/fixtures/` |
| Fixture regen | `make -C pkg regen-fixture` per project, 1MB cap |
| Scenarios | 1 = full migrate, 2 = partial uninstall, 3 = retro-target |
| Acceptance gate | Scenario 3 fails pre-fix commit, passes HEAD |
| Retro targets | APF `bbdf048`, BFD `8bbe0b7`, LMD `cde510b` |
| Execution | Three parallel per-project implementation plans |
| Dependencies | None — starts immediately after spec approval |
| Release target | 2.0.3 / 2.1.0 per project, non-blocking |
| Out of scope | Scriptlet refactor, manifest-driven cleanup, batsman promotion |
