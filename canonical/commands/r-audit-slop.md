AI slop audit. Finds dead code, orphan helpers, noop functions,
tautological guards, redundant implementations, and over-engineered
abstractions. Read-only static analysis. Uses a discovery-first protocol
to build a per-project call-site manifest before scanning — prevents the
false-positive wall that hits naive dead-code scanners when projects use
runtime-sourced templates, CLI dispatch tables, or vendored shared
libraries.

After candidate verification, dispatches an independent **sentinel**
peer-review pass (rdf-reviewer) and an **engineer** FP-validation pass
(rdf-engineer, read-only) over HIGH findings. Final report includes only
findings that survive both passes.

## Arguments
- `$ARGUMENTS` — optional flags and category filter:
  - `--quick` — single-agent mode (skip sentinel + engineer FP passes,
    behavior of the legacy `/r-util-slop-scan`)
  - `--no-sentinel` — skip Phase 5 (sentinel peer review)
  - `--no-engineer` — skip Phase 6 (engineer FP-validation)
  - Category filter: `dead`, `orphan`, `noop`, `redundant`,
    `over-engineered`
  - Single file or directory path to scope the scan
  - Default: all categories across all primary sources, both FP passes ON

## Setup

Read `.rdf/governance/index.md` to identify:
- Project language and source dirs (from governance/architecture.md)
- Test framework and test locations (from governance/verification.md)
- Known exception classes (from governance/anti-patterns.md)
- Shared-library vendor relationships (from governance/architecture.md)

If no governance is present, fall back to auto-discovery in Phase 0.

## Category Definitions

**Dead** — defined but never reachable at runtime
- D1 Functions with zero call sites across all primary sources + extended
  scope (templates, dispatch tables, entry points, tests, packaging)
- D2 Global variables set but never read
- D3 Unreachable branches (`if false`, code after unconditional return)
- D4 Sourced files whose exported symbols are all uncalled
- D5 Commented-out code blocks >= 3 lines

**Orphan / Disconnected**
- O1 Private helpers (`_foo()`) called only by a dead public function
- O2 Config variables declared but never consumed
- O3 Vestigial compat shims for platforms below the supported floor
- O4 Stale vocabulary (names referring to features no longer present)

**Noop / Tautological**
- N1 Pure-passthrough wrappers (`foo() { bar "$@"; }` with no logic)
- N2 Stub function bodies (`{ return 0; }`, `{ :; }`, single-echo)
- N3 Tautological conditionals (`[ -n "$x" ] || [ -z "$x" ]`)
- N4 Useless `|| true` on commands that cannot fail
- N5 Double-validation — same input checked twice in a chain with no
  intervening state change

**Redundant**
- R1 Duplicate implementations under different names
- R2 Copy-paste variants differing only by hardcoded string/number
  (parameterization candidates)

**Over-engineered**
- E1 Single-use abstractions — helper used exactly once, trivially inlineable
- E2 Future-proofing — `case` arms or config branches with no live callers

## NOT Slop (do not flag)
- Hook points intentionally left empty for user override (identified in
  Phase 0 as entry-point files with empty/skeleton bodies)
- OS/platform-portability branches for targets in the supported matrix
- Source guards (`_LOADED` idempotency checks at top of libraries)
- IPv6/optional-feature parallel paths guarded by config flags
- Documented CLI aliases required for flock-wrapper / dispatch parity
- Vendored shared-library public API — raise against canonical, not consumer

---

## Phase 0 — Discovery (mandatory, runs before any scanning)

Build a verification manifest. The manifest gates every subsequent finding.
Record the output of each step.

### 0.1 Project root + primary sources
- PROJECT_ROOT = nearest ancestor containing `.git`
- Primary source dirs: directories matching `files|src|lib|bin|internals`
  at depth <= 3 under PROJECT_ROOT
- Entry executables: `find $PROJECT_ROOT -maxdepth 3 -type f -executable`,
  filter by bash/sh shebang

### 0.2 RUNTIME_SOURCES — runtime-sourced files
```
grep -rnE '^\s*(source|\.)\s+[^#]' $PRIMARY_DIRS $ENTRY_EXECUTABLES
```
Resolve each source target (handle `${VAR}` and relative paths by reading
the containing file's defaults). Every function/variable reference inside
a RUNTIME_SOURCE file is a live call site.

### 0.3 DISPATCH_TARGETS — CLI dispatch
For each entry executable, find the dominant `case "$1"` / `case "$cmd"`
block. Extract every function name appearing in a case arm. These
functions are alive via string-dispatch even if direct grep shows them
unreferenced.

### 0.4 ENTRY_POINTS — external entry files
```
find $PROJECT_ROOT -maxdepth 4 -type f \( \
    -path '*/cron.*' -o -name 'cron.*' -o -name '*.service' -o \
    -name '*.timer' -o -name 'hook_*' -o -name 'init.d.*' -o \
    -name 'install.sh' -o -name 'uninstall.sh' -o -name 'postinst' -o \
    -name 'preinst' -o -name 'postrm' -o -name 'prerm' \)
```
Treat as live call sites. Also include cron scripts and init units.

### 0.5 CANONICAL_LIB_ROOTS — cross-project canonical sources
For each file in `$PRIMARY_DIRS` matching `*_lib.sh` or `lib*.sh`, check
for a sibling canonical repo at `$(dirname $PROJECT_ROOT)/<basename>/`.
```
find $(dirname $PROJECT_ROOT) -maxdepth 2 -type d -name '*_lib'
```
Vendored functions must be verified against the canonical repo's tree
and tests before being flagged. If the canonical has callers or test
coverage, the finding is `CANONICAL-FIRST` (raise against canonical),
not `DELETE`.

### 0.6 TEST_SOURCES — test files
```
find $PROJECT_ROOT -type f \( -name '*.bats' -o -name '*_test.*' -o \
    -name 'test_*.*' -o -name '*.test.*' -o -name '*.spec.*' \)
```
Tested functions are not dead.

### 0.7 PACKAGE_SPECS — packaging scriptlets
```
find $PROJECT_ROOT -type f \( -name '*.spec' -o -path '*/debian/*' -o \
    -name 'Makefile' -path '*/pkg/*' \)
```
Scriptlet blocks and Makefile recipes reference runtime code.

### 0.8 Emit the manifest
Print a summary block:
```
Manifest:
  PRIMARY_DIRS:       <list>
  ENTRY_EXECUTABLES:  <list>
  RUNTIME_SOURCES:    <N files>
  DISPATCH_TARGETS:   <N functions>
  ENTRY_POINTS:       <N files>
  CANONICAL_LIB_ROOTS: <list or none>
  TEST_SOURCES:       <N files>
  PACKAGE_SPECS:      <N files>
```
If RUNTIME_SOURCES or DISPATCH_TARGETS is empty in a non-trivial Bash
project, STOP and flag the discovery gap — most maintained Bash projects
have at least one of each. An empty result usually means the discovery
missed something and will cause a false-positive wall downstream.

---

## Phase 1 — Candidate Discovery

Scan primary sources for each category above. Collect raw candidates with
file:line + symbol + category. Do not assign confidence yet.

## Phase 2 — Per-Finding Verification Checklist

For EVERY candidate, run and attach the output of each relevant check.
A finding cannot be HIGH unless every relevant check returned zero hits.

Function candidates:
- [ ] V1 Direct callers in primary sources
- [ ] V2 Referenced in any RUNTIME_SOURCES file
- [ ] V3 Member of DISPATCH_TARGETS
- [ ] V4 Referenced in ENTRY_POINTS
- [ ] V5 Referenced in TEST_SOURCES
- [ ] V6 Referenced in PACKAGE_SPECS
- [ ] V7 If defined in a vendored lib file: check canonical tree + tests

Variable candidates:
- [ ] V8 `local[[:space:]].*\bVAR\b` returns zero — rules out scope error
- [ ] V9 Referenced as `$VAR` or `${VAR` anywhere
- [ ] V10 Referenced in RUNTIME_SOURCES (templates often consume config)
- [ ] V11 Sourced as a path (`source "$VAR"`, `. "$VAR"`)
- [ ] V12 Referenced in PACKAGE_SPECS or ENTRY_POINTS

## Phase 3 — Confidence Gate

- **HIGH** — every relevant check returned zero, AND the defining block
  was read end-to-end. Attach grep commands and their zero-count output.
- **MED** — one or more checks ambiguous or not runnable in this project.
  State the specific gap.
- **LOW** — pattern match only; structural reason to suspect indirect use.

**Density safeguard:** if HIGH findings in a single category exceed 10,
or total HIGH findings exceed 25, STOP and self-audit. At those densities
in a maintained codebase, Phase 0 probably missed an extended-scope
class. Re-run discovery with a wider net before emitting. **Do not
dispatch sentinel or engineer passes on a discovery-failure result** —
re-run Phase 0 first.

## Phase 4 — Self-Challenge Gate

For each HIGH finding, attempt to DISPROVE it in one line:
"If this were alive, the caller would look like ___. I checked ___ and
found ___."

If you cannot describe what a live caller would look like, downgrade to
MED. This forces the scanner to reason about the call graph rather than
rely on grep negatives alone.

## Phase 5 — Sentinel Peer Review (default ON)

**Skip if:**
- `--quick` or `--no-sentinel` was passed
- Phase 4 produced zero HIGH findings (nothing to review)
- Phase 3 density safeguard triggered (re-run discovery first)

Dispatch the `rdf-reviewer` subagent in **sentinel mode** with a
read-only adversarial review payload. The reviewer attempts to disprove
each HIGH finding using independent grep / source reading.

**Dispatch payload:**

```
MODE: sentinel
DEPTH: full
SCOPE: AI-slop audit findings (read-only review of static-analysis output)
TARGET_FINDINGS: <inline copy of the HIGH findings table from Phase 4>
DISCOVERY_MANIFEST: <inline copy of Phase 0 manifest>
PROJECT_ROOT: <absolute path>

GOVERNANCE:
  index: .rdf/governance/index.md
  anti-patterns: .rdf/governance/anti-patterns.md
  constraints: .rdf/governance/constraints.md
  conventions: .rdf/governance/conventions.md

REVIEW_TASK:
  For each HIGH finding, perform an independent adversarial cross-check:
  1. Re-grep for the symbol with a fresh pattern (word boundary, including
     mid-line and inside $() / `` substitutions).
  2. Check for indirect references — eval, ${!var}, dispatch tables,
     config-driven exec (BAN_COMMAND, ALERT_*, etc.), template
     expansion, alert variants (_JSON, _TG suffixes).
  3. Identify any extended-scope file the discovery agent likely skipped
     (cron.daily, install.sh, importconf, postinst, postrm, RPM/DEB
     scriptlets, man pages, sample configs).
  4. For each finding, return one of:
     - SENTINEL-CONFIRMED-DEAD — independent check agrees, action stands
     - SENTINEL-FALSE-POSITIVE — found a live reference, with file:line
     - SENTINEL-NEEDS-ENGINEER — ambiguous; engineer pass should verify

REPORT_FORMAT:
  Per finding: file:line · symbol · sentinel verdict · evidence (one
  line, with grep cmd or file:line of the contradicting reference).
  Footer: counts by verdict, plus any new findings discovered during
  the cross-check (extended-scope misses).
```

**On reviewer return:**
- Drop SENTINEL-FALSE-POSITIVE items from the HIGH set; log them in the
  FP-filter log with the reviewer's evidence.
- Pass SENTINEL-CONFIRMED-DEAD items to Phase 6 (or directly to Phase 7
  if `--no-engineer`).
- Pass SENTINEL-NEEDS-ENGINEER items to Phase 6; if `--no-engineer` is
  set, downgrade them to MED in the final report rather than emitting
  HIGH without engineer verification.

## Phase 6 — Engineer FP-Validation (default ON)

**Skip if:**
- `--quick` or `--no-engineer` was passed
- Phase 5 produced zero items needing engineer verification
- Phase 3 density safeguard triggered

Dispatch the `rdf-engineer` subagent with **explicit read-only
constraints** (no edits, no commits, no test execution beyond verification
greps). Engineer is dispatched here for its toolset (Bash for `git log
-S`, Read for source files, Grep for cross-references), not its TDD
protocol.

**Dispatch payload:**

```
MODE: read-only verification (do NOT modify any file, do NOT commit,
      do NOT run tests, do NOT invoke /r-build or any write workflow)
SCOPE: Final FP-validation pass for AI-slop audit
TARGET_ITEMS: <inline list of SENTINEL-CONFIRMED-DEAD +
              SENTINEL-NEEDS-ENGINEER findings from Phase 5>
DISCOVERY_MANIFEST: <inline copy of Phase 0 manifest>
SENTINEL_NOTES: <inline copy of Phase 5 evidence per item>
PROJECT_ROOT: <absolute path>

GOVERNANCE:
  index: .rdf/governance/index.md
  architecture: .rdf/governance/architecture.md
  conventions: .rdf/governance/conventions.md

VALIDATION_TASK:
  For each TARGET_ITEM, run and report:
  1. git log -S '<symbol>' -- '<path>' — was it added in a recent commit
     with a deferred consumer? Was it removed and re-added?
  2. Package manifest scan — grep for the symbol in pkg/rpm/*.spec,
     pkg/deb/debian/*, pkg/symlink-manifest, Makefile recipes.
  3. Public surface scan — grep in man pages (*.1, *.5, *.8), README*,
     docs/, sample config files, completion scripts (*.bash-completion).
  4. External-config scan — for variables: check if the name is part of
     a documented public config surface that consumers may set without
     source visibility.
  5. Final per-item verdict (one of):
     - DEAD-SAFE-TO-REMOVE — all checks zero, action stands
     - KEEP-PUBLIC-API — public CLI/config surface, deletion would break
     - KEEP-PACKAGED — referenced in package scriptlets / install path
     - KEEP-DESIGN-SYMMETRY — part of intentional dispatch parity (e.g.,
       N-backend × M-op matrix); deletion would break the pattern
     - KEEP-FUTURE-CONSUMER — git log shows recent add with planned use

OUTPUT_FORMAT:
  Per item: file:line · symbol · final verdict · one-line evidence
  (specific grep result, commit hash, or man-page reference).
  Strictly read-only. No file modifications. No commits.
```

**On engineer return:**
- Items verdict DEAD-SAFE-TO-REMOVE remain in the final HIGH set.
- All KEEP-* verdicts move to the FP-filter log with the engineer's
  reason; they are removed from the final HIGH set.

## Phase 7 — Output

```
# AI Slop Audit — <project>

## Discovery Manifest
<Phase 0 summary — reviewer uses this to audit scan scope>

## Pipeline Summary
| Phase                       | Count | Notes |
|-----------------------------|-------|-------|
| Phase 1 raw candidates      |   N   |       |
| Phase 3 HIGH (pre-challenge)|   N   |       |
| Phase 4 HIGH (post-challenge)|  N   |       |
| Phase 5 sentinel filtered   |   N   | <skipped if --no-sentinel> |
| Phase 6 engineer filtered   |   N   | <skipped if --no-engineer> |
| **Final HIGH**              |   N   |       |

## Summary
| Category          | HIGH | MED | LOW | Total |
|-------------------|------|-----|-----|-------|
| Dead              |  N   |  N  |  N  |   N   |
| Orphan            |  N   |  N  |  N  |   N   |
| Noop              |  N   |  N  |  N  |   N   |
| Redundant         |  N   |  N  |  N  |   N   |
| Over-engineered   |  N   |  N  |  N  |   N   |
| **Total**         |  N   |  N  |  N  |   N   |

## Findings (post-sentinel + post-engineer)

### <Category>

**[file:line] symbol — category tag**
Evidence:
  V1 (direct callers): <grep cmd> → <count>
  V2 (runtime sources): <grep cmd> → <count>
  V3 (dispatch): <not in DISPATCH_TARGETS>
  V4 (entry points): <grep cmd> → <count>
  V5 (tests): <grep cmd> → <count>
  V6 (packaging): <grep cmd> → <count>
  V7 (canonical): <N/A or canonical grep result>
Challenge attempted: <one line>
Sentinel: SENTINEL-CONFIRMED-DEAD — <evidence>
Engineer: DEAD-SAFE-TO-REMOVE — <evidence>
Confidence: HIGH
Action: DELETE | PARAMETERIZE | LEAVE | CANONICAL-FIRST

## FP Filter Log

Items dropped by sentinel or engineer passes, with the disqualifying
reference. This section is the audit trail for everything the discovery
phase wanted to flag but the FP passes vetoed.

### Dropped by Sentinel
- **[file:line] symbol** — SENTINEL-FALSE-POSITIVE: <evidence>

### Dropped by Engineer
- **[file:line] symbol** — KEEP-PUBLIC-API: man bfd.1 line 240
- **[file:line] symbol** — KEEP-PACKAGED: pkg/rpm/bfd.spec %install
- **[file:line] symbol** — KEEP-DESIGN-SYMMETRY: 8-backend × 4-op matrix

## Skipped (known-alive, verified in Phase 0)
- <N> functions reachable via DISPATCH_TARGETS
- <N> functions referenced in RUNTIME_SOURCES
- <N> vendored-library public API (canonical-managed)
- <N> hook skeleton files (user-override contract)
```

## Rules
- Read-only — do NOT modify any files at any phase
- Phase 0 discovery is mandatory; do not skip even for scoped scans
- Every HIGH finding must attach grep evidence for each relevant check
- Density safeguard triggers a re-run, not a downgrade — if >10 HIGH in
  a category, the discovery missed a class, fix Phase 0 and re-scan
- Vendored-library findings must always be `CANONICAL-FIRST` unless the
  canonical repo itself has zero callers — per workspace Shared Libraries
  rule 1 (canonical project edits first)
- When uncertain, classify as MED — never emit HIGH without evidence
- Output the Discovery Manifest at the top of every report so the
  reviewer can audit scan scope before trusting findings
- Sentinel and engineer dispatch payloads must be self-contained — copy
  the HIGH findings table inline; do not assume subagents read external
  state files
- Engineer dispatch must explicitly state read-only constraints (no
  edits, no commits, no /r-build) — the agent's default mode is TDD
  with file modifications
- If sentinel returns SENTINEL-NEEDS-ENGINEER but `--no-engineer` is
  set, downgrade those items to MED in the final report — never emit
  HIGH without the engineer pass when the reviewer specifically
  requested it
