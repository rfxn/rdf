Canonical finding schema reference for all audit pipeline agents.
This file is NOT a runnable command — it is a shared specification.

## Finding Format

Each finding MUST use this exact structure:

```
### [PREFIX-NNN] Title
- **Severity**: Critical | Major | Minor | Info
- **File**: path/to/file:line
- **Evidence**: verbatim code, grep output, or command output (fenced block)
- **Verified**: YES — <1-line proof of real impact> | NO — <reason unverifiable>
- **Description**: 2-3 sentence explanation of the issue
- **Impact**: what breaks, what is at risk, or what is degraded
- **Recommendation**: specific actionable fix (one line)
- **Phase**: P1-Immediate | P2-NextRelease | P3-Backlog
```

## Severity Scale (3-tier + Info)

| Severity | Phase | Criteria |
|----------|-------|----------|
| Critical | P1-Immediate | Data loss, security vulnerability, silent wrong behavior, blocked release |
| Major | P2-NextRelease | Functional bug, standards violation with runtime impact, missing coverage for critical path |
| Minor | P3-Backlog | Style, docs drift, low-impact inconsistency, cosmetic, missing edge-case test |
| Info | P3-Backlog | Observation, suggestion, no current defect |

## Agent Registry

Canonical source for agent-to-number-to-prefix mapping, condense group assignments,
and quick-mode inclusion. Both orchestrators (audit.md, audit-quick.md) reference
this table — do NOT maintain separate agent lists in those files.

| # | Agent | Prefix | Command File | Output | Group | Quick | Domain |
|---|-------|--------|--------------|--------|-------|-------|--------|
| 1 | regression | REG | audit-regression.md | agent1.md | A | yes | Recent changes |
| 2 | latent | LAT | audit-latent.md | agent2.md | A | yes | Full codebase bugs |
| 3 | standards | STD | audit-standards.md | agent3.md | A | yes | Shell standards/portability |
| 4 | cli | CLI | audit-cli.md | agent4.md | B | yes | CLI dispatchers/help/validation |
| 5 | docs | DOC | audit-docs.md | agent5.md | B | yes | Documentation accuracy |
| 6 | config | CFG | audit-config.md | agent6.md | A | yes | Config files/parsers/defaults |
| 7 | test-coverage | COV | audit-test-coverage.md | agent7.md | B | yes | BATS coverage analysis |
| 8 | test-exec | TEX | audit-test-exec.md | agent8.md | B | no | BATS execution results |
| 9 | install | INS | audit-install.md | agent9.md | A | no | Install/uninstall correctness |
| 10 | build-ci | BCI | audit-build-ci.md | agent10.md | B | yes | Makefiles/Docker/CI |
| 11 | upgrade | UPG | audit-upgrade.md | agent11.md | B | no | Upgrade/migration paths |
| 12 | version | VER | audit-version.md | agent12.md | B | yes | Version/copyright consistency |
| 13 | security | SEC | audit-security.md | agent13.md | A | yes | Security posture |
| 14 | interfaces | INT | audit-interfaces.md | agent14.md | B | yes | Integration contracts/patterns |
| 15 | modernize | MOD | audit-modernize.md | agent15.md | A | no | Code maturity/structural quality |

**Condense-dedup groups:**
- **Group A** (code-focused): agents 1, 2, 3, 6, 9, 13, 15 → findings-a.md
- **Group B** (surface-focused): agents 4, 5, 7, 8, 10, 11, 12, 14 → findings-b.md

**Quick mode** skips agents where Quick=no: test-exec (8), install (9), upgrade (11),
modernize (15). Context agent always runs in both modes.

## Pipeline Architecture

```
Round 1:  15 domain agents + context agent    (parallel)
          Output: agent1-15.md + context.md

Round 2:  2 condense-dedup agents             (parallel)
          Input:  agent files (per group) + false-positives.md
          Output: findings-a.md + findings-b.md
          Work:   extract, FP-filter, intra-group dedup, severity demotion

Round 3:  1 compile agent                     (sequential)
          Input:  findings-a.md + findings-b.md + context.md
          Output: AUDIT.md
          Work:   cross-group merge, prior work reconciliation, format
```

**Key constraint:** The compile agent receives ~150 lines of input and produces
~200 lines of output. All heavy lifting (extraction, dedup, verification
demotion) happens in Round 2 where it runs in parallel.

## Verification Protocol (MANDATORY — all agents)

Every finding MUST be verified against the actual codebase before reporting.
A finding without verification is a guess — and guesses produce false positives.

### What verification means:
1. **Read the surrounding code** — not just the matched line, but 20+ lines of
   context. Understand what the code actually does before flagging it.
2. **Check for guards** — the "problem" may be handled by a condition, wrapper,
   or caller you haven't read yet. Grep for the variable/function name across
   the codebase to find all usage sites.
3. **Check for intentional patterns** — comments like `# intentional`, config
   that makes the behavior conditional, or documented design decisions.
4. **Test your assumption** — if you claim "variable X is unquoted," verify it's
   not inside a context where quoting is unnecessary (e.g., inside `[[ ]]`,
   assignment RHS, array index). If you claim "function Y is dead," verify no
   file sources or calls it.
5. **Check install-time transforms** — hardcoded paths in source trees may be
   replaced by `install.sh` sed patterns at install time. Verify before flagging.
6. **Verify existence at definition site** — When claiming a function is
   duplicated, dead, or misplaced, grep for the DEFINITION site (look for
   `function name()` or `name() {`), not just the function name as a string.
   A function name appearing in a comment, a variable, or a disabled block
   is not evidence of duplication or existence. When claiming two functions
   contain duplicated logic, read BOTH function bodies in full — name
   similarity is not evidence of body similarity.

### Severity gates:
- **Info**: May report with lighter verification (observation-level)
- **Minor**: Must verify the issue exists and is not guarded/intentional
- **Major**: Must verify runtime impact — show the execution path that triggers it
- **Critical**: Must verify data loss, security breach, or silent wrong behavior
  with concrete evidence of the failure mode

### Discard, don't report:
If during verification you discover the issue is not real, DISCARD it silently.
Do NOT report it as Info "for completeness." An audit with 8 real findings is
worth far more than one with 8 real findings buried in 22 false positives.

### Footer addition:
Include a verification summary in the SUMMARY footer:
```
VERIFIED: <N>/<total> findings verified against code
```

## Limits

- Maximum **20 findings** per agent. If you exceed 20, merge the lowest-severity
  items or drop Info-level findings until at or below the cap.
- Be selective, not comprehensive. Prioritize verified high-severity findings
  over exhaustive low-severity enumeration.

## Counter-Hypothesis Protocol (MANDATORY — all agents, all findings Minor+)

The verification protocol confirms a finding exists. The counter-hypothesis
protocol confirms it is not intentional. Both must pass before reporting.

Before reporting any finding at Minor severity or above:

1. **Hypothesis**: "This code has [issue] because [evidence]"
2. **Counter-hypothesis**: "This code might be correct because [alternative]"
3. **Seek counter-evidence** — check ALL (do not stop at first match):
   (a) Does false-positives.md list this pattern FOR THIS FILE/FUNCTION?
       Pattern matches against different file locations are not counter-evidence.
   (b) Is there an inline comment within 5 lines explaining the choice?
   (c) Does the project CLAUDE.md document this as intentional behavior?
   (d) Is this a shared library file where the "issue" is expected library
       behavior? Libraries intentionally lack project-specific context,
       use portable defaults, and have no install.sh.
   (e) Is this path replaced by install.sh sed transforms at install time?
   (f) Does surrounding code (20+ lines) contain guards, wrappers, or
       callers that handle the concern?

   **Evidence floor**: Counter-evidence must be LOCATION-SPECIFIC — same
   file and function (or direct caller). A project-wide pattern match is
   not sufficient to discard a finding.

4. **Verdict** (based on weight of ALL checks, not any single check):
   - Counter-evidence specific and compelling across multiple checks →
     DISCARD silently (do not report, do not report as Info)
   - Counter-evidence present but single check or ambiguous →
     DEMOTE severity one level, note ambiguity in the finding
   - No location-specific counter-evidence → REPORT at assessed severity

5. **Record in each finding**:
   ```
   CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
   ```

6. **Footer addition** (alongside existing VERIFIED footer):
   ```
   DISCARDED: <N> findings discarded via counter-hypothesis
   ```

## Required Footer

Every agent MUST end its output file with these exact lines:

```
SUMMARY: <total_findings> findings (C:<n> M:<n> m:<n> I:<n>)
COMPLETION: <PREFIX> DONE
```

Where C=Critical, M=Major, m=Minor, I=Info. Example:
```
VERIFIED: 12/12 findings verified against code
DISCARDED: 3 findings discarded via counter-hypothesis
SUMMARY: 12 findings (C:1 M:4 m:5 I:2)
COMPLETION: LAT DONE
```

## false-positives.md Entry Format

Each entry in a project's `./audit-output/false-positives.md` MUST include
a file-path scope so agents can apply the entry only when the location matches:

```
<file_path> | <pattern description> | <reason it is not a finding>
```

Examples:
```
files/internals/tlog_lib.sh | BASERUN /tmp default | install-time replaced by consuming projects
files/bfd | declare -A arrays | global in production, local in test sourcing — intentional
files/internals/bfd_alert.sh | SC2086 $rules_arg | intentional word-splitting for YARA arguments
```

Entries WITHOUT a file-path scope are treated as project-wide but carry lower
weight in counter-hypothesis evaluation — they cannot alone justify discarding
a finding in a file they were not written about.

Entries should be reviewed at each release cycle. Remove entries for code that
no longer exists. Update file paths after refactors.
