# Post-Install Scriptlet Consolidation — APF & BFD

> **Type:** Cross-project packaging refactor (design spec)
> **Scope:** APF, BFD. LMD is the reference, not a target.
> **Parent:** Phase 2 / Action D of the cross-project packaging hardening
> initiative (`HANDOFF-packaging-hardening.md` lines 118-137, 17-41).
> **Umbrella strategy:** `rdf/docs/specs/2026-04-08-packaging-hardening-strategy.md`.
> **Hard dependency:** Phase 1 migration-path test fixtures (Action B) must
> land and be green for both APF and BFD before this phase is merged.

---

## 1. Problem Statement

APF and BFD carry parallel copies of post-install logic across their RPM
`%post` scriptlets and Debian `postinst` scripts. The two copies must be
kept byte-for-byte equivalent by hand; nothing couples them. The next
behaviour change in APF or BFD will silently miss one distro family — the
same failure mode LMD eliminated by consolidating into a single
`pkg/scripts/pkg-postinst.sh` script invoked by both `%post` and `postinst`
(reference commit lives in `linux-malware-detect/pkg/scripts/pkg-postinst.sh`).

Concrete evidence of duplication:

| Project | RPM `%post` | DEB `postinst` | Overlap |
|---|---|---|---|
| APF | `pkg/rpm/apf.spec` lines 248-290 | `pkg/deb/debian/postinst` lines 13-66 | importconf, legacy-artifact cleanup, systemd daemon-reload, firewalld/ufw masking — all duplicated verbatim with only RPM-macro vs dpkg-arg differences |
| BFD | `pkg/rpm/bfd.spec` lines 275-306 | `pkg/deb/debian/bfd.postinst` lines 7-47 | importconf, systemd daemon-reload, `update-ipcountry.sh` background fetch, `update-cdn-providers.sh` conditional background fetch — all duplicated verbatim |
| LMD | `pkg/rpm/maldet.spec` lines 298-321 | `pkg/deb/debian/postinst` lines 16-45 | **Thin dispatch wrappers only** — both call `pkg-postinst.sh <mode>` |

LMD is the existence proof that the pattern works. APF and BFD are the
targets. LMD's implementation is frozen for this spec — refinements to
LMD's `pkg-postinst.sh` are out of scope.

---

## 2. Current State — What's Duplicated

### 2.1 APF

**RPM `%post` — `advanced-policy-firewall/pkg/rpm/apf.spec` lines 248-290:**

1. Fresh-install interface auto-detection (lines 250-255) — gated by
   `$1 = 1` and absence of `%{legacy_path}/internals/.apf.restore`;
   `sed -i` of `IFACE_UNTRUSTED` in `conf.apf`.
2. `importconf` invocation on migration from `install.sh` backup
   (lines 257-259) — gated by existence of `%{legacy_path}.bk.last`.
3. Legacy artifact cleanup (lines 261-273) — removes pre-2.0.2 files
   (`firewall`, `internals/functions.apf`, `internals/geoip.apf`,
   `internals/ctlimit.apf`) and legacy cron entries
   (`/etc/cron.hourly/fw`, `/etc/cron.daily/fw`, `/etc/cron.d/refresh.apf`,
   `/etc/cron.d/apf_develmode`, `/etc/cron.d/ctlimit.apf`). Gated by
   `[ -L "%{legacy_path}.bk.last" ]`.
4. Systemd `daemon-reload` (lines 275-277).
5. Conflicting-firewall teardown — loops over `firewalld` and `ufw`,
   calls `systemctl stop` and `systemctl mask` if active (lines 279-284).

**DEB `postinst` — `advanced-policy-firewall/pkg/deb/debian/postinst`
lines 13-66:**

1. Permission fixups on config files and directories (lines 15-21) —
   `chmod 640` on rules files, `chmod 750` on `hook_*.sh`,
   `/var/lib/apf/tmp`, `/etc/apf/geoip`, `/var/log/apf`. **Not present
   in RPM `%post`** — dh_fixperms motivation is DEB-specific, but the
   call is harmless on RPM and belongs in the shared script.
2. Fresh-install interface auto-detection (lines 23-28) — gated by
   absence of `$2` and `.apf.restore`. Equivalent to RPM block 1.
3. `importconf` invocation (lines 30-34) — equivalent to RPM block 2.
4. Legacy artifact cleanup (lines 36-48) — byte-identical to RPM block 3.
5. Systemd `daemon-reload` (lines 50-52) — equivalent to RPM block 4.
6. Conflicting-firewall teardown (lines 54-59) — equivalent to RPM block 5.

**Inventory of behaviours to consolidate:** 6 logical blocks, 5 of them
already duplicated across both scriptlets, 1 (permission fixups) that
should become shared as part of the consolidation.

**Not touched by this spec:** APF's `%pretrans` logic at `apf.spec`
lines 197-246 — see §3.3 and §10.

### 2.2 BFD

**RPM `%post` — `brute-force-detection/pkg/rpm/bfd.spec` lines 275-306:**

1. Systemd `daemon-reload` (lines 277-279).
2. `importconf` invocation on migration (lines 281-285) — gated by
   `[ -d "%{legacy_path}.bk.last" ]`.
3. Unconditional background `update-ipcountry.sh` (lines 287-290) —
   `( exec >/dev/null 2>&1; ... || true ) & disown`.
4. Conditional background `update-cdn-providers.sh` (lines 291-306) —
   reads `CDN_ENABLE` from `/etc/bfd/conf.bfd` via awk, evaluates
   `1` / `auto` semantics, runs in detached subshell.

**DEB `postinst` — `brute-force-detection/pkg/deb/debian/bfd.postinst`
lines 7-47:**

1. Permission fixups on config files and state/log directories
   (lines 9-15) — `chmod 640` on conf files, `chmod 750` on `tmp/`,
   `stats/`, `/var/log/bfd`. **Not present in RPM `%post`** — same
   dh_fixperms-vs-RPM asymmetry as APF.
2. Systemd `daemon-reload` (lines 17-19) — equivalent to RPM block 1.
3. `importconf` invocation (lines 21-25) — equivalent to RPM block 2.
4. Background `update-ipcountry.sh` (lines 27-30) — equivalent to RPM
   block 3.
5. Conditional background `update-cdn-providers.sh` (lines 31-46) —
   byte-identical to RPM block 4, including the awk parser.

**Inventory:** 5 logical blocks, 4 of them already duplicated, 1
(permission fixups) to promote into the shared script.

### 2.3 LMD Reference Pattern

**Script:** `linux-malware-detect/pkg/scripts/pkg-postinst.sh`
(lines 48-146, 146 lines total).

**Shape:**

- `set -u`, top-level `LEGACY_PATH` / `SIGS_DIR` / `MALDET` constants.
- Private helpers prefixed `_` (`_log`, `_clamav_linksigs`,
  `_link_clamav_all`, `_migrate_sigs`, `_seed_custom_sigs`).
- Main dispatch: `mode="${1:-fresh}"` + `case "$mode" in`
  `migrate | fresh | upgrade | *)` (lines 99-142).
- `migrate` branch resolves `.bk.last` and calls `_migrate_sigs`.
- `fresh` branch skips migration, runs `maldet --update 1`.
- `upgrade` branch re-seeds and re-links only.
- Script exits `0` on success, `1` on unknown mode.

**RPM dispatch (`maldet.spec` lines 313-321):**

```
if [ -x /usr/lib/maldet/internals/pkg-postinst.sh ]; then
    if [ "$1" -eq 1 ] && [ -d "${LEGACY_PATH}.bk.last" ]; then
        /usr/lib/maldet/internals/pkg-postinst.sh migrate || true
    elif [ "$1" -eq 1 ]; then
        /usr/lib/maldet/internals/pkg-postinst.sh fresh || true
    else
        /usr/lib/maldet/internals/pkg-postinst.sh upgrade || true
    fi
fi
```

**DEB dispatch (`linux-malware-detect/pkg/deb/debian/postinst`
lines 35-43):** identical three-way dispatch but keyed on
`[ -z "$2" ] && [ -d "${LEGACY_PATH}.bk.last" ]` / `[ -z "$2" ]` / else.

**Integration points:**

- `maldet.spec` line 32: `Source2: pkg-postinst.sh`.
- `maldet.spec` line 204:
  `install -m 750 %{SOURCE2} %{buildroot}/usr/lib/maldet/internals/pkg-postinst.sh`.
- `maldet.spec` line 383:
  `%attr(750,root,root) /usr/lib/maldet/internals/pkg-postinst.sh`.
- `linux-malware-detect/pkg/deb/debian/rules` line 87:
  `install -m 750 pkg/scripts/pkg-postinst.sh $(CURDIR)/debian/maldet/usr/lib/maldet/internals/pkg-postinst.sh`.
- `linux-malware-detect/pkg/Makefile` lines 61, 75-77: tar-fallback build
  copies `pkg-postinst.sh` into `rpmbuild/SOURCES/` and into the DEB
  source tree under `$(NAME)-$(VERSION)/pkg/scripts/`.

---

## 3. Design

### 3.1 Pattern

One shell script per project at `pkg/scripts/pkg-postinst.sh`. Invoked by
both RPM `%post` and DEB `postinst`. Installed to
`/usr/lib/<proj>/internals/pkg-postinst.sh` with mode `750`. Contains
**all** post-install logic (importconf invocation, permission fixups,
legacy artifact cleanup, daemon-reload, background fetches, cron seeding,
firewall teardown). RPM spec and DEB postinst become thin dispatch
wrappers that do only:

1. Translate RPM `$1` / DEB dpkg argument to a unified `migrate` /
   `fresh` / `upgrade` token.
2. Call `/usr/lib/<proj>/internals/pkg-postinst.sh <token>`.
3. Nothing else.

### 3.2 Mode Vocabulary

| Token | RPM condition | DEB condition | Semantic |
|---|---|---|---|
| `migrate` | `[ "$1" -eq 1 ] && [ -d "${LEGACY_PATH}.bk.last" ]` | `[ -z "$2" ] && [ -d "${LEGACY_PATH}.bk.last" ]` | First package install over an existing `install.sh`-based install — backup exists, importconf must run, legacy artifacts must be swept |
| `fresh` | `[ "$1" -eq 1 ]` (else) | `[ -z "$2" ]` (else) | First-time install, no prior state |
| `upgrade` | `[ "$1" -eq 2 ]` (else) | `[ -n "$2" ]` (else) | Package-to-package upgrade — no importconf, no migration cleanup |

Translation happens in the dispatch wrapper, not in the script. The
script treats the mode as an opaque token it matches on in a `case`
block. This keeps the script unaware of RPM-vs-DEB semantics.

### 3.3 APF `%pretrans` Stays Separate (Decision)

APF's `%pretrans` logic (`apf.spec` lines 197-246) performs
install.sh-backup creation, state preservation, legacy service teardown,
and legacy-path wiping. It runs in RPM's `%pretrans` phase — **before**
conffile scanning — because RPM locks `%config(noreplace)` dispositions
before `%pre` and would leave `.rpmnew` files if this work ran later.

**Decision: `%pretrans` is NOT consolidated into `pkg-postinst.sh`.**

Reasons:

1. LMD's pattern covers post-install only. There is no proven companion
   pattern for pre-install / pretrans consolidation across RPM and DEB.
2. DEB has no `%pretrans` equivalent. The DEB equivalent for APF's
   backup logic lives in `preinst`, not `postinst`, and runs at a
   different point in the dpkg lifecycle. Collapsing pretrans-phase
   work into a post-install script would break both its timing contract
   and its RPM-phase-ordering rationale (which is load-bearing — see
   `apf.spec` lines 198-206).
3. Pre-install consolidation is explicitly out of scope for Phase 2 of
   the packaging hardening initiative
   (`HANDOFF-packaging-hardening.md` lines 118-137). If it is warranted,
   it belongs in a separate spec after LMD establishes a `pkg-preinst.sh`
   reference implementation.

Any existing `%pretrans` behaviour in APF stays where it is.

---

## 4. Per-Project Deliverables

### 4.1 APF

**New file:** `advanced-policy-firewall/pkg/scripts/pkg-postinst.sh`.

**Content boundaries** — the script must contain the following blocks,
each accepting the unified mode token and gating on it:

| Block | Applies in modes | Source of current logic |
|---|---|---|
| Permission fixups (config files, hook scripts, state/log dirs) | `fresh`, `migrate`, `upgrade` | DEB postinst lines 15-21 |
| Fresh-install interface auto-detection | `fresh` only | RPM spec lines 250-255 / DEB postinst lines 23-28 |
| `importconf` invocation | `migrate` only | RPM spec lines 257-259 / DEB postinst lines 30-34 |
| Legacy artifact cleanup (pre-2.0.2 files + legacy cron entries) | `migrate` only | RPM spec lines 261-273 / DEB postinst lines 36-48 |
| Systemd `daemon-reload` | all modes | RPM spec lines 275-277 / DEB postinst lines 50-52 |
| Conflicting firewall teardown (`firewalld`, `ufw`) | `fresh`, `migrate` | RPM spec lines 279-284 / DEB postinst lines 54-59 |

**Not in scope for the script:**

- ClamAV linking (LMD-only).
- `%pretrans` work — see §3.3.
- Service auto-enable — intentionally disabled in both RPM and DEB
  today (see RPM spec lines 285-290), must remain disabled.
- VNET generation — deferred to first `apf -s`, must remain deferred.

**Dispatch wrappers:**

- `apf.spec` `%post` becomes (pseudo-diff):
  ```
  if [ -x /usr/lib/apf/internals/pkg-postinst.sh ]; then
      if [ "$1" -eq 1 ] && [ -d "%{legacy_path}.bk.last" ]; then
          /usr/lib/apf/internals/pkg-postinst.sh migrate || true
      elif [ "$1" -eq 1 ]; then
          /usr/lib/apf/internals/pkg-postinst.sh fresh || true
      else
          /usr/lib/apf/internals/pkg-postinst.sh upgrade || true
      fi
  fi
  ```
- `advanced-policy-firewall/pkg/deb/debian/postinst` `configure)` branch
  becomes the equivalent three-way dispatch keyed on `[ -z "$2" ]` and
  `[ -d "${LEGACY_PATH}.bk.last" ]`.

### 4.2 BFD

**New file:** `brute-force-detection/pkg/scripts/pkg-postinst.sh`.

**Content boundaries:**

| Block | Applies in modes | Source of current logic |
|---|---|---|
| Permission fixups (config files, state/log dirs) | `fresh`, `migrate`, `upgrade` | DEB postinst lines 9-15 |
| Systemd `daemon-reload` | all modes | RPM spec lines 277-279 / DEB postinst lines 17-19 |
| `importconf` invocation | `migrate` only | RPM spec lines 281-285 / DEB postinst lines 21-25 |
| Background `update-ipcountry.sh` | `fresh`, `migrate` | RPM spec lines 287-290 / DEB postinst lines 27-30 |
| Conditional background `update-cdn-providers.sh` (awk-parsed `CDN_ENABLE=1\|auto`) | `fresh`, `migrate` | RPM spec lines 291-306 / DEB postinst lines 31-46 |

**Open question:** whether background fetches should also fire on
`upgrade`. Current behaviour — both RPM and DEB — runs them on every
`configure`/install call, not just fresh/migrate. The spec defers the
answer to §12; the safe default is to preserve current behaviour and
fire in all three modes.

**Not in scope for the script:**

- ClamAV linking (LMD-only).
- `%pre` work — BFD uses `%pre` not `%pretrans` (`bfd.spec` lines
  215-273); pre-install consolidation is out of scope.

**Dispatch wrappers:** identical shape to APF's, with `apf` →
`bfd` / `maldet` → `bfd` path rewrites, keyed on the same RPM `$1` and
DEB `$2` semantics.

---

## 5. Scoping — One Spec, Two Plans

- **One spec (this document)** covers both APF and BFD because the
  pattern and the per-project adaptation rules are shared.
- **Two implementation plans**, produced independently via `/r-plan`:
  - `advanced-policy-firewall/docs/plans/2.1.0-postinst-consolidation.md`
  - `brute-force-detection/docs/plans/2.1.0-postinst-consolidation.md`
- Plans can run sequentially or in parallel worktrees. No shared file
  ownership exists across projects; each plan owns only files under its
  own project root.
- LMD is not a target. Any refinements to LMD's `pkg-postinst.sh` are
  out of scope and belong in a separate LMD-local spec.

---

## 6. Dependency — Phase 1 Test Fixtures Must Land First

This is a refactor of live packaging scriptlets. Without migration-path
test coverage, regressions can ship silently — exactly the class of bug
Phase 1 (Action B in `HANDOFF-packaging-hardening.md`) exists to catch.

**Gate criteria before Phase 2 may merge:**

- Phase 1 Scenario 1 (*Migrate from source install*) is implemented for
  both APF and BFD in their respective `tests/` suites.
- Scenario 1 fails on the pre-refactor HEAD when the refactor is
  accidentally broken (regression trap is armed).
- Scenario 1 passes on the post-refactor HEAD before merge.

A plan that tries to start before Phase 1 lands must be rejected at
review.

---

## 7. Packaging Manifest Updates

New file `pkg/scripts/pkg-postinst.sh` must be registered at every
packaging insertion point, per project. Grep every sibling file under
`pkg/` for all locations — `install.sh` installs via globs, RPM and DEB
use explicit file lists.

### 7.1 RPM (`pkg/rpm/<proj>.spec`)

- Add `Source2: pkg-postinst.sh` in the preamble (mirror LMD
  `maldet.spec` line 32).
- Add `install -m 750 %{SOURCE2} %{buildroot}/usr/lib/<proj>/internals/pkg-postinst.sh`
  in `%install` (mirror LMD `maldet.spec` line 204).
- Add `%attr(750,root,root) /usr/lib/<proj>/internals/pkg-postinst.sh`
  in `%files` (mirror LMD `maldet.spec` line 383). APF's `%files` starts
  at `apf.spec` line 348; BFD's at `bfd.spec` line 342.
- Replace inline `%post` body with dispatch wrapper (§4).

### 7.2 DEB (`pkg/deb/debian/rules`)

- Add `install -D -m 750 pkg/scripts/pkg-postinst.sh $(DESTDIR)/usr/lib/<proj>/internals/pkg-postinst.sh`
  in `override_dh_auto_install` (mirror LMD `rules` line 87). APF's
  `override_dh_auto_install` starts at `rules` line 18; BFD's at line 33.
- Replace inline `configure)` body in `postinst` with dispatch wrapper
  (§4). For APF the postinst file is `pkg/deb/debian/postinst`; for BFD
  it is `pkg/deb/debian/bfd.postinst`.

### 7.3 `pkg/Makefile` tar-fallback build

- RPM target: add `cp $(CURDIR)/scripts/pkg-postinst.sh $(BUILDDIR)/rpmbuild/SOURCES/`
  alongside the existing `symlink-manifest` copy (mirror LMD
  `pkg/Makefile` line 61).
- DEB target: add `mkdir -p $(BUILDDIR)/deb-build/$(NAME)-$(VERSION)/pkg/scripts`
  and `cp $(CURDIR)/scripts/pkg-postinst.sh $(BUILDDIR)/deb-build/$(NAME)-$(VERSION)/pkg/scripts/`
  (mirror LMD `pkg/Makefile` lines 75-77).
- APF and BFD `pkg/Makefile` currently have no `pkg-postinst` references
  (verified via grep). Both need the additions.

### 7.4 `pkg/symlink-manifest`

- **Decision: no entry.** The manifest tracks symlinks from the legacy
  farm into FHS paths. `pkg-postinst.sh` is a real file installed into
  `/usr/lib/<proj>/internals/` and has no farm-side counterpart. LMD's
  `symlink-manifest` does not list it; APF's and BFD's must not either.

### 7.5 `install.sh` / source install

- **Decision: no change to `install.sh`.** `pkg-postinst.sh` is
  package-only. Source installs do not invoke it — `install.sh` already
  performs the post-install work inline (sigup, importconf, etc.). LMD's
  `install.sh` contains no `pkg-postinst.sh` references (verified via
  grep). APF's and BFD's must not either.

### 7.6 `.gitattributes`

- No change. `pkg/` is already `export-ignore`'d in all three projects'
  `.gitattributes` (verified in LMD `.gitattributes` line 4). Placing
  `pkg-postinst.sh` under `pkg/scripts/` keeps it inside the already-
  excluded tree.

---

## 8. Testing Strategy

### 8.1 Primary Validation — Phase 1 Migration Fixtures

Phase 1's *Scenario 1 — Migrate from source install* is the load-bearing
test. Any change in `pkg-postinst.sh` behaviour relative to the pre-
refactor inline scripts must surface there.

### 8.2 Standalone Smoke Tests

Add a per-project BATS file
(`tests/NN-pkg-postinst.bats`) that invokes
`pkg/scripts/pkg-postinst.sh` directly — without RPM or DEB wrapping —
with each mode token:

- `pkg-postinst.sh fresh` (no `.bk.last`) — must exit 0, must not call
  `importconf`, must skip migration cleanup.
- `pkg-postinst.sh migrate` (with staged `.bk.last`) — must exit 0, must
  call `importconf`, must remove staged legacy artifacts.
- `pkg-postinst.sh upgrade` — must exit 0, must skip importconf, must
  skip migration cleanup, must still daemon-reload.
- `pkg-postinst.sh bogus-mode` — must exit non-zero.

These tests exercise the dispatch contract without needing a full
package build; they complement, not replace, the Phase 1 fixtures.

### 8.3 Regression — Docker Package Install Tests

Every existing `pkg/test/` install scenario must continue to pass after
the refactor. The refactor is only valid if the output end-state is
byte-equivalent to the pre-refactor inline logic (modulo ordering).

### 8.4 Cross-Matrix Requirement

Because this touches both RPM and DEB scriptlets, **full distro matrix
must run before merge** per the parent CLAUDE.md testing rule. Debian 12
+ Rocky 9 is the dev-phase minimum; full matrix is mandatory for merge
to master.

---

## 9. Risks

1. **Mode translation bug.** RPM uses numeric `$1` (`0` / `1` / `2`);
   DEB uses string `$2` with `configure` / `upgrade` / etc. A
   mis-translation in either dispatch wrapper silently routes to the
   wrong branch. *Mitigation:* explicit per-mode per-distro test
   coverage (§8.2 + §8.3), line-by-line review of both wrappers against
   the LMD reference.
2. **Subtle behaviour divergence.** Extracting inline logic into a
   sourced-elsewhere script can reorder side effects (e.g., whether
   `chmod` runs before or after `importconf`). *Mitigation:* the plan
   must include a per-block before/after line-map showing which inline
   block became which function and in what order, and must preserve
   current ordering unless a change is explicitly justified.
3. **APF `%pretrans` phase-ordering subtlety.** The `%pretrans` block is
   load-bearing for the `%config(noreplace)` scan contract
   (`apf.spec` lines 198-206). Any accidental move of its logic into
   `pkg-postinst.sh` silently breaks conffile handling on upgrade.
   *Mitigation:* `%pretrans` is explicitly out of scope (§3.3, §10).
   Plan reviewers must verify `%pretrans` is unmodified.
4. **BFD background-fetch semantics.** Current behaviour runs
   `update-ipcountry.sh` and (conditionally) `update-cdn-providers.sh`
   on every `configure` call including plain upgrades. Changing that
   silently is a regression. *Mitigation:* §4.2 states the preserve-
   current-behaviour default; see open question §12.
5. **Systemd `daemon-reload` ordering on DEB.** Today's DEB postinst
   runs daemon-reload before `importconf` in BFD (lines 17-19 precede
   lines 21-25) but **after** `importconf` in APF (lines 30-34 precede
   lines 50-52). The two projects are inconsistent. *Mitigation:* the
   plan must preserve each project's current ordering; do not silently
   normalise the two.

---

## 10. Out of Scope

- LMD refinements of any kind (`linux-malware-detect/pkg/scripts/pkg-postinst.sh`
  is frozen for this spec).
- APF `%pretrans` consolidation (§3.3).
- Pre-install consolidation (no counterpart pattern yet — no
  `pkg-preinst.sh` exists in LMD).
- Orphan-enumeration refactor (Phase 3 / Action C in the packaging
  hardening initiative).
- Legacy-path migration (`/etc/apf/` → `/usr/local/apf/`, Phase 4 /
  Action E — explicitly deferred).
- Changes to `install.sh` post-install flow.

---

## 11. Target Release

| Project | Target | Branch |
|---|---|---|
| APF | 2.1.0 | new feature branch off master |
| BFD | 2.1.0 | new feature branch off master |
| LMD | — | no change |

This is a refactor, not a bugfix. It does not belong in a 2.0.x patch
line. Do not attempt either plan until Phase 1 (Action B) has landed
and Scenario 1 is green for the target project.

---

## 12. Open Questions

Deferred to the implementation plans or to reviewer challenge:

1. **BFD background-fetch mode coverage.** Should `update-ipcountry.sh`
   and `update-cdn-providers.sh` fire on `upgrade` as well as `fresh`
   and `migrate`? Current behaviour does — preserving it is the safe
   default. A follow-up may narrow it, but not in this phase.
2. **APF permission-fixup RPM coverage.** The DEB postinst runs
   `chmod 640` / `chmod 750` fixups that do not appear in the RPM
   `%post`. The DEB-side rationale is `dh_fixperms` normalisation. After
   consolidation, running the fixups on both distros is harmless and
   tightens guarantees — but it is a behaviour change on RPM. Confirm
   in review that this is acceptable or gate the block on a DEB-only
   marker passed by the dispatch wrapper.
3. **Systemd daemon-reload ordering normalisation.** APF and BFD
   currently run `daemon-reload` at different points relative to
   `importconf` (§9.5). Should the shared pattern normalise them? The
   spec says no — preserve per-project ordering. Confirm in review or
   propose a single canonical order with evidence.
4. **Dispatch wrapper location for DEB `postinst`.** APF's file is
   `pkg/deb/debian/postinst` (unprefixed); BFD's is
   `pkg/deb/debian/bfd.postinst` (prefixed). The plans must use the
   correct path per project — do not mechanically rename during the
   refactor.
5. **BATS namespace for the new smoke-test file.** Each project assigns
   BATS file numbers from its own sequence. The plans must pick an
   unused number at plan-writing time by running
   `ls tests/*.bats` against the current branch — do not guess.
6. **Error-exit policy in the dispatch wrappers.** LMD's wrapper uses
   `|| true` after every `pkg-postinst.sh <mode>` invocation. Should
   APF and BFD match, or should they propagate a non-zero exit (e.g.,
   for `fresh` failures only)? LMD's `|| true` is the proven default.
   Non-zero propagation is a policy change that belongs in a separate
   discussion.

---

## Appendix A — Evidence Index

| Claim | File | Lines |
|---|---|---|
| APF RPM post-install block | `advanced-policy-firewall/pkg/rpm/apf.spec` | 248-290 |
| APF `%pretrans` block | `advanced-policy-firewall/pkg/rpm/apf.spec` | 197-246 |
| APF `%install` section | `advanced-policy-firewall/pkg/rpm/apf.spec` | 73-164 |
| APF `%files` section | `advanced-policy-firewall/pkg/rpm/apf.spec` | 348- |
| APF DEB postinst block | `advanced-policy-firewall/pkg/deb/debian/postinst` | 13-66 |
| APF DEB rules install target | `advanced-policy-firewall/pkg/deb/debian/rules` | 18-94 |
| BFD RPM post-install block | `brute-force-detection/pkg/rpm/bfd.spec` | 275-306 |
| BFD `%pre` block | `brute-force-detection/pkg/rpm/bfd.spec` | 215-273 |
| BFD `%files` section | `brute-force-detection/pkg/rpm/bfd.spec` | 342- |
| BFD DEB postinst block | `brute-force-detection/pkg/deb/debian/bfd.postinst` | 7-47 |
| BFD DEB rules install target | `brute-force-detection/pkg/deb/debian/rules` | 33-105 |
| LMD pkg-postinst.sh | `linux-malware-detect/pkg/scripts/pkg-postinst.sh` | 1-146 |
| LMD RPM dispatch block | `linux-malware-detect/pkg/rpm/maldet.spec` | 298-321 |
| LMD RPM Source2 declaration | `linux-malware-detect/pkg/rpm/maldet.spec` | 32 |
| LMD RPM install line | `linux-malware-detect/pkg/rpm/maldet.spec` | 204 |
| LMD RPM %files entry | `linux-malware-detect/pkg/rpm/maldet.spec` | 383 |
| LMD DEB rules install line | `linux-malware-detect/pkg/deb/debian/rules` | 87 |
| LMD DEB postinst dispatch | `linux-malware-detect/pkg/deb/debian/postinst` | 16-45 |
| LMD pkg/Makefile RPM source copy | `linux-malware-detect/pkg/Makefile` | 61 |
| LMD pkg/Makefile DEB source copy | `linux-malware-detect/pkg/Makefile` | 75-77 |
| LMD .gitattributes pkg exclusion | `linux-malware-detect/.gitattributes` | 4 |
| Parent handoff Phase 2 scope | `HANDOFF-packaging-hardening.md` | 118-137 |
| Parent handoff architecture baseline | `HANDOFF-packaging-hardening.md` | 17-41 |
