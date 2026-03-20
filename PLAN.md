# Implementation Plan: Gate Simplification & VPE Pipeline Orchestrator

**Goal:** Replace the risk×type gate selection matrix with a 5-level scope classification, restore v2-style self-routing finding qualifiers across all agents, and add an optional VPE pipeline orchestrator command.

**Architecture:** Three independent change streams: (1) dispatcher scope classification replaces tag-driven gates, (2) agent finding vocabularies gain qualifier syntax, (3) new /r:vpe command. Stream 1 and 2 are tightly coupled (dispatcher routing reads qualifiers). Stream 3 is independent.

**Tech Stack:** Markdown (agent/command definitions), no runtime code. Verification via grep + `rdf generate claude-code`.

**Spec:** docs/specs/2026-03-20-gate-simplification-vpe-design.md

**Phases:** 8

**Bootstrap note:** This plan uses the new 4-field metadata format it implements. Risk, Type, and Gates fields are intentionally omitted. All phases are serial-context (main conversation) — the spec is available in the same context as the plan, so spec section references serve as anchors for the exact replacement text.

**Line number note:** Line numbers reference the ORIGINAL file state before any phase executes. After Phase 1 modifies dispatcher.md, downstream line references within that file will have shifted. Use section headings to locate content when line numbers are stale.

## Conventions

**Commit message format:**
```
Description of change

[Change] line item 1
[New] line item 2
```

**CRITICAL:** Stage files explicitly by name — never `git add -A` or `git add .`. Force-add with `-f` if gitignore blocks spec/doc files.

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `canonical/commands/r-vpe.md` | ~250 | VPE pipeline orchestrator command | N/A (manual verification) |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `canonical/agents/dispatcher.md` | Replace gate selection matrix with scope classification; update finding resolution for qualifiers | N/A (manual verification) |
| `canonical/agents/reviewer.md` | Update report formats with qualifier syntax; update counter-hypothesis threshold text | N/A (manual verification) |
| `canonical/agents/qa.md` | Update report format with qualifiers + ESCALATION_RECOMMENDED | N/A (manual verification) |
| `canonical/agents/uat.md` | Update report format with qualifiers + UX ratings | N/A (manual verification) |
| `canonical/commands/r-plan.md` | Remove Risk/Type/Gates from Section 2.3 and 2.6; update quality standard | N/A (manual verification) |
| `canonical/commands/r-build.md` | Remove RISK/TYPE from dispatch payload; always load all governance | N/A (manual verification) |
| `canonical/commands/r-review.md` | Update finding labels in dispatch descriptions | N/A (manual verification) |
| `canonical/reference/framework.md` | Replace gate selection text with scope classification summary | N/A (manual verification) |
| `reference/diagrams.md` | Replace Section 4 quality gates diagram and table | N/A (manual verification) |
| `modes/development/context.md` | Update stale "phase tags" reference | N/A (manual verification) |
| `canonical/commands/r-start.md` | Add VPE in-flight signal detection | N/A (manual verification) |
| `canonical/commands/r-status.md` | Add VPE pipeline stage to dashboard | N/A (manual verification) |
| `canonical/reference/session-safety.md` | Add vpe-progress.md to recovery signals | N/A (manual verification) |

## Phase Dependencies

All phases sequential — no parallelization.

Phases 1-2: Core engine changes (dispatcher + agents)
Phases 3-4: Plan/build command alignment
Phase 5: Documentation surfaces
Phase 6: VPE command (independent but after docs are updated)
Phase 7: Integration points (start/status/session-safety)
Phase 8: Regenerate, verify, push

---

### Phase 1: Replace dispatcher gate selection with scope classification

Replace the tag-driven gate selection matrix (lines 58-71) with the scope classification system. Update finding resolution vocabulary (CONCERN→SHOULD-FIX, SUGGESTION→INFORMATIONAL) and add qualifier-based routing.

**Files:**
- Modify: `canonical/agents/dispatcher.md` (gate selection + finding resolution)

- **Mode**: serial-context
- **Accept**: dispatcher.md contains `scope:docs` through `scope:sensitive` (5 levels), precedence rule, and qualifier-routed finding resolution with SHOULD-FIX/INFORMATIONAL vocabulary
- **Test**: `grep -c 'scope:docs\|scope:focused\|scope:multi-file\|scope:cross-cutting\|scope:sensitive' canonical/agents/dispatcher.md` returns >= 5; `grep -c 'CONCERN\|SUGGESTION' canonical/agents/dispatcher.md` returns 0
- **Edge cases**: "Phase description says security but files are docs-only" — covered by precedence rule; "Default scope when cannot determine" — covered by default scope:multi-file

- [ ] **Step 1: Replace Gate Selection section (lines 58-71) with Scope Classification**

  Old (lines 58-71):
  ```
  ### Gate Selection (dispatcher-internal)

  The dispatcher reads phase tags from PLAN.md as hints and selects
  gates automatically. The developer never needs to understand this
  matrix — it is orchestrator intelligence, like RDF 2.x's mgr.

  - risk:low, type:config → Gate 1 only
  - risk:medium, type:feature → Gates 1 + 2 + 3-lite
  - risk:medium, type:refactor → Gates 1 + 2 + 3-full
  - risk:high (any type) → Gates 1 + 2 + 3-full
  - type:security (any risk) → Gates 1 + 2 + 3-full
  - type:user-facing, risk:medium → Gates 1 + 2 + 3-lite + 4
  - type:user-facing, risk:high → All 4 gates (3-full)
  - Default (no tags): Gates 1 + 2 + 3-lite
  ```

  New:
  ```
  ### Scope Classification (dispatcher-internal)

  The dispatcher classifies each phase by change scope, derived
  automatically from the phase's file list, description, and governance
  context. The planner does not tag scope — the dispatcher infers it.

  Derivation rules:
  1. Read the phase file list and description from the dispatch payload
  2. Count files. Read file paths and match against governance signals.
  3. Classify at the highest matching scope level. Evaluation order:
     sensitive > cross-cutting > multi-file > focused > docs

    scope:docs
      All files are documentation, changelog, comments, or README.
      No source code changes.

    scope:focused
      1 file changed, or all changes confined to config/scaffolding.
      Single function modification.

    scope:multi-file
      2+ source files changed. Standard feature or refactor work.
      No install paths, CLI entry points, or security-critical paths.

    scope:cross-cutting
      Changes touch install scripts, CLI entry points, cross-OS logic,
      breaking changes, or paths flagged in governance/constraints.md.

    scope:sensitive
      Changes touch security-critical paths, shared libraries consumed
      by other projects, data migration logic, or credential handling.
      Also: any file path flagged in governance/anti-patterns.md as
      security-sensitive.

  Gate mapping:
    scope:docs          → Gate 1 only
    scope:focused       → Gates 1 + 2
    scope:multi-file    → Gates 1 + 2 + Gate 3 (sentinel-lite, 2-pass)
    scope:cross-cutting → Gates 1 + 2 + Gate 3 (sentinel-full, 4-pass)
    scope:sensitive     → Gates 1 + 2 + Gate 3 (sentinel-full, 4-pass)

  User-facing modifier (any scope level):
    If the file list contains CLI entry points, help text, or man pages,
    add Gate 4 (UAT) regardless of scope level.

  Default (cannot determine scope): scope:multi-file
  ```

- [ ] **Step 2: Update Gate 3 description (lines 48-52)**

  Old (lines 48-52):
  ```
  Gate 3 — Reviewer sentinel (adversarial gate, auto-scaled):
    Dispatcher selects depth based on phase tags from planner:
      lite (2-pass): anti-slop + regression
      full (4-pass): anti-slop, regression, security, performance
    Tags are planner hints, not developer responsibilities.
  ```

  New:
  ```
  Gate 3 — Reviewer sentinel (adversarial gate, auto-scaled):
    Dispatcher selects depth based on scope classification:
      lite (2-pass): anti-slop + regression — for scope:multi-file
      full (4-pass): anti-slop, regression, security, performance — for scope:cross-cutting and scope:sensitive
    Scope is derived from phase content, not planner tags.
  ```

- [ ] **Step 3: Update Gate 4 description (lines 54-56)**

  Old:
  ```
  Gate 4 — UAT (conditional):
    For type:user-facing phases
    Real-world scenarios, install flows, CLI interactions
  ```

  New:
  ```
  Gate 4 — UAT (conditional):
    Added when file list contains CLI entry points or help text
    Real-world scenarios, install flows, CLI interactions
  ```

- [ ] **Step 4: Update Finding Resolution section (lines 152-207)**

  Replace `CONCERN` with `SHOULD-FIX` and `SUGGESTION` with `INFORMATIONAL` throughout. Add qualifier-based routing table after the "The dispatcher owns..." paragraph. Replace lines 191-207 with the qualifier-routed version from the spec. Retain the existing fix/refute loop and escalation format unchanged — only vocabulary and routing table change.

  Key replacements:
  - "CONCERN findings — advisory:" → "SHOULD-FIX findings — advisory:"
  - "Dispatcher collects all CONCERNs" → "All qualifiers → collect, present at phase end"
  - "SUGGESTION findings — logged:" → "INFORMATIONAL findings — logged:"
  - "3 advisory concerns" → "3 advisory findings"
  - Add MUST-FIX qualifier routing table, ESCALATION_RECOMMENDED, and VERIFIED_SOUND handling

- [ ] **Step 5: Verify**

  ```bash
  grep -c 'scope:docs\|scope:focused\|scope:multi-file\|scope:cross-cutting\|scope:sensitive' canonical/agents/dispatcher.md
  # expect: >= 5
  grep -c 'CONCERN\b' canonical/agents/dispatcher.md
  # expect: 0
  grep -c 'SUGGESTION' canonical/agents/dispatcher.md
  # expect: 0
  grep -c 'SHOULD-FIX' canonical/agents/dispatcher.md
  # expect: >= 2
  grep -c 'qualifier' canonical/agents/dispatcher.md
  # expect: >= 2
  ```

- [ ] **Step 6: Commit**

  ```
  git add -f canonical/agents/dispatcher.md
  git commit -m "Replace gate selection matrix with scope classification

  [Change] Gate selection: risk×type matrix → 5-level scope classification
  [Change] Finding resolution: CONCERN→SHOULD-FIX, SUGGESTION→INFORMATIONAL
  [New] Qualifier-based finding routing (merge-block, fix-or-refute, etc.)
  [New] Scope precedence rule: sensitive > cross-cutting > multi-file > focused > docs"
  ```

---

### Phase 2: Update agent finding vocabularies with qualifier syntax

Update reviewer, QA, and UAT agent definitions to produce findings with the shared severity spine + agent-scoped qualifiers. Restore v2 per-pass default severities in sentinel mode.

**Files:**
- Modify: `canonical/agents/reviewer.md` (challenge + sentinel report formats)
- Modify: `canonical/agents/qa.md` (report format + ESCALATION_RECOMMENDED)
- Modify: `canonical/agents/uat.md` (report format + UX ratings)

- **Mode**: serial-context
- **Accept**: All 3 agent files use qualifier syntax; reviewer has per-pass default severities; QA has ESCALATION_RECOMMENDED; UAT has UX ratings and WORKFLOW-BREAKING/USER-FACING/COSMETIC qualifiers
- **Test**: `grep -c 'merge-block\|fix-or-refute' canonical/agents/reviewer.md canonical/agents/qa.md` returns >= 1 per file; `grep -c 'workflow-breaking' canonical/agents/uat.md` returns >= 1
- **Edge cases**: "Finding report has bare MUST-FIX (no qualifier)" — backward compatible per spec edge case row 3

- [ ] **Step 1: Update reviewer.md Challenge Mode report format (lines 29-36)**

  Replace BLOCKING/CONCERN/SUGGESTION labels with MUST-FIX(blocking-concern)/SHOULD-FIX(advisory-concern)/INFORMATIONAL(risk-area). Add VERIFIED_SOUND section.

- [ ] **Step 2: Update reviewer.md Sentinel Mode report format (lines 69-89)**

  Add per-finding severity with qualifier syntax to each pass. Replace Summary line. Add verdict vs severity clarification note and v2 per-pass default severities.

- [ ] **Step 3: Update reviewer.md counter-hypothesis text (line 97)**

  "MUST-FIX or CONCERN" → "MUST-FIX or SHOULD-FIX"

- [ ] **Step 4: Update qa.md report format (lines 35-53)**

  Replace with qualifier-aware format: MUST-FIX(merge-block), SHOULD-FIX(advisory), INFORMATIONAL, ESCALATION_RECOMMENDED.

- [ ] **Step 5: Update uat.md report format (lines 34-51)**

  Replace with qualifier-aware format: MUST-FIX(workflow-breaking), SHOULD-FIX(user-facing), INFORMATIONAL(cosmetic). Add UX_RATING, OUTPUT_QUALITY, WORKFLOW_INTEGRITY ratings. Add verdict status rules.

- [ ] **Step 6: Verify**

  ```bash
  grep -c 'blocking-concern\|advisory-concern\|fix-or-refute' canonical/agents/reviewer.md
  # expect: >= 4
  grep -c 'VERIFIED_SOUND\|Verified Sound' canonical/agents/reviewer.md
  # expect: >= 1
  grep -c 'merge-block' canonical/agents/qa.md
  # expect: >= 1
  grep -c 'ESCALATION_RECOMMENDED' canonical/agents/qa.md
  # expect: >= 1
  grep -c 'workflow-breaking\|user-facing' canonical/agents/uat.md
  # expect: >= 2
  grep -c 'UX_RATING\|OUTPUT_QUALITY' canonical/agents/uat.md
  # expect: >= 2
  ```

- [ ] **Step 7: Commit**

  ```
  git add -f canonical/agents/reviewer.md canonical/agents/qa.md canonical/agents/uat.md
  git commit -m "Update agent finding vocabularies with qualifier syntax

  [Change] Reviewer: challenge uses MUST-FIX(blocking-concern)/SHOULD-FIX(advisory-concern)/INFORMATIONAL(risk-area) + VERIFIED_SOUND
  [Change] Reviewer: sentinel uses MUST-FIX(fix-or-refute)/SHOULD-FIX(pass:<name>) with v2 per-pass defaults
  [Change] QA: uses MUST-FIX(merge-block)/SHOULD-FIX(advisory) + ESCALATION_RECOMMENDED
  [Change] UAT: uses MUST-FIX(workflow-breaking)/SHOULD-FIX(user-facing)/INFORMATIONAL(cosmetic) + UX ratings"
  ```

---

### Phase 3: Simplify r-plan phase metadata

Remove Risk, Type, and Gates from the phase tagging section and format template. Update the quality standard and reviewer dispatch checklist.

**Files:**
- Modify: `canonical/commands/r-plan.md` (Sections 2.3, 2.6, 3.1, quality standard)

- **Mode**: serial-context
- **Accept**: `grep -c '^\- \*\*Risk\*\*\|^\- \*\*Type\*\*\|^\- \*\*Gates\*\*' canonical/commands/r-plan.md` returns 0; quality standard says "4 metadata fields"
- **Test**: No Risk/Type/Gates in phase format; "4 metadata fields" in quality standard
- **Edge cases**: "Plan has old-format metadata" — backward compatible, dispatcher ignores extra fields

- [ ] **Step 1: Replace Section 2.3 (lines 231-261) — remove Risk, Type, Gates, gate table**

  New Section 2.3 (execution mode only, with note that dispatcher derives scope):
  ```
  ### 2.3 Tag Each Phase

  For each phase, provide orchestration metadata:

  **Execution mode** (how the dispatcher runs it):
  - `[serial-context]` — 1 file, simple change, stays in main session
  - `[serial-agent]` — 2-5 files or files with dependencies, one subagent
  - `[parallel-agent]` — 6+ independent files, parallel subagents

  The dispatcher automatically classifies change scope and selects
  quality gates based on the phase's file list, description, and
  governance context. No risk, type, or gate tagging is needed in the
  plan — the dispatcher derives these at execution time.
  ```

- [ ] **Step 2: Update phase format template (lines 320-326) — remove Risk/Type/Gates lines**

- [ ] **Step 3: Update mandatory fields text (line 346) — "7" → "4", remove Risk/Type/Gates**

- [ ] **Step 4: Update reviewer checklist item 3 (line 382) — "7 metadata fields" → "4 metadata fields"**

- [ ] **Step 5: Update quality standard item 8 (line 472) — "7 metadata fields" → "4 metadata fields"**

- [ ] **Step 6: Verify**

  ```bash
  grep -c '^\- \*\*Risk\*\*' canonical/commands/r-plan.md
  # expect: 0
  grep -c '^\- \*\*Type\*\*' canonical/commands/r-plan.md
  # expect: 0
  grep -c '^\- \*\*Gates\*\*' canonical/commands/r-plan.md
  # expect: 0
  grep -c 'risk:low\|risk:medium\|risk:high' canonical/commands/r-plan.md
  # expect: 0
  grep '4 metadata fields' canonical/commands/r-plan.md
  # expect: 2 matches
  ```

- [ ] **Step 7: Commit**

  ```
  git add -f canonical/commands/r-plan.md
  git commit -m "Simplify r-plan phase metadata to 4 fields

  [Remove] Risk, Type, Gates metadata fields from phase format
  [Remove] Gate derivation table from Section 2.3
  [Change] Mandatory fields: 7 → 4 (Mode, Accept, Test, Edge cases)
  [Change] Quality standard and reviewer checklist updated to match"
  ```

---

### Phase 4: Simplify r-build dispatch payload

Remove RISK and TYPE from the dispatch payload. Always load all governance files.

**Files:**
- Modify: `canonical/commands/r-build.md` (Sections 4 and 5)

- **Mode**: serial-context
- **Accept**: `grep -c '^RISK:\|^TYPE:' canonical/commands/r-build.md` returns 0; all governance files loaded unconditionally
- **Test**: No RISK/TYPE in payload; no "if applicable" in governance loading
- **Edge cases**: none

- [ ] **Step 1: Update governance loading (lines 54-61) — always load all files**

- [ ] **Step 2: Remove RISK and TYPE from dispatch payload (lines 73-74) and remove "if applicable" from governance lines**

- [ ] **Step 3: Verify**

  ```bash
  grep -c '^RISK:\|^TYPE:' canonical/commands/r-build.md
  # expect: 0
  grep -c 'if applicable' canonical/commands/r-build.md
  # expect: 0
  ```

- [ ] **Step 4: Commit**

  ```
  git add -f canonical/commands/r-build.md
  git commit -m "Simplify r-build dispatch payload

  [Remove] RISK and TYPE fields from dispatcher dispatch payload
  [Change] Governance loading: always load all files for scope derivation"
  ```

---

### Phase 5: Update documentation surfaces

Update framework.md, diagrams.md, r-review.md, and modes/development/context.md.

**Files:**
- Modify: `canonical/reference/framework.md` (lines 163-172)
- Modify: `reference/diagrams.md` (Section 4, lines 180-229)
- Modify: `canonical/commands/r-review.md` (lines 103-107)
- Modify: `modes/development/context.md` (lines 25-26)

- **Mode**: serial-context
- **Accept**: framework.md has scope classification summary; diagrams.md has scope-based flowchart; r-review.md uses qualifier labels; context.md references "auto-derives scope"
- **Test**: `grep 'scope:' canonical/reference/framework.md` matches; `grep 'phase tags' modes/development/context.md` returns 0
- **Edge cases**: none

- [ ] **Step 1: Replace framework.md gate selection section (lines 163-172) with scope summary**

- [ ] **Step 2: Replace diagrams.md Section 4 (lines 180-229) with scope-based flowchart and table**

- [ ] **Step 3: Update r-review.md finding labels (lines 103-107) to qualifier syntax**

- [ ] **Step 4: Update modes/development/context.md (lines 25-26) — "phase tags" → "auto-derives scope"**

- [ ] **Step 5: Verify**

  ```bash
  grep -c 'scope:' canonical/reference/framework.md
  # expect: >= 5
  grep 'Scope Classification' reference/diagrams.md
  # expect: 1 match
  grep 'blocking-concern' canonical/commands/r-review.md
  # expect: 1 match
  grep 'phase tags' modes/development/context.md
  # expect: 0
  ```

- [ ] **Step 6: Commit**

  ```
  git add -f canonical/reference/framework.md reference/diagrams.md canonical/commands/r-review.md modes/development/context.md
  git commit -m "Update documentation for scope classification and qualifier vocabulary

  [Change] framework.md: gate selection → scope classification summary
  [Change] diagrams.md: Section 4 → scope-based classification flowchart
  [Change] r-review.md: finding labels → qualifier syntax
  [Change] development/context.md: phase tags → auto-derives scope"
  ```

---

### Phase 6: Create VPE pipeline orchestrator command

Create the new /r:vpe command file.

**Files:**
- Create: `canonical/commands/r-vpe.md` (~250 lines)

- **Mode**: serial-context
- **Accept**: File exists, contains all 5 pipeline stages, crash recovery protocol, adaptive intake logic
- **Test**: `test -f canonical/commands/r-vpe.md && echo exists`; `grep -c 'Stage [1-5]' canonical/commands/r-vpe.md` returns 5
- **Edge cases**: "VPE invoked but user already has spec" — handled by Stage 2 detection; "VPE crash during build" — handled by vpe-progress.md

- [ ] **Step 1: Create canonical/commands/r-vpe.md with full content from spec Section 5.7**

- [ ] **Step 2: Verify**

  ```bash
  test -f canonical/commands/r-vpe.md && echo "exists"
  # expect: exists
  grep -c 'Stage [1-5]' canonical/commands/r-vpe.md
  # expect: 5
  grep -c '/r:spec\|/r:plan\|/r:build\|/r:ship' canonical/commands/r-vpe.md
  # expect: >= 8
  grep -c 'vpe-progress' canonical/commands/r-vpe.md
  # expect: >= 2
  grep -ci 'dispatcher\|Gate [0-9]' canonical/commands/r-vpe.md
  # expect: 0 (VPE is decoupled from gate internals)
  ```

- [ ] **Step 3: Commit**

  ```
  git add -f canonical/commands/r-vpe.md
  git commit -m "Add VPE pipeline orchestrator command

  [New] /r:vpe — optional end-to-end pipeline orchestrator
  [New] Adaptive intake conversation (1-4 exchanges)
  [New] Pipeline automation with approval gates (spec→plan→build→ship)
  [New] Crash recovery via vpe-progress.md state file"
  ```

---

### Phase 7: Add VPE integration points

Update r-start, r-status, and session-safety to recognize VPE state files.

**Files:**
- Modify: `canonical/commands/r-start.md` (in-flight detection)
- Modify: `canonical/commands/r-status.md` (pipeline table)
- Modify: `canonical/reference/session-safety.md` (recovery signals)

- **Mode**: serial-context
- **Accept**: All 3 files reference vpe-progress.md
- **Test**: `grep 'vpe-progress' canonical/commands/r-start.md canonical/commands/r-status.md canonical/reference/session-safety.md` returns matches in all 3
- **Edge cases**: "VPE not in use" — sections conditional on state file existence

- [ ] **Step 1: Add VPE in-flight signal to r-start.md (near line 119-140)**

- [ ] **Step 2: Add VPE pipeline stage to r-status.md (conditional row)**

- [ ] **Step 3: Add vpe-progress.md to session-safety.md recovery signals (after line 56)**

- [ ] **Step 4: Verify**

  ```bash
  grep 'vpe-progress' canonical/commands/r-start.md
  # expect: >= 1
  grep 'vpe-progress' canonical/commands/r-status.md
  # expect: >= 1
  grep 'vpe-progress' canonical/reference/session-safety.md
  # expect: >= 1
  ```

- [ ] **Step 5: Commit**

  ```
  git add -f canonical/commands/r-start.md canonical/commands/r-status.md canonical/reference/session-safety.md
  git commit -m "Add VPE integration points to start, status, and session safety

  [New] r-start: detect vpe-progress.md as in-flight signal
  [New] r-status: show VPE pipeline stage when active
  [New] session-safety: add vpe-progress.md to recovery signals"
  ```

---

### Phase 8: Regenerate, verify cross-references, push

Regenerate Claude Code output. Run full verification suite. Update changelogs.

**Files:**
- All generated output (via `rdf generate claude-code`)
- CHANGELOG, CHANGELOG.RELEASE

- **Mode**: serial-context
- **Accept**: `rdf generate claude-code` succeeds; all spec Section 10b verification commands pass; zero stale gate references
- **Test**: Full verification suite from spec Section 10b
- **Edge cases**: none

- [ ] **Step 1: Regenerate Claude Code output**

  ```bash
  bash bin/rdf generate claude-code 2>&1 | tail -5
  # expect: success, no errors
  ```

- [ ] **Step 2: Run full verification suite from spec Section 10b**

- [ ] **Step 3: Verify VPE not coupled to existing commands**

  ```bash
  grep -ci 'vpe' canonical/commands/r-spec.md canonical/commands/r-plan.md canonical/commands/r-build.md canonical/commands/r-ship.md
  # expect: 0 each
  ```

- [ ] **Step 4: Review generated diff**

  ```bash
  git diff --stat
  # expect: changes only in adapters/claude-code/output/ and files listed in the File Map
  ```

- [ ] **Step 5: Update CHANGELOG and CHANGELOG.RELEASE**

  Add entry covering the full plan:
  ```
  3.1.0 — Gate Simplification & VPE Pipeline Orchestrator
  [Change] Gate selection: risk×type matrix replaced with 5-level scope classification
  [Change] Finding vocabulary: shared severity spine + agent-scoped qualifiers (v2 routing restored)
  [Change] Plan metadata: 7 mandatory fields → 4 (Risk/Type/Gates removed)
  [New] /r:vpe — optional end-to-end pipeline orchestrator (spec→plan→build→ship)
  [New] Scope classification: docs, focused, multi-file, cross-cutting, sensitive
  [New] Finding qualifiers: merge-block, fix-or-refute, workflow-breaking, blocking-concern, etc.
  ```

  Note: Changelog updates are batched to Phase 8 for this plan since all phases modify markdown definitions, not shipping code.

- [ ] **Step 6: Commit and push**

  ```
  git add -f CHANGELOG CHANGELOG.RELEASE adapters/claude-code/output/
  git commit -m "Regenerate and verify gate simplification + VPE changes

  [Change] Regenerated Claude Code output from canonical sources
  [Change] Updated CHANGELOG and CHANGELOG.RELEASE for 3.1.0"

  git push
  ```

---
