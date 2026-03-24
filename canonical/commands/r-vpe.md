# /r-vpe — Pipeline Orchestrator

Optional end-to-end pipeline orchestrator. Takes outcome-oriented
conversation from the user and manages the full
spec → plan → build → ship workflow.

This command is purely additive. It calls existing pipeline commands
unchanged. Users who prefer manual control can continue using
/r-spec, /r-plan, /r-build, and /r-ship independently.

## Invocation

/r-vpe                — start new pipeline from conversation
/r-vpe --resume       — resume interrupted pipeline from state file

## Task List Protocol

Create tasks progressively — one stage at a time, not all upfront.
The task list UI sorts by status bucket (in_progress → pending →
completed), then by creation order within each bucket. Creating all
pipeline tasks at startup causes future-stage tasks (Plan, Build,
Ship) to appear before the current sub-command's tasks (Research,
Write spec, Phase 2...) in the pending list.

**Rules:**
- Create only Intake at startup
- Sub-commands (/r-spec, /r-plan, /r-build) create their own task
  lists — do NOT create duplicate umbrella tasks for those stages
- Create Ship only after /r-build completes all phases — this keeps
  it after all phase tasks in creation order

At startup:

TaskCreate: "Intake: understand outcome and scope"
  activeForm: "Understanding desired outcome"

After all build phases pass:

TaskCreate: "Ship: release workflow"
  activeForm: "Shipping"

## Resume Protocol

If --resume is specified or .rdf/work-output/vpe-progress.md exists:

1. Read the state file
2. Determine pipeline stage reached
3. Present resume state:
   "Resuming pipeline for: {topic}
    Stage: {intake|spec|plan|build|ship}
    Progress: {stage-specific detail}
    Continue? [Y/start fresh]"
4. If continuing: skip completed stages, resume current stage
   (delegate to the appropriate command's own resume mechanism)

## Stage 1: Intake

Mark task "Intake" as in_progress.

### Adaptive Conversation

Read the user's input. Assess clarity:

**Clear input** (actionable problem statement with scope):
  Restate as structured problem statement. Ask for confirmation.
  1 exchange.

**Partially clear** (has direction but missing scope or motivation):
  Ask 1-2 targeted questions:
  - "What's driving this?" (if motivation unclear)
  - "What does success look like?" (if acceptance unclear)
  Then synthesize. 2-3 exchanges.

**Vague input** (general dissatisfaction or broad goal):
  Ask up to 3 questions:
  - "What specific friction are you experiencing?"
  - "What's driving this change now?"
  - "What would success look like?"
  Then synthesize. 3-4 exchanges.

**Max 4 exchanges before synthesizing.** Do not let intake become
an unbounded conversation.

### Problem Statement Synthesis

After intake, present:

"Here's what I understand:

**Problem:** {1-2 sentences describing the current state}
**Goal:** {1-2 sentences describing desired outcome}
**Scope:** {what's in, what's explicitly out}
**Success:** {how to verify it's done}

Ready to design? [Y/adjust]"

Wait for user confirmation.

Write state:
  .rdf/work-output/vpe-progress.md:
    TOPIC: {topic}
    STAGE: intake
    STATUS: complete
    PROBLEM: {problem statement}
    GOAL: {goal}
    SCOPE: {scope}

Mark task "Intake" as completed.

## Stage 2: Design (invokes /r-spec)

Before invoking /r-spec, check docs/specs/ for existing specs. If a
recent spec exists and matches the intake topic, present:
  "Found existing spec: {path}. Use this? [Y/new spec]"
If Y, skip to Stage 3 (Plan).

Otherwise, invoke /r-spec with the synthesized problem statement as
the seed input. The user participates in brainstorming and design
questions as normal — VPE does not suppress or shortcut the /r-spec
workflow.

VPE's role during spec:
- Ensure the problem statement from intake is the starting context
- Let /r-spec handle all brainstorming, research, and spec writing
- After /r-spec completes, read the committed spec path

After spec is committed:

"Spec complete: {spec path}
 Ready to plan the implementation? [Y/pause]"

If user says pause: write state and stop (user can resume with
/r-vpe --resume).

Write state:
  STAGE: spec
  STATUS: complete
  SPEC_PATH: {path}

## Stage 3: Plan (invokes /r-plan)

Invoke /r-plan with the spec path. The user approves the plan as
normal — VPE does not suppress the /r-plan workflow.

After plan is committed:

"Plan ready: PLAN.md ({N} phases)
 Ready to build? [Y/pause/build-specific-phase]"

Write state:
  STAGE: plan
  STATUS: complete
  PLAN_PHASES: {N}

## Stage 4: Build (invokes /r-build --parallel)

Invoke /r-build --parallel. The build command handles all phase
orchestration: dependency graph reading, batch computation, parallel
dispatch, merge, quality gates, and failure handling.

VPE receives the aggregate result:
- All phases passed → continue to ship
- Failures exist → present to user:
  "Build completed with failures:
   {failure summary from /r-build}
   [retry-failed / pause / continue-to-ship]"
  Wait for user decision.

After all phases complete:
  "All {N} phases complete. End-of-plan review: {verdict}.
   Ready to ship? [Y/pause]"

Write state after build completes:
  STAGE: build
  STATUS: complete
  COMPLETED_PHASES: [1, 2, ..., N]

Create the Ship task now (after all phase tasks exist, so it
appears last in the pending list):

TaskCreate: "Ship: release workflow"
  activeForm: "Shipping"

## Stage 5: Ship (invokes /r-ship)

Mark task "Ship" as in_progress.

Invoke /r-ship. The user confirms the PR as normal — VPE does not
suppress the /r-ship workflow.

After ship completes:

"> **Pipeline complete** — {project} shipped.
>  Spec: {spec_path}
>  Plan: PLAN.md ({N} phases)
>  Ship: {PR URL}"

Write state:
  STAGE: ship
  STATUS: complete

Mark task "Ship" as completed.

Clean up: vpe-progress.md retained for session log reference.

## Constraints

- Never modify existing pipeline commands — call them as-is
- Never suppress user interaction within pipeline commands
- Never skip approval gates (spec approval, plan approval, ship confirmation)
- Auto-continue between build phases only (phases are already approved
  as a batch when the plan was approved)
- Max 4 exchanges during intake — escalate to /r-spec if more exploration needed
- Track state in vpe-progress.md for crash recovery at every stage transition
