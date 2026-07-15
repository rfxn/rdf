# RDF Roadmap

Where RDF is headed. Horizons are ordered by dependency, not by date —
each one has to hold before the next matters. Suggestions and PRs
against any of this are welcome (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Now — polish the public surface

- [x] LICENSE file, dynamic badges, accurate command inventory
- [x] Community health files: security policy, code of conduct, issue templates
- [x] User-agnostic paths throughout docs and CLI output (`~/.claude`, not
      hardcoded home directories)
- [ ] Custom social-preview image and project homepage

## Next — the five-minute on-ramp

Make "drop it on any repo" true for someone with zero rfxn context:

- [ ] Quickstart: clone → generate → deploy → `/r-init` on your own repo,
      with a worked example on a generic project
- [ ] Recorded demo (real session, not mockups) at the top of the README
- [ ] First-run hardening: everything works from a fresh clone under any
      user account — no rfxn workspace assumptions

## Soon — first-class Claude Code plugin

RDF ships a `plugin.json` today; the goal is full plugin-marketplace
citizenship:

- [x] Installable via `/plugin marketplace add rfxn/rdf` +
      `/plugin install rdf@rdf` (repo as its own marketplace)
- [x] Design pass on command namespacing (`/r-start` vs `/rdf:r-start`)
      and dual install modes (symlink deploy vs plugin install)
- [x] `claude plugin validate --strict` in CI
- [ ] Submission to the community plugin marketplace

## Later — ecosystem

- [ ] Deep-dive writeups from the spec archive (`docs/specs/` — design
      documents from real releases)
- [ ] Community profile packs (language/domain governance beyond the
      built-in 11)
- [ ] Additional adapter targets as new AI runtimes stabilize

## Delivered — 3.4 "Memory & Context"

- [x] Context-scoped governance loading (3.2 T3): scoped `.claude/rules/`,
      core left unscoped so it survives compaction
- [x] Zero-effort auto-memory: SessionEnd journal capture + a lessons ID-index
      injected read-only at session start
- [x] Published per-session context cost with the `rdf-overhead.sh` harness
      (default ~0.1K / `--rules` ~2.1K / `rdf-lite` ~0.7K always-loaded tokens)
- [x] `rdf-lite` minimal deploy variant

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
