AI slop audit. Finds dead code, orphan helpers, noop functions,
tautological guards, redundant implementations, and over-engineered
abstractions. Read-only static analysis. Uses a discovery-first protocol
to build a per-project call-site manifest before scanning — prevents the
false-positive wall that hits naive dead-code scanners when projects use
runtime-sourced templates, CLI dispatch tables, or vendored shared
libraries.

## Arguments
- `$ARGUMENTS` — optional: category filter (`dead`, `orphan`, `noop`,
  `redundant`, `over-engineered`) or single file/directory to scope the
  scan. Default: all categories across all primary sources.

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
class. Re-run discovery with a wider net before emitting.

## Phase 4 — Self-Challenge Gate

For each HIGH finding, attempt to DISPROVE it in one line:
"If this were alive, the caller would look like ___. I checked ___ and
found ___."

If you cannot describe what a live caller would look like, downgrade to
MED. This forces the scanner to reason about the call graph rather than
rely on grep negatives alone.

## Phase 5 — Output

```
# AI Slop Audit — <project>

## Discovery Manifest
<Phase 0 summary — reviewer uses this to audit scan scope>

## Summary
| Category          | HIGH | MED | LOW | Total |
|-------------------|------|-----|-----|-------|
| Dead              |  N   |  N  |  N  |   N   |
| Orphan            |  N   |  N  |  N  |   N   |
| Noop              |  N   |  N  |  N  |   N   |
| Redundant         |  N   |  N  |  N  |   N   |
| Over-engineered   |  N   |  N  |  N  |   N   |
| **Total**         |  N   |  N  |  N  |   N   |

## Findings

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
Confidence: HIGH | MED | LOW
Action: DELETE | PARAMETERIZE | LEAVE | CANONICAL-FIRST

## Skipped (known-alive, verified in Phase 0)
- <N> functions reachable via DISPATCH_TARGETS
- <N> functions referenced in RUNTIME_SOURCES
- <N> vendored-library public API (canonical-managed)
- <N> hook skeleton files (user-override contract)
```

## Rules
- Read-only — do NOT modify any files
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
