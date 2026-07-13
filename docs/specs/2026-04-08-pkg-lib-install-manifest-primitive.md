# pkg_lib Install Manifest Primitive — Manifest-Driven Orphan Cleanup

> Phase 3 / Action C of the cross-project packaging hardening initiative.
> Parent strategy: `rdf/docs/specs/2026-04-08-packaging-hardening-strategy.md`.
> Origin context: `HANDOFF-packaging-hardening.md` (lines 140-158, plus the
> Architecture baseline lines 17-41).
> Target release: **pkg_lib v1.0.10** (follow-up to v1.0.9, which must land
> first as a focused `pkg_config_merge` fix).

---

## 1. Problem Statement

BFD and LMD both clean up "orphan" source-install directories from their
package preinst/`%pre` scriptlets so that the symlink farm laid down by
`rpm`/`dpkg` does not collide with real directories left by a prior
`install.sh` run. The list of orphans is **hardcoded verbatim** in each
project's preinst and spec file. Any future directory added to `install.sh`
silently breaks upgrades unless every downstream scriptlet is updated in
the same commit. Nothing couples the two.

This is pure latent risk: it does not trigger on first install, does not
show up in fresh-container migration tests, and only detonates during an
upgrade from an `install.sh` tree that has gained a new top-level directory
since the package cleanup list was last touched. It is the same class of
brittleness that produced APF's `/etc/apf/doc` dir-vs-symlink P0 in the
2026-04-06 hotfix cascade — just waiting for the next add.

The fix is to treat the list of cleanup-candidate directories as **data**
written by `install.sh` at source-install time, not as prose duplicated
across three files per project.

---

## 2. Current State

### 2.1 BFD — 7-entry hardcoded list

**DEB preinst:** `/root/admin/work/proj/brute-force-detection/pkg/deb/debian/bfd.preinst`

- Lines 50-54 — `for _orphan in alert data rules tmp stats; do`
  — five simple orphans handled by a single loop with `[ -d ] && [ ! -L ]` guard.
- Lines 57-61 — `internals/` directory, gated by a sentinel discriminator
  (`internals/bfd.lib.sh` being a real file vs a symlink) because
  `internals/` is a real directory in both source and package installs.
- Lines 62-64 — `ipcountry.dat` file (not a directory), gated by
  `[ -f ] && [ ! -L ]`.

**RPM %pre:** `/root/admin/work/proj/brute-force-detection/pkg/rpm/bfd.spec`

- Lines 257-261 — same five-orphan loop, literal copy.
- Lines 265-269 — `internals/` sentinel discriminator, literal copy.
- Lines 271-273 — `ipcountry.dat` file guard, literal copy.

Total: **7 names** (5 simple dirs + `internals/` + `ipcountry.dat`),
duplicated across DEB preinst and RPM spec with identical logic.

### 2.2 LMD — 9-entry hardcoded list

**DEB preinst:** `/root/admin/work/proj/linux-malware-detect/pkg/deb/debian/preinst`

- Line 29 — inline enumeration inside the conflict detector:
  `for _d in sigs quarantine sess tmp pub clean logs cron internals/alert; do`
- The loop sets `_lmd_conflict=1` and breaks on first hit. The cleanup
  itself is a whole-directory backup+`rm -rf` (lines 37-71), not a
  per-orphan loop. The enumeration is a **detection** list, not a
  deletion list — but it is functionally the same problem: adding a
  tenth source directory to `install.sh` leaves partial source installs
  undetectable.

**RPM %pre:** `/root/admin/work/proj/linux-malware-detect/pkg/rpm/maldet.spec`

- Line 267 — identical inline enumeration, literal copy of the DEB loop.

Total: **9 names**, duplicated across DEB preinst and RPM spec.

LMD's shape differs from BFD's — LMD uses a single detect-and-wipe
path rather than per-orphan surgical cleanup — but the drift surface
is identical: the 9-entry list must stay in sync with what `install.sh`
creates (`_install_core()` in `linux-malware-detect/install.sh`
lines 41-75, especially the `pkg_create_dirs 750` call at lines 48-49).

### 2.3 APF — out of scope for Phase 3

APF uses `%pretrans` with a full wipe of the legacy `/etc/apf/` tree
(`HANDOFF-packaging-hardening.md` line 33). It has no hardcoded orphan
enumeration to retire. Switching APF from "wipe everything" to
"manifest-driven selective cleanup" is a behaviour change, not a
refactor — it would require its own risk analysis and its own spec.

**Decision:** APF is **not** a consumer of this primitive in Phase 3.
Revisit only if and when APF's `%pretrans` strategy is independently
reconsidered (unlikely — `%pretrans` exists specifically because APF's
legacy path overlaps conffile territory).

---

## 3. Design — New pkg_lib Primitives

Two new functions, both in the existing `# Section: FHS layout
primitives` block of `files/pkg_lib.sh` (near
`pkg_fhs_gen_manifest` at line 3080 and `pkg_fhs_verify_farm` at
line 3112, whose conventions they follow):

### 3.1 `pkg_fhs_emit_install_manifest <legacy_path>`

Called at **source-install time** from each consuming project's
`install.sh`, after `pkg_copy_tree` has laid down the source tree.
Writes a newline-delimited list of top-level names (directories and
files) that the source install just created, to:

```
<legacy_path>/internals/.install-manifest
```

Matches the existing `.symlink-manifest` convention used by the
package path (e.g., `/usr/lib/bfd/internals/.symlink-manifest`
written at `brute-force-detection/install.sh` lines 71-76). Different
file, different purpose: `.symlink-manifest` is about repairing the
symlink farm on an **installed package**; `.install-manifest` is about
enumerating what was laid down by a **source install** so a later
package upgrade can clean it up.

**Signature:**

```
pkg_fhs_emit_install_manifest <legacy_path> <name1> [name2 …]
```

- `$1` — legacy install root (e.g., `/usr/local/bfd`, `/usr/local/maldetect`).
  Must be non-empty and an existing directory; function fails with
  `pkg_error` otherwise.
- `$2..$N` — one or more top-level names (no slashes, no `..`, no
  leading `.`). Names are validated before write; any reject produces
  `pkg_error` and aborts the emit with no partial file written.

**Output:**

- Header line: `# pkg_lib:install-manifest:1` (schema version, matches
  the `pkg_lib:symlink-manifest:1` header at line 3094).
- Body: one name per line, **sorted** (deterministic diffs across
  reinstalls).
- Permissions: `640`, root-owned, same as `.symlink-manifest` (line 3098
  precedent and `install.sh` line 76 precedent).
- Written atomically via `mktemp` + `mv` inside `<legacy_path>/internals/`
  (must be same filesystem) to avoid torn writes if the install is
  interrupted.

**Failure modes:**

- `legacy_path` empty, missing, or not a directory → `pkg_error`, return 1.
- `<legacy_path>/internals/` missing → `pkg_error`, return 1. (Caller
  must have already laid down the tree; the manifest lives inside it.)
- Any name argument containing `/`, `..`, a null byte, a leading `.`,
  or an empty string → `pkg_error`, return 1, no file written.
- `mv` from tmp to final path fails → `pkg_error`, return 1.

### 3.2 `pkg_fhs_read_install_manifest <legacy_path> <fallback_name...>`

Called from **preinst/`%pre`** to obtain the list of orphan candidates
to act on. Behaviour:

- If `<legacy_path>/internals/.install-manifest` exists and is a regular
  file with a valid header line, parse it, validate each entry, and
  print one validated name per line to stdout. Return 0.
- If the manifest is **absent** (the common case for every install that
  predates pkg_lib v1.0.10), print the caller-supplied fallback names
  (one per line) and return 0. This is the backward-compatibility path.
- If the manifest exists but is unreadable, header-mismatched, or
  empty, emit a `pkg_warn`, fall back to the caller's hardcoded list,
  and return 0. **Corrupt manifest never blocks cleanup.**
- If any parsed entry fails validation (contains `/`, `..`, null byte,
  leading `.`, or is empty), drop **that line** with a `pkg_warn`,
  keep the rest. Do not fall back wholesale — a single bad line should
  not mask a good manifest.

**Signature:**

```
pkg_fhs_read_install_manifest <legacy_path> [fallback_name...]
```

- `$1` — legacy install root.
- `$2..$N` — fallback name list used when manifest is absent, empty,
  or corrupt. **Callers pass their current hardcoded list verbatim.**
  Per-project fallback lives at the call site, not in pkg_lib — pkg_lib
  carries zero project-specific state (§ consuming-project convention
  in `pkg_lib/CLAUDE.md`).

**Output contract:**

- One validated name per line on stdout.
- No leading/trailing whitespace, no duplicates.
- Caller reads via `while IFS= read -r _orphan; do ... done < <(pkg_fhs_read_install_manifest ...)`.

**Validation gate (applied to both manifest lines and fallback args):**

```
name_pat='^[A-Za-z0-9_][A-Za-z0-9_.-]*$'
[[ -n "$name" ]] \
  && [[ "$name" =~ $name_pat ]] \
  && [[ "$name" != *..* ]]
```

Rationale: the caller will use each returned name as the trailing
component of `"$LEGACY_PATH/$name"` in `rm -rf "${LEGACY_PATH:?}/$name"`.
A path separator, a `..`, or a null byte in that component is a path
traversal. The gate must reject those **even for fallback arguments**
so misuse by a consuming project cannot turn the primitive into a
foot-gun.

### 3.3 File location and format

**Path:** `<legacy_path>/internals/.install-manifest`

**Format:** newline-delimited UTF-8, deterministic order:

```
# pkg_lib:install-manifest:1
alert
data
internals
ipcountry.dat
rules
stats
tmp
```

(Example for BFD; all seven names sorted lexicographically.)

**Why newline-delimited and not JSON or shell-sourceable:**

- Matches `.symlink-manifest` precedent (same directory, same permission,
  same header schema).
- Grep-friendly for operators debugging a broken migration — no jq,
  no `source`-time side effects.
- Trivial to parse in a preinst scriptlet that runs on CentOS 6 with
  `/bin/sh` dash in the worst case (BFD's preinst has `#!/bin/bash`,
  LMD's preinst also has `#!/bin/bash` — both safe for bash 4.1+
  parsing, but the pkg_lib primitive itself is what parses it, not
  the scriptlet, and pkg_lib is bash 4.1+).
- No injection surface: every line is a bare name, never eval'd.

**Why a new file and not an extension of `.symlink-manifest`:**

- `.symlink-manifest` lives inside `/usr/lib/<proj>/internals/` on an
  installed package. `.install-manifest` lives inside the legacy
  `<legacy_path>/internals/` under a source install. These are
  different paths with different audiences — overloading one file
  would couple two otherwise independent lifecycles.
- `.symlink-manifest` has a tab-delimited `<legacy_link>\t<fhs_target>`
  body; `.install-manifest` is a flat name list. Different schemas
  on the same filename would be a documentation trap.

---

## 4. Per-project integration plans (high-level)

### 4.1 pkg_lib v1.0.10

1. Add `pkg_fhs_emit_install_manifest` and `pkg_fhs_read_install_manifest`
   to `files/pkg_lib.sh` in the FHS section (near line 3080 onwards).
   Follow the style of `pkg_fhs_gen_manifest` and `pkg_fhs_verify_farm`:
   tab-indented bodies, `pkg_error`/`pkg_warn` for diagnostics, no
   dependency on consuming-project logging.
2. Bump `PKG_LIB_VERSION="1.0.9"` (line 32) → `1.0.10`.
3. Add tests to `tests/10-fhs.bats` (or a new `tests/14-install-manifest.bats`
   if the file gets unwieldy — current `10-fhs.bats` is 857 lines per
   `wc -l`, bordering on split-worthy):
   - `emit: writes sorted names under internals/.install-manifest`
   - `emit: rejects names with slash`
   - `emit: rejects names with ..`
   - `emit: rejects empty name args`
   - `emit: rejects missing internals/ directory`
   - `emit: atomic write (no partial file on validation failure)`
   - `emit: 640 permissions after write`
   - `read: returns manifest names when file present`
   - `read: falls back to args when file absent`
   - `read: falls back to args when header mismatch`
   - `read: drops malformed lines but keeps good ones`
   - `read: roundtrip (emit then read returns same list)`
   - `read: validates fallback args (rejects slash in fallback)`
4. Update `CHANGELOG` and `CHANGELOG.RELEASE` with:
   - `[New] pkg_fhs_emit_install_manifest — record top-level source-install names`
   - `[New] pkg_fhs_read_install_manifest — read manifest with hardcoded fallback`
5. Release v1.0.10 as a standalone vendor-syncable drop. **Do not
   fold into v1.0.9** — v1.0.9 is a focused `pkg_config_merge`
   correctness fix that must land as a narrow, imminent release.
   Folding widens the blast radius and delays the fix.

### 4.2 BFD integration (deferred to BFD 2.0.3 or 2.1.0)

- **Vendor sync** `files/internals/pkg_lib.sh` to pkg_lib v1.0.10
  (single vendor-sync commit, same pattern as v1.0.9 vendor sync
  in Phase 0).
- **`brute-force-detection/install.sh`** — after line 45
  (`pkg_copy_tree "./files" "$INSPATH"`) and after the
  `pkg_create_dirs` call at line 49, insert:

  ```
  pkg_fhs_emit_install_manifest "$INSPATH" \
      alert data internals ipcountry.dat rules stats tmp
  ```

  (Argument order is irrelevant — the primitive sorts.)
- **`brute-force-detection/pkg/deb/debian/bfd.preinst`** — replace
  lines 50-64 (the three hardcoded orphan blocks) with a single
  loop driven by `pkg_fhs_read_install_manifest`, passing the current
  hardcoded list as fallback. The internals/ sentinel discriminator
  and `ipcountry.dat` file-vs-dir handling remain at the call site;
  the primitive only provides the **list**, not the cleanup logic.
  See open questions §12 for the sentinel-handling decision.
- **`brute-force-detection/pkg/rpm/bfd.spec`** — same replacement
  at lines 257-273. Identical fallback list.
- Bump BFD version, update `CHANGELOG`/`CHANGELOG.RELEASE`.

### 4.3 LMD integration (deferred to LMD 2.0.2 or 2.1.0)

- **Vendor sync** `files/internals/pkg_lib.sh` to pkg_lib v1.0.10.
- **`linux-malware-detect/install.sh`** — after line 42
  (`pkg_copy_tree "files" "$inspath"`) and after `pkg_create_dirs`
  at lines 48-49, insert:

  ```
  pkg_fhs_emit_install_manifest "$inspath" \
      sigs quarantine sess tmp pub clean logs cron internals
  ```

  Note: LMD's current enumeration uses `internals/alert` as the
  detection sentinel for `internals/` (since `internals/` itself is
  a real dir in both modes). The **manifest** records `internals`;
  the sentinel-vs-manifest semantics are resolved at the preinst
  call site, not in the manifest itself.
- **`linux-malware-detect/pkg/deb/debian/preinst`** — replace line 29's
  inline enumeration with a call to `pkg_fhs_read_install_manifest`,
  passing the current 9-name fallback list. The detect-and-wipe
  control flow (`_lmd_conflict`, backup, stop services, `rm -rf`)
  stays as-is; only the list source changes.
- **`linux-malware-detect/pkg/rpm/maldet.spec`** — same replacement
  at line 267.
- Update `CHANGELOG` / `CHANGELOG.RELEASE` with `[Change] Manifest-driven
  orphan detection in preinst`.

### 4.4 APF integration — **out of scope** (see §2.3)

---

## 5. Migration Path

Purely additive, no behaviour change on existing installs:

1. **pkg_lib v1.0.10** ships with both primitives and tests. No
   consumer impact until vendored.
2. **Consumer vendor sync** updates the in-tree pkg_lib copy. Still
   no behaviour change — `install.sh` does not yet call the emit
   function, and the preinst does not yet call the read function.
3. **Consumer integration commit** wires both ends. After this commit:
   - Fresh source installs (via `install.sh`) emit the manifest.
   - Next package upgrade from that fresh source install uses the
     manifest to drive cleanup — identical behaviour to the current
     hardcoded path because the emitted list equals the hardcoded
     fallback list, by construction.
   - Package upgrades from **older** source installs (which predate
     the integration commit) see no manifest and fall through to
     the caller-passed hardcoded fallback — identical behaviour to
     today.
4. **Future work (not part of this spec):** After one release cycle
   during which the vast majority of the source-install installed
   base has rolled over, the hardcoded fallback in each consumer's
   preinst can be narrowed or removed. Track as a deferred cleanup
   item, not a requirement of Phase 3.

The critical property: **for every migration scenario that works
today, this change is a no-op.** It only improves the story for
future source-install directory additions — those now couple to
`install.sh` automatically.

---

## 6. Dependency Chain

| Step | Depends on | Blocks |
|---|---|---|
| pkg_lib v1.0.9 release (Phase 0) | — | v1.0.10 |
| pkg_lib v1.0.10 release | v1.0.9 (clean base for follow-up) | all consumer syncs |
| BFD vendor sync + integration | v1.0.10 tag | BFD consumer test run |
| LMD vendor sync + integration | v1.0.10 tag | LMD consumer test run |
| Phase 1 migration fixtures | — (parallel track) | integration-commit test signal |

This is the longest dependency chain in the cross-project packaging
hardening initiative — four sequential gates (v1.0.9 → v1.0.10 →
vendor → integration), two of them requiring a fresh release tag.
Surface this fact in the umbrella strategy doc
(`2026-04-08-packaging-hardening-strategy.md`) so the initiative
ordering reflects it.

**The pkg_lib primitives themselves do not depend on Phase 1 fixtures**
— pkg_lib has its own BATS suite and tests in isolation. The
**consumer integration commits** should wait for Phase 1 migration
fixtures to provide a meaningful regression signal; without those
fixtures, the integration commits land on the same test blind spot
that produced the original hotfix cascade.

---

## 7. Testing Strategy

### 7.1 pkg_lib unit tests

Scope: emit and read in isolation, no real package install paths.
Every test uses `mktemp -d` for its scratch legacy root — never
touches `/usr/local/bfd` or `/usr/local/maldetect` (parent CLAUDE.md
test isolation rule).

Required scenarios (both emit and read):

- **Emit roundtrip:** write N names, read them back, assert sorted
  equality.
- **Emit header:** assert first line is `# pkg_lib:install-manifest:1`.
- **Emit permissions:** assert `stat -c '%a'` = `640`.
- **Emit atomicity:** inject a bad name mid-list, assert the final
  file either contains a complete good list or does not exist — no
  partial writes.
- **Emit validation matrix:** slash, `..`, null byte, empty arg,
  leading dot, missing `internals/` directory, missing legacy root.
- **Read-missing:** no manifest file, fallback args returned verbatim.
- **Read-corrupt:** manifest exists with wrong header → fallback used,
  `pkg_warn` emitted.
- **Read-malformed-lines:** manifest has one good line + one bad line,
  good line returned, bad dropped.
- **Read-validates-fallback:** caller passes a fallback containing
  `../etc` or `foo/bar` → rejected by the same gate.

Put tests in `pkg_lib/tests/10-fhs.bats` if the file stays under
~1000 lines after additions, or split into a new
`pkg_lib/tests/14-install-manifest.bats` if it would exceed that.
Judgement call at implementation time; either is acceptable.

### 7.2 Consumer integration tests

The integration commits (§4.2, §4.3) rely on **Phase 1 migration
fixtures** (`HANDOFF-packaging-hardening.md` §Phase 1) to provide a
full pre-staged source install → package upgrade migration scenario.
Without Phase 1, the integration commits cannot be validated beyond
unit-level testing of the manifest file itself.

**Explicit dependency:** The consumer integration commits should
land **after** Phase 1 fixtures ship in BFD and LMD. The pkg_lib
primitive itself has no such dependency — it can ship as soon as its
own tests pass.

Per-project integration tests to add alongside the integration commit:

- **Fresh-install emits manifest:** after `install.sh`, assert
  `$INSPATH/internals/.install-manifest` exists, has the right header,
  is mode 640, and contains every name the caller passed.
- **Missing-manifest fallback:** pre-stage a legacy source install
  with the manifest deleted, run package install, assert cleanup ran
  (reuses Phase 1 pre-stage helpers).
- **Manifest-driven cleanup on upgrade:** pre-stage a source install
  with an **extra** name in the manifest that is not in the hardcoded
  fallback, run package install, assert that extra name was cleaned
  up. This is the regression lock — it fails on the current code
  and passes only once the manifest is wired through.

### 7.3 Test cost and gating

- pkg_lib v1.0.10 full BATS matrix is required before release tag
  (Debian 12 + Rocky 9 minimum per parent CLAUDE.md; full 9-OS matrix
  for a release commit).
- Consumer vendor-sync commits: lint-only suffices (parent CLAUDE.md
  "docs, comments, single-line fixes" tier does not fit here, so
  Debian 12 + Rocky 9 minimum).
- Consumer integration commits: full matrix — they modify preinst
  scriptlets, which are the highest-risk surface in either project.

---

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Fallback list goes stale over time | A manifest-less upgrade fails to clean an orphan added after fallback was written | Keep the fallback list **verbatim identical** to today's hardcoded list in the integration commit. Do not shrink it until a future spec after installed-base rollover. |
| Manifest corruption blocks upgrade | Preinst aborts, install fails | Read primitive never fails on corrupt manifest — it emits `pkg_warn` and falls back. Corrupt manifest is functionally identical to missing manifest. |
| Manifest path traversal via crafted name | `rm -rf "$LEGACY_PATH/../etc"` | Validation gate rejects `/`, `..`, null byte, leading dot, and empty names at **both** emit and read time. Gate also applies to caller-supplied fallback args. |
| pkg_lib primitive called with wrong legacy root | Manifest written to unintended location | Emit validates `legacy_path` is an existing directory with an `internals/` subdirectory; fails early otherwise. |
| Consumer integration without Phase 1 fixtures | Regression escapes CI | Dependency documented in §6 and §7.2. Integration commits should wait for fixtures. Strategy doc surfaces this ordering. |
| LMD preinst uses detection (not cleanup) semantics | Manifest list drives detection; a missing entry produces false-negative detection | Fallback list is the full 9-name current enumeration; missing manifest degrades to today's behaviour. Integration commit preserves the detect-and-wipe control flow unchanged. |
| BFD `internals/` sentinel discriminator | Manifest cannot encode the "real file vs symlink inside" sentinel | Sentinel logic stays at the call site, not in the manifest. The manifest lists `internals` as a name; the caller's loop knows that `internals` requires the sentinel check while the other six orphans do not. See open questions §12. |
| Forgetting to update `install.sh` when adding a source directory | Same drift risk as today, just relocated | The whole point of the primitive: adding a source directory is now a **single-site** change in `install.sh`, not a three-site change across install + preinst + spec. The drift surface shrinks from 3 files to 1 file per project. |
| Schema drift (v1 → v2) | Old preinst cannot read new manifest | Header line includes schema version `pkg_lib:install-manifest:1`. `pkg_fhs_read_install_manifest` rejects unknown schemas with `pkg_warn` and falls back — equivalent to missing manifest. |

---

## 9. Out of Scope

The following are explicitly **not** part of this spec:

- **APF integration.** APF's `%pretrans` full-wipe strategy is a
  different shape than BFD's and LMD's selective orphan cleanup.
  Migrating APF to manifest-driven selective cleanup would be a
  behaviour change with its own risk profile. Revisit in a separate
  follow-up after Phase 2 of the packaging hardening initiative lands.
- **Folding into pkg_lib v1.0.9.** v1.0.9 is a focused correctness
  fix for `pkg_config_merge` and must land imminently. Widening its
  scope to include a new API surface would delay the fix and couple
  two unrelated changes. **Rejected explicitly.**
- **Narrowing or removing the hardcoded fallback lists.** Deferred
  to a future release after one full installed-base rollover cycle.
- **A batsman helper that pre-stages source installs.** That is
  Phase 1's responsibility (Action B in `HANDOFF-packaging-hardening.md`).
- **Retiring `pkg_fhs_verify_farm` duplication between pkg_lib and
  consumers.** Unrelated to orphan cleanup.
- **Changing the symlink manifest schema or format.**

---

## 10. Target Releases

- **pkg_lib v1.0.10** — primitives + tests + CHANGELOG, tag cut.
- **BFD 2.0.3 or 2.1.0** — vendor sync + integration commit, on a
  branch that does not block current 2.0.2 PRs. Decide at integration
  time which release train is appropriate.
- **LMD 2.0.2 or 2.1.0** — same shape as BFD, decided at integration
  time.
- **APF** — no release target (out of scope).

All three project integrations are **out-of-tree** relative to the
current 2.0.x PRs — this Phase 3 work must not block imminent
shipping work on any project.

---

## 11. Acceptance Criteria

A release of pkg_lib v1.0.10 is accepted when:

1. `pkg_fhs_emit_install_manifest` and `pkg_fhs_read_install_manifest`
   are present in `files/pkg_lib.sh`, follow existing FHS primitive
   style (tab indent, `pkg_error`/`pkg_warn`, no project-specific
   references).
2. `PKG_LIB_VERSION` is bumped to `1.0.10`.
3. BATS unit tests cover every scenario in §7.1 and all pass on
   Debian 12 + Rocky 9 + CentOS 6 (bash 4.1 floor).
4. `CHANGELOG` and `CHANGELOG.RELEASE` have new `[New]` entries for
   both primitives.
5. `bash -n` and `shellcheck` pass on `files/pkg_lib.sh`.
6. No project-specific strings present in `files/pkg_lib.sh` (parent
   CLAUDE.md shared-library rule §2).

A consumer integration commit (BFD or LMD) is accepted when:

1. Vendor-synced `pkg_lib.sh` matches pkg_lib v1.0.10 byte-for-byte.
2. `install.sh` calls `pkg_fhs_emit_install_manifest` exactly once,
   with the full current orphan list as arguments.
3. Preinst and RPM `%pre` both call `pkg_fhs_read_install_manifest`
   with the same fallback list; no divergence between DEB and RPM.
4. Fallback list passed to `pkg_fhs_read_install_manifest` matches
   the **current** hardcoded list verbatim (no shrinking in this
   commit).
5. A migration test (from Phase 1 fixtures) demonstrates the
   manifest-driven path is exercised — ideally the "extra name in
   manifest" regression lock from §7.2.
6. `bash -n` and `shellcheck` pass on install.sh and the preinst.
7. CHANGELOG / CHANGELOG.RELEASE updated per project commit protocol.

---

## 12. Open Questions

These are flagged for resolution during implementation (not blocking
spec approval). None materially alter the design decisions above.

1. **BFD `internals/` sentinel handling.** The current BFD preinst
   uses a sentinel check (`internals/bfd.lib.sh` being a real file vs
   a symlink) to distinguish source installs from package installs
   for the `internals/` directory only. The manifest can list
   `internals` as a name, but the preinst still needs the sentinel
   check — a package install also has a real `internals/` directory
   containing symlinks. **Question:** should the manifest-driven
   loop special-case `internals`, or should the preinst keep
   `internals` out of the manifest and handle it separately as
   today? **Recommendation:** keep `internals` out of the manifest
   emit list for BFD; the sentinel logic is a genuine BFD-specific
   concern, not a candidate for generalisation. LMD has the same
   issue — its current enumeration uses `internals/alert` as the
   LMD sentinel for the same reason. Resolve per-project at
   integration time.

2. **LMD `internals/alert` vs `internals` in the manifest.** LMD's
   current detection list contains `internals/alert` (a nested
   path). The manifest primitive rejects names containing `/`.
   **Question:** does LMD emit `internals` or special-case the
   nested sentinel outside the manifest? **Recommendation:** same
   as BFD — keep nested-path sentinels at the call site, not in
   the manifest. The manifest encodes top-level source-install
   names only. Document this in the primitive's header comment.

3. **Test file split threshold.** `pkg_lib/tests/10-fhs.bats` is
   already 857 lines. Adding ~13 new tests would push it near or
   past 1000. **Question:** split into `14-install-manifest.bats`
   now, or keep in `10-fhs.bats`? Judgement call for the
   implementer — either is acceptable per parent CLAUDE.md.

4. **`.install-manifest` under `internals/` vs at legacy root.**
   The spec chose `<legacy_path>/internals/.install-manifest` for
   symmetry with `.symlink-manifest`. An alternative is
   `<legacy_path>/.install-manifest` at the legacy root. The
   chosen location avoids cluttering the legacy root with
   dotfiles; `internals/` is already conventionally "stuff
   users don't touch." **Not a blocker, but the decision is
   irreversible once the first v1.0.10 tag ships** — confirm
   with stakeholders before tagging.

5. **Atomic write filesystem assumption.** The emit primitive
   uses `mktemp` + `mv` inside `internals/` for atomicity. This
   requires `mktemp` to honour the directory hint (`-p` or
   `--tmpdir`). **Question:** any OS target in the matrix
   (CentOS 6, FreeBSD) where `mktemp -p` is unavailable or
   behaves differently? CentOS 6 coreutils ship `mktemp` with
   `-p` support. FreeBSD `mktemp` lacks `-p` but pkg_lib targets
   the Linux install path primarily. **Recommendation:** use
   `mktemp "<dir>/.install-manifest.XXXXXX"` (positional template)
   which works on every target. Verify at implementation time.

6. **Sort order determinism across locales.** Sorting the manifest
   body for deterministic diffs requires a stable locale. `LC_ALL=C`
   sort is the only reliable choice. **Recommendation:** set
   `LC_ALL=C` locally inside the emit function (`local LC_ALL=C`
   with a `sort` pipeline, or use bash `readarray` + mapfile
   — except `mapfile -d` is banned by the bash 4.1 floor, so use
   `while IFS= read`). Confirmed at implementation time.

7. **Does pkg_lib ship its own `pkg_fhs_emit_install_manifest`
   example in the header comment?** Existing FHS primitives in
   `pkg_lib.sh` have short usage hints in their function comments
   (see lines 2731, 2769, 2838). The new primitives should follow
   the same convention. Non-blocking — style consistency.
