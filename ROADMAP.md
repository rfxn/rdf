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

- [ ] Deep-dive writeups from the spec archive (`docs/specs/` — 24 design
      documents from real releases)
- [ ] Community profile packs (language/domain governance beyond the
      built-in 11)
- [ ] Additional adapter targets as new AI runtimes stabilize

## Deferred (tracked, not scheduled)

- Context-scoped governance loading (3.2 T3)
- Debt cleanup: Agent-Teams triad, dead-code sweep (3.2 T5)

---

*This file tracks direction, not promises. The changelog records what
actually shipped.*
