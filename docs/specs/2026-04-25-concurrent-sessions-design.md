# RDF — Concurrent Multi-Session Coordination Design

**Date:** 2026-04-25
**Status:** Design draft (awaiting review)
**Companion research:** inline (synthesized from 2024–2026 sources, see Sources at end)

Scope: redesign RDF's concurrent-session model so that multiple Claude Code sessions, parallel `/r-build` worktrees, and subagent dispatches can run against the same repository (or against `~/.rdf/` global state) without clobbering each other. Replaces the current ad-hoc per-milestone filename suffix workaround with a coherent set of primitives drawn from observed failures, RDF v2 archaeology, and current industry practice.

---

## 1. Problem Statement

RDF was designed for **carefully-coordinated parallel execution within one controller session** — a single dispatcher fans out to subagents, owns shared state, and consolidates. In practice, blacklight's M6–M13 work has been done in **two-or-more concurrent top-level sessions** (separate terminals, separate VPE pipelines on different milestones at once), which the framework does not handle.

The result is a recurring class of failures: state files clobbered, agents writing outside assigned worktrees, builds absorbing uncommitted parallel work, and orphaned worktrees with no cleanup path. The team's response has been per-milestone filename suffixes (`vpe-progress-M9.md`) and tribal knowledge in lessons-learned — both of which are advisory and don't survive a careless dispatch.

This brief proposes a layered primitive set that fixes the underlying mechanism rather than papering over each instance.

---

## 2. Evidence (what we observed)

### Six incidents in blacklight session history

1. **Un-scoped `vpe-progress.md` collisions** — M6 and M9 both had to write the same file; M9 manually scoped to `vpe-progress-M9.md`. Per-milestone suffixes are a manual workaround, not a primitive.
2. **`build-progress.md` overwritten across sessions** — current file holds M13 state; prior sessions' content survived only in manually-suffixed variants.
3. **75% worktree-leak rate** in M11 B3, recorded in `~/.rdf/insights.jsonl`: *"agents default to writing wherever the prompt's first absolute path goes."*
4. **`phase-N-result.md` collisions** — `framework.md:67-68` and `dispatcher.md:19-20` hardcode the filename; parallel sessions running phases 1–9 mutually overwrite.
5. **M10 P4 absorbed-changes incident** — `make bl` aggregation absorbed an operator's uncommitted `bl_observe_substrate` (303 lines) into a "polish" phase commit. Mitigation in lessons-learned, not enforced.
6. **`/r-save` race on `~/.rdf/insights.jsonl`** — out-of-order timestamps in the live file (`2026-04-25T22:00:00Z` followed by `2026-04-25T14:29:58Z`), plus orphaned `insights.jsonl.new` and `insights.jsonl.trimmed` siblings: signature of an interrupted read-append-trim with no atomic semantics.

### Two probes confirming framework gaps

- **Zero `flock` usage in canonical** — single hit is a slop-audit comment that *flags* projects using flock; RDF defines no lock primitive for itself.
- **Zero `git worktree prune` or `git worktree list` calls** in canonical. Single hit is `git worktree remove` in `r-build.md:203`. The parent CLAUDE.md rule *"controller must verify `git worktree list` is clean before pushing"* lives only in prose.

### v2 archaeology

`docs/plans/archived/2026-03-16-rdf-2.0-phase5.md` documents:
- File-locked task claim model: *"File locking prevents race conditions on concurrent task claims."*
- Self-claiming teammates: separate CC instances, own context windows, coordinate via shared task file with locks.
- `lib/dispatch-agents.json` static registry (kept the static-catalog idea in v3 profiles; lost the runtime-registry side effect).

`canonical/reference/framework.md:150` references `collect-spool.sh` reading `.rdf/work-output/spool/*.jsonl`. Neither the script nor the directory exists anywhere in v3 — **phantom contract** inherited from v2 docs without implementation.

---

## 3. Design Principles

Drawn from current best practice (Cargo, Bazel, Buck2, Temporal, OpenHands V1, LangGraph 1.0 production deployments):

1. **Enforcement, not advice.** Worktree boundary, lock acquisition, scope verification — these must be checked by code, not the prompt. Industry post-mortem consensus: *"Shared filesystem state is the root cause — not Claude's intelligence, not your prompt quality."*
2. **FD-bound liveness over PID-bound.** Locks held via open file descriptors are kernel-released on process death. PID files are racy; PID+hostname+start-epoch triples are needed when FD-binding isn't possible.
3. **Atomic rename for state mutations.** `mktemp` in same dir → write → `fsync(file)` → `rename` → `fsync(dir)`. POSIX atomic vs. concurrent observers; the two `fsync`s make it crash-safe.
4. **Append-only for log-shaped state.** `O_APPEND` writes ≤`PIPE_BUF` (4096 bytes on Linux) are POSIX-atomic with no locks needed. NDJSON line per event is the canonical shape.
5. **Idempotency separate from concurrency.** Optimistic locking ≠ idempotency. Each phase-result write needs both: a UUIDv7 idempotency key in the filename AND a CAS check ("file exists already").
6. **Two durability classes split at the directory level.** `$XDG_RUNTIME_DIR/rdf/$session_id/` for ephemeral session state (tmpfs, auto-cleaned on logout); `~/.rdf/` for persistent cross-session state.
7. **Always-on, opt-out.** Coordination primitives must be cheap enough to enable by default. Per-command-boundary polling (5 syscalls per `/r-*` invocation) qualifies.
8. **Avoid coupling enforcement to process boundary.** OpenHands V1 explicitly decoupled sandbox from agent because *"the sandbox might crash while the agent continued (or vice versa), leading to corrupted sessions."* RDF should follow.

---

## 4. The Primitive Set

Twelve primitives. Each is independently useful; they compose to cover the observed failure classes. Listed in dependency order — earlier primitives are foundational for later ones.

### P1 — Session identity (`RDF_SESSION_ID` and parent linkage)

**What.** Every top-level RDF-aware session generates a UUIDv7 at start. Subagent invocations generate their own UUIDv7 and record the parent's ID. Linux PID/PPID model: independent identity, parent reference.

**Where.** Exported as env vars by the SessionStart hook:
```
RDF_SESSION_ID=01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105     # UUIDv7
RDF_PARENT_ID=                                             # empty for root
```
Subagent dispatches inherit `RDF_PARENT_ID = ${parent's RDF_SESSION_ID}` and generate fresh `RDF_SESSION_ID`.

**Why UUIDv7.** Sortable (48-bit ms timestamp prefix), ~74 bits of randomness, ~2³⁷ ops/ms before 50% birthday collision. Last 12 chars (`a4b3f9c2e105`) are the human-readable short form for log display; full UUID for state files.

**Replaces.** `r-build.md:185`'s 8-char hex (`session-id`).

---

### P2 — Two-tier state directory layout

**What.** Split state by durability requirement:

```
$XDG_RUNTIME_DIR/rdf/$RDF_SESSION_ID/         # ephemeral (tmpfs, auto-clean on logout)
  status.json                                  # heartbeat + current activity
  scratch/                                     # per-session scratch space
  locks/                                       # OFD lock files held by this session

~/.rdf/                                        # persistent (cross-session)
  bus.jsonl                                    # global message bus
  bus.jsonl.YYYY-MM-DD                         # rotated daily
  insights.jsonl                               # rolling 30
  lessons-learned.md                           # promoted insights
  config.json                                  # user prefs
  sessions/                                    # archived session status (post-15m staleness)
    $RDF_SESSION_ID-status.json
  repos/$REPO_HASH/                            # per-repo persistent state
    build-lock                                 # OFD-lock target
    worktree-registry.jsonl                    # worktrees this RDF session owns
```

`$REPO_HASH` = first 12 chars of `sha256(realpath(repo))`. Stable across sessions, derives from filesystem.

**Fallback** when `$XDG_RUNTIME_DIR` is unset (e.g., non-systemd hosts): `${TMPDIR:-/tmp}/rdf-$UID/$RDF_SESSION_ID/` with `0700` mode and explicit `mktemp -d` creation.

**Replaces.** Hardcoded `.rdf/work-output/` for ephemeral writes; consolidates the implicit `~/.rdf/` layout into a documented schema.

---

### P3 — Atomic write helper (`rdf_write_atomic`)

**What.** Single bash function in `state/rdf-bus.sh`:

```bash
rdf_write_atomic() {           # path content
  local path="$1" tmp
  tmp="$(command mktemp "${path}.XXXXXX")"
  command printf '%s' "$2" > "$tmp"
  command sync -d "$tmp" 2>/dev/null || true   # fsync file; -d skips metadata
  command mv "$tmp" "$path"                    # rename(2) — atomic vs concurrent readers
  command sync -d "$(dirname "$path")" 2>/dev/null || true   # fsync dir for crash safety
}
```

Used by: status broadcast (P9), MEMORY.md updates, insights.jsonl trim, any state mutation that is not append-only.

**Why both fsyncs.** `rename(2)` is atomic vs. concurrent observers but the npm/write-file-atomic post-mortem and LWN article 789600 confirm: without `fsync(file)` + `fsync(dir)`, a crash mid-rename can leave the target as a zero-byte file. The cost is a few hundred microseconds — cheap.

---

### P4 — OFD-locked critical sections (`rdf_with_lock`)

**What.** Wrapper that takes an exclusive open file description lock, runs a command, releases on FD close (process death-safe):

```bash
rdf_with_lock() {              # lockpath cmd...
  local lockpath="$1"; shift
  command mkdir -p "$(dirname "$lockpath")"
  ( exec 9>"$lockpath"
    command flock --fcntl -x 9 || exit 1   # OFD lock (POSIX.1-2024)
    "$@"
  )
}
```

**Where applied:**
- `/r-save` read-append-trim of `~/.rdf/insights.jsonl` — wrap the entire `read → append → wc → sed` block.
- `MEMORY.md` index R-M-W in `/r-save`.
- `lessons-learned.md` append.
- `~/.rdf/repos/$REPO_HASH/build-lock` — held by `/r-build` for the duration; second concurrent `/r-build` blocks or fails fast (configurable).

**Why OFD over flock.** Resolves the re-entry deadlock the parent CLAUDE.md already documents: classical `flock(2)` keys to PID, so two FDs on the same file in the same process don't stack — the inner blocks. `fcntl(F_OFD_SETLK)` keys to open file description, behaves correctly on re-entry, and is POSIX.1-2024 standard. `flock(1)`'s `--fcntl` flag exposes it.

**Fallback.** On systems without `flock --fcntl`, fall back to advisory `flock` with a documented constraint: callee must not lock if caller already holds.

---

### P5 — Append-only NDJSON bus (`rdf_msg_send` / `rdf_msg_read` / `rdf_msg_stream`)

**What.** Single shared file `~/.rdf/bus.jsonl`. Each line is one message ≤4KB, written with `O_APPEND` — POSIX-atomic, no `flock` needed.

```bash
# In state/rdf-bus.sh
rdf_msg_send() {               # type to body
  local type="$1" to="$2" body="$3"
  local line
  line=$(command printf '{"ts":"%s","from":"%s","parent":"%s","to":"%s","type":"%s","body":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$RDF_SESSION_ID" \
    "${RDF_PARENT_ID:-}" \
    "$to" \
    "$type" \
    "$(printf '%s' "$body" | jq -Rs .)")    # JSON-escape body
  # Single write call, <4KB → atomic per POSIX O_APPEND
  command printf '%s' "$line" >> ~/.rdf/bus.jsonl
}

rdf_msg_read() {               # [N=50]
  command tail -n "${1:-50}" ~/.rdf/bus.jsonl
}

rdf_msg_stream() {             # filter
  command tail -F ~/.rdf/bus.jsonl | jq -c "select(${1:-true})"
}
```

**Message types** (closed vocabulary, validated on send):
- `announce` — claiming ownership: *"M14 build starting, owning vpe-progress-M14.md"*
- `release` — *"done with X, others can claim"*
- `status` — periodic: *"M9 P5 retrying flaky test"*
- `request` — directed, expects reply: *"session a8b4f291: did you finish M9 P5?"*
- `reply` — response to `request`
- `warn` — *"noticed src/bl.d/observe.sh dirty before make bl"*
- `stale` — sweeper-emitted: *"session 3c7351cb went stale at TS"*

**Schema:**
```json
{"ts":"2026-04-25T22:34:00Z","from":"<UUIDv7>","parent":"<UUIDv7|empty>","to":"<UUIDv7|*>","type":"announce","body":"..."}
```

**Daily rotation.** At midnight UTC (or on first command after midnight), `/r-save` runs:
```bash
command mv ~/.rdf/bus.jsonl ~/.rdf/bus.jsonl.$(date -u +%Y-%m-%d)
```
Atomic rename; new appends start fresh. Past 7 days kept; older deleted.

---

### P6 — Per-session status broadcast

**What.** Each session maintains a single small file:

```
$XDG_RUNTIME_DIR/rdf/$RDF_SESSION_ID/status.json
```

```json
{
  "session_id": "01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105",
  "parent_id": null,
  "tool": "claude-code",
  "project": "blacklight",
  "branch": "main",
  "repo_hash": "f3a2c8d1e4b5",
  "started": "2026-04-25T22:10:00Z",
  "heartbeat": "2026-04-25T22:34:12Z",
  "current": "M14 P3 — engineer on src/bl.d/observe.sh",
  "command": "/r-build",
  "pid": 12345,
  "host": "freedom"
}
```

Update points: command start, command end, phase transition, and on heartbeat tick at command boundaries. Each write is `rdf_write_atomic` — ~200 bytes, two fsyncs, no locks needed.

**"What's everyone working on?"** = read `$XDG_RUNTIME_DIR/rdf/*/status.json`. Filter by heartbeat freshness. This is the v2 in-flight-registry equivalent, distributed as one file per session instead of centralized.

---

### P7 — Staleness handling (15m / 60m tiers)

**What.** Two thresholds with different actions:

| Heartbeat age | State | Action |
|---|---|---|
| ≤ 15m | `live` | normal |
| 15–60m | `stale` | sweeper emits `bus` message `{"type":"stale","body":"session X heartbeat 18m old"}` once; status remains in place; `/r-status` shows with warning marker |
| > 60m | `dead` | sweeper archives `status.json` to `~/.rdf/sessions/$RDF_SESSION_ID-status.json`; advisory claims announced by that session can be reclaimed; worktrees owned by that session enter the sweeper queue (P10) |

**Sweeper trigger.** Cheap, runs at every command boundary by `/r-*` commands. Walks `$XDG_RUNTIME_DIR/rdf/*/status.json`, computes age, takes the appropriate action. ~10ms even with 50 sessions.

**Why two tiers.** A 15m gap might be a long QA run or a coffee break; you want a heads-up but not premature reclamation. A 60m gap is meaningful work-loss territory — assume the session is gone and recover.

**No active reaper daemon.** Recovery is opportunistic: any RDF command run in any session does the sweep. This avoids the "Bazel client hangs on stale lock" trap (`bazelbuild/bazel#11020`) where lack of an external sweeper means dead state never gets cleaned.

---

### P8 — Worktree boundary enforcement (pre-commit hook + post-merge defense-in-depth)

**What.** Two-layer enforcement, structural primary + dispatcher backstop. Validated against active running session feedback (M13 dispatch produced 5/5 scope violations despite explicit prose instruction to surface drift — *"prose-in-the-payload doesn't enforce."*).

**Layer 1 (primary) — pre-commit hook installed in worktree on creation:**

```bash
# state/git-hooks/pre-commit (installed into .git/hooks/ on worktree create)
#!/usr/bin/env bash
set -euo pipefail
# Derive phase N from current branch: rdf/phase-N-<UUID>
branch=$(git rev-parse --abbrev-ref HEAD)
phase_n=$(echo "$branch" | sed -nE 's|rdf/phase-([0-9]+)-.*|\1|p')
[[ -z "$phase_n" ]] && exit 0   # not a worktree branch, no enforcement
# Read PLAN.md phase Files + Tests-may-touch (P13)
expected=$(parse_phase_scope "$phase_n")   # helper from rdf-bus.sh
staged=$(git diff --cached --name-only)
violations=$(grep -vE "^($expected)$" <<< "$staged" || true)
if [[ -n "$violations" ]]; then
  echo "SCOPE VIOLATION: files outside Phase $phase_n scope:" >&2
  echo "$violations" >&2
  echo "Phase Files: $(echo "$expected" | tr '|' ' ')" >&2
  echo "If this addition is legitimate test-infra, add the path to" >&2
  echo "the phase's **Tests-may-touch:** field in PLAN.md." >&2
  exit 1   # reject commit
fi
```

The hook fires before the engineer can produce an out-of-scope commit. Dispatcher cannot retroactively undo a violation that was never created.

**Layer 2 (defense-in-depth) — dispatcher post-merge check:**

```bash
violations=$(git -C "$worktree_path" diff-tree --no-commit-id --name-only -r HEAD \
  | grep -vE "^($expected_scope_regex)$" || true)
if [[ -n "$violations" ]]; then
  rdf_msg_send warn "*" "scope violation in phase ${N}: $violations"
  return 1   # block merge
fi
```

If layer 1 was bypassed (hook missing, hook bug, manual `--no-verify`), layer 2 catches before merge to base branch.

**Hook installation.** When `r-build.md` Section 6b creates a worktree, it copies `state/git-hooks/pre-commit` into `.git/worktrees/<name>/hooks/pre-commit` and `chmod +x`. Each worktree gets its own hook instance — pre-commit hooks are not shared across worktrees by default in git.

**Replaces.** The advisory `PROJECT_ROOT` hint, which the 75%-leak insight shows is insufficient. Converts the rule from advisory prose to physically-enforced.

---

### P13 — Tests-may-touch scope-flex zone (drift authorization)

**What.** A new optional `**Tests-may-touch:**` phase metadata field that pre-authorizes specific paths for trivial drift without requiring per-file enumeration in `**Files:**`. Honored by P8's pre-commit hook and P9's dirty check. Validated against active session feedback (5/5 phases needed scope-flex; 4/5 of those drifts were `tests/fixtures/*` or `tests/helpers/*`).

**Schema rule** (added to `plan-schema.md`):

```markdown
## Rule 8: Tests-may-touch (optional)

Phases that add or extend tests MAY declare a scope-flex zone:

```
**Tests-may-touch:** tests/fixtures/*.json, tests/helpers/*.bash
```

Paths must be glob expressions or directory prefixes. The pre-commit
hook (P8) and engineer's dirty check (P9) treat any change inside
these paths AS-IF it were in the **Files:** list, with two ceilings:

- Per-file ceiling: ≤30 lines added/changed
- Global ceiling: ≤3 files touched per phase

Drift exceeding either ceiling triggers the same rejection as
out-of-scope drift.

Default: empty (no flex zone). Explicit opt-in only.
```

**Why both ceilings.** Without them, `Tests-may-touch: tests/**` becomes a blanket pass. With them, the engineer can add a fixture file or a one-off helper without ceremony, but a substantive test rewrite still requires explicit Files declaration.

**Why now (Wave A).** Without P13, P8's pre-commit enforcement creates a worse problem than it solves: every legitimate test-infra addition becomes BLOCKED. The active session feedback was unambiguous — *"surfacing is genuinely worse than committing when the addition is necessary for the test gate."* P13 is the safety valve that makes P8 livable.

**Composition.** Pre-commit hook (P8 layer 1) computes scope as `Files ∪ Tests-may-touch`. Dispatcher post-merge check (P8 layer 2) does the same. Engineer dirty check (P9) does the same. All three cite the same rule from `plan-schema.md`.

---

### P9 — Pre-aggregation-build dirty check

**What.** Engineer protocol gains a precondition before any aggregation step (e.g., `make bl`):

```bash
expected_scope="${this_phase_files}|${this_phase_tests_may_touch}"   # P13 union
dirty=$(git status --porcelain | grep -vE "^.. (${expected_scope})$" || true)
if [[ -n "$dirty" ]]; then
  rdf_msg_send warn "*" "phase ${N}: dirty files outside scope: $dirty"
  return 1   # phase fails fast; engineer reports to dispatcher
fi
```

**Replaces.** Lessons-learned tribal knowledge from M10 P4 (the absorbed `bl_observe_substrate`). Encoded in dispatcher protocol so a future engineer can't skip it.

**Composition with P13.** Honors the `**Tests-may-touch:**` zone — adding a fixture during TDD red-green is not a dirty-state violation if the fixture path is in the flex zone (and within the ceilings).

---

### P10 — Worktree liveness sweeper

**What.** Stale-worktree reaper that runs at command-boundary alongside P7:

```bash
for wt_meta in .git/worktrees/*/locked; do
  pid=$(grep -oE 'pid [0-9]+' "$wt_meta" | grep -oE '[0-9]+')
  host=$(grep -oE 'host=[^ )]+' "$wt_meta" | cut -d= -f2)
  [[ "$host" != "$(hostname)" ]] && continue           # other machine
  kill -0 "$pid" 2>/dev/null && continue               # still alive
  # Verify start-epoch hasn't been recycled to a new process
  rec_epoch=$(grep -oE 'epoch=[0-9]+' "$wt_meta" | cut -d= -f2)
  cur_epoch=$(awk '{print $22}' /proc/$pid/stat 2>/dev/null || echo "")
  [[ -n "$cur_epoch" && "$cur_epoch" == "$rec_epoch" ]] && continue
  # Dead PID + same host + clean tree → reclaim
  wt_dir=$(dirname "$wt_meta")
  if [[ -z "$(git -C "$wt_dir" status --porcelain 2>/dev/null)" ]]; then
    git worktree unlock "$wt_dir"
    git worktree remove --force "$wt_dir"
    rdf_msg_send release "*" "reclaimed orphan worktree $wt_dir"
  fi
done
```

**Why this matters.** `gsd-build/get-shit-done#2431` documents the exact failure: Claude Code keys worktree lock to outer-session PID, subagent termination doesn't release it, accumulating locked worktrees across sessions. Git itself does no liveness check on its own lock files — the sweeper has to be application-layer.

**Encoding.** When `/r-build` creates a worktree, lock reason includes structured metadata:
```bash
git worktree lock "$wt" --reason "rdf:session=${RDF_SESSION_ID} pid=$$ host=$(hostname) epoch=$(awk '{print $22}' /proc/$$/stat)"
```

---

### P11 — Filename scoping for phase results

**What.** The framework.md contract (`phase-N-status.md`, `phase-N-result.md`) gains a session/motion suffix:

```
.rdf/work-output/sessions/${RDF_SESSION_ID}/phase-${N}-result.md
.rdf/work-output/sessions/${RDF_SESSION_ID}/phase-${N}-status.md
```

Or, equivalently, kept flat with suffix:
```
.rdf/work-output/phase-${N}-result-${RDF_SESSION_ID}.md
```

Same story for `vpe-progress.md`, `build-progress.md`, `spec-progress.md`, `ship-progress.md` — all gain `-${RDF_SESSION_ID}` suffix automatically.

**`/r-vpe --resume`.** Resume reads `$XDG_RUNTIME_DIR/rdf/*/status.json`, finds the most recent entry for the current project where `command: /r-vpe`, and resumes its scoped progress file. No more "which vpe-progress.md is mine?"

**Replaces.** Per-milestone manual suffixes (`vpe-progress-M9.md`). Suffix is now systematic, derived from session identity, not from milestone naming.

---

### P12 — `/r-msg` slash command + `/r-status` extension

**What.**

`/r-msg` — thin wrapper over the bus helpers:
- `/r-msg send <to|*> <body>` — emit one `status` (or typed) message
- `/r-msg tail [N=20]` — show last N bus entries (filtered to recent + this project by default)
- `/r-msg announce <body>` — broadcast claim
- `/r-msg release <body>` — broadcast release
- `/r-msg request <to> <body>` — directed request (no blocking — bus is fire-and-forget)

`/r-status` — extended to show:
- Live peer sessions from `$XDG_RUNTIME_DIR/rdf/*/status.json` (heartbeat-filtered)
- Recent bus activity (last 20 lines)
- Stale/dead sessions awaiting cleanup
- Worktrees claimed by RDF sessions on this host

---

## 5. Helper Library — `state/rdf-bus.sh`

A new shell library, sourced by every RDF-aware command. Surface area:

```bash
# Identity
rdf_session_init          # Generate RDF_SESSION_ID if unset; export; create scratch dir
rdf_session_archive       # End-of-session cleanup; called by /r-save

# Atomic state writes
rdf_write_atomic PATH CONTENT

# Locking
rdf_with_lock LOCKPATH CMD...

# Bus
rdf_msg_send TYPE TO BODY
rdf_msg_read [N=50]
rdf_msg_stream FILTER

# Status broadcast
rdf_status_update CURRENT [COMMAND]      # rewrites $XDG_RUNTIME_DIR/rdf/$ID/status.json
rdf_status_heartbeat                     # cheap: bumps heartbeat ts only

# Sweeper
rdf_sweep_stale                          # P7 + P10; idempotent; safe to call often

# Repo identity
rdf_repo_hash                            # first 12 hex of sha256(realpath PWD)
```

Total expected size: ~250 lines of bash. Single dependency: `jq` for JSON construction. CentOS 6+ compatible (Bash 4.1 floor; `flock --fcntl` available on Linux ≥ 3.15, with the OFD fallback path documented).

Library is sourced by:
- All `/r-*` commands at startup (one-line invocation)
- `dispatcher.md`, `engineer.md`, `qa.md`, `reviewer.md` agent protocols (read-only access for `rdf_msg_send` to announce phase work)

---

## 6. How the primitives compose against each incident

| Incident (§2) | Primitives that fix it |
|---|---|
| `vpe-progress.md` collisions | P1 + P11 (scoped filename derived from session ID) |
| `build-progress.md` overwrites | P1 + P11 |
| 75% worktree leak | P8 (pre-commit hook primary + dispatcher post-merge check) + P13 (legitimizes test-infra drift so enforcement is livable) |
| `phase-N-result.md` collisions | P1 + P11 |
| M10 P4 absorbed changes | P9 (pre-aggregation dirty check) + P13 |
| `/r-save` insights race | P4 (OFD-locked R-M-W) + P3 (atomic rename for trim) |
| Worktree orphans | P10 (liveness sweeper) + P1 (encoded in lock reason) |
| Cross-session "what's running" | P5 + P6 + P12 |
| Cross-session claims/coordination | P5 (announce/release on bus) |
| Crashed-session recovery | P7 (15m/60m tiers) + P10 (worktree reclaim) |

The bus (P5) plus status broadcast (P6) together replace the phantom `collect-spool.sh` contract in `framework.md:150` with something concrete and minimal.

---

## 7. Migration / Staging

Pain-first ordering. Wave A ships the four primitives that map directly to observed user-visible incidents in blacklight. Waves B and C are follow-on work — visibility and hygiene — sequenced after the bleeding stops.

### Wave A — Stop the bleeding (~3-4 days)

The minimum primitive set that makes the observed blacklight incidents stop happening, plus the structural enforcement layer surfaced by active-running-session feedback (M13 dispatch confirmed prose-in-payload doesn't enforce; 5/5 scope-flex needs went unaddressed; 75%-leak rate persists without structural gate).

- **P1** — Session identity (UUIDv7, env vars, SessionStart hook). Foundation; everything else keys off `RDF_SESSION_ID`.
- **P11** — Scoped phase-result and progress filenames (`phase-N-result-${SESSION_ID}.md`, `vpe-progress-${SESSION_ID}.md`, etc.). Depends on P1.
- **P8** — Worktree boundary enforcement: pre-commit hook (primary) + dispatcher post-merge check (defense-in-depth). Independent.
- **P9** — Pre-aggregation `git status --porcelain` dirty check in engineer protocol. Honors P13 scope-flex zone. Independent.
- **P13** — Tests-may-touch scope-flex zone (plan-schema rule + metadata field). Required for P8/P9 to be livable. Independent.

**Fixes:** Incidents #1, #2, #3, #4, #5 — every observed user-visible failure except the quiet `/r-save` insights race.

**Files touched:** new `state/rdf-bus.sh` (~80 lines), new `state/git-hooks/pre-commit` (~40 lines, installed into worktrees), `r-build.md` worktree dispatch + merge + `cwd:` parameter on Agent calls, `r-vpe.md`/`r-spec.md`/`r-ship.md` state writes, `dispatcher.md` scope-check + hook installation, `engineer.md` dirty-check addition, `framework.md` schema update for scoped filenames, `plan-schema.md` Rule 8 (Tests-may-touch).

**Backwards compat:** sessions without `RDF_SESSION_ID` (older entry points) fall back to current un-suffixed behavior with a deprecation warning. Phases without `**Tests-may-touch:**` field default to strict `**Files:**`-only enforcement (no flex zone). Worktrees missing the pre-commit hook still get caught by dispatcher's post-merge check (defense-in-depth).

### Wave B — Coordination & visibility (~3 days)

Adds the cross-session messaging and peer-awareness layer originally requested. Always-on, opt-out via `RDF_BUS_DISABLE=1`.

- **P2** — Two-tier directory layout (`$XDG_RUNTIME_DIR/rdf/` ephemeral + `~/.rdf/` persistent).
- **P5** — Append-only NDJSON bus + helpers (`rdf_msg_send`/`read`/`stream`).
- **P6** — Per-session `status.json` heartbeat + activity broadcast.
- **P7** — Staleness sweeper (15m=`stale` warning, 60m=archive+reclaim).
- **P12** — `/r-msg` slash command + `/r-status` extension.

**Adds:** "What's everyone working on", advisory claim/release messaging, crashed-session detection, peer-aware command output.

**Composition with Wave A:** the scope-violation reporter (P8) and dirty-check (P9) start emitting `warn` messages on the bus instead of just failing silently. Wave A's session ID becomes the bus participant identity.

### Wave C — Hygiene (~3 days)

Closes out the remaining failure modes. None map to a user-visible blacklight incident, but they prevent classes of future incidents.

- **P3** — `rdf_write_atomic` helper with fsync recipe.
- **P4** — OFD-locked `/r-save` insights/MEMORY/lessons-learned writes. **Fixes the quiet `/r-save` insights race (incident #6).**
- **P10** — Worktree liveness sweeper (PID + hostname + start-epoch reclamation).

**Why last:** the insights race is real but invisible to the user (out-of-order JSONL timestamps don't break workflows, just data quality). The worktree sweeper is preventive — it cleans up orphans from crashed sessions, which is hygienic but not actively painful.

---

**Total estimate:** ~9 days of focused work, plus tests. Each wave is independently shippable with full backwards compatibility. Wave A is the only wave with hard dependencies on subsequent waves (the deprecation notices are silent until Wave B).

---

## 8. Anti-Patterns (don't do)

These are research-confirmed traps. RDF should explicitly avoid them:

1. **PID files as primary liveness signal.** Stale PIDs after reboot, PID reuse, TOCTOU in `[ -f $PIDFILE ] && kill -0`. Use FD-bound locks (P4) where possible; pair with hostname+epoch when not.
2. **`flock` re-entry from same process via different FDs.** Already documented in CLAUDE.md. P4 uses OFD locks specifically to dodge this.
3. **`rename(2)` without `fsync`.** Atomic vs. concurrent observers but not crash-safe. Single rename can leave zero-byte target on power loss. P3 includes both fsyncs.
4. **In-process IPC between forked CC SDK processes.** humanlayer's two-week debugging session on MCP sHTTP races between forked Claude Code SDK processes is the cautionary tale. RDF stays file-state-only — no sockets, no signals, no shared memory.
5. **Coupling enforcement to process lifetime.** OpenHands V1 split workspace from agent because *"the sandbox might crash while the agent continued (or vice versa)."* RDF locks are FD-bound to the holder's process; cleanup is opportunistic by other sessions, not delegated to the dying session.
6. **Polling loops with sleep.** The bus is read on command boundaries (effectively zero cost). `rdf_msg_stream` exists for ad-hoc human use (`tail -F`); no RDF code should poll on a timer.
7. **Centralized registry as the only source of liveness truth.** Failure modes: registry gets out of sync, sessions die without cleanup, stale entries cause new sessions to refuse to start. P6's distributed status (one file per session) avoids this — there's no single registry to corrupt.

---

## 9. Open Questions

These need decisions before implementation:

1. **`flock --fcntl` availability.** Linux ≥ 3.15. CentOS 6 is at 2.6.32 — does it have it? If not, the fallback (advisory `flock` with re-entry contract) is what ships there. **Probe needed.**
2. **`$XDG_RUNTIME_DIR` on non-systemd hosts.** Always set on modern Linux desktops; absent on minimal containers, FreeBSD, etc. Fallback is `${TMPDIR:-/tmp}/rdf-$UID/` — but tmp on some systems is auto-cleaned aggressively. Acceptable risk for ephemeral session state? **Probably yes** — sessions that outlive a tmp cleanup are already pathological.
3. **Bus rotation cadence.** Daily proposed. For a heavy user with 20+ sessions/day, that's ~500-1000 lines/day = ~150KB/day. 7-day retention = ~1MB. Trivial. Can keep longer if useful for debugging.
4. **Sub-agent bus participation.** Should subagents emit their own `status` messages, or is parent-only sufficient? Linux PID/PPID model says yes — agents have their own identity. But verbosity could swamp the bus. Proposed: agents emit `status` on dispatch start and on commit only; parent emits everything else.
5. **How does this interact with the SessionStart hook?** Wave 1 adds a SessionStart hook for `rdf_session_init`. Existing hooks (if any) need to compose. **Confirm hook ordering.**
6. **Worktree on different filesystems.** If `.git/worktrees/*/locked` is on a different filesystem from the worktree itself, `/proc/$pid/stat` start-epoch comparison still works (it's PID-keyed, not filesystem-keyed). But hostname check requires same host. Cross-host worktrees (Docker volume, NFS) are out of scope for the sweeper.
7. **Should P11 introduce an `.rdf/work-output/sessions/$ID/` subdirectory or stay flat with suffix?** Subdirectory is cleaner for cleanup but breaks current readers that glob `.rdf/work-output/phase-*.md`. Flat-with-suffix is uglier but backwards-compat. **Recommend flat-with-suffix for Wave 3, optionally migrate to subdirs in a later wave.**

---

## 10. Sources

Web research synthesizing 2024–2026 best practice. Key references:

- [cargo/src/cargo/util/flock.rs](https://github.com/rust-lang/cargo/blob/master/src/cargo/util/flock.rs) — RAII FD-bound locking
- [Cargo PR #2486 "Fix running Cargo concurrently"](https://github.com/rust-lang/cargo/pull/2486)
- [fcntl_locking(2) — POSIX.1-2024 OFD locks](https://man7.org/linux/man-pages/man2/fcntl_locking.2.html)
- [LWN: A way to do atomic writes](https://lwn.net/Articles/789600/)
- [npm/write-file-atomic#64 — rename atomicity is not enough](https://github.com/npm/write-file-atomic/issues/64)
- [git-worktree(1)](https://git-scm.com/docs/git-worktree)
- [gsd-build/get-shit-done#2431 — worktree teardown silently accumulates locked worktrees](https://github.com/gsd-build/get-shit-done/issues/2431)
- [OpenHands V1 SDK paper, arXiv 2511.03690](https://arxiv.org/html/2511.03690v1)
- [Diagrid: LangGraph in production (no native distributed locking)](https://www.diagrid.io/solutions/langgraph-production)
- [Temporal: Idempotency and Durable Execution](https://temporal.io/blog/idempotency-and-durable-execution)
- [iXam: UUIDv4 vs v7 vs ULID](https://www.ixam.net/en/blog/2025/08/uuidv4v7ulid/)
- [MindStudio: Parallel Claude Code Sessions](https://www.mindstudio.ai/blog/parallel-agentic-development-claude-code-worktrees)
- [humanlayer ACE-FCA — race conditions in agent SDK IPC](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents/blob/main/ace-fca.md)

RDF-internal references:
- `docs/plans/archived/2026-03-16-rdf-2.0-phase5.md` — v2 file-locked task claim model
- `canonical/reference/framework.md:150` — phantom spool contract
- `~/.rdf/insights.jsonl` — out-of-order timestamp evidence
- `r-build.md:185-204` — current worktree dispatch with no cleanup logic
- `r-save.md:216-244` — current racy R-M-W on insights.jsonl
