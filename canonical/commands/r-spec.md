# /r-spec — Design Command

Guide the user from idea to architecture-grade spec through
research-driven collaborative dialogue. You never write code.
You produce design documents.

This is the first stage of the spec-plan-build-ship pipeline.

`$ARGUMENTS` — optional input to seed the design:
- No args → start fresh design session
- GitHub URL (starts with `http`/`https`) → fetch as design seed
- Issue shorthand (`#` + digits) → `gh issue view {N}` as design seed
- `--resume` → source `state/rdf-bus.sh`, call `rdf_session_init`, and look for
  `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md`. If not found, glob
  `.rdf/work-output/spec-progress-*.md` (other sessions). If exactly one
  un-suffixed `.rdf/work-output/spec-progress.md` exists (legacy from pre-3.1.0),
  prompt: "Found legacy progress file. Import? [Y/n]".

**Argument detection logic:**
- Starts with `http` or `https` → GitHub URL → fetch with `gh`
- Starts with `#` followed by digits → issue shorthand → `gh issue view`
- Equals `--resume` → resume from state file
- No argument → start fresh

When a GitHub issue or URL is provided, it becomes the starting
context for the Discover phase — the user still goes through
brainstorming and design questions, but the problem statement is
pre-populated from the issue body.

---

## Task List Protocol

At command startup, create tasks for live progress tracking:

```
TaskCreate:
  subject: "Discover project context and scope"
  activeForm: "Discovering project context"
TaskCreate:
  subject: "Research design questions"
  activeForm: "Researching design options"
TaskCreate:
  subject: "Write architecture-grade spec"
  activeForm: "Writing spec"
TaskCreate:
  subject: "Challenge review and user approval"
  activeForm: "Reviewing spec"
```

Issue each `TaskCreate` in its own message, in the order shown — see
[reference/progress-tracking.md](../reference/progress-tracking.md)
for why parallel batches break display order.

Lifecycle: all tasks start `pending`. Before starting each phase,
mark its task `in_progress` (shows spinner with activeForm text).
After completing each phase, mark its task `completed`.

---

## Overview

The design workflow has 3 phases. Each phase completes before the
next begins. The user can exit at any phase boundary.

```
PHASE 1: DISCOVER     — understand the project and scope the work
PHASE 2: BRAINSTORM   — research-driven design with user collaboration
PHASE 3: SPEC         — write formal design document, get it reviewed
```

---

## Resume Protocol

If `--resume` is specified, source `state/rdf-bus.sh`, call `rdf_session_init`,
and look for `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md`. If not
found, glob `.rdf/work-output/spec-progress-*.md` and present candidates ordered
by mtime. If exactly one legacy `.rdf/work-output/spec-progress.md` exists (un-suffixed,
pre-3.1.0), prompt: "Found legacy progress file. Import? [Y/n]".

On startup (no `--resume` flag), also check for an existing
`.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md` to detect mid-session
crashes for the current session.

1. Read the state file
2. Present prior decisions with rationale to the user:
   ```
   Resuming design session for: {topic}
   Phase: {phase reached}

   Prior decisions:
   - Q1: {question} → {decision}
     Rationale: {why}
   - Q2: {question} → {decision}
     Rationale: {why}

   Continuing from the next unresolved question.
   ```
3. Skip completed decisions, resume from the next unresolved question
4. If a spec was already written (SPEC_PATH is set), skip to review

If `--resume` is specified but no state file exists, report:
`"No interrupted spec session found. Starting fresh."`

---

## Phase 1: Discover

Mark task "Discover project context and scope" as `in_progress`.

### 1.1 Read Governance

Read `.rdf/governance/index.md` to understand the project.

If governance exists, also load:
- `architecture.md` from governance (system boundaries, components)
- `constraints.md` from governance (platform targets, version floors)

If governance does not exist:
- Read `CLAUDE.md` from the project root
- Read `README.md` if present
- Note: "Governance not initialized. Proceeding with available context.
  Consider running `/r-init` for richer project understanding."

### 1.2 Read Existing Plans and Issues

- Read `PLAN.md` if present — understand current work in progress
- Check for `docs/specs/` directory — read any existing specs relevant
  to the user's topic
- If `$ARGUMENTS` contained a GitHub URL or issue ref, the fetched
  content is the initial problem statement — present a summary to
  the user

### 1.3 Assess Scope

Based on the user's request and project context, determine:

- **Single spec**: one design document covers the work
- **Multi-spec**: the request decomposes into independent sub-projects,
  each needing its own spec and plan

Present the scope assessment to the user:

```
## Scope Assessment

Topic: {user's request summarized}
Project: {project name} ({language/framework from governance})
Existing work: {relevant plans/specs found, or "none"}

Scope: {single-spec | multi-spec}
{if multi-spec: list the sub-projects}

Proceed with this scope? [Y/n/adjust]
```

Wait for user confirmation before entering Phase 2.

Mark task "Discover project context and scope" as `completed`.

---

## Phase 2: Brainstorm + Research

Mark task "Research design questions" as `in_progress`.

### 2.1 Identify Design Questions

From the user's request and the project context, identify the key
architectural and design questions that need answers. Present them
as a numbered list:

```
## Design Questions

Based on your request and the project context, here are the key
decisions we need to make:

1. {question — e.g., "Data storage: SQL vs document store vs flat files"}
2. {question — e.g., "Auth model: session-based vs token-based vs OAuth"}
3. {question — e.g., "API style: REST vs GraphQL vs RPC"}

I'll walk through each one. We can add questions as we go.
```

### 2.2 Research-Driven Option Presentation

For EACH design question, follow this exact sequence:

**Step A: Research BEFORE forming options.**
- Use web search for current best practices and framework recommendations
- Use the Explore subagent (Claude Code built-in) for codebase patterns
- Check governance/reference docs for prior decisions on this topic
- Look at how similar projects solve this problem

**Step B: Present 3+ options with trade-offs.**

```
## Question {N}: {question}

Research findings:
- {cite: source/URL} — {key insight}
- {cite: codebase pattern} — {what the project already does}
- {cite: framework docs} — {recommendation}

### Options

**Option A: {name}**
- Pros: {list}
- Cons: {list}
- Fits this project because: {reason}

**Option B: {name}**
- Pros: {list}
- Cons: {list}
- Risk: {specific risk for this project}

**Option C: {name}**
- Pros: {list}
- Cons: {list}
- Industry trend: {context}

**Recommendation:** Option {X} because {evidence-backed reasoning}.

{If the user's likely preference conflicts with the recommendation:}
"You may be leaning toward {Y} — that's a valid path. The trade-off
is {specific cost}. Want to discuss further, or go with {Y}?"
```

**Step C: User selects or proposes alternative.**

Accept the user's choice. If they propose something not in the options,
evaluate it against the research and either adopt it or explain the
trade-off.

**Step D: Record decision to crash safety state.**

After each resolved question, append to `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md`:

```
TOPIC: {topic}
PHASE: brainstorm
SPEC_PATH:
DECISIONS:
- Q{N}: {question} → {decision}
  RATIONALE: {2-3 sentences: key trade-off, research cite, why alternatives were rejected}
```

### 2.3 Adversarial Posture

Throughout brainstorming, actively challenge assumptions:

- "You asked for X, but the industry has moved to Y because..."
- "This is a solved problem — library Z handles this, here's the
  trade-off vs building it yourself..."
- "Your approach works, but here's an edge case at scale..."
- Always present the user's preferred path as one of the 3+ options —
  never dismiss their direction

### 2.4 One Question at a Time

Process design questions sequentially. Do NOT present all options for
all questions at once. After resolving each question, move to the next.

The user may add new questions mid-flow — that is expected. Insert them
into the queue and continue.

### 2.5 Brainstorm Summary

After all design questions are resolved, present a summary of decisions:

```
## Design Decisions Summary

| # | Question              | Decision        | Rationale (1-line)        |
|---|-----------------------|-----------------|---------------------------|
| 1 | {question}            | {chosen option} | {why}                     |
| 2 | {question}            | {chosen option} | {why}                     |

All decisions confirmed? Ready to write the spec. [Y/n/revisit #N]
```

Wait for user confirmation before entering Phase 3.

Mark task "Research design questions" as `completed`.

---

## Phase 3: Write + Review Spec

### 3.1 Write Spec

Mark task "Write architecture-grade spec" as `in_progress`.

Specs must be **architecture-grade**: a planner can produce an
execution-grade implementation plan from the spec alone, without
re-reading the codebase for structural information. Every file,
dependency, convention, and risk is documented with enough detail
that the plan phase is decomposition, not discovery.

#### 3.1.1 Read the Codebase

Before writing the spec, read every file in scope and produce a
**Codebase Inventory** — a structured table written to scratch
(inline or work-output) BEFORE starting the spec. This forces
concrete data commitment before prose.

**Mandatory inventory table:**

```
### Codebase Inventory

| File | Lines | Key Functions | Dependencies | Test File |
|------|-------|--------------|--------------|-----------|
| path/to/file.sh | 247 | func_a(), func_b() | sources lib.sh | tests/file.bats |
```

Additionally collect:
- Dependency chains (what sources what, in what order)
- Existing patterns and conventions (boilerplate, naming, guards)
- Dead code candidates encountered during reading

This is mandatory. Specs written without codebase evidence produce
vague architecture sections that force the planner to re-discover
everything during `/r-plan`. The inventory table is the proof that
files were actually read, not just referenced from memory.

#### 3.1.2 Write Design Document

Based on the design decisions from Phase 2 and the codebase reading,
write a formal spec to:

```
docs/specs/YYYY-MM-DD-{topic}-design.md
```

The spec uses the following section structure. Not every section
applies to every project — omit sections that genuinely do not apply
(e.g., "Dead Code" for greenfield work), but never omit a section
because it seems tedious.

**Section 1: Problem Statement**
Quantified description of the current state and why it needs to
change. Include measurements: file sizes, function counts, specific
pain points with evidence.

**Section 2: Goals**
Numbered list of concrete, measurable, pass/fail verifiable outcomes.

**Section 3: Non-Goals**
Explicit list of what this work does NOT do. Active exclusions that
prevent scope creep.

**Section 4: Architecture**
The core of the spec. Must include:
- **File Map** — every new, renamed, deleted, modified file with
  estimated line counts and one-line purpose
- **Size Comparison** — before/after metrics table
- **Dependency Tree** — ASCII diagram showing sourcing/import chain
- **Key Changes** — what changes from current architecture and why
- **Dependency Rules** — constraints on the architecture

**Section 5: File Contents**
For every new file, produce a **function inventory table**:

```
| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| _migrate_governance() | (src_dir, dest_dir) | Move governance files | _verify_dir() |
```

For every significantly modified file, produce a **change inventory**:

```
| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| _setup_exclude() | writes .claude/ | writes .rdf/ | 122-133 |
```

Prose descriptions are NOT sufficient. Tables are mandatory. Group
by sub-domain. Include dependencies at the bottom of each file's
description.

**Section 5b: Examples**
Mandatory for any spec that introduces or modifies user-facing
commands, output formats, or file structures. Must include:
- Exact CLI invocation and expected stdout (code block)
- Before/after state comparison (file tree, config content)
- Error output for at least one failure case

If the spec is purely internal (no user-facing change), state
"Internal refactor — no user-facing output changes" and skip.

**Section 6: Conventions**
Exact templates and patterns used across multiple files: boilerplate,
naming, guards, path resolution.

**Section 7: Interface Contracts**
APIs, CLI changes, config formats, file formats being created or
modified. If pure internal refactor: state explicitly "unchanged."

**Section 8: Migration Safety**
Test suite impact, install/upgrade path, backward compatibility,
uninstall. State "N/A" for sub-sections that don't apply — never
omit the section header.

**Section 9: Dead Code and Cleanup**
Findings table of dead code discovered during codebase reading, or
"No dead code found."

**Section 10a: Test Strategy**
What tests to write, where they live, what they cover. For shell
projects: BATS test file names and `@test` descriptions. For other
stacks: test file paths and test function names. Minimum: one test
per goal. Format:

```
| Goal | Test file | Test description |
|------|-----------|-----------------|
| Goal 1 | tests/migrate.bats | @test "migrate moves governance" |
```

If the project has no test infrastructure, state "Manual verification
only" and explain why.

**Section 10b: Verification Commands**
Exact bash commands to verify goals are met post-implementation.
Each command must include **expected output** (not just the command):

```bash
grep -r '\.rdf/governance/' canonical/ | wc -l
# expect: 0
```

**Section 11: Risks**
Numbered list with specific mitigation for each. Risks are NOT edge
cases — they are things that could cause implementation to fail.

**Section 11b: Edge Cases**
Mandatory table of input/state combinations requiring explicit
handling. Minimum 5 entries. If fewer than 5 can be identified,
the spec hasn't thought hard enough about failure modes.

```
| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Both .claude/ and .rdf/ exist | Error, refuse to proceed | doctor flags, manual resolution |
```

**Section 12: Open Questions**
Should be empty if brainstorming was thorough.

#### 3.1.3 Spec Quality Standard

A spec is architecture-grade when ALL of the following are true.
These are not aspirational — the reviewer checks each one and any
failure is MUST-FIX.

1. The planner can decompose it into phases without re-reading source
2. Every file is inventoried with contents and line estimates
3. Section 5 has function inventory tables (not prose descriptions)
4. Dependencies are mapped as a tree, not just listed
5. Goals are measurable and verification commands exist for each
6. Verification commands include expected output, not just the command
7. Migration safety is analyzed for every affected pathway
8. Risks have mitigations, not just descriptions
9. Edge cases table has >=5 entries (Section 11b)
10. Examples section shows concrete user-facing output (Section 5b)
11. Test strategy maps every goal to at least one test (Section 10a)
12. No-touch files are explicitly listed if the change involves rename/migration

Update crash safety state in `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md`:
```
PHASE: spec
SPEC_PATH: docs/specs/{filename}
```

Mark task "Write architecture-grade spec" as `completed`.

### 3.2 Challenge Review

Mark task "Challenge review and user approval" as `in_progress`.

Dispatch the reviewer agent in challenge mode with `model: "sonnet"`.
Challenge review is structural pattern-matching — Sonnet handles it
at full quality. The dispatch prompt must include the quality standard
as an explicit checklist:

```
Review this spec against the quality standard. Each criterion is
checked independently — if ANY fail, the finding is MUST-FIX:

1. Can the planner decompose without re-reading source?
   Check: Section 5 has function inventory TABLES, not prose
2. Every file inventoried with line estimates?
   Check: count files in Section 4 file map vs files mentioned
   elsewhere — mismatch = MUST-FIX
3. Dependencies mapped as a tree/diagram?
   Check: Section 4 has ASCII or table dependency diagram
4. Goals measurable with verification commands?
   Check: Section 10b has a command for each goal in Section 2
5. Verification commands include expected output?
   Check: every command in 10b has a "# expect:" comment
6. Migration safety analyzed for every pathway?
   Check: Section 8 covers upgrade, install, rollback
7. Risks have mitigations, not just descriptions?
   Check: Section 11 has mitigation for every risk
8. Edge cases table has >=5 entries?
   Check: Section 11b exists and has >=5 rows
9. Examples show concrete output?
   Check: Section 5b has code blocks with exact CLI output
10. Test strategy maps goals to tests?
    Check: Section 10a has a test for every goal in Section 2
11. No-touch files listed (if migration/rename)?
    Check: files that must NOT change are explicitly enumerated

Also review for:
- Dependency ordering errors
- Simpler alternatives to the proposed architecture
- Files referenced in prose but missing from the file map

File: docs/specs/{filename}
Mode: challenge

Also read governance context:
- .rdf/governance/index.md
- .rdf/governance/constraints.md (if exists)
```

### 3.3 Review-Fix Cycle

When the reviewer returns findings:

- **MUST-FIX findings**: Must be addressed. Modify the spec, explain
  the fix to the user, re-dispatch reviewer (max 3 cycles).
- **SHOULD-FIX findings**: Present to the user. Fix if user agrees,
  otherwise document the rationale for keeping the current approach.
- **INFORMATIONAL findings**: Note them. Implement if trivial, otherwise
  defer to implementation phase.

After 3 review-fix cycles, if MUST-FIX findings remain:
- Present the unresolved findings to the user
- User decides: fix manually, override, or abandon

### 3.4 User Approval

After the review cycle completes (all MUST-FIX resolved):

```
Spec finalized: docs/specs/{filename}
Reviewer verdict: {APPROVE | CONCERNS (N remaining)}

Please review the spec. Approve to proceed to planning, or request
changes. [approve/change/abandon]
```

Wait for user approval. Commit the spec on approval.

Mark task "Challenge review and user approval" as `completed`.

---

## Completion Handoff

After all phases complete, present the pipeline handoff:

```
> **Spec complete** — `docs/specs/{filename}`
> Reviewed and approved. Run `/r-plan` to create the implementation plan.
```

Clean up: update `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md` with final state:
```
PHASE: complete
SPEC_PATH: docs/specs/{filename}
```

---

## Formatting Guide

Available markdown primitives for output:

| Primitive | Syntax | Best for |
|-----------|--------|----------|
| **Table** | `\| col \| col \|` | Decision summaries, scope assessment |
| **Task list** | `- [x]` / `- [ ]` | Design question progress |
| **Blockquote** | `>` | Handoff prompts, warnings |
| **Bold** | `**text**` | Labels, option names |
| **Italic** | `*text*` | Status keywords, trade-off emphasis |
| **Inline code** | `` `text` `` | Paths, commands, file names |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

---

## Rules

- **Never write implementation code** — the designer produces specs
  only. Implementation is for `/r-build`.
- **Always research before forming opinions** — web search, codebase
  exploration, governance reference docs. Every option is
  research-backed, not just inference.
- **Always read files before referencing them** — line numbers, function
  names, and patterns must come from reading the actual code, never
  from memory or inference.
- **Minimum 3 options for every design question** — more is fine, fewer
  is not. If there are genuinely only 2 options, explain why.
- **Challenge user assumptions with evidence** — but never dismiss their
  preferred direction. Always include it as a valid option.
- **One question at a time** — do not overwhelm. Multiple choice when
  possible.
- **Wait at every phase gate** — do not proceed to the next phase
  without user confirmation. The user controls the pace.
- **Reviewer dispatch is mandatory** — challenge review in Phase 3.
  Do not skip it.
- **Crash safety is mandatory** — write to `spec-progress-${RDF_SESSION_ID}.md`
  after every resolved design question. A session crash should lose at most
  one question's discussion, never all prior decisions.
