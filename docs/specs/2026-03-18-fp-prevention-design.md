# False Positive Prevention — Counter-Hypothesis Protocol

**Date:** 2026-03-18
**Status:** Approved
**Scope:** sys-sentinel.md, sys-qa.md, sys-eng.md, mgr.md, sys-uat.md, audit-schema.md

---

## Problem Statement

Agent skills that produce findings (Sentinel, QA, SE self-review, audit agents)
generate a high rate of false positives. Evidence from project history:

- **tlog_lib**: 14 documented FPs from a single audit cycle — all architectural
  misunderstanding (library code flagged for missing project context, /tmp defaults,
  no install.sh)
- **BFD**: 37% FP rate on test dedup findings (name-only comparison, not body)
- **APF**: F-039/F-043 flagged functions that don't exist (grep-based phantom
  duplicates from name matching)
- **LMD**: ClamAV /dev/null flagged for wrong reason (pattern match, not runtime
  behavior)

### Root Cause Classes

| Class | Frequency | Root Cause |
|-------|-----------|------------|
| Intentional design decisions | Very high | Agents flag documented choices as bugs |
| Library vs application confusion | High | Agents expect project context that libraries intentionally lack |
| Pattern match without semantics | High | Grep finds names, not definitions; name similarity ≠ body similarity |
| Install-time transforms ignored | Medium | Hardcoded paths in source are sed-replaced at install |
| ShellCheck without context | Medium | SC2086 on intentional word-splitting flagged as violation |

### Fundamental Gap

Verification happens AFTER a finding is drafted, not BEFORE. Agents look for
evidence that something IS wrong but never look for evidence that it ISN'T.
Additionally, `false-positives.md` files exist per-project but are only loaded by
the condense-dedup round of the audit pipeline — Sentinel, QA, and SE don't
systematically consult them during phase reviews.

---

## Design

### Approach: Context Phase + Per-Finding Counter-Hypothesis (Weighted)

Two layers of FP prevention, tightly coupled into each skill file. No external
shared reference doc. Each agent carries its own discipline.

**Layer 1 — Context Establishment**: Runs once before any finding work. Agents
build a context model that prevents findings from being drafted in ignorance.

**Layer 2 — Per-Finding Counter-Hypothesis**: Runs for each finding above Info
severity. Before reporting, the agent formulates why the code might be correct
and actively seeks evidence supporting the current implementation.

### Weight Distribution

| Role | Layer 1 (Context) | Layer 2 (Counter-Hypothesis) | Rationale |
|------|-------------------|------------------------------|-----------|
| Sentinel | Library check + FP file load | Every MUST-FIX and SHOULD-FIX finding | Primary adversarial reviewer, heaviest finding producer |
| QA | Library check + FP file load + sed catalog | MUST-FIX and SHOULD-FIX findings | Mandatory verification gate, second heaviest |
| SE | Library check + FP file read | Self-review flags only | Code author, moderate FP exposure in self-review |
| MGR | FP calibration on agent output | N/A (no findings) | Dispatch/orchestration role, catches anomalies |
| UAT | Intentional behavior check | WORKFLOW-BREAKING findings only | Tests installed behavior, lowest code-analysis FP exposure |
| Audit Schema | Inherited by all 15 audit agents | All findings Minor+ | Cross-cutting; agents reference schema |

---

## Challenger Review

Reviewed by Challenger agent 2026-03-18. 2 blocking concerns, 6 advisory.
All addressed in final design. Key revisions:

| Concern | Resolution |
|---------|------------|
| CH-001: Suppression bias from "stop at first match" | Removed sequential exit; evaluate ALL checks; location-specific evidence floor |
| CH-002: Shared Layer 1 breaks Sentinel/QA independence | QA reads FP file at Step 5.1 (post-independent Steps 2-5), not preprocessing |
| CH-003: false-positives.md staleness | File-path scope on entries; release-cycle review trigger |
| CH-004: Artifact type underdetermined | Simplified to single yes/no library check |
| CH-005: Check (g) duplicates audit-schema verification | Removed from generic protocol; surgical definition-site grep in audit-schema |
| CH-006: Full Layer 1 conflicts with Sentinel efficiency | Sentinel gets lightweight Layer 1 (no sed catalog, no pattern grep) |
| CH-007: MGR work order artifact field | Dropped; artifact type stays in CLAUDE.md |
| CH-008: Pattern-match FP class not addressed | Definition-site grep added to audit-schema verification protocol |

---

## Skill Changes

### 1. sys-sentinel.md (Heavy)

#### Step 1.5 — FP Context Establishment (MANDATORY)

Inserted between existing Step 1 "Gather Context" and Step 2 "Run Four Passes".

Before running any pass, build context that prevents false positive findings:

1. **Library check**: For each modified file, answer: "Is this file part of a
   shared library consumed by other projects?" (tlog_lib, alert_lib, elog_lib,
   pkg_lib, geoip_lib). If yes, apply library rules for that file:
   - Missing project-specific context is a FEATURE, not a gap
   - Portable defaults (/tmp, empty registries) are expected — consuming
     projects replace them at install time
   - No install.sh is expected — consuming projects handle installation
   - Empty arrays/registries are expected — consumers populate them

2. **Load false-positives.md**: If `./audit-output/false-positives.md` exists,
   read it. These entries are used during the per-finding counter-hypothesis —
   NOT as a preprocessing filter. Do not suppress findings based on FP file
   alone; use it as one input to the per-finding verdict.

#### Per-Finding Counter-Hypothesis Gate

Added to Step 3 "Write Findings". Applies before each finding is written.
Mandatory for every MUST-FIX and SHOULD-FIX finding.

**Protocol:**

1. **Hypothesis**: State what you believe is wrong: "Line N does X, which
   causes Y"
2. **Counter-hypothesis**: Formulate why this code might be correct: "This
   might be intentional if Z"
3. **Seek counter-evidence** — check ALL of the following (do not stop at
   first match; weigh collectively):
   (a) Does false-positives.md list this pattern FOR THIS FILE/FUNCTION?
       A pattern match against a different file location is not counter-evidence.
   (b) Is there an inline comment within 5 lines explaining the choice?
   (c) Does the project CLAUDE.md document this as intentional behavior?
   (d) Is this a shared library file where the "issue" is expected library
       behavior? (from Step 1.5 library check)
   (e) Does surrounding code (20+ lines) contain guards, wrappers, or
       callers that handle the concern?

   **Evidence floor**: Counter-evidence must be LOCATION-SPECIFIC — it must
   reference the same file and function (or direct caller) as the finding.
   A generic project-wide pattern match is not sufficient to discard a
   finding. "CLAUDE.md says /tmp is intentional in tlog_lib.sh" does not
   excuse /tmp in a new function in bfd.lib.sh.

4. **Verdict** (based on weight of ALL checks, not any single check):
   - Counter-evidence specific and compelling across multiple checks →
     DISCARD (do not report)
   - Counter-evidence present but only one check, or ambiguous →
     DEMOTE severity one level, note the ambiguity in the finding
   - No location-specific counter-evidence found →
     REPORT at assessed severity

5. **Record**: For REPORTED and DEMOTED findings, include in the finding:
   ```
   CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
   CH_REASON: <one-line summary of counter-evidence evaluation>
   ```
   Discarded findings have no finding record — they appear only in the
   suppression log.

6. **Suppression log** at end of output, after SUMMARY and before COMPLETION:
   ```
   DISCARDED_FINDINGS: <N>
     D-001: <file:line> | <original hypothesis> | <discard reason>
   ```
   Enables EM and QA to audit suppression decisions. If DISCARDED exceeds
   REPORTED, flag this as unusual in the SUMMARY footer.

---

### 2. sys-qa.md (Heavy)

#### Step 1.5 — FP Context Establishment (MANDATORY)

Inserted after existing Step 1 "Gather context".

1. **Library check**: For each modified file, answer: "Is this file part of a
   shared library consumed by other projects?" (tlog_lib, alert_lib, elog_lib,
   pkg_lib, geoip_lib). If yes, apply library rules for that file throughout
   all subsequent review steps:
   - Missing project-specific context is a FEATURE, not a gap
   - Portable defaults (/tmp, empty registries) are expected — consuming
     projects replace them at install time
   - No install.sh is expected — consuming projects handle installation
   - Empty arrays/registries are expected — consumers populate them

2. **Load false-positives.md**: If `./audit-output/false-positives.md` exists,
   read it. Hold these entries for use during Step 5.1 — NOT during Steps 2-4.
   Steps 2-4 must produce independent findings without FP file influence to
   preserve QA's independent assessment.

3. **Catalog install-time transforms**: If `install.sh` exists:
   ```bash
   grep -n 'sed.*s|' install.sh 2>/dev/null | head -30
   ```
   Any path appearing in a sed replacement is transformed at install time and
   is NOT a hardcoded path in production.

#### Step 5.1 — Counter-Hypothesis Gate (MANDATORY)

After completing Steps 2-5 independently, apply to each MUST-FIX and SHOULD-FIX
finding before writing the verdict. INFORMATIONAL findings exempt.

**Protocol:**

1. **Hypothesis**: State what QA believes is wrong: "Line N does X, which
   violates Y"
2. **Counter-hypothesis**: Formulate why this code might be correct: "This
   might be intentional if Z"
3. **Seek counter-evidence** — check ALL (do not stop at first match):
   (a) Does false-positives.md list this pattern FOR THIS FILE/FUNCTION?
       A pattern match against a different file location is not counter-evidence.
   (b) Is there an inline comment within 5 lines explaining the choice?
   (c) Does the project CLAUDE.md document this as intentional behavior?
   (d) Is this a shared library file where the "issue" is expected library
       behavior? (from Step 1.5 library check)
   (e) Is this path in the install-time transform catalog from Step 1.5?
   (f) Does surrounding code (20+ lines) contain guards, wrappers, or
       callers that handle the concern?

   **Evidence floor**: Counter-evidence must be LOCATION-SPECIFIC — same
   file and function (or direct caller). A project-wide pattern match is
   not sufficient to discard.

4. **Verdict** (based on weight of ALL checks, not any single check):
   - Counter-evidence specific and compelling across multiple checks →
     DISCARD (do not report)
   - Counter-evidence present but single check or ambiguous →
     DEMOTE severity one level, note ambiguity
   - No location-specific counter-evidence → REPORT at assessed severity

5. **Record in each finding**:
   ```
   CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
   CH_REASON: <one-line summary of counter-evidence evaluation>
   ```

6. **Suppression log** in verdict file before VERDICT_SUMMARY:
   ```
   DISCARDED_FINDINGS: <N>
     D-001: <file:line> | <original hypothesis> | <discard reason>
   ```
   If DISCARDED exceeds REPORTED, note as unusual.

#### Step 5.5 Update — Sentinel Disagreement Resolution

When comparing Sentinel findings against QA findings at Step 5.5:
- If both QA and Sentinel DISCARDED the same pattern, this is stronger
  confirmation of a true false positive (independent corroboration of non-issue).
- If Sentinel REPORTED a finding that QA DISCARDED (or vice versa), this
  disagreement requires explicit resolution in the verdict. Document which
  agent's reasoning is more location-specific.

---

### 3. sys-eng.md (Moderate)

#### Step 1 — Library Awareness (addition to existing context list)

Add to the end of the existing Step 1 bullet list:

- **Library check**: If any file to be modified is part of a shared library
  (tlog_lib, alert_lib, elog_lib, pkg_lib, geoip_lib), note this for Step 5e.
  Library files have different correctness criteria: no project-specific
  references is a requirement, portable defaults are expected, and install.sh
  is the consuming project's responsibility.
- If `./audit-output/false-positives.md` exists, read it. Known FP patterns
  inform self-review — avoid flagging your own code for patterns that are
  documented intentional behavior.

#### Step 5e — Counter-Hypothesis on Self-Review Flags (new item 6)

Added as item 6 in the existing self-review checklist (after "File path
contract scan"):

6. **Counter-hypothesis on self-review flags** — When self-review identifies
   a potential issue in your own code, before flagging it in the result file:
   - Is this an intentional pattern documented in CLAUDE.md or
     false-positives.md for this file?
   - Is this a library file where the "issue" is expected behavior?
   - Does the code you wrote follow an existing pattern established
     elsewhere in the same project?

   Weigh collectively — a single check with weak or ambiguous evidence is
   not sufficient to suppress. If multiple checks align with location-specific
   evidence, do not flag the pattern — but DO include a one-line note in
   the SELF_REVIEW block explaining
   why the pattern is correct:
   ```
   INTENTIONAL_PATTERNS: "/tmp default in tlog_lib.sh — install-time
     replaced per CLAUDE.md Canonical Path Rule"
   ```
   This gives downstream reviewers (Sentinel, QA) context that the author
   considered the pattern and judged it correct, reducing their FP surface.

---

### 4. mgr.md (Light)

#### FP Calibration Check (addition to Status Output Protocol)

Added after the existing "After Verification Gate Completes" status block.

When reading Sentinel and QA output, check for suppression anomalies:

- If an agent's DISCARDED_FINDINGS count exceeds REPORTED findings count,
  flag this in the status output:
  ```
  WARNING: <agent> discarded more findings than it reported (<D> discarded,
  <R> reported). Review suppression log for over-broad FP matching.
  ```

- If Sentinel and QA disagree on a finding (one REPORTED, one DISCARDED),
  include in the Verification Gate status:
  ```
  FP_DISAGREEMENT: <N> findings where Sentinel and QA reached different
  conclusions. See verdict for resolution.
  ```

- If an agent's output contains zero findings AND zero discarded findings
  for a tier 2+ change, note as unusual:
  ```
  NOTE: <agent> produced 0 findings and 0 discards on a tier 2+ change.
  Verify the agent reviewed the full diff.
  ```

---

### 5. sys-uat.md (Light)

#### Intentional Behavior Verification (addition to Step 4)

Added after the existing Step 4 UX assessment checklist. Mandatory for
WORKFLOW-BREAKING findings only.

Before classifying any finding as WORKFLOW-BREAKING:

1. **Check CLAUDE.md**: Does the project CLAUDE.md document this behavior
   as intentional? Key sections: Known Gotchas, exit code documentation,
   config-conditional behavior, backward compatibility notes.

2. **Check observed vs documented**: If the behavior matches what CLAUDE.md
   describes as expected, it is not a finding — even if it looks wrong from
   a sysadmin perspective. Exit code 3 from a library function may be a
   documented graceful fallback, not an error.

3. **Check config state**: If the behavior depends on a config value, verify
   you tested with the documented default. Non-default behavior is a finding
   only if user-settable and undocumented.

If intentional behavior confirmed, reclassify from WORKFLOW-BREAKING to
USER-FACING with a note:
```
INTENTIONAL_BEHAVIOR: <behavior> documented in CLAUDE.md section <X>.
Reclassified from WORKFLOW-BREAKING to USER-FACING — behavior is by design.
```

---

### 6. audit-schema.md (Cross-cutting)

#### Definition-Site Verification (addition to Verification Protocol)

Added after existing item 5 "Check install-time transforms":

6. **Verify existence at definition site** — When claiming a function is
   duplicated, dead, or misplaced, grep for the DEFINITION site (look for
   `function name()` or `name() {`), not just the function name as a string.
   A function name appearing in a comment, a variable, or a disabled block
   is not evidence of duplication or existence. When claiming two functions
   contain duplicated logic, read BOTH function bodies in full — name
   similarity is not evidence of body similarity.

#### Counter-Hypothesis Protocol (new section)

Added after "Verification Protocol". Mandatory for all 15 audit agents,
all findings at Minor severity or above.

**Protocol:**

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
     DEMOTE severity one level, note ambiguity
   - No location-specific counter-evidence → REPORT at assessed severity

5. **Record in each finding**:
   ```
   CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
   ```

6. **Footer addition** (alongside existing VERIFIED footer):
   ```
   DISCARDED: <N> findings discarded via counter-hypothesis
   ```

#### false-positives.md Entry Format (new section)

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

---

## Suppression Accountability

Three mechanisms prevent the counter-hypothesis protocol from becoming a
suppression engine:

1. **Agent-level**: Every agent logs discarded findings with reason in a
   DISCARDED_FINDINGS section. Suppression decisions are visible, not silent.

2. **MGR-level**: EM flags anomalies — discard-exceeds-report ratio,
   Sentinel/QA disagreements, zero-finding tier 2+ reviews.

3. **FP file lifecycle**: false-positives.md entries are scoped to file paths
   and reviewed at release cycles. Stale entries are removed.

---

## What This Does NOT Change

- No new shared reference docs or external dependencies
- No changes to dispatch logic, tier routing, or pipeline architecture
- No changes to severity definitions or finding format structure. Adds new
  fields to agent output: CH_RESULT and CH_REASON (per finding), DISCARDED_FINDINGS
  (suppression log), INTENTIONAL_PATTERNS (SE result), INTENTIONAL_BEHAVIOR (UAT),
  and DISCARDED footer (audit agents)
- No changes to the Sentinel/QA independence model (QA Steps 2-4 remain FP-file-free)
- Existing verification protocol in audit-schema preserved and extended, not replaced
- No changes to work order schema

---

## Implementation Plan

Phase 1: audit-schema.md (cross-cutting — all 15 audit agents inherit)
Phase 2: sys-sentinel.md (heaviest FP producer)
Phase 3: sys-qa.md (mandatory gate)
Phase 4: sys-eng.md (moderate — self-review)
Phase 5: mgr.md (light — calibration checks)
Phase 6: sys-uat.md (light — WORKFLOW-BREAKING gate)
Phase 7: false-positives.md format migration (update existing files to scoped format)
