# RDF — Current-State Spec (living)

The maintained current-state view of RDF's architecture. Unlike the dated
`docs/specs/*.md` design records — each a point-in-time proposal that stays
frozen as a historical archive — this file tracks what RDF *is* right now.

## How this file works

`/r-ship` Stage 3e folds each shipped plan's outcome into this file as a dated
delta block (`## <version> — <date>`) with ADDED / MODIFIED / REMOVED lines
derived from the plan File Map (New→ADDED, Modified→MODIFIED, Deleted→REMOVED)
and the changelog. The newest block is prepended at the top, so reading
top-to-bottom gives the reverse-chronological history of what changed. The fold
is user-approved and lightweight (a few bullets), and is skipped for
`bugfix`-tier releases — a defect fix does not change the architecture. The
dated design specs remain the authoritative rationale for each change.

## 3.6.0 — 2026-07-15

ADDED: `agent-skills` adapter — emits the shared `.agents/skills/<cmd>/SKILL.md`
surface (Codex + Antigravity) from `adapters/agent-skills/skill-meta.json`, one
SKILL.md per lifecycle command; `rdf generate agent-skills`.
ADDED: `antigravity` composite generate target (skills + `AGENTS.md`) and an
`agent-skills` deploy target (`--project-root`, default CWD).
ADDED: Claude Code intent-trigger `description:` frontmatter on every generated
command (shared skill-meta trigger, first-sentence fallback); `rdf sync` and
`rdf doctor` strip the leading frontmatter block on the reverse flow so canonical
stays frontmatter-free.
ADDED: `docs/multi-tool-parity.md` — first-class trio (Claude Code, Codex,
Antigravity CLI) plus frozen legacy Gemini CLI feature matrix; deploy/sync
install-surface BATS coverage (`tests/deploy.bats`).
MODIFIED: `gemini-cli` recast as a frozen legacy tier — command TOML now emits
`'''`-literal prompt bodies (strict-parse escaping fix), otherwise unchanged.
MODIFIED: `README.md`, `RDF.md`, `docs/_config.yml` — trio framing.

## 3.5.0 — 2026-07-15

ADDED: task-class tiers (`full`/`quick-plan`/`bugfix`) — `reference/tiers.md`,
rdf-bus tier pointer helpers, plan-schema Rule 10 `**Tier:**` marker; the
dispatcher applies `max(security_floor, min(scope_gate, tier_cap))` so tiers
only remove ceremony, never the security pass.
ADDED: `/r-spec` Phase 1.5 Clarify de-ambiguation micro-gate (skipped for
bugfix); `/r-plan` quick-plan and bugfix condensed paths.
ADDED: `state/rdf-consistency.sh` — spec↔plan↔tasks structural check wired
into `/r-build` Section 1 (`--warn-only` escape hatch; legacy plans without a
`**Tier:**` marker are downgraded to warnings).
ADDED: this file — `/r-ship` Stage 3e living-spec fold.
MODIFIED: `r-spec.md`, `r-plan.md`, `r-build.md`, `r-ship.md`,
`agents/dispatcher.md`, `state/rdf-bus.sh`, `reference/plan-schema.md`.

## 3.4.0 — baseline

**Lifecycle verbs (4):** `/r-spec` (design), `/r-plan` (decompose), `/r-build`
(dispatch + gates), `/r-ship` (release).

**Agents (6):** `dispatcher`, `planner`, `engineer`, `qa`, `reviewer`, `uat`.

**Adapters (6):** `claude-code`, `claude-plugin`, `codex`, `gemini-cli`,
`agents-md`, `agent-skills` — each generated from tool-agnostic `canonical/`
content.

**State:** `state/rdf-bus.sh` is the session bus (active-plan pointer + tier
pointer); governance is loaded from `.rdf/governance/`.
