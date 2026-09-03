# RDF Roadmap

Where RDF is headed. Horizons are ordered by dependency, not by date —
each one has to hold before the next matters. Suggestions and PRs
against any of this are welcome (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Now — polish the public surface

- [x] LICENSE file, dynamic badges, accurate command inventory
- [x] Community health files: security policy, code of conduct, issue templates
- [x] User-agnostic paths throughout docs and CLI output (`~/.claude`, not
      hardcoded home directories)
- [x] Custom social-preview image and project homepage

## Next — the five-minute on-ramp

Make "drop it on any repo" true for someone with zero rfxn context:

- [x] Quickstart: clone → generate → deploy → `/r-init` on your own repo,
      with a worked example on a generic project
- [x] Recorded demo (real session, not mockups) at the top of the README
- [ ] First-run hardening: everything works from a fresh clone under any
      user account — no rfxn workspace assumptions (folded into the
      2026-08 top-5, item 2 below)

## Soon — first-class Claude Code plugin

RDF ships a `plugin.json` today; the goal is full plugin-marketplace
citizenship:

- [x] Installable via `/plugin marketplace add rfxn/rdf` +
      `/plugin install rdf@rdf` (repo as its own marketplace)
- [x] Design pass on command namespacing (`/r-start` vs `/rdf:r-start`)
      and dual install modes (symlink deploy vs plugin install)
- [x] `claude plugin validate --strict` in CI
- [x] Plugin-tier state parity: SessionStart bootstrap delivers the
      `~/.rdf/state` helpers, so the full pipeline runs on plugin installs
      (3.6.4)
- [x] Submission to the community plugin marketplace

## Now — the 2026-08 top-5

From a full product-quality pass (architecture, docs, assumptions, measured
usage, industry landscape — every item below verified against source before
it earned a slot):

1. [x] **Core-seam reliability** — shipped in 3.6.4 (see below)
2. [x] **Make "drop it on any repo" true** — shipped in 3.6.5: rfxn content
       extracted to the opt-in `rfxn-workspace` profile (hooks, `/r-init`
       output, commands, reference docs all generic + grep-guarded),
       `reference/` ships in CC-family outputs and `~/.claude/reference`,
       deploy exits 1 on skips with a real hooks-merge how-to, node profile
       detection, doc truth sweep (bash 3.2+ floor, links, `--tools`)
3. [ ] **Right-size the command surface to measured usage** — fold session
       bookkeeping into hooks, retire unwired commands, fix the
       security-floor substring matching, deduplicate the phase/plan/ship
       triple review; target ~20 commands
4. [x] **Consolidate adapters on evidence** — built (this release, pending
       tag): shared adapter library, skills-native cc/plugin output, codex
       via composite, project-scoped AGENTS.md, `--tools` real, dead
       catalogs removed
5. [~] **Platform-alignment gate + eval hardening** — first case ruled
       (Agent Teams → keep dispatcher; `docs/platform-triage.md` ledger +
       `/r-ship` 1d gate); contract hardening landed (negation guards +
       structural assertions, D3). Trigger/activation evals and OWASP
       posture remain — see *Next minor* below

## Next minor — platform alignment follow-ons

From the platform-alignment spike's Go/No-Go summary
([design](docs/specs/2026-09-02-platform-alignment-spike-design.md) §8), not
carried in this release:

- [ ] **D1 — Workflow-backed `/r-build` behind a flag.** Gated spike: fix the
      `tiers.md` bugfix/`min()` contradiction, define a plan `Status:` form,
      add a `deploy.sh` workflows dir, a `/r-build --workflow` arg (BATS
      covered), an A/B run on one real plan, and an indicator-list contract.
      The prototype (`docs/specs/support/rdf-build-workflow.prototype.js`)
      stays unwired until this lands.
- [ ] **D2 — local trigger-eval harness.** `state/rdf-trigger-eval.sh`
      reading `evals/*/case.yaml` (37 positive + ~10 negative cases), a
      `/r-ship` 1e line, and an optional CI job; switch to `claude plugin
      eval` once it exits early access (see `docs/platform-triage.md`).

## Later — ecosystem

- [ ] Deep-dive writeups from the spec archive (`docs/specs/` — design
      documents from real releases)
- [ ] Community profile packs (language/domain governance beyond the
      built-in profiles — see `profiles/registry.json`)
- [ ] Additional adapter targets as new AI runtimes stabilize

## Delivered — 3.4 "Memory & Context"

- [x] Context-scoped governance loading (3.2 T3): scoped `.claude/rules/`,
      core left unscoped so it survives compaction
- [x] Zero-effort auto-memory: SessionEnd journal capture + a lessons ID-index
      injected read-only at session start
- [x] Published per-session context cost with the `rdf-overhead.sh` harness
      (default ~0.1K / `--rules` ~2.1K / `rdf-lite` ~0.7K always-loaded tokens)
- [x] `rdf-lite` minimal deploy variant

## Shipped in 3.6.4 — core-seam reliability

Top-5 item 1, executed spec → plan → build → sentinel in one pass.
[design](docs/specs/2026-08-18-core-seam-reliability-design.md) ·
[plan](docs/plans/2026-08-18-core-seam-reliability-plan.md).

- [x] `rdf sync` truncation data-loss path closed; one shared
      frontmatter-strip for sync + doctor
- [x] Generation hard-fails when an agent is missing from `agent-meta.json`
- [x] State-helper delivery inverted: deploy-owned per-file symlinks
      (drift-impossible on checkouts), `rdf generate` never writes to `$HOME`
- [x] Plugin SessionStart bootstrap — full pipeline on plugin installs
- [x] Doctor `catalogs` + `state-helpers` scopes (11 → 13 checks); BATS
      222 → 246

## Delivered — 3.5.0 "Scale"

- [x] Scale-adaptive ceremony: task-class tiers (full / quick-plan / bugfix)
      with a security floor — tiers only remove ceremony, never the security
      pass
- [x] `/r-spec` Phase 1.5 Clarify de-ambiguation micro-gate
- [x] `/r-build` consistency micro-gate (`rdf-consistency.sh`,
      spec↔plan↔tasks)
- [x] Living current-state spec (`docs/specs/CURRENT.md`) folded at `/r-ship`

## Shipped in 3.6.0 — "Reach" (Wave 2)

Built on a primary-source Skills-schema probe + fresh re-plan of Phases 8-11
(as gated). Antigravity CLI locked in as a first-class citizen alongside
Claude Code and Codex; gemini-cli demoted to a frozen legacy tier for
enterprise Gemini CLI users. Spec + plan:
[design](docs/specs/2026-07-15-scale-reach-design.md) ·
[plan](docs/plans/2026-07-15-scale-reach-plan.md).

- [x] agent-skills adapter — shared `.agents/skills/<cmd>/SKILL.md` surface
      (Codex + Antigravity), `rdf generate agent-skills` + `antigravity`
      composite, workspace deploy symlink
- [x] Claude Code intent-trigger `description:` frontmatter on generated
      commands (canonical stays frontmatter-free — contract-tested)
- [x] gemini-cli TOML-escaping fix (`'''` literal strings; 15/37 command
      files previously failed strict parsing) + `{{args}}` lossy NOTE
- [x] Deploy/sync BATS coverage (audit M6) + doctor/sync frontmatter-strip
      guards + [multi-tool parity matrix](docs/multi-tool-parity.md)

## Deferred (tracked, not scheduled)

- Wave 3 coordination re-triage → a later minor (message bus recommended against —
  obsoleted by native background agents; only phantom collect-spool cleanup
  and an optional read-only peer view survive)
- Debt cleanup follow-ups beyond the executed 3.2 T5 cuts (shipped in 3.3.1)

---

*This file tracks direction, not promises. The changelog records what
actually shipped.*
