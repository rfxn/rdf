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

## 3.4.0 — baseline

**Lifecycle verbs (4):** `/r-spec` (design), `/r-plan` (decompose), `/r-build`
(dispatch + gates), `/r-ship` (release).

**Agents (6):** `dispatcher`, `planner`, `engineer`, `qa`, `reviewer`, `uat`.

**Adapters (5):** `claude-code`, `claude-plugin`, `codex`, `gemini-cli`,
`agents-md` — each generated from tool-agnostic `canonical/` content.

**State:** `state/rdf-bus.sh` is the session bus (active-plan pointer + tier
pointer); governance is loaded from `.rdf/governance/`.
