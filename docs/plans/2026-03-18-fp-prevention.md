# FP Prevention — Counter-Hypothesis Protocol Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed counter-hypothesis FP prevention logic into 6 agent skill files to reduce false positive findings across all review agents.

**Architecture:** Two-layer approach — Layer 1 (context establishment) runs once before finding work, Layer 2 (per-finding counter-hypothesis) runs before each finding is reported. Weighted by agent role: heavy for Sentinel/QA, moderate for SE, light for MGR/UAT.

**Spec:** `docs/specs/2026-03-18-fp-prevention-design.md`

**Tech Stack:** Markdown skill files in `rdf/canonical/commands/`. Deployed via `rdf generate claude-code`.

---

## File Map

All files are in `/root/admin/work/proj/rdf/canonical/commands/`:

| File | Change Type | Weight |
|------|------------|--------|
| `audit-schema.md` | Modify (add verification item 6 + counter-hypothesis section + FP format section) | Cross-cutting |
| `sys-sentinel.md` | Modify (add Step 1.5 + per-finding gate + suppression log) | Heavy |
| `sys-qa.md` | Modify (add Step 1.5 + Step 5.1 gate + Step 5.5 update) | Heavy |
| `sys-eng.md` | Modify (add Step 1 bullets + Step 5e item 6) | Moderate |
| `mgr.md` | Modify (add FP calibration check to status output) | Light |
| `sys-uat.md` | Modify (add intentional behavior check to Step 4) | Light |

False-positives.md files to migrate (5 files):

| File | Current Format | Entries |
|------|---------------|---------|
| `tlog_lib/audit-output/false-positives.md` | Mixed (some scoped, some not) | 14 |
| `brute-force-detection/audit-output/false-positives.md` | Mixed | 17 |
| `linux-malware-detect/audit-output/false-positives.md` | Unscoped | 8 |
| `batsman/audit-output/false-positives.md` | Mostly scoped | 8 |
| `sigforge/audit-output/false-positives.md` | Mostly scoped | 9 |

---

## Chunk 1: Cross-Cutting Foundation

### Task 1: audit-schema.md — Definition-Site Verification

**Files:**
- Modify: `rdf/canonical/commands/audit-schema.md:81-117` (Verification Protocol section)

- [ ] **Step 1: Read current Verification Protocol**

Read `audit-schema.md` lines 81-117. The verification protocol has 5 items
ending at the "Severity gates" subsection. Item 5 is "Check install-time
transforms."

- [ ] **Step 2: Add item 6 after existing item 5**

Insert after the line ending item 5 (`5. **Check install-time transforms**...`)
and before the `### Severity gates:` heading. Add:

```markdown
6. **Verify existence at definition site** — When claiming a function is
   duplicated, dead, or misplaced, grep for the DEFINITION site (look for
   `function name()` or `name() {`), not just the function name as a string.
   A function name appearing in a comment, a variable, or a disabled block
   is not evidence of duplication or existence. When claiming two functions
   contain duplicated logic, read BOTH function bodies in full — name
   similarity is not evidence of body similarity.
```

- [ ] **Step 3: Verify insertion**

Read `audit-schema.md` and confirm item 6 appears between item 5 and
"Severity gates". Confirm no existing content was displaced.

---

### Task 2: audit-schema.md — Counter-Hypothesis Protocol

**Files:**
- Modify: `rdf/canonical/commands/audit-schema.md:119` (after Limits section, before Required Footer)

- [ ] **Step 1: Identify insertion point**

Read `audit-schema.md` lines 119-141. The section order is: Verification
Protocol → Limits → Required Footer. Insert the new section between Limits
and Required Footer.

- [ ] **Step 2: Add Counter-Hypothesis Protocol section**

Insert after the Limits section (after "Be selective, not comprehensive...")
and before `## Required Footer`:

```markdown
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
```

- [ ] **Step 3: Verify section ordering**

Read `audit-schema.md` and confirm order is: Verification Protocol →
Limits → Counter-Hypothesis Protocol → Required Footer.

---

### Task 3: audit-schema.md — false-positives.md Entry Format

**Files:**
- Modify: `rdf/canonical/commands/audit-schema.md` (append after Required Footer)

- [ ] **Step 1: Add false-positives.md format section**

Append after the Required Footer section:

```markdown
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
```

- [ ] **Step 2: Verify**

Read final section of `audit-schema.md` and confirm the new section appears
after Required Footer.

- [ ] **Step 3: Deploy and verify**

```bash
cd /root/admin/work/proj/rdf && rdf generate claude-code 2>&1 | tail -5
rdf doctor 2>&1 | tail -10
```

Confirm no drift warnings for `audit-schema.md`.

- [ ] **Step 4: Commit**

```bash
cd /root/admin/work/proj/rdf
git add canonical/commands/audit-schema.md
git commit -m "$(cat <<'EOF'
Add counter-hypothesis protocol and definition-site verification to audit schema

[New] Counter-Hypothesis Protocol section — mandatory for all 15 audit agents,
  all findings Minor+; location-specific evidence floor prevents suppression bias
[New] Definition-site verification (item 6) in Verification Protocol — grep for
  function definitions, not just name strings; read both bodies before claiming
  duplication
[New] false-positives.md entry format spec — file-path scoped entries, release
  cycle review trigger, weight rules for unscoped entries
EOF
)"
```

---

## Chunk 2: Sentinel (Heavy)

### Task 4: sys-sentinel.md — Step 1.5 FP Context Establishment

**Files:**
- Modify: `rdf/canonical/commands/sys-sentinel.md:86-87` (between Step 1 end and Step 2 start)

- [ ] **Step 1: Read insertion point**

Read `sys-sentinel.md` lines 76-90. Step 1 "Gather Context" ends at line 86
(item 6: "Read MEMORY.md for past failures..."). Step 2 "Run Four Passes"
starts at line 87.

- [ ] **Step 2: Insert Step 1.5**

Insert between Step 1's last item and `### Step 2 -- Run Four Passes`:

```markdown

### Step 1.5 -- FP Context Establishment (MANDATORY)

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

```

- [ ] **Step 3: Verify**

Read `sys-sentinel.md` and confirm Step 1.5 appears between Step 1 and Step 2.

---

### Task 5: sys-sentinel.md — Per-Finding Counter-Hypothesis Gate

**Files:**
- Modify: `rdf/canonical/commands/sys-sentinel.md:185` (Step 3 "Write Findings")

- [ ] **Step 1: Read Step 3 context**

Read `sys-sentinel.md` lines 185-260. Step 3 "Write Findings" defines the
output format. The per-finding gate goes at the start of Step 3, before the
filename discipline paragraph.

- [ ] **Step 2: Insert counter-hypothesis gate**

Insert at the beginning of Step 3, after the `### Step 3 -- Write Findings`
heading and before the `**Filename discipline:**` paragraph:

```markdown

**Per-Finding Counter-Hypothesis Gate (MANDATORY — every MUST-FIX and
SHOULD-FIX finding)**

Before writing any MUST-FIX or SHOULD-FIX finding, run this protocol:

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

```

- [ ] **Step 3: Verify gate placement**

Read `sys-sentinel.md` Step 3 and confirm the gate appears before the
filename discipline paragraph.

---

### Task 6: sys-sentinel.md — Suppression Log in Output Format

**Files:**
- Modify: `rdf/canonical/commands/sys-sentinel.md:236-240` (SUMMARY block area)

- [ ] **Step 1: Read output format**

Read `sys-sentinel.md` lines 195-260. Find the SUMMARY block in the output
template.

- [ ] **Step 2: Add suppression log and CH_RESULT to output template**

Add `CH_RESULT` and `CH_REASON` lines to each finding template (inside the
`S-001 | SHOULD-FIX | [title]` blocks), and add the suppression log section
after the SUMMARY block:

In each finding block template, add after the last field (e.g., after
`Suggestion:`):
```
    CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
    CH_REASON: <one-line counter-evidence evaluation>
```

After the SUMMARY block (`QA_ATTENTION: [pass names...]`), add:
```markdown

DISCARDED_FINDINGS: <N>
  D-001: <file:line> | <original hypothesis> | <discard reason>

If DISCARDED_FINDINGS exceeds total reported findings, add to SUMMARY:
  FP_WARNING: Discarded (<N>) exceeds reported (<N>) — review suppression log
```

- [ ] **Step 3: Verify output template**

Read the full output template section and confirm CH_RESULT appears in
finding blocks and DISCARDED_FINDINGS appears after SUMMARY.

- [ ] **Step 4: Deploy and verify**

```bash
cd /root/admin/work/proj/rdf && rdf generate claude-code 2>&1 | tail -5
rdf doctor 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
cd /root/admin/work/proj/rdf
git add canonical/commands/sys-sentinel.md
git commit -m "$(cat <<'EOF'
Add counter-hypothesis FP prevention to Sentinel

[New] Step 1.5 — FP Context Establishment: library check + false-positives.md
  load before running adversarial passes
[New] Per-finding counter-hypothesis gate with location-specific evidence floor;
  evaluate all checks collectively, DISCARD/DEMOTE/REPORT verdict
[New] CH_RESULT and CH_REASON fields in finding output; DISCARDED_FINDINGS
  suppression log after SUMMARY for EM/QA audit of suppression decisions
EOF
)"
```

---

## Chunk 3: QA (Heavy)

### Task 7: sys-qa.md — Step 1.5 FP Context Establishment

**Files:**
- Modify: `rdf/canonical/commands/sys-qa.md:88-98` (between Step 1 and Step 2)

- [ ] **Step 1: Read insertion point**

Read `sys-qa.md` lines 88-100. Step 1 "Gather context" ends at line 96
(`git diff`). Step 2 "Structural review" starts at line 98.

- [ ] **Step 2: Insert Step 1.5**

Insert between Step 1's last item and `### 2. Structural review`:

```markdown

### 1.5. FP Context Establishment (MANDATORY)

Before running structural or behavioral review, build context that prevents
false positive findings:

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
   is NOT a hardcoded path in production. Hold this catalog for reference
   during Steps 2-3.

```

- [ ] **Step 3: Verify**

Read `sys-qa.md` and confirm Step 1.5 appears between Steps 1 and 2.

---

### Task 8: sys-qa.md — Step 5.1 Counter-Hypothesis Gate

**Files:**
- Modify: `rdf/canonical/commands/sys-qa.md:270` (between Step 5 and Step 5.5)

- [ ] **Step 1: Read insertion point**

Read `sys-qa.md` lines 241-275. Step 5 "Pattern-class sweep" ends before
Step 5.5 "Sentinel Integration" at line 270.

- [ ] **Step 2: Insert Step 5.1**

Insert between the end of Step 5 content and `### 5.5. Sentinel Integration`:

```markdown

### 5.1. Counter-Hypothesis Gate (MANDATORY — every MUST-FIX and SHOULD-FIX)

After completing Steps 2-5 independently, apply the counter-hypothesis
protocol to each MUST-FIX and SHOULD-FIX finding before writing the verdict.
INFORMATIONAL findings are exempt.

**Protocol:**

1. **Hypothesis**: State what QA believes is wrong: "Line N does X, which
   violates Y"
2. **Counter-hypothesis**: Formulate why this code might be correct: "This
   might be intentional if Z"
3. **Seek counter-evidence** — check ALL (do not stop at first match;
   weigh collectively):
   (a) Does false-positives.md list this pattern FOR THIS FILE/FUNCTION?
       A pattern match against a different file location is not counter-
       evidence.
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
     DEMOTE severity one level, note ambiguity in the finding
   - No location-specific counter-evidence → REPORT at assessed severity

5. **Record in each reported finding**:
   ```
   CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
   CH_REASON: <one-line summary of counter-evidence evaluation>
   ```

6. **Suppression log** in verdict file before VERDICT_SUMMARY:
   ```
   DISCARDED_FINDINGS: <N>
     D-001: <file:line> | <original hypothesis> | <discard reason>
   ```
   If DISCARDED exceeds REPORTED, note as unusual — it may indicate
   an overly broad false-positives.md or overly cautious assessment.

```

- [ ] **Step 3: Verify step ordering**

Read `sys-qa.md` and confirm: Step 5 → Step 5.1 → Step 5.5 → Step 6.

---

### Task 9: sys-qa.md — Step 5.5 Sentinel Disagreement Resolution

**Files:**
- Modify: `rdf/canonical/commands/sys-qa.md:270-286` (Step 5.5 section)

- [ ] **Step 1: Read Step 5.5**

Read `sys-qa.md` lines 270-286. Step 5.5 describes how QA reads Sentinel
output after completing independent assessment.

- [ ] **Step 2: Append disagreement resolution to Step 5.5**

Add at the end of the Step 5.5 section, after item 5 ("Note findings QA
disagrees with..."):

```markdown

6. **Suppression disagreement resolution**: When comparing discarded findings:
   - If both QA and Sentinel DISCARDED the same pattern, this is stronger
     confirmation of a true false positive (independent corroboration of
     non-issue).
   - If Sentinel REPORTED a finding that QA DISCARDED (or vice versa), this
     disagreement requires explicit resolution in the verdict. Document which
     agent's reasoning is more location-specific.
```

- [ ] **Step 3: Update verdict template**

In the verdict template (Step 6), add `DISCARDED_FINDINGS` block before
`VERDICT_SUMMARY:` and add `CH_RESULT`/`CH_REASON` to the finding format.

In the finding block template (`### QA-001 | <severity> | <title>`), add
after `Action:`:
```
CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
CH_REASON: <one-line counter-evidence evaluation>
```

Add before `VERDICT_SUMMARY:`:
```
DISCARDED_FINDINGS: <N>
  D-001: <file:line> | <original hypothesis> | <discard reason>
```

- [ ] **Step 4: Deploy and verify**

```bash
cd /root/admin/work/proj/rdf && rdf generate claude-code 2>&1 | tail -5
rdf doctor 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
cd /root/admin/work/proj/rdf
git add canonical/commands/sys-qa.md
git commit -m "$(cat <<'EOF'
Add counter-hypothesis FP prevention to QA

[New] Step 1.5 — FP Context Establishment: library check + false-positives.md
  hold + install-time transform catalog before independent review
[New] Step 5.1 — Counter-hypothesis gate for MUST-FIX and SHOULD-FIX findings
  after independent Steps 2-5; location-specific evidence floor
[New] Step 5.5 update — Sentinel/QA suppression disagreement resolution
[New] CH_RESULT, CH_REASON, DISCARDED_FINDINGS fields in verdict output
EOF
)"
```

---

## Chunk 4: SE, MGR, UAT (Moderate/Light)

### Task 10: sys-eng.md — Step 1 Library Awareness + Step 5e Item 6

**Files:**
- Modify: `rdf/canonical/commands/sys-eng.md:181-189` (Step 1) and `:370-418` (Step 5e)

- [ ] **Step 1: Read Step 1 context**

Read `sys-eng.md` lines 181-191. Step 1 "Understand Context" ends with
`git status` and `git branch`. Add two new bullet points after the last
existing bullet.

- [ ] **Step 2: Add library check and FP file read to Step 1**

Append after the `git status` and `Check MEMORY.md` lines:

```markdown
- **Library check**: If any file to be modified is part of a shared library
  (tlog_lib, alert_lib, elog_lib, pkg_lib, geoip_lib), note this for Step 5e.
  Library files have different correctness criteria: no project-specific
  references is a requirement, portable defaults are expected, and install.sh
  is the consuming project's responsibility.
- If `./audit-output/false-positives.md` exists, read it. Known FP patterns
  inform self-review — avoid flagging your own code for patterns that are
  documented intentional behavior.
```

- [ ] **Step 3: Read Step 5e context**

Read `sys-eng.md` lines 370-420. Step 5e has items 1-5 (Behavioral parity,
Data flow tracing, Cross-project reference, Edge case scan, File path contract
scan). Add item 6 after item 5.

- [ ] **Step 4: Add item 6 to Step 5e**

Insert after the "File path contract scan" item (item 5) and before the
"Evidence mandate" paragraph:

```markdown

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
   the SELF_REVIEW block explaining why the pattern is correct:
   ```
   INTENTIONAL_PATTERNS: "/tmp default in tlog_lib.sh — install-time
     replaced per CLAUDE.md Canonical Path Rule"
   ```
   This gives downstream reviewers (Sentinel, QA) context that the author
   considered the pattern and judged it correct, reducing their FP surface.
```

- [ ] **Step 5: Add INTENTIONAL_PATTERNS to result template**

In the Step 7 result file template (the `VERIFICATION:` block), add after
the `BASH41_GREP:` line inside `SELF_REVIEW:`:
```
    INTENTIONAL_PATTERNS: "<patterns noted as correct, or N/A>"
```

- [ ] **Step 6: Verify**

Read `sys-eng.md` Step 1 and Step 5e. Confirm library check is in Step 1,
item 6 is in Step 5e after item 5, INTENTIONAL_PATTERNS is in the result
template.

- [ ] **Step 7: Deploy and commit**

```bash
cd /root/admin/work/proj/rdf && rdf generate claude-code 2>&1 | tail -5
git add canonical/commands/sys-eng.md
git commit -m "$(cat <<'EOF'
Add counter-hypothesis FP prevention to SE

[New] Step 1 — library check and false-positives.md read for self-review context
[New] Step 5e item 6 — counter-hypothesis on self-review flags with collective
  evidence weighing; INTENTIONAL_PATTERNS output field for downstream reviewers
EOF
)"
```

---

### Task 11: mgr.md — FP Calibration Check

**Files:**
- Modify: `rdf/canonical/commands/mgr.md:134-148` (after Verification Gate status block)

- [ ] **Step 1: Read insertion point**

Read `mgr.md` lines 134-150. The "After Verification Gate Completes" status
block ends before "Parallel Mode Status Table" at line 148.

- [ ] **Step 2: Insert FP Calibration Check**

Insert between the Verification Gate status block and the Parallel Mode
Status Table:

```markdown

### FP Calibration Check

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

```

- [ ] **Step 3: Verify**

Read `mgr.md` and confirm the FP Calibration Check appears between the
Verification Gate and Parallel Mode sections.

- [ ] **Step 4: Deploy and commit**

```bash
cd /root/admin/work/proj/rdf && rdf generate claude-code 2>&1 | tail -5
git add canonical/commands/mgr.md
git commit -m "$(cat <<'EOF'
Add FP calibration checks to EM status output

[New] FP Calibration Check — flags suppression anomalies: discard > report
  ratio, Sentinel/QA disagreement, zero-finding tier 2+ reviews
EOF
)"
```

---

### Task 12: sys-uat.md — Intentional Behavior Verification

**Files:**
- Modify: `rdf/canonical/commands/sys-uat.md:433-434` (between Step 4 and Step 4b)

- [ ] **Step 1: Read insertion point**

Read `sys-uat.md` lines 395-440. Step 4 "UX Assessment" ends at line 433
(after the structured output checks). Step 4b "Output Intelligence" starts
at line 434.

- [ ] **Step 2: Insert intentional behavior check**

Insert between Step 4's last item and `### Step 4b — Output Intelligence`:

```markdown

### Step 4a — Intentional Behavior Verification (MANDATORY for WORKFLOW-BREAKING)

Before classifying any finding as WORKFLOW-BREAKING (which EM treats as
equivalent to QA MUST-FIX and blocks merge):

1. **Check CLAUDE.md**: Does the project CLAUDE.md document this behavior
   as intentional? Key sections to check:
   - "Known Gotchas" or equivalent
   - Exit code documentation
   - Config-conditional behavior descriptions
   - Backward compatibility notes

2. **Check observed vs documented**: If the behavior you observed matches
   what CLAUDE.md describes as expected, it is not a finding — even if it
   looks wrong from a sysadmin perspective. Example: exit code 3 from a
   library function may be a documented graceful fallback, not an error.

3. **Check config state**: If the behavior depends on a config value, verify
   you tested with the documented default. Behavior under non-default config
   is a valid finding only if the config value is user-settable and the
   behavior is undocumented.

If intentional behavior is confirmed, do NOT classify as WORKFLOW-BREAKING.
Reclassify as USER-FACING with a note:
```
INTENTIONAL_BEHAVIOR: <behavior> documented in CLAUDE.md section <X>.
Reclassified from WORKFLOW-BREAKING to USER-FACING — behavior is by design.
```

```

- [ ] **Step 3: Verify step ordering**

Read `sys-uat.md` and confirm: Step 4 → Step 4a → Step 4b → Step 5.

- [ ] **Step 4: Deploy and commit**

```bash
cd /root/admin/work/proj/rdf && rdf generate claude-code 2>&1 | tail -5
git add canonical/commands/sys-uat.md
git commit -m "$(cat <<'EOF'
Add intentional behavior verification to UAT

[New] Step 4a — mandatory CLAUDE.md check before WORKFLOW-BREAKING classification;
  reclassify documented intentional behavior as USER-FACING with evidence note
EOF
)"
```

---

## Chunk 5: false-positives.md Format Migration

### Task 13: Migrate false-positives.md files to scoped format

**Files:**
- Modify: `tlog_lib/audit-output/false-positives.md`
- Modify: `brute-force-detection/audit-output/false-positives.md`
- Modify: `linux-malware-detect/audit-output/false-positives.md`
- Verify: `batsman/audit-output/false-positives.md` (already mostly scoped)
- Verify: `sigforge/audit-output/false-positives.md` (already mostly scoped)

- [ ] **Step 1: Migrate tlog_lib false-positives.md**

Each entry must follow: `<file_path> | <pattern> | <reason>`

Read the current file. For each entry that lacks a file-path scope, add the
appropriate path. Most tlog_lib entries apply to `files/tlog_lib.sh`. The
BATSMAN_CONTAINER_TEST_PATH entry applies to `CLAUDE.md`. The Dockerfile
entry applies to `tests/Dockerfile*`.

- [ ] **Step 2: Migrate BFD false-positives.md**

Read the current file. Add file-path scopes to entries that lack them.
Key mappings:
- tlog_journal_read SC2086 → `files/internals/tlog_lib.sh`
- BAN_ESCALATION → `files/internals/bfd.lib.sh`
- declare -A entries → `files/bfd` or `files/internals/thresholds.conf`
- Test dedup rate → `tests/` (project-wide test scope)
- SC2086 docker run → `lib/run-tests-core.sh` (batsman ref, or `tests/`)

- [ ] **Step 3: Migrate LMD false-positives.md**

Read the current file. Add file-path scopes:
- F-082/F-083 → add file path from AUDIT.md if known, or mark project-wide
- QA-001 hardcoded symlink → `files/internals/functions`
- F-034 clean rules → `files/internals/functions`
- $rules_arg → `files/internals/functions`
- lmd.user.* symlinks → `files/internals/internals.conf`
- TLOG_FLOCK → `files/maldet`
- cron.daily flock → `cron.daily`
- Slack/Telegram curl → `files/internals/lmd_alert.sh` or `files/internals/alert_lib.sh`
- elog_output_enable → `files/maldet`

- [ ] **Step 4: Verify batsman and sigforge**

Read both files. Confirm entries are already scoped. Add file-path scopes
to any entries that lack them.

- [ ] **Step 5: Final deploy and verify**

```bash
cd /root/admin/work/proj/rdf && rdf generate claude-code 2>&1 | tail -5
rdf doctor 2>&1 | tail -10
```

Confirm all 6 skill files deployed without drift.

Note: false-positives.md files are per-project working artifacts (excluded
from git via .git/info/exclude) — no git commit needed for these files.

---

## Verification Checklist

After all tasks complete:

- [ ] `rdf doctor` shows no drift for any of the 6 modified skill files
- [ ] `audit-schema.md` has: item 6 in Verification Protocol + Counter-Hypothesis Protocol section + false-positives.md format section
- [ ] `sys-sentinel.md` has: Step 1.5 + per-finding gate in Step 3 + CH_RESULT in output + DISCARDED_FINDINGS after SUMMARY
- [ ] `sys-qa.md` has: Step 1.5 + Step 5.1 gate + Step 5.5 disagreement + CH_RESULT/DISCARDED_FINDINGS in verdict
- [ ] `sys-eng.md` has: library check in Step 1 + item 6 in Step 5e + INTENTIONAL_PATTERNS in result template
- [ ] `mgr.md` has: FP Calibration Check between Verification Gate and Parallel Mode status blocks
- [ ] `sys-uat.md` has: Step 4a between Step 4 and Step 4b
- [ ] All 5 false-positives.md files use `<file_path> | <pattern> | <reason>` format
