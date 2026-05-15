# RDF — Plan Canonicalization Design

**Date:** 2026-05-15
**Status:** Design draft (awaiting review)
**Companion:** sibling state-collision design at `docs/specs/2026-04-25-concurrent-sessions-design.md` (Wave A, shipped 3.1.0)

Move the active-plan storage from `PLAN.md` at the project root (gitignored, single-slot, prone to clobbering between sessions) to `docs/plans/{YYYY-MM-DD}-{topic}-plan.md` (committed at creation, named, multiple coexist). Eliminates the "plan written in session N is silently overwritten by session N+1" class of failure. Mirrors the existing r-spec convention for `docs/specs/`. Back-compat preserved through a transitional resolver that falls back to root `PLAN.md` when no pointer is set.

---

## 1. Problem Statement

The active plan during a build lives at root `PLAN.md`. The file is gitignored (in `.git/info/exclude` and partially also tracked as a stale snapshot — see Risk 5). `r-plan` writes it on creation; `r-build`/`dispatcher` read it; `r-save`/`r-ship`/`r-status`/`r-refresh` read or sync from it. The optional Step 3.3 "Commit the plan? [Y/n]" prompt commits only the *spec*, never the plan — `PLAN.md` is gitignored.

**Observed loss:** The v2-chrome-promotion plan (built in session 989b26fd, 2026-05-14 22:25 CDT; 12-phase plan for a blacklight repo re-skin) was written to `PLAN.md` and never copied to `docs/plans/`. A subsequent session overwrote `PLAN.md` with the forensic-stream-indexing plan, and a third session overwrote that with the plan for *this* very topic. The plan now lives only in conversation transcripts on the Claude harness ring buffer.

**Quantification:**

| Metric | Value | Source |
|---|---:|---|
| `PLAN.md` references across canonical/lib/state | **132** | `grep -rn 'PLAN\.md'` |
| Files referencing `PLAN.md` | **20** | grep above |
| Plans committed in `docs/plans/` | **18** (+9 archived) | `ls docs/plans/` |
| Plans ever committed at root | **1** (3.0.3 snapshot at `6308d6d`, never updated) | `git log --all -- PLAN.md` |
| Loss incidents in last 30 days | **≥1** confirmed (v2-chrome-promotion) | transcript forensics |

**Infrastructure already named-plan-friendly:**
- `.git/info/exclude` already lists `PLAN.md`, `PLAN*.md`, `PLAN-*.md`
- `lib/cmd/doctor.sh:202-208` globs `PLAN*.md` (returns count, not single file)
- `docs/plans/` is committed per `rdf/CLAUDE.md` ("Specs (`docs/specs/`) and plans (`docs/plans/`) ARE committed")
- Phase execution state already lives outside the plan file (see Section 1a below) — moving the plan doesn't require touching the status mechanism

**Infrastructure NOT yet named-plan-friendly (these are blockers the migration must fix):**
- `.git/info/exclude` line 18 contains `docs/` — newly written plan files under `docs/plans/` would be gitignored. The two existing tracked plans (`2026-04-25-...`, `2026-04-26-...`) survive because they were committed before that exclude line was added. Verified: `git check-ignore -v docs/plans/2026-99-test.md` → `.git/info/exclude:18:docs/`. **This line must be removed before Phase 1 executes.**
- `lib/cmd/generate.sh:_generate_deploy_state_helpers` (lines 37-51) deploys `rdf-state.sh`, `context-audit.sh`, `rotate-work-output.sh` to `~/.rdf/state/` but does NOT deploy `rdf-bus.sh`. The new resolver helpers must be reachable from consumers — `rdf-bus.sh` must be added to the deploy list.

### 1a. Where phase status actually lives today

The framework reference (`canonical/reference/framework.md:55-62`) lists status markers (`pending`/`in-progress`/`complete`/`deferred`/`blocked`) as if they were inline in `PLAN.md`. **In practice the existing committed plans in `docs/plans/` contain no status markers** (verified: `grep -E 'status:|Status:' docs/plans/2026-04-26-reviewer-roi-3.1.1-plan.md` returns zero hits; only `**Mode**` fields exist). Phase completion is derived from:

1. `STATUS: DONE` / `STATUS: DONE_WITH_CONCERNS` in `.rdf/work-output/phase-N-result-${SESSION}.md` (engineer-written, read by dispatcher)
2. `git log --oneline` cross-reference against phase description (read by `r-save.md:95-110`)
3. Trailing `---` rule per phase (crash-safety marker, read by `r-plan` `--resume`)

The "PLAN.md is the source of truth for phase status" mental model is partially myth. **Moving the plan to `docs/plans/` does not require rewriting the status model** — it formalizes what already exists.

### 1b. Codebase Inventory

| File | Lines | Key Functions / Sections | PLAN.md refs | Test File |
|---|---:|---|---:|---|
| `canonical/commands/r-plan.md` | 573 | Step 2 Write PLAN.md (l.132); Step 3.3 Commit (l.479-493) | 13 | `tests/adapter.bats` |
| `canonical/commands/r-build.md` | 346 | §1 Locate and Validate PLAN.md (l.18-46); §2b worktree dispatch | 13 | `tests/adapter.bats` |
| `canonical/commands/r-ship.md` | 308 | Verify ALL phases complete (l.46-48) | 2 | `tests/adapter.bats` |
| `canonical/commands/r-save.md` | 387 | §2 Sync PLAN.md (l.93-125) | 9 | `tests/adapter.bats` |
| `canonical/commands/r-status.md` | 221 | Read plan, derive build stage (l.17-117) | 6 | `tests/adapter.bats` |
| `canonical/commands/r-vpe.md` | 219 | Plan dispatch text (l.147-200) | 2 | `tests/adapter.bats` |
| `canonical/commands/r-start.md` | 232 | Plan preview block (l.172-228) | 3 | `tests/adapter.bats` |
| `canonical/commands/r-refresh.md` | 344 | §5b Refresh PLAN.md (l.176-265) | 5 | `tests/adapter.bats` |
| `canonical/agents/dispatcher.md` | 480 | Load (l.13); Worktree PLAN.md sync (l.55-75); commit (l.475) | 13 | `tests/adapter.bats` |
| `canonical/agents/engineer.md` | 181 | Scope read (l.30) | 1 | `tests/adapter.bats` |
| `canonical/reference/framework.md` | 271 | Status markers (l.55-62); plan inventory (l.235) | 5 | `tests/adapter.bats` |
| `canonical/reference/session-safety.md` | 78 | Plan sync table (l.15, l.73) | 6 | `tests/adapter.bats` |
| `canonical/reference/progress-tracking.md` | 57 | PLAN.md reference (l.~) | 1 | `tests/adapter.bats` |
| `canonical/reference/plan-schema.md` | 336 | Three-call-site enforcement table (l.185, l.317) | 5 | `tests/adapter.bats` |
| `lib/cmd/refresh.sh` | 395 | `_refresh_plan` l.134; issue cross-ref l.221-280 | 14 | `tests/rdf-bus.bats` |
| `lib/cmd/dispatch.sh` | 60 | Usage examples l.50-53 | 4 | N/A (usage doc) |
| `lib/cmd/doctor.sh` | 898 | `_check_plan` l.198-225 (already globs `PLAN*.md`) | 0 (uses glob) | N/A |
| `state/rdf-bus.sh` | 110 | `rdf_uuidv7`, `rdf_session_init`, `rdf_scoped_filename`, `rdf_session_short`, `rdf_parse_phase_scope` | 0 | `tests/rdf-bus.bats` |
| `state/rotate-work-output.sh` | 98 | Reads PLAN.md to protect active basenames l.43-56 | 4 | N/A |
| `state/git-hooks/pre-commit` | 207 | Locates project root via PLAN.md ancestor walk l.15-26; parses scope l.49-55 | 6 | `tests/pre-commit-anti-patterns.bats` + `tests/rdf-bus.bats` |
| **`.gitignore`** | 18 | Currently does not list `PLAN.md` (only `.git/info/exclude` does) | 0 | N/A |
| `lib/cmd/generate.sh` | ~150 | `_generate_deploy_state_helpers` loop (l.37-51) — must add `rdf-bus.sh` to deploy list | 0 | `tests/adapter.bats` |
| `.git/info/exclude` | 18 | Line 18 (`docs/`) blocks new plan commits; must be removed | 0 | N/A (verified via `git check-ignore`) |

**Test files (pre-existing infra):**

| File | Lines | Purpose |
|---|---:|---|
| `tests/adapter.bats` | 509 | Verifies canonical content regenerates correctly to adapter output |
| `tests/rdf-bus.bats` | 161 | Tests rdf-bus helpers + pre-commit hook against fixture repos |
| `tests/pre-commit-anti-patterns.bats` | 139 | Tests pre-commit hook anti-pattern checks |
| `tests/fixtures/` | (dir) | Fixture data for the above |

**Dependency chain (sourcing/import order):**

```
state/rdf-bus.sh   (no deps — provides helpers)
        ↑
        ├── state/git-hooks/pre-commit      (sources rdf-bus.sh)
        ├── tests/rdf-bus.bats              (sources rdf-bus.sh)
        ├── lib/cmd/*.sh                    (transitively via shell scripts that source state helpers)
        └── canonical/agents/dispatcher.md  (documents the contract)

canonical/commands/r-plan.md   ─writes→ docs/plans/{date}-{topic}-plan.md (NEW)
                               ─writes→ .rdf/active-plan-${SESSION_ID}   (NEW pointer)
                               (LEGACY: writes PLAN.md at root)

canonical/commands/r-build.md       ─reads→ rdf_active_plan_path  ─→ pointer | PLAN.md fallback
canonical/agents/dispatcher.md      ─reads→ rdf_active_plan_path
canonical/commands/r-save.md        ─reads→ rdf_active_plan_path
canonical/commands/r-status.md      ─reads→ rdf_active_plan_path
canonical/commands/r-ship.md        ─reads→ rdf_active_plan_path,  ─calls→ rdf_clear_active_plan after release
canonical/commands/r-refresh.md     ─reads→ rdf_active_plan_path
canonical/commands/r-start.md       ─reads→ rdf_active_plan_path
canonical/commands/r-vpe.md         ─reads→ rdf_active_plan_path (output text only)

lib/cmd/refresh.sh                  ─sources→ rdf-bus.sh, calls→ rdf_active_plan_path
state/rotate-work-output.sh         ─sources→ rdf-bus.sh, calls→ rdf_active_plan_path
state/git-hooks/pre-commit          ─sources→ rdf-bus.sh, calls→ rdf_active_plan_path
```

**Existing patterns to preserve:**
- All shell uses `set -euo pipefail`, `command <util>` prefix, double-quoted vars, `#!/usr/bin/env bash`
- All canonical content is frontmatter-free markdown; adapter regen (`rdf generate claude-code`) deploys to `~/.claude/`
- Plan files are named `YYYY-MM-DD-{topic}-plan.md` (existing 18-file pattern in `docs/plans/`)
- Spec files are named `YYYY-MM-DD-{topic}-design.md` (existing pattern in `docs/specs/`)
- Status state lives in `.rdf/work-output/`, suffixed with `-${RDF_SESSION_ID}`

---

## 2. Goals

1. New plans land at `docs/plans/{YYYY-MM-DD}-{topic}-plan.md` and are committed by `/r-plan` at creation (no longer optional).
2. A pointer file `.rdf/active-plan-${RDF_SESSION_ID}` (gitignored) records the active plan for the current session. When `RDF_SESSION_ID` is unset, falls back to `.rdf/active-plan`.
3. All consumers (commands, agents, lib scripts, state scripts, hook) resolve the active plan via a single helper `rdf_active_plan_path` exported from `state/rdf-bus.sh`.
4. The resolver supports a transitional fallback: pointer file → root `PLAN.md` (legacy) → empty string.
5. Worktree dispatch copies the named plan file (not literally `PLAN.md`) into the worktree at the same `docs/plans/` relative path.
6. The stale tracked `PLAN.md` snapshot (committed at `6308d6d`, never updated) is `git rm --cached`-ed and added to `.gitignore`.
7. `r-ship` clears the pointer (`rdf_clear_active_plan`) after a successful release; the named plan in `docs/plans/` remains as historical record.
8. `r-plan --resume` works against the pointer-target plan, not root `PLAN.md`.
9. Two concurrent sessions on the same repo, building different plans, do not collide on pointer or status files (pointer is session-scoped).
10. All 132 existing PLAN.md references either: (a) route through the resolver, or (b) refer to the legacy fallback by explicit name, or (c) refer to output-text formatting (no code path).
11. `tests/adapter.bats` passes; `tests/rdf-bus.bats` covers the three new helpers; new tests cover pointer-write, pointer-read, fallback, and clear lifecycle.

---

## 3. Non-Goals

- **Not** modifying the phase-status model (already lives in `.rdf/work-output/phase-N-result-${SESSION}.md`).
- **Not** changing the plan file format or schema (`plan-schema.md` Rules 1-9 untouched).
- **Not** adding a plan-status aggregator file. Status remains distributed across per-phase result files.
- **Not** removing the legacy `PLAN.md` read path. The resolver keeps it as a fallback for transitional projects.
- **Not** auto-migrating existing root-`PLAN.md`-bearing projects. They keep working via fallback; users opt in by re-planning.
- **Not** touching CHANGELOG or version bump as part of this work's first commit — those land in the final release phase.
- **Not** introducing symlinks at root. Pointer file is plain text.
- **Not** removing `dispatcher.md`'s worktree-copy mechanism. Path source changes; mechanism stays.
- **Not** changing `r-spec` (already writes to `docs/specs/` — that pattern is the target).
- **Not** introducing parallel plan execution semantics. One session = one active plan, same as today.

---

## 4. Architecture

### 4.1 File Map

#### New Files

| File | Lines (est.) | Purpose |
|---|---:|---|
| `docs/specs/2026-05-15-plan-canonicalization-design.md` | (this file) | Design spec |
| `tests/plan-canonicalization.bats` | ~120 | BATS coverage for resolver, pointer write/read/clear, fallback |
| `tests/fixtures/plan-canon/legacy-plan-md/PLAN.md` | ~10 | Fixture: minimal legacy root PLAN.md |
| `tests/fixtures/plan-canon/canonical/docs/plans/2026-05-15-test-plan.md` | ~10 | Fixture: minimal canonical plan |

#### Modified Files

| File | Change |
|---|---|
| `state/rdf-bus.sh` | Add `rdf_active_plan_path`, `rdf_set_active_plan`, `rdf_clear_active_plan` (~50 lines). Update header function inventory. |
| `canonical/commands/r-plan.md` | Step 2 writes `docs/plans/{date}-{topic}-plan.md` directly; Step 3.3 commit becomes mandatory; Resume Protocol reads via resolver. |
| `canonical/commands/r-build.md` | §1 reads via resolver; §2b worktree dispatch copies resolver result. |
| `canonical/commands/r-ship.md` | Reads via resolver; calls `rdf_clear_active_plan` after successful release commit. |
| `canonical/commands/r-save.md` | §2 reads via resolver. |
| `canonical/commands/r-status.md` | Reads via resolver; output text shows the named plan path, not `PLAN.md`. |
| `canonical/commands/r-vpe.md` | Output text shows named plan path. |
| `canonical/commands/r-start.md` | Reads via resolver. |
| `canonical/commands/r-refresh.md` | §5b reads via resolver; issue cross-ref reads via resolver. |
| `canonical/agents/dispatcher.md` | Load reads via resolver; worktree sync uses resolver+basename. |
| `canonical/agents/engineer.md` | Scope read mentions resolver. |
| `canonical/reference/framework.md` | Status markers section: clarify status lives in work-output, not in plan body. Plan inventory updated. |
| `canonical/reference/session-safety.md` | Plan sync table: update to resolver-based reading. |
| `canonical/reference/progress-tracking.md` | One-line reference update. |
| `canonical/reference/plan-schema.md` | Three-call-site enforcement table: rule-application points unchanged; just rewords "after PLAN.md write" → "after plan write". |
| `lib/cmd/refresh.sh` | Source rdf-bus, replace `${project_path}/PLAN.md` lookups with `$(rdf_active_plan_path "$project_path")`. |
| `lib/cmd/dispatch.sh` | Usage examples reference named plan paths. |
| `lib/cmd/doctor.sh` | `_check_plan` already globs — add active-plan resolution check (pointer points to existing file). |
| `state/rotate-work-output.sh` | Source rdf-bus; use resolver instead of `${_project_root}/PLAN.md`. |
| `state/git-hooks/pre-commit` | Ancestor walk: locate project root by walking for `.rdf/` OR `PLAN.md` OR a non-empty `docs/plans/`. Use resolver to find plan file. |
| `.gitignore` | Add `PLAN.md`, `PLAN*.md`, `PLAN-*.md`, `.rdf/active-plan*`. |
| `lib/cmd/generate.sh` | Add `rdf-bus.sh` to `_generate_deploy_state_helpers` loop (line 41) so resolver helpers reach consumer projects. |
| `.git/info/exclude` | Remove line 18 (`docs/`) — blocks commits of new plan files. **Manual operator action**, not part of any commit (this file is local-only, never tracked). |
| `(git index)` | `git rm --cached PLAN.md` (untrack stale 3.0.3 snapshot — handled in migration phase). |

#### Deleted Files

None. The root `PLAN.md` on disk gets untracked, not deleted — operators may keep it as a legacy working file until they re-plan, and the resolver supports the fallback.

#### No-Touch Files

The following files are explicitly out of scope. An engineer touching any of these is over-stepping the phase boundary and the dispatcher should reject the commit:

| File / Path | Reason it stays untouched |
|---|---|
| `bin/rdf` | CLI entry point; argument parsing unchanged |
| `lib/rdf_common.sh` | Common helpers used by `rdf_init`; no plan-related changes |
| `state/rdf-state.sh` | Project-state JSON emitter; reads PLAN existence as a flag, not the path (line 148 uses `[[ -f PLAN.md ]]` which is appropriate signal for "any plan exists" — keep as-is, no resolver call needed) |
| `state/context-audit.sh` | Token-weight audit; out of scope |
| `tests/infra/` | batsman submodule; vendored |
| `lib/cmd/doctor.sh` `_check_plan` | Already globs `PLAN*.md` for diagnostic. May receive an additive line to also check pointer state — diagnostic only, no behavioral change |
| `CHANGELOG`, `CHANGELOG.RELEASE`, `VERSION`, `README.md`, `RDF.md` | Touched only in the final release phase, not in any feature phase |
| `adapters/*/adapter.sh`, `adapters/*/output/` | Adapter regen runs in the release phase; adapter logic is unchanged |
| All `canonical/skills/*.md` and other agent files not listed in Section 4.1 | Out of scope |

Engineers must not refactor adjacent code "while they're in there." Comment pruning is permitted (per rdf/CLAUDE.md), but no behavioral changes outside the file map.

### 4.2 Size Comparison

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| `state/rdf-bus.sh` | 110 | ~160 | +50 |
| `canonical/commands/r-plan.md` | 573 | ~580 | +7 |
| `canonical/agents/dispatcher.md` | 480 | ~485 | +5 |
| `lib/cmd/refresh.sh` | 395 | ~395 | ±0 (in-place replace) |
| `state/rotate-work-output.sh` | 98 | ~100 | +2 |
| `state/git-hooks/pre-commit` | 207 | ~210 | +3 |
| `tests/plan-canonicalization.bats` | 0 | ~120 | +120 |
| `.gitignore` | 18 | 22 | +4 |
| Total source delta | — | — | **~+200 lines net** |

### 4.3 Key Changes

**Plan write path (r-plan):**

```
BEFORE:
  Step 2: Write PLAN.md   ──→ root PLAN.md (gitignored, ephemeral)
  Step 3.3: Commit? [Y/n] ──→ commits spec only (PLAN.md is gitignored)

AFTER:
  Step 2: Write plan      ──→ docs/plans/{YYYY-MM-DD}-{topic}-plan.md
                          ──→ .rdf/active-plan-${SESSION_ID}  (pointer)
  Step 3.3: Commit (mandatory)  ──→ git add docs/plans/{name}.md; commit
```

**Plan read path (all consumers):**

```
BEFORE:
  read "${project_root}/PLAN.md"   ──→ implicit single slot

AFTER:
  plan_path="$(rdf_active_plan_path "$project_root")"
  [[ -z "$plan_path" ]] && { error "No active plan"; exit 1; }
  read "$plan_path"

Resolver internal:
  1. If .rdf/active-plan-${RDF_SESSION_ID} exists and points to a real file → return that path
  2. Else if .rdf/active-plan (no session suffix) exists and points to a real file → return that path
  3. Else if PLAN.md exists at project root → return PLAN.md  (LEGACY FALLBACK)
  4. Else → emit empty string, return 1
```

**Worktree dispatch:**

```
BEFORE (dispatcher.md:70):
  command cp "${PROJECT_ROOT_MAIN}/PLAN.md" "${PROJECT_ROOT}/PLAN.md"

AFTER:
  _main_plan="$(rdf_active_plan_path "$PROJECT_ROOT_MAIN")"
  _rel_path="${_main_plan#$PROJECT_ROOT_MAIN/}"
  command mkdir -p "${PROJECT_ROOT}/$(command dirname "$_rel_path")"
  command cp "$_main_plan" "${PROJECT_ROOT}/${_rel_path}"
  # Then set pointer inside the worktree to the worktree-relative path:
  rdf_set_active_plan "${PROJECT_ROOT}/${_rel_path}" "$PROJECT_ROOT"
```

**Pre-commit hook ancestor walk:**

```
BEFORE: walk up looking for PLAN.md
AFTER:  walk up looking for .rdf/ OR (docs/plans/ AND state/rdf-bus.sh)
        Then call rdf_active_plan_path to locate the actual plan file
        Then call rdf_parse_phase_scope on that path
```

**Stale tracked snapshot cleanup:**

```
git rm --cached PLAN.md   # remove the 6308d6d snapshot from index
                          # file stays on disk (operator's working copy)
echo 'PLAN.md'         >> .gitignore  # paper-trail of untrack
echo 'PLAN-*.md'       >> .gitignore
echo 'PLAN*.md'        >> .gitignore
echo '.rdf/active-plan*' >> .gitignore
```

### 4.4 Dependency Rules

1. `rdf_active_plan_path` is the single point of truth. No consumer may grep, glob, or assume `PLAN.md` directly except `lib/cmd/doctor.sh` which already globs for diagnostic purposes (kept as-is).
2. The resolver's session-scoped pointer takes precedence over the un-suffixed pointer. The un-suffixed pointer takes precedence over the legacy `PLAN.md`. No other lookup paths.
3. The pointer file is **never** committed. `.gitignore` enforces.
4. Plan files in `docs/plans/` are **immutable post-commit**. Phase status updates go to `.rdf/work-output/`, not to the plan body. (This is current behavior — formalized.)
5. `r-ship` clearing the pointer is the only authorized post-release pointer mutation. `r-save` reads but does not clear.
6. The worktree pointer points at the worktree-local plan copy, not the main repo's plan path. This isolates worktree dispatch from main-repo pointer churn.

---

## 5. File Contents

### 5.1 `state/rdf-bus.sh` — new helper functions

Three new functions, appended after `rdf_parse_phase_scope`:

| Function | Signature | Purpose | Dependencies |
|---|---|---|---|
| `rdf_active_plan_path` | `(project_root="$PWD") → stdout: abs path or ""` | Resolve current active plan. Returns 0 if found, 1 if not. | `rdf_session_init`, filesystem |
| `rdf_set_active_plan` | `(plan_path, project_root="$PWD") → exit 0/1` | Write session-scoped pointer file. Creates `.rdf/` if missing. Validates plan_path exists. | `rdf_session_init` |
| `rdf_clear_active_plan` | `(project_root="$PWD") → exit 0` | Remove the session-scoped pointer only. Idempotent — silently succeeds if no pointer. The un-suffixed `.rdf/active-plan` is NOT touched: the new flow never writes it (it exists only as a legacy fallback from pre-resolver state), so `r-ship` has no authority to remove it. | `rdf_session_init` |

**Function bodies (canonical):**

```bash
# rdf_active_plan_path [project_root] — resolve active plan path
# Resolution order:
#   1. .rdf/active-plan-${RDF_SESSION_ID}  (session-scoped)
#   2. .rdf/active-plan                    (un-suffixed default)
#   3. PLAN.md                             (legacy fallback)
# Returns 0 with path on stdout if found; 1 with empty stdout otherwise.
rdf_active_plan_path() {
    local root="${1:-$PWD}" pointer plan
    rdf_session_init
    # Session-scoped pointer
    pointer="${root}/.rdf/active-plan-${RDF_SESSION_ID}"
    if [[ -f "$pointer" ]]; then
        plan="$(< "$pointer")"
        plan="${plan%[$'\r\n']}"
        plan="${plan%[$'\r\n']}"
        if [[ -n "$plan" && -f "$plan" ]]; then
            printf '%s\n' "$plan"
            return 0
        fi
    fi
    # Un-suffixed pointer
    pointer="${root}/.rdf/active-plan"
    if [[ -f "$pointer" ]]; then
        plan="$(< "$pointer")"
        plan="${plan%[$'\r\n']}"
        plan="${plan%[$'\r\n']}"
        if [[ -n "$plan" && -f "$plan" ]]; then
            printf '%s\n' "$plan"
            return 0
        fi
    fi
    # Legacy fallback
    if [[ -f "${root}/PLAN.md" ]]; then
        printf '%s\n' "${root}/PLAN.md"
        return 0
    fi
    return 1
}

# rdf_set_active_plan <plan_path> [project_root] — write pointer
# plan_path may be relative or absolute; it is absolutized before write
# so consumers can rely on the pointer always containing an abs path.
rdf_set_active_plan() {
    local plan="${1:?rdf_set_active_plan requires plan path}"
    local root="${2:-$PWD}"
    rdf_session_init
    # Absolutize plan path
    if [[ "$plan" != /* ]]; then
        plan="$(command pwd)/${plan}"
    fi
    if [[ ! -f "$plan" ]]; then
        printf 'rdf_set_active_plan: plan file does not exist: %s\n' "$plan" >&2
        return 1
    fi
    command mkdir -p "${root}/.rdf"
    printf '%s\n' "$plan" > "${root}/.rdf/active-plan-${RDF_SESSION_ID}"
}

# rdf_clear_active_plan [project_root] — remove session pointer
rdf_clear_active_plan() {
    local root="${1:-$PWD}"
    rdf_session_init
    command rm -f "${root}/.rdf/active-plan-${RDF_SESSION_ID}"
}
```

Header comment block (lines 5-8) updated to reflect new exports:

```bash
# Provides: rdf_session_init, rdf_scoped_filename, rdf_session_short,
#           rdf_parse_phase_scope, rdf_active_plan_path,
#           rdf_set_active_plan, rdf_clear_active_plan.
```

### 5.2 `canonical/commands/r-plan.md` — write to `docs/plans/`

Change inventory:

| Function/Section | Current behavior | New behavior | Lines affected |
|---|---|---|---|
| Step 2 header (l.132) | "Write PLAN.md" | "Write Plan File" | 132 |
| Step 2.1 file path (l.455) | `File: PLAN.md` | `File: docs/plans/{YYYY-MM-DD}-{topic}-plan.md` | 455 |
| Step 2.7 schema validation (l.374-399) | reads "PLAN.md" | reads the just-written plan path | 374 |
| Step 3.1 review block (l.455-456) | `File: PLAN.md` | `File: docs/plans/{name}.md` | 455 |
| Step 3.2 summary text (l.467) | "Plan written to: PLAN.md" | "Plan written to: docs/plans/{name}.md" | 467 |
| Step 3.3 commit (l.479-493) | Optional commit (PLAN.md gitignored anyway) | Mandatory commit (plan file is tracked); pointer set; commit msg updated | 479-493 |
| Resume Protocol (l.67-89) | Reads `PLAN.md` | Reads via `rdf_active_plan_path` | 67-89 |
| Completion Handoff (l.502-505) | "PLAN.md (N phases)" | "docs/plans/{name}.md (N phases)" | 502-505 |
| Auto-detect logic (l.12, 24-32) | (still scans docs/specs/ — unchanged) | (unchanged) | — |

**New Step 2.0 (Choose Plan Filename)** added before existing Step 2 content:

```
### 2.0 Determine Plan File Path

Derive the plan filename:
  TODAY="$(command date +%Y-%m-%d)"
  TOPIC="{slugified topic from spec or user input}"
  PLAN_FILE="docs/plans/${TODAY}-${TOPIC}-plan.md"

If PLAN_FILE already exists:
  - Append a disambiguating suffix: -v2, -v3, etc.
  - Or: prompt user for alternate slug

Create docs/plans/ if absent (rare — should already exist).
```

**New Step 3.3.1 (Set Pointer):**

```
### 3.3.1 Set the Active-Plan Pointer

After committing the plan file:
  source state/rdf-bus.sh
  rdf_set_active_plan "$PLAN_FILE"

This records the plan as active for the current session.
The pointer is gitignored.
```

### 5.3 `canonical/agents/dispatcher.md` — resolver-driven read + worktree sync

Change inventory:

| Section | Current | New | Lines affected |
|---|---|---|---|
| Role description (l.6) | "read PLAN.md" | "read the active plan (resolved via `rdf_active_plan_path`)" | 6 |
| Load step (l.13) | "Read PLAN.md" | "Read the active plan (resolver)" | 13 |
| Worktree PLAN.md sync (l.55-92) | `cp PROJECT_ROOT_MAIN/PLAN.md → PROJECT_ROOT/PLAN.md` | `cp resolver-result → same relative path in worktree; set worktree pointer` | 55-92 |
| Post-merge scope check eval (l.110) | `eval "$(rdf_parse_phase_scope PLAN.md $N)"` | `eval "$(rdf_parse_phase_scope $(rdf_active_plan_path) $N)"` | 110 |
| Red/Green Decision (l.325) | "update PLAN.md" | "update phase result file" (clarify status doesn't live in plan body) | 325 |
| Commit Strategy (l.475) | "from PLAN.md phase description" | "from active-plan phase description" | 475 |

### 5.4 `state/git-hooks/pre-commit` — ancestor walk + resolver

Change inventory:

| Section | Current | New | Lines affected |
|---|---|---|---|
| Ancestor walk (l.15-26) | walks for `PLAN.md` | walks for `state/rdf-bus.sh` (RDF-anchor) | 15-26 |
| Plan path resolution (l.49) | `rdf_parse_phase_scope "$_proj/PLAN.md"` | `_plan="$(rdf_active_plan_path "$_proj")"; rdf_parse_phase_scope "$_plan"` | 49 |

Rationale for changing the ancestor anchor: previously `PLAN.md` served two roles — "we are in an RDF project" AND "this is the plan." Splitting them: `state/rdf-bus.sh` is the RDF anchor; the plan is whatever resolver returns. Avoids a chicken-and-egg when projects re-plan and have no `PLAN.md` at root.

### 5.5 `lib/cmd/refresh.sh`, `state/rotate-work-output.sh` — resolver wiring

Each script's source-path strategy differs because the scripts execute in different contexts. Bare `source state/rdf-bus.sh` is wrong in both cases.

**`lib/cmd/refresh.sh`** — invoked by `bin/rdf refresh`. The launcher `rdf_init()` (in `lib/rdf_common.sh:33-36`) sets `RDF_STATE_DIR="${RDF_HOME}/state"`. Source the helper via that variable:

```bash
# At the top of refresh.sh, after the existing sourcing block:
# shellcheck source=/dev/null
source "${RDF_STATE_DIR}/rdf-bus.sh"
```

Then replace `${project_path}/PLAN.md` (~5 occurrences) with `$(rdf_active_plan_path "$project_path")`.

**`state/rotate-work-output.sh`** — deployed to `~/.rdf/state/rotate-work-output.sh` by `lib/cmd/generate.sh:_generate_deploy_state_helpers`. The script runs against consumer projects (LMD, APF, BFD, …) which do NOT carry `state/rdf-bus.sh`. Two changes required:

1. **`lib/cmd/generate.sh` extension (mandatory companion change):** add `rdf-bus.sh` to the `_generate_deploy_state_helpers` deploy loop so the helper ships alongside other state scripts to `~/.rdf/state/`. Diff:

   ```bash
   # lib/cmd/generate.sh:41 — current loop
   for _helper in rdf-state.sh context-audit.sh rotate-work-output.sh; do
   # after change:
   for _helper in rdf-state.sh context-audit.sh rotate-work-output.sh rdf-bus.sh; do
   ```

2. **`rotate-work-output.sh` self-resolution:** at the top, source the sibling helper from the script's own directory:

   ```bash
   # shellcheck source=/dev/null
   source "$(command dirname "$0")/rdf-bus.sh"
   ```

   Then replace `${_project_root}/PLAN.md` with `$(rdf_active_plan_path "$_project_root")`.

This pattern (`$(dirname "$0")/sibling.sh`) is used by other deployed helpers and survives the `~/.rdf/state/` deploy location.

**Why both refactors are needed simultaneously:** `rotate-work-output.sh` is the only state script in this surface that runs against arbitrary projects via `~/.rdf/state/`. Until `rdf-bus.sh` is deployed alongside, `rotate-work-output.sh` cannot resolve it. The generate.sh change ships in the same phase as the rotate-work-output.sh change.

### 5.6 `.gitignore` — additions

Append:

```
# Plans — active state at root is transitional; canonical is docs/plans/
PLAN.md
PLAN*.md
PLAN-*.md

# Active-plan pointer (resolver state)
.rdf/active-plan*
```

### 5.7 Other canonical content (one-line reference updates)

`framework.md`, `session-safety.md`, `progress-tracking.md`, `plan-schema.md`, `r-build.md`, `r-ship.md`, `r-save.md`, `r-status.md`, `r-vpe.md`, `r-start.md`, `r-refresh.md`, `engineer.md`: replace `PLAN.md` → "active plan" / "the plan file" / explicit path as the context demands. No semantic changes beyond the wording.

---

## 5b. Examples

### Example 1: Creating a new plan

```bash
$ /r-plan docs/specs/2026-05-15-foo-design.md
...
Step 2: Writing plan to docs/plans/2026-05-15-foo-plan.md
Step 2.7: Schema validation pass — clean
Step 3.1: Challenge review — APPROVE
Step 3.3: Committing plan
  → git add docs/plans/2026-05-15-foo-plan.md
  → git commit -m "Add foo implementation plan"
Step 3.3.1: Active plan pointer set: .rdf/active-plan-019018f1-...

> Plan ready — docs/plans/2026-05-15-foo-plan.md (8 phases)
> Run /r-build to begin execution.
```

### Example 2: Resuming an interrupted plan

```bash
$ /r-plan --resume
Resolver found pointer → docs/plans/2026-05-15-foo-plan.md
Resuming plan for: foo
Written: 5 phases complete
Truncated: Phase 6 (will regenerate)
Missing: Phases 7-8

Continue? [Y/start fresh]
```

### Example 3: Build dispatcher resolving the plan

```bash
$ /r-build
Resolver:
  .rdf/active-plan-019018f1-... → docs/plans/2026-05-15-foo-plan.md  ✓
Phase 3 selected (next pending).
Dispatching engineer subagent...
```

### Example 4: Legacy fallback for transitional project

```bash
$ /r-build           # project has no .rdf/active-plan, has PLAN.md
Resolver:
  .rdf/active-plan-019018f1-... → missing
  .rdf/active-plan              → missing
  PLAN.md                       → present (legacy fallback)  ✓
Phase 1 selected.
```

### Example 5: No plan found

```bash
$ /r-build
Error: No active plan found.
  Resolver checked:
    .rdf/active-plan-019018f1-... (missing)
    .rdf/active-plan              (missing)
    PLAN.md                       (missing)
  Run /r-plan to create one.
```

### Example 6: r-ship clears pointer

```bash
$ /r-ship
Reading plan: docs/plans/2026-05-15-foo-plan.md
All phases complete ✓
Release commit landed.
Active-plan pointer cleared.
Plan file retained at docs/plans/2026-05-15-foo-plan.md as historical record.
```

### Example 7: Two concurrent sessions on same repo

```
Session A (RDF_SESSION_ID=AAA...):
  .rdf/active-plan-AAA  → docs/plans/2026-05-15-foo-plan.md
Session B (RDF_SESSION_ID=BBB...):
  .rdf/active-plan-BBB  → docs/plans/2026-05-15-bar-plan.md

# A's /r-build reads pointer AAA → foo plan
# B's /r-build reads pointer BBB → bar plan
# Neither clobbers the other. Both plans are committed in docs/plans/.
```

### Example 8: Filesystem state before/after

**Before (legacy):**

```
project-root/
├── PLAN.md                              # gitignored (mostly), ephemeral, single-slot
├── docs/
│   ├── plans/
│   │   └── 2026-04-26-reviewer-roi-3.1.1-plan.md  # historical
│   └── specs/
│       └── 2026-04-26-reviewer-roi-3.1.1-design.md
└── .rdf/work-output/
    └── phase-1-result.md
```

**After (canonical):**

```
project-root/
├── docs/
│   ├── plans/
│   │   ├── 2026-04-26-reviewer-roi-3.1.1-plan.md
│   │   └── 2026-05-15-plan-canonicalization-plan.md   # NEW
│   └── specs/
│       ├── 2026-04-26-reviewer-roi-3.1.1-design.md
│       └── 2026-05-15-plan-canonicalization-design.md
└── .rdf/
    ├── active-plan-019018f1-...           # gitignored pointer
    └── work-output/
        └── phase-1-result.md
# (no root PLAN.md)
```

---

## 6. Conventions

**Plan filename:** `docs/plans/{YYYY-MM-DD}-{slug}-plan.md` — date = creation date (UTC date, `date +%Y-%m-%d`); slug = kebab-case topic, words from spec filename or user input; `-plan` suffix distinguishes from specs.

**Disambiguation:** If filename collides, append `-v2`, `-v3`. Never overwrite a committed plan.

**Pointer file format:** One line containing the absolute path to the plan, no trailing whitespace (resolver strips a single trailing `\n`).

**Pointer file naming:** `.rdf/active-plan-${RDF_SESSION_ID}` for session-scoped (preferred); `.rdf/active-plan` for default/un-suffixed.

**Resolver call pattern (Bash):**

```bash
source state/rdf-bus.sh
rdf_session_init
plan_path="$(rdf_active_plan_path "$project_root")" || {
    echo "No active plan found." >&2
    exit 1
}
# Use $plan_path henceforth — never assume PLAN.md
```

**Resolver call pattern (documentation prose):** "the active plan" or "the plan file" — avoid hardcoding `PLAN.md` except when describing legacy fallback.

**Commit message for plan creation:** `Add {topic} implementation plan` (subject) + `[New] docs/plans/{filename} — {N}-phase implementation plan` (body line).

**Worktree path mirroring:** Worktree gets the plan at the same relative path as main repo (`docs/plans/2026-05-15-foo-plan.md` in both). Pointer in worktree points to worktree-local copy.

---

## 7. Interface Contracts

**New shell API (in `state/rdf-bus.sh`):**

- `rdf_active_plan_path [project_root]` → stdout: abs path; exit 0 if resolved, 1 if not
- `rdf_set_active_plan <plan_path> [project_root]` → exit 0 on success, 1 on validation failure (path missing)
- `rdf_clear_active_plan [project_root]` → exit 0 (idempotent)

**Filesystem contract:**

- `.rdf/active-plan-{UUIDV7}` — session pointer; single line; gitignored
- `.rdf/active-plan` — un-suffixed pointer; single line; gitignored; used only when session ID unset
- `docs/plans/{date}-{topic}-plan.md` — committed plan; immutable post-creation

**CLI contract (`/r-plan`):**

- `/r-plan` (no args) — unchanged behavior except writes to docs/plans/, commits, sets pointer
- `/r-plan docs/specs/foo.md` — unchanged behavior with same path change
- `/r-plan --resume` — reads via resolver, no longer assumes root PLAN.md
- `/r-plan --resume <path>` (new) — set the pointer to `<path>`, then enter resume flow without re-writing the plan file. Behavior: validate `<path>` exists and is a readable file, call `rdf_set_active_plan "<path>"`, then proceed with the existing Resume Protocol. This addresses the fresh-checkout-with-committed-plan case (Risk 8): a teammate clones the repo, has `docs/plans/foo.md` committed, but no `.rdf/active-plan-*`. They run `/r-plan --resume docs/plans/foo.md` to take over.

**CLI contract (`/r-build`, `/r-ship`, `/r-save`, `/r-status`, `/r-vpe`, `/r-refresh`, `/r-start`):**

- Reads via resolver. Output text mentions the named plan path instead of `PLAN.md`.

**Legacy fallback (transitional):**

- Projects with a root `PLAN.md` (no pointer set, no `docs/plans/` plan) continue to work. Resolver returns `PLAN.md`.
- When such a project runs `/r-plan` for a new topic, the new plan lands at `docs/plans/` and the pointer is set. The legacy `PLAN.md` becomes inert.

---

## 8. Migration Safety

### 8.1 Test suite impact

Affected:
- `tests/adapter.bats` — verifies canonical regen; will pick up reworded canonical content. Existing tests pass unchanged; new tests added for resolver wording in r-plan/r-build/dispatcher.
- `tests/rdf-bus.bats` — extends with three new test groups covering the resolver, set, and clear helpers.
- `tests/pre-commit-anti-patterns.bats` — unaffected (no resolver-touched anti-patterns).
- New: `tests/plan-canonicalization.bats` — end-to-end coverage of pointer lifecycle and resolver fallback.

### 8.2 Install path

`rdf generate claude-code` deploys canonical → `~/.claude/`. The deployed agents and commands embed the new wording. No new top-level files in canonical/; existing files modified.

### 8.3 Upgrade path

Existing projects (with root `PLAN.md`, no pointer):
- First `/r-build` or `/r-status` invocation works via fallback — no breakage.
- First `/r-plan` writes to `docs/plans/`, sets pointer. From that point on, fallback is unused.

Existing projects (no `PLAN.md`, no plan in `docs/plans/`):
- Resolver returns empty. Commands error with "No active plan." Same as today.

Existing projects (this repo: rdf):

Migration phase performs three operator-visible actions in order, with verification commands after each:

1. **Remove `docs/` from `.git/info/exclude` line 18:**

   ```bash
   command sed -i '/^docs\/$/d' .git/info/exclude
   git check-ignore -v docs/plans/2026-99-test.md 2>&1; echo "exit: $?"
   # expect: exit: 1  (path not ignored)
   ```

   `.git/info/exclude` is local-only (never tracked), so this edit produces no commit. Document the action in the release notes / CHANGELOG so other operators on existing clones perform the same edit. Provide a one-liner in `r-init` or a doctor check (future work) to detect and offer the fix.

2. **Untrack the stale 3.0.3 `PLAN.md` snapshot:**

   ```bash
   git ls-files --error-unmatch PLAN.md 2>&1 && \
     git rm --cached PLAN.md
   # File stays on disk as legacy fallback content
   git ls-files --error-unmatch PLAN.md 2>&1 | head -1
   # expect: error: pathspec 'PLAN.md' did not match any file(s) known to git
   ```

3. **Extend `.gitignore`:**

   ```bash
   {
     printf '\n# Plans — root location is transitional; canonical is docs/plans/\n'
     printf 'PLAN.md\nPLAN*.md\nPLAN-*.md\n'
     printf '\n# Active-plan pointer (resolver state)\n'
     printf '.rdf/active-plan*\n'
   } >> .gitignore
   grep -cE '^PLAN(\*|-\*)?\.md$|^\.rdf/active-plan' .gitignore
   # expect: 4
   ```

The current `PLAN.md` on disk content (3.1.1 reviewer-ROI plan) is already preserved at `docs/plans/2026-04-26-reviewer-roi-3.1.1-plan.md` (commit `ff65b85`). No content migration is needed.

### 8.4 Backward compatibility

- The resolver's three-tier resolution preserves all current `PLAN.md`-bearing projects.
- `lib/cmd/doctor.sh:_check_plan` already globs `PLAN*.md` — diagnostic output broadens slightly (will see plan files in `docs/plans/` too; extend to also list pointer state).
- `dispatcher.md` worktree sync: pre-existing worktrees in flight do NOT migrate mid-build. Worktrees created after the change use the new path.
- No CLI flag changes, no breaking syntax.

### 8.5 Uninstall

No uninstall path — RDF doesn't ship an uninstaller. Removing the framework from a project: `command rm -rf .rdf/` cleans pointers. `docs/plans/` files are committed history and stay in the repo.

---

## 9. Dead Code and Cleanup

Dead code encountered during reading:

| File | Lines | Finding | Action |
|---|---:|---|---|
| `(git index)` | n/a | Stale `PLAN.md` tracked snapshot at commit `6308d6d` (3.0.3 plan, abandoned, never updated) | `git rm --cached PLAN.md` in migration phase |
| `canonical/reference/framework.md` | 55-62 | Status-marker list (`pending`/`in-progress`/...) suggests inline-in-plan tracking; current behavior is per-phase result files | Clarify wording: status markers describe semantic states, but storage is in `.rdf/work-output/phase-N-result.md` |
| `lib/cmd/refresh.sh` | 221-280 | `_refresh_scope_github` parses `COMPLETE`/`IN_PROGRESS`/`PENDING` inline in PLAN.md to cross-reference with GitHub issue state. Committed canonical plans in `docs/plans/` carry no such markers (verified). After migration, this loop will see `UNKNOWN` for every phase and silently skip all issue mismatches. | Out of scope for this work. Acknowledged casualty — `_refresh_scope_github` becomes a no-op for canonical plans until a follow-up rewrites it to derive status from `.rdf/work-output/phase-N-result-${SESSION}.md`. Annotated in the engineer phase notes. The pre-existing behavior already produced incomplete results (no committed plan in this repo had inline status), so this is not a regression. |
| `.git/info/exclude` | 18 | Line `docs/` blocks new plan commits | Removed in migration phase (Section 8.3 step 1). |

No other dead code identified in the surface area.

---

## 10a. Test Strategy

| Goal | Test file | Test description |
|---|---|---|
| Goal 1 (r-plan writes to docs/plans/) | `tests/adapter.bats` | `@test "r-plan canonical names docs/plans path"` — grep regenerated output for `docs/plans/` references |
| Goal 1 (commits mandatory) | `tests/adapter.bats` | `@test "r-plan Step 3.3 marks commit as mandatory"` — grep for absence of "[Y/n]" on commit prompt |
| Goal 2 (pointer file exists) | `tests/plan-canonicalization.bats` | `@test "rdf_set_active_plan writes session-scoped pointer"` |
| Goal 2 (un-suffixed fallback) | `tests/plan-canonicalization.bats` | `@test "rdf_active_plan_path falls back to un-suffixed pointer"` |
| Goal 3 (resolver in all consumers) | `tests/adapter.bats` | `@test "consumers route through rdf_active_plan_path"` — grep canonical content for `rdf_active_plan_path` in 11 files |
| Goal 4 (legacy fallback) | `tests/plan-canonicalization.bats` | `@test "rdf_active_plan_path returns PLAN.md as last resort"` |
| Goal 5 (worktree sync uses resolver) | `tests/adapter.bats` | `@test "dispatcher worktree sync references rdf_active_plan_path"` |
| Goal 6 (gitignore updated) | `tests/plan-canonicalization.bats` | `@test ".gitignore includes plan + pointer patterns"` |
| Goal 7 (r-ship clears pointer) | `tests/adapter.bats` | `@test "r-ship calls rdf_clear_active_plan"` |
| Goal 8 (--resume reads via resolver) | `tests/adapter.bats` | `@test "r-plan Resume Protocol calls rdf_active_plan_path"` |
| Goal 9 (session isolation) | `tests/plan-canonicalization.bats` | `@test "two RDF_SESSION_IDs maintain independent pointers"` |
| Goal 10 (no orphan PLAN.md refs) | `tests/plan-canonicalization.bats` | `@test "canonical PLAN.md references are scoped to legacy/fallback context"` — grep word-boundary scan |
| Goal 11 (existing tests pass) | (all) | `make -C tests test` exits 0 |
| Resolver: empty pointer file | `tests/plan-canonicalization.bats` | `@test "rdf_active_plan_path skips empty pointer and falls through"` |
| Resolver: pointer to missing file | `tests/plan-canonicalization.bats` | `@test "rdf_active_plan_path skips pointer to nonexistent file"` |
| Pre-commit hook still works | `tests/rdf-bus.bats` | existing tests pass with updated ancestor walk |

**Test count baseline:** the planner must re-derive the count from source at plan-writing time using `grep -rc '^\s*@test ' tests/*.bats | awk -F: '{s+=$2}END{print s}'`. The spec's "~68" is an estimate, not a binding floor. Expected delta: +13 tests in `tests/plan-canonicalization.bats` + ~5 adapter assertions. The planner produces phase-level test-count assertions only where Rule 9 requires them (when the plan explicitly asserts a count).

---

## 10b. Verification Commands

```bash
# Goal 1 (r-plan canonical writes to docs/plans/)
grep -n 'docs/plans/{' canonical/commands/r-plan.md | wc -l
# expect: >= 3

# Goal 1 (commit is mandatory, no [Y/n])
grep -n 'Commit the plan? \[Y/n\]' canonical/commands/r-plan.md
# expect: (no match — was at l.484)

# Goal 2 (pointer name pattern)
grep -nE '\.rdf/active-plan(-\$\{RDF_SESSION_ID\}|-\{UUIDV7\})?' state/rdf-bus.sh
# expect: >= 2 hits (set + resolve)

# Goal 3 (resolver wired in 11 consumers)
grep -lE 'rdf_active_plan_path' canonical/commands/r-{plan,build,ship,save,status,vpe,start,refresh}.md \
    canonical/agents/{dispatcher,engineer}.md lib/cmd/refresh.sh state/rotate-work-output.sh \
    state/git-hooks/pre-commit | wc -l
# expect: 13 (11 canonical + 2 lib/state)

# Goal 4 (legacy fallback path)
grep -nE 'PLAN\.md.*fallback|legacy' state/rdf-bus.sh
# expect: >= 1

# Goal 5 (worktree sync uses resolver)
grep -n 'rdf_active_plan_path' canonical/agents/dispatcher.md
# expect: >= 2 (load + worktree sync)

# Goal 6 (gitignore updated)
grep -cE '^PLAN(\*|-\*)?\.md$|^\.rdf/active-plan' .gitignore
# expect: 4 (PLAN.md, PLAN*.md, PLAN-*.md, .rdf/active-plan*)

# Goal 7 (r-ship clears pointer)
grep -n 'rdf_clear_active_plan' canonical/commands/r-ship.md
# expect: >= 1

# Goal 8 (Resume reads resolver)
grep -nE 'rdf_active_plan_path|the active plan' canonical/commands/r-plan.md
# expect: >= 3

# Goal 9 (session isolation)
grep -n 'RDF_SESSION_ID' state/rdf-bus.sh | grep -c active-plan
# expect: >= 1

# Goal 10 (no orphan PLAN.md references)
# Every remaining mention must be in legacy-fallback or output-text context
grep -rn '\bPLAN\.md\b' canonical/ lib/ state/ | grep -vE 'legacy|fallback|LEGACY|deprecated|FALLBACK' | wc -l
# expect: <= 10  (10 = output-text mentions in r-start/r-status banner, lib/cmd/dispatch.sh usage)

# Goal 11 (tests pass)
make -C tests test 2>&1 | tail -5
# expect: contains "ok ..." and zero "not ok"

# Stale tracked snapshot removed
git ls-files --error-unmatch PLAN.md 2>&1
# expect: error: pathspec 'PLAN.md' did not match any file(s) known to git

# rdf-bus helpers export check
source state/rdf-bus.sh; declare -F rdf_active_plan_path rdf_set_active_plan rdf_clear_active_plan
# expect: 3 declarations

# Migration: docs/ no longer blocks new plan commits
git check-ignore docs/plans/2026-99-test.md; echo "exit: $?"
# expect: exit: 1  (path NOT ignored)

# Migration: rdf-bus.sh ships to ~/.rdf/state/ after generate
grep -n "rdf-bus.sh" lib/cmd/generate.sh
# expect: >= 1 hit in _generate_deploy_state_helpers loop

# Migration: refresh.sh sources rdf-bus from RDF_STATE_DIR
grep -n 'RDF_STATE_DIR.*rdf-bus.sh\|source.*RDF_STATE_DIR' lib/cmd/refresh.sh
# expect: 1 hit

# Migration: rotate-work-output.sh sources sibling rdf-bus.sh
grep -nE 'dirname.*\$0.*rdf-bus|source.*\$0.*rdf-bus' state/rotate-work-output.sh
# expect: 1 hit
```

---

## 11. Risks

1. **Resolver pointer drift** — pointer file points to a deleted plan. *Mitigation:* resolver validates `[[ -f "$plan" ]]` before returning; falls through to next tier. Test coverage includes "pointer to missing file" case.

2. **Concurrent session races on pointer write** — two sessions both call `rdf_set_active_plan` against the same `.rdf/` dir. *Mitigation:* pointer is session-scoped (`-${RDF_SESSION_ID}` suffix); writes never collide. Un-suffixed pointer is only written manually or by legacy code (not by the new flow).

3. **Worktree pointer breakage** — worktree gets the main repo's pointer pointing to a path that doesn't exist inside the worktree. *Mitigation:* worktree dispatch explicitly calls `rdf_set_active_plan` against the worktree-local plan copy after `cp`. Documented in dispatcher.md.

4. **27-file refactor sentinel risk** — large cross-cutting change is the highest-finding class historically. *Mitigation:* phased approach (5+ phases by surface; helper + tests first, then consumers in logical groups); end-of-plan sentinel-full at depth 3; per-phase sentinel-lite or sentinel-full per dispatcher scope classification (this falls in scope:cross-cutting).

5. **Tracked-PLAN.md untrack risk** — `git rm --cached PLAN.md` is destructive of tracking, not content. *Mitigation:* file stays on disk; verified before commit; only one snapshot was ever committed (6308d6d), and the content of that snapshot is irrelevant (3.0.3 plan, replaced 3 versions ago).

6. **Legacy projects with no `.rdf/` directory** — pre-Wave-A projects have no `.rdf/`. *Mitigation:* resolver's third tier handles `PLAN.md` at root with no `.rdf/` present. No `.rdf/` directory creation forced unless `rdf_set_active_plan` is called.

7. **Worktree commit of `docs/plans/`** — the worktree's pre-commit hook enforces phase-scope on commits. A worktree dispatched for phase N might try to commit a plan-file update — currently `docs/plans/` would not be in the phase's allowed file list. *Mitigation:* worktree never modifies the plan file (immutable post-commit); plan changes only happen during `/r-plan`, which is never run inside a worktree.

8. **`r-build` from a fresh checkout with no pointer** — operator clones repo, has `docs/plans/foo.md` committed, but no `.rdf/active-plan-*`. *Mitigation:* graceful fallback. The resolver returns empty (no pointer + no `PLAN.md`). `r-build` errors with "No active plan; run `/r-plan --resume docs/plans/foo.md`" — add a new `--resume <path>` flag to r-plan that sets the pointer without re-writing the file.

9. **Resolver fragility under `set -u`** — `${RDF_SESSION_ID}` may be unset in callers that don't call `rdf_session_init` first. *Mitigation:* every helper calls `rdf_session_init` internally; consumers don't need to remember.

10. **Adapter regen drift** — if `~/.claude/` deployment lags behind canonical, the deployed agents reference old PLAN.md paths. *Mitigation:* `rdf generate claude-code` runs as part of the final phase; `rdf doctor` flags drift before push (per project CLAUDE.md workflow rule).

---

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|---|---|---|
| `.rdf/active-plan-*` exists but pointed-to file deleted | Resolver falls through to next tier; warn if all fall through | Validation in resolver, last tier returns 1 |
| Two sessions in same checkout (rare; non-worktree) | Each session writes its own `-${SESSION_ID}` pointer; independent | Session-scoped pointer key |
| Worktree has stale pointer from another worktree's `.rdf/` | Worktree dispatch overwrites pointer at sync time | `rdf_set_active_plan` post-cp |
| `r-plan --resume` with no pointer and no `PLAN.md` | "No interrupted plan session found. Starting fresh." | Existing handling preserved |
| `r-plan --resume <path>` (new flag) | Set pointer to `<path>`, then enter resume flow | Add to r-plan argument parsing |
| Pointer file is empty (zero bytes) | Resolver detects empty content, falls through | `[[ -n "$plan" ]]` guard |
| Pointer file content has Windows CRLF | Resolver strips trailing `\n` only — `\r` would persist | Tighten strip to `${plan%[$'\r\n']}` (sed-style) or `printf` echo trims |
| `docs/plans/` directory missing | `r-plan` creates it (mkdir -p) | Existing convention |
| Project has no `.rdf/` and no `state/rdf-bus.sh` | Pre-commit hook silently skips (existing behavior) | No change |
| Existing `PLAN.md` is non-empty at first `/r-plan` after upgrade | New plan goes to `docs/plans/`; old PLAN.md becomes inert legacy fallback (resolver prefers pointer) | Documented as transitional |
| `git rm --cached PLAN.md` on a clone with PLAN.md untracked | `git rm` errors; benign | Guard with `git ls-files --error-unmatch PLAN.md >/dev/null 2>&1 && git rm --cached PLAN.md` |
| Adapter regen detects PLAN.md references in stale `~/.claude/` | `rdf doctor` flags drift | Existing doctor behavior; not new |
| Session ID changes mid-build (operator switches terminals) | Old session pointer remains; new session has no pointer; resolver falls back to un-suffixed pointer or PLAN.md | Document: session continuity matters; `rdf_session_init` is idempotent per-process |
| `r-ship` runs but pointer is for a different plan than the one referenced in `docs/plans/` | r-ship reads resolver, validates phase-count matches, errors on mismatch | Existing r-ship phase-complete check |

---

## 12. Open Questions

None.

---

## Plan Outline (deferred to /r-plan)

Phase breakdown will be produced by `/r-plan`. Approximate decomposition (the planner decides exact boundaries):

1. **Helper API + tests** — `state/rdf-bus.sh` new functions + `tests/plan-canonicalization.bats` (TDD)
2. **r-plan rewrite** — write to docs/plans/, set pointer, mandatory commit, --resume via resolver
3. **Consumer pass A (commands)** — r-build, r-ship, r-save, r-status, r-vpe, r-start, r-refresh route through resolver
4. **Consumer pass B (agents + reference)** — dispatcher.md (incl. worktree sync), engineer.md, framework.md, session-safety.md, progress-tracking.md, plan-schema.md
5. **Consumer pass C (lib + state)** — lib/cmd/refresh.sh, lib/cmd/dispatch.sh, state/rotate-work-output.sh, state/git-hooks/pre-commit, lib/cmd/doctor.sh
6. **Migration + gitignore** — `.gitignore` update, `git rm --cached PLAN.md`, adapter regen verification
7. **Release** — CHANGELOG, version bump, final adapter regen, push

Phases 3 and 4 may run as a parallel-worktree batch (file ownership is non-overlapping). Phases 5 and 6 are serial (5 touches files 4 also touches if dispatcher worktree-sync mentions are extended).
