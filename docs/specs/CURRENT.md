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

## 3.6.5 — 2026-08-18

ADDED: `profiles/rfxn-workspace/` — opt-in org overlay (`detect: []`, never
auto-detected) housing `reference/cross-project.md` and
`scripts/comment-snapshot.sh` (both moved out of the generic core); overlay
pattern per ESLint shareable-configs / Renovate presets / Spec Kit precedent.
ADDED: `profiles/node/` — plain-JS governance; `_detect_profiles` gains a
node branch (package.json sole gate, suppressed when typescript matches;
counts as a language, so Dockerfile now co-activates infrastructure).
ADDED: `canonical/reference/` ships as a first-class adapter artifact —
`cc_generate_reference` (hash sidecars) / `cpl_generate_reference` /
agent-skills reference dir; `rdf deploy claude-code` symlinks
`~/.claude/reference`; doctor content-drift + sync loops cover it (sync also
gained the pre-existing missing `governance` target).
ADDED: `tests/derfxn.bats` — 13-test de-rfxn regression suite including a
canonical org-identifier allowlist guard; suite 246 → 262.
MODIFIED: `canonical/scripts/subagent-stop.sh` — hardcoded workspace fallback
replaced by `./.rdf` → `~/.rdf/agent-feed.log` (HOME-guarded, 100 KB
size-capped, mktemp-staged rotation).
MODIFIED: `lib/cmd/deploy.sh` — exits 1 when any item is skipped; usage
carries the real hooks.json jq-merge how-to (mktemp-staged) and the exit
contract; hooks.json notice is exit-neutral.
MODIFIED: `lib/cmd/init.sh` — companion files de-rfxn'd (contact via
repo-local git identity with private-vulnerability-reporting fallback,
license detected from LICENSE head, org/repo-URL from the actual remote).
MODIFIED: docs made truthful — README (`--tools`, `/r-init` fences, scripts
table), quickstart (bash 3.2+ floor, absolute Pages links), CLAUDE.md floor
wording, doc-stats counts (16 scripts / 13 profiles).
REMOVED: `profiles/core/reference/cross-project.md`,
`canonical/scripts/comment-snapshot.sh` (both relocated into the org
overlay; no rfxn content remains in what `rdf init`/adapters deliver).

## 3.6.4 — 2026-08-18

ADDED: `canonical/scripts/state-bootstrap.sh` — SessionStart hook delivering
`~/.rdf/state` helpers on plugin installs (version-stamped, no-op on checkout
installs); the full pipeline now runs on the plugin tier.
ADDED: `rdf_strip_frontmatter` + `rdf_require_agent_meta` in `lib/rdf_common.sh`
— single frontmatter-strip implementation (sync + doctor) and a generate
preflight that fails when an agent is missing from `agent-meta.json`.
ADDED: doctor scopes `catalogs` and `state-helpers` (11 → 13 checks).
ADDED: `tests/strip.bats`, `tests/sync.bats`, `tests/bootstrap.bats` (BATS
222 → 246).
MODIFIED: state-helper delivery inverted — `rdf deploy claude-code` owns
`~/.rdf/state` as glob-driven per-file symlinks (auto-migrating byte-identical
legacy copies; stamps retired on ownership); `rdf generate` no longer writes
under `$HOME`; `rdf-overhead.sh` resolves checkout-shaped plugin roots via the
`.rdf-source` stamp.
MODIFIED: `rdf sync` agents path guarded (head-1 + empty-body) — the
frontmatter-less truncation data-loss path is closed.
MODIFIED: plugin-tier wording in 9 lifecycle commands and
README/quickstart/index — hooks auto-register via `plugin.json`; degraded mode
applies only before the first post-install session restart.
REMOVED: `_generate_deploy_state_helpers` (generate-side copy delivery) and
sync's count-based `_strip_frontmatter`.

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
