# RDF 3.6 — Harness Primitives Research

**Date:** 2026-04-21
**Status:** Research (no implementation)
**Scope:** Identify low-friction, high-value additions for RDF 3.6 by surveying primitives from Claude Code, Codex/AGENTS.md, Cursor, Aider, Continue.dev, Cline, Roo Code, Anthropic's Superpowers, agent-engineering research, and awesome-claude-code.

Baseline: RDF v3.0.5, HEAD `0224097`. Already ships 6 agents, 33 commands, 4 shared reference docs, and operating-primitives codified in `CLAUDE.md.ref` (Trust but Verify / Scope Discipline / Adversarial Review / Context Preservation / Comment Discipline / Safe Execution).

---

## 1. Top 10 Ranked Proposals

Ranked by value / friction, with outcome-regression risk as tiebreaker (lower risk wins).

### 1. Deterministic SessionStart context-inject hook
- **Source:** Claude Code hooks (`SessionStart` with `hookSpecificOutput.additionalContext`, 10k char cap); mirrored by Codex `AGENTS.md` auto-load.
- **RDF integration shape:** New optional adapter artifact — `adapters/claude-code/hooks/rdf-session-start.sh` + equivalent `AGENTS.md` preamble. Shell-native. Emits a stable deterministic payload: current branch, last 3 commits, `.rdf/work-output/` last-phase status, open PLAN phase IDs. Wired by `rdf generate claude-code`.
- **Value:** Eliminates the "what was I doing" replay every session; turns `/r-start` into a no-op for the 80% case. The payload is exactly what `/r-start` already produces — promoting it to a hook means it primes context *before* the first user prompt, not after.
- **Friction:** ~40 lines of bash + settings.json entry. Codex parity: the same script's output is the seed section of a generated `AGENTS.md` block.
- **Outcome risk:** Low. Stable output preserves prompt-cache prefix. Must be idempotent to avoid the "duplicate injection" bug documented in claude-code#14281.

### 2. `/r-verify-claim` — evidence-demand command
- **Source:** Superpowers `verification-before-completion`; Chroma's context-rot research (coding agents accumulate 80k-150k tokens of unverified assumption).
- **RDF integration shape:** New utility command that takes a claim ("Phase 3 landed", "the lock file is fsync'd", "old pattern is gone") and produces a triage report: (a) grep/stat/log commands to run, (b) what each result means, (c) a structured PASS/FAIL verdict. No agent dispatch; it's a skill the model invokes on itself.
- **Value:** Operationalizes "Trust but Verify" beyond aspiration. Current primitive says "cite evidence"; this command tells the model *how* to produce the citation for a given claim class.
- **Friction:** Single markdown file, ~60 lines. Reuses existing grep/stat patterns from `CLAUDE.md` verification block.
- **Outcome risk:** Low. Additive. Replaces no existing workflow.

### 3. `.rdf/context-budget.md` — per-agent token-budget reference
- **Source:** Chroma context-rot research (15-30% retrieval drop at 128k); Anthropic's subagent isolation doctrine; Cline `.clineignore` pattern.
- **RDF integration shape:** New reference doc under `canonical/reference/`. Declares per-agent context budgets (engineer: 30k; reviewer: 60k; dispatcher: 40k), and a reading-discipline checklist: "read governance/index before governance/shell"; "grep before read"; "never re-read unchanged files". Each agent persona gets a one-line reference link.
- **Value:** Context rot is invisible — it degrades silently before it overflows. Codifying budgets gives the dispatcher a quantitative gate for "should I spawn a subagent vs. continue in main?".
- **Friction:** ~40 lines of markdown + six 1-line patches to agent personas. Zero tool changes.
- **Outcome risk:** Low. Prescriptive, not enforced.

### 4. `/r-brainstorm` — Socratic pre-plan skill
- **Source:** Superpowers `brainstorming` skill; Cline Plan-mode.
- **RDF integration shape:** New command that runs *before* `/r-spec`. Given a rough feature description, the model asks 3-7 clarifying questions in a single batch (not sequential), presents a chunked design outline, and produces the design-brief that `/r-spec` currently expects the user to hand over.
- **Value:** Today `/r-spec` assumes the user arrives with a shaped brief. Most sessions don't. Brainstorm mode closes that gap without forcing users into full spec-mode early. Also surfaces external-probe work before the plan crystallizes (matches Adversarial Review: "probes take minutes, rewrites take days").
- **Friction:** Single markdown command. Feeds its output to `/r-spec` unchanged.
- **Outcome risk:** Medium. Risk is the model over-asks and frustrates users. Kill criterion built in: hard-cap at 7 questions.

### 5. Evidence schema for engineer result files
- **Source:** Anthropic's Building Effective Agents orchestrator-worker pattern (distilled findings); existing RDF `phase-N-result.md` schema.
- **RDF integration shape:** Extend the existing engineer result schema with a mandatory `EVIDENCE` block: each line cites file+line, commit SHA, or grep-output snippet. Dispatcher rejects results with empty evidence as `NEEDS_CONTEXT`. Patch to `engineer.md` + `dispatcher.md` + `framework.md`.
- **Value:** Makes Trust-but-Verify mechanically enforced at the agent boundary rather than constitutionally asserted. The dispatcher already reads these files; adding a shape check is ~5 lines.
- **Friction:** Schema addition + 3-file patch. No new infrastructure.
- **Outcome risk:** Low. Strengthens an existing contract.

### 6. `.rdf/constraints.md` ignore-list (RDF's `.clineignore` analog)
- **Source:** Cline `.clineignore` (single biggest context-reduction tool per their docs — 200k → 50k).
- **RDF integration shape:** Extend existing `.rdf/governance/constraints.md` with an `EXCLUDED_PATHS` section. Dispatcher and agents read it and skip matching globs when running `grep -r` / scans. Ships with sensible defaults (`node_modules/`, `vendor/`, `.git/`, generated artifacts).
- **Value:** Repeat complaint in long sessions: grep returns thousands of hits in generated dirs. A governance-declared ignore set fixes it once per project.
- **Friction:** ~15 lines added to existing file. No new file.
- **Outcome risk:** Low. Opt-in; defaults are conservative.

### 7. `/r-probe` — externals-first pre-plan check
- **Source:** Adversarial Review primitive (already in CLAUDE.md.ref: "probe externals before plan crystallizes"); Superpowers pre-impl challenge.
- **RDF integration shape:** New lifecycle command that takes a spec and outputs a structured probe list — binary paths to verify, protocols to sanity-check, auth shapes, install-environment footprints. Each probe is a one-liner the user runs; results feed back into the spec as facts.
- **Value:** The primitive is currently advisory ("probe before plan"). Giving it a command makes it a step, not a reminder. The `.rdf/work-output/probe-N.md` artifact becomes a reviewable plan input.
- **Friction:** Single command, ~50 lines. Slots between `/r-spec` and `/r-plan`.
- **Outcome risk:** Low. Skippable for simple changes.

### 8. `/r-compact` — conversation-compaction skill
- **Source:** Claude Code `SessionStart` compact matcher; context-rot research (coding agents hit 80-150k by minute 35).
- **RDF integration shape:** New utility command. The model writes a structured summary to `.rdf/work-output/compact-<ts>.md` (commits landed, files touched, open questions, active governance pointers), then the user can `/clear` with confidence. On resume, `/r-start` reads the most recent compact file.
- **Value:** Explicit compaction hand-off. Currently users hit 200k and either (a) live with degraded output, (b) lose context on `/clear`. A manual compact command is tool-agnostic and works identically on Codex/Gemini.
- **Friction:** Single command. Reuses `/r-save` session-log writer pattern.
- **Outcome risk:** Medium. Compaction quality depends on model discipline — same risk as `/r-save` today.

### 9. `/r-review-answer` — reviewer-feedback routing
- **Source:** Superpowers `receiving-code-review`; Adversarial Review primitive ("challenges must be answered with a fix or documented rebuttal").
- **RDF integration shape:** New command. Takes a `sentinel-N.md` file as input, enumerates each finding, and requires a structured response per finding: `FIX <sha>` or `REBUT <reason>` or `DEFER <issue-link>`. Writes `sentinel-N-answer.md`. Dispatcher blocks merge if any finding is unanswered.
- **Value:** Closes the "silence is unacceptable" loop. Today the sentinel primitive asserts it; this command operationalizes it. Produces an audit trail for every finding.
- **Friction:** Single command + 1 dispatcher patch (block on unanswered findings).
- **Outcome risk:** Low. Additive; exits cleanly when no sentinel exists.

### 10. Regression-case schema in `/r-plan` output
- **Source:** Adversarial Review primitive ("every behavior change ships a regression case"); AG2 generator-verifier pattern.
- **RDF integration shape:** Extend `/r-plan` template so each phase with behavior change includes an explicit `REGRESSION_CASE:` field pointing to a named test. `/r-build` refuses phases where the field is missing for non-docs scope. Three-file patch (planner, dispatcher, framework).
- **Value:** Same delta as proposal #5 — promote a constitutional rule into a mechanical contract. Regression gaps are the most common post-merge bug source.
- **Friction:** Template change + two agent patches.
- **Outcome risk:** Low. Scope-gated (docs phases exempt).

---

## 2. Secondary Proposals (11-22)

Shorter entries. Backup list.

### 11. Tiered model strategy doc
- **Source:** Claude Code Opus-orchestrator/Sonnet-worker pattern.
- **Shape:** New reference section recommending Opus for dispatcher/planner, Sonnet for engineer/qa. Tool-agnostic (Codex has gpt-5/5-mini analog).
- **Value:** Real cost savings.
- **Friction:** ~20 lines of reference.

### 12. `/r-batch-parallel` thinking doc
- **Source:** CLAUDE.md.ref Context Preservation ("batch independent tool calls in parallel").
- **Shape:** Short reference file with 5-6 concrete examples (grep+read+glob batching).
- **Value:** The primitive is asserted but not exemplified.
- **Friction:** ~30 lines.

### 13. `AGENTS.md` as a canonical deployment target
- **Source:** agents.md spec adoption by Codex/Cursor/Windsurf/Roo Code.
- **Shape:** Adapter `adapters/agents-md/` alongside claude-code/codex/gemini. Symlink-friendly so a single file serves all AGENTS.md-compliant tools.
- **Value:** Free tool compatibility.
- **Friction:** One adapter directory.

### 14. `/r-worktree` dispatcher sub-skill
- **Source:** Superpowers `using-git-worktrees`.
- **Shape:** Extract worktree lifecycle (create, commit-verify, clean) from `r-build.md` into a standalone command callable by dispatcher.
- **Value:** Reuse across build and manual parallel work.
- **Friction:** Refactor-only; no new logic.

### 15. Toggle rules (Cline-style popover analog)
- **Source:** Cline v3.13 rules popover.
- **Shape:** `/r-mode --toggle <rule-id>` temporarily disables a governance section for one session (stored in `.rdf/work-output/session-overrides.json`).
- **Value:** Escape hatch for emergency work.
- **Friction:** New flag + persistence file.
- **Risk:** Non-trivial — governance bypass has blast radius.

### 16. Skill-description budget audit
- **Source:** Claude Code skill descriptions capped at 1536 chars; `SLASH_COMMAND_TOOL_CHAR_BUDGET` env.
- **Shape:** Extend `/r-context-audit` to flag commands whose front-matter description exceeds the 1% context budget.
- **Value:** Prevents silent truncation.
- **Friction:** Small patch to existing command.

### 17. `just-in-time` reading doctrine in reviewer persona
- **Source:** Chroma context-rot JIT-retrieval guidance.
- **Shape:** One-paragraph patch to `reviewer.md` saying "grep the finding scope first; only read files you need to cite."
- **Value:** Shrinks reviewer context substantially.
- **Friction:** One-paragraph patch.

### 18. `/r-kill-switch` — 3-failed-attempts tripwire
- **Source:** CLAUDE.md.ref Scope Discipline ("after three failed attempts, stop and reconsider").
- **Shape:** Reviewer-like agent run on a phase-in-progress; reads attempt log and emits a STOP verdict if 3+ failed commits/tests.
- **Value:** Catches the "layer workarounds" anti-pattern automatically.
- **Friction:** Requires attempt-tracking in work-output.
- **Risk:** False positives during legitimate TDD red iterations.

### 19. Pre-commit artifact validator
- **Source:** Claude Code `PreToolUse` hook pattern (deterministic, 100% vs advisory).
- **Shape:** Deploy an optional pre-commit hook that fails when a commit touches excluded working files (CLAUDE.md, PLAN.md, MEMORY.md).
- **Value:** Mechanical enforcement of the existing "never commit working files" rule.
- **Friction:** One hook script, opt-in.

### 20. Structured debug-loop skill
- **Source:** Superpowers `systematic-debugging` 4-phase.
- **Shape:** New `/r-debug` command structuring an investigation into (1) reproduce, (2) hypothesize, (3) instrument, (4) root-cause + fix.
- **Value:** Prevents the "try random fixes" anti-pattern.
- **Friction:** Single markdown command.

### 21. "Conversation chunking" directive in planner persona
- **Source:** Superpowers brainstorming ("shows it to you in chunks short enough to actually read and digest").
- **Shape:** One-sentence planner patch: "present plan in 200-line chunks; request user ack between chunks."
- **Value:** Surfaces plan errors earlier.
- **Friction:** One-sentence patch.

### 22. Dispatcher "parallel boundary validator" extraction
- **Source:** Agent-teams file-locking primitive.
- **Shape:** Extract current file-ownership check from dispatcher.md into a callable scripted step in `canonical/scripts/`.
- **Value:** Reuse outside `/r-build`.
- **Friction:** Refactor.

---

## 3. Explicit Rejections

- **Claude Code plugins marketplace** — hard-binds to Claude Code; RDF is tool-agnostic. Rejected.
- **Cursor `.mdc` frontmatter / globs** — Cursor-specific `alwaysApply`/`agentRequested` metadata has no Codex analog; wrong abstraction for a governance layer. The activation question belongs in `rdf generate`, not in canonical content. Rejected.
- **Agent Teams (peer coordination / teammate messaging)** — requires Claude Code 2.1.32+ and proprietary experimental env vars. Over-engineers what RDF already handles with dispatcher + worktrees. Violates tool-agnostic stance. Rejected.
- **LangGraph-style state-machine graphs** — framework dependency; Python runtime; direct contradiction of "start with LLM APIs directly" advice Anthropic themselves give. Rejected.
- **Memory Bank 6-file system** (Cline) — duplicates RDF's existing MEMORY.md / governance / PLAN.md triad. Adding 6 more mandatory files violates "LESS ceremony". Reject. (Selective borrowing in proposal #8.)
- **AutoGen conversational loops** — 20+ LLM calls per task; cost explosion; maintenance-mode status. Rejected.
- **Marketplace distribution** (superpowers / awesome-claude-code registry) — nothing to distribute until 3.6 stabilizes; deferring is correct. Rejected for 3.6.
- **Output Styles** (Claude Code-specific) — formatting concerns don't belong in canonical content; adapters can handle per-tool tone. Rejected.
- **Ralph Wiggum autonomous loop** — unbounded iteration is the opposite of RDF's dispatcher pattern (bounded phases with explicit gates). Rejected on philosophical grounds.
- **TDD Guard real-time file hook** — TDD already enforced by engineer persona's evidence block; adding a realtime monitor is ceremony. Rejected.
- **Parry prompt-injection detector** — security tool, not a governance primitive. Out of scope. Rejected.
- **Mode-specific rule directories** (`.roo/rules-{mode}/`) — RDF's modes are already lightweight; per-mode rule sprawl is exactly the ceremony the framework rejects. Rejected.
- **Hub-distributed rules** (Continue.dev) — vendor lock-in; RDF's distribution is `rdf generate`. Rejected.

---

## 4. Adversarial Review of the Top 10

### 1. SessionStart hook
- **Strongest objection:** Hook output becomes part of the prompt-cache prefix. Non-deterministic content (timestamps, seconds-since-epoch) invalidates the cache, 5x-ing cost. Also the known duplicate-injection bug (claude-code#14281).
- **Integration pitfall:** User disables hooks globally for one project and now every session starts cold with no warning.
- **Kill criterion:** If `/r-start` cache hit rate drops below 85% over 20 sessions, revert.

### 2. `/r-verify-claim`
- **Strongest objection:** Model invokes it on trivial claims, producing ceremony; or skips it on genuinely fraudulent claims because it's opt-in.
- **Integration pitfall:** The verification commands it generates may themselves hallucinate (wrong grep pattern, wrong file path).
- **Kill criterion:** If >30% of uses produce verification commands that error out, the skill is generating plausible but wrong commands — drop.

### 3. Context-budget reference
- **Strongest objection:** Prescriptive budgets without measurement are theater. Models don't know their own token count reliably.
- **Integration pitfall:** Users cite the budget as proof of discipline without actually measuring.
- **Kill criterion:** If no agent ever cites the doc in a result file within 30 days of ship, delete it.

### 4. `/r-brainstorm`
- **Strongest objection:** Senior users (RDF's target) don't need Socratic questioning; it's condescending.
- **Integration pitfall:** Model asks 7 questions about things obvious from CLAUDE.md.
- **Kill criterion:** If the user flag `--skip-questions` is used in >50% of invocations, the command is wrong-shaped — redesign as a "sanity check" not an "interrogation".

### 5. Evidence schema enforcement
- **Strongest objection:** Forces the engineer to produce evidence even for trivial changes (comment tweak, docs); ceremony tax on the 60% case.
- **Integration pitfall:** Engineer satisfies schema with fake evidence (grep output that doesn't prove the claim).
- **Kill criterion:** If `qa` rejection rate for "evidence-insufficient" doesn't drop after 2 weeks, the schema is being gamed.

### 6. `.rdf/constraints.md` ignore-list
- **Strongest objection:** Real bug lives in an "ignored" directory; grep misses it; wasted investigation.
- **Integration pitfall:** Excluded paths drift over time; new `build/` dir added, never added to the list.
- **Kill criterion:** If a post-mortem ever cites "bug was in an ignored path", drop or narrow defaults.

### 7. `/r-probe`
- **Strongest objection:** Adds a step for the 80% case where externals are already well-known (just a bash change).
- **Integration pitfall:** Model generates plausible-looking probes that don't actually probe (e.g. `command -v foo` when the real uncertainty is `foo --version` output shape).
- **Kill criterion:** If `/r-probe` output is used by `/r-spec` in <30% of invocations, it's ritual.

### 8. `/r-compact`
- **Strongest objection:** Users will use `/compact` (Claude Code built-in) instead because it's muscle memory; `/r-compact` becomes orphaned.
- **Integration pitfall:** Compact summary drops the one detail that mattered.
- **Kill criterion:** If session-log indicates `/compact` used ≥5x more than `/r-compact`, replace with a CLAUDE.md directive ("before /compact, run /r-save").

### 9. `/r-review-answer`
- **Strongest objection:** Forces a response to every finding including low-value ones; users game with boilerplate REBUT.
- **Integration pitfall:** The "block merge on unanswered" gate annoys users who never used the reviewer in the first place.
- **Kill criterion:** If >40% of REBUT entries are boilerplate ("not applicable"), the finding severity grading upstream is wrong — fix there.

### 10. Regression-case schema
- **Strongest objection:** Every behavior change isn't independently testable (performance tweaks, logging additions) — forced regression case becomes `# TODO: add test`.
- **Integration pitfall:** Planner writes overly-broad regression cases ("existing tests still pass") to satisfy the field.
- **Kill criterion:** If QA verdicts with regression-PASS but real-world regressions still land, the schema is satisfied but toothless — make `qa` require the regression case references a *named* test.

---

## 5. Recommended 3.6 Scope

**Ship** (6 items, ranked): #1 SessionStart hook, #2 `/r-verify-claim`, #5 evidence schema, #6 ignore-list, #10 regression-case schema, #13 AGENTS.md adapter (from secondary).

**Rationale for the cut:**

- #1 and #13 together are the biggest tool-agnostic wins and reinforce each other — the hook payload and the AGENTS.md preamble share one generator. Ships one primitive with two adapters.
- #2, #5, #10 are a coordinated "evidence becomes mechanical" tranche: they promote three existing constitutional rules (cite evidence, every behavior change ships a regression, result files are schema-checked) into enforceable contracts with minimal new surface area. This is where RDF's leverage is highest — the principles are already written; only the enforcement wiring is new.
- #6 is a self-contained quality-of-life win with zero outcome risk.

**Defer to 3.7:**

- #3 context-budget, #4 brainstorm, #7 probe, #8 compact, #9 review-answer. Each has medium outcome risk and needs real-world calibration data (cache-hit rates, question-counts, reviewer use-patterns) that only shipping #1-#2 first will generate. Ship lightweight primitives first, then measure, then add.

**Drop permanently:** Everything in §3.

**Non-goals for 3.6:** No new agents. No changes to the dispatcher's scope-classification logic. No mandatory workflow additions — every shipped item is either a new opt-in command, a schema extension to an existing artifact, or a single-file reference.

**Success criteria for the 3.6 ship:**

- SessionStart hook: measurable cache-hit improvement and no duplicate-injection regressions.
- Evidence schema + regression schema: qa verdict "evidence-insufficient" or "regression-missing" fires at least once in real work within 2 weeks — proves the check bites.
- `/r-verify-claim`: appears in at least one session-log `insights.jsonl` as "avoided a false done".
- AGENTS.md adapter: `rdf doctor` shows zero drift between Claude Code and Codex deployments.

If any of these doesn't fire, the corresponding item is ceremony — cut it in 3.6.1.

---

## Sources

- Claude Code docs: https://code.claude.com/docs/en/skills, https://code.claude.com/docs/en/hooks, https://code.claude.com/docs/en/agent-teams, https://code.claude.com/docs/en/output-styles
- Superpowers: https://github.com/obra/superpowers, https://claude.com/plugins/superpowers
- Anthropic cookbook / patterns: https://github.com/anthropics/anthropic-cookbook/tree/main/patterns/agents
- Building Effective Agents: https://www.anthropic.com/research/building-effective-agents
- Multi-agent coordination patterns: https://claude.com/blog/multi-agent-coordination-patterns
- AGENTS.md spec: https://agents.md/, https://github.com/agentsmd/agents.md, https://developers.openai.com/codex/guides/agents-md
- Cursor rules: https://cursor.com/docs/rules
- Aider conventions: https://aider.chat/docs/usage/conventions.html
- Continue.dev rules: https://docs.continue.dev/customize/rules
- Cline Memory Bank: https://docs.cline.bot/features/memory-bank
- Roo Code custom instructions: https://docs.roocode.com/features/custom-instructions
- Context-rot research: https://www.trychroma.com/research/context-rot
- Claude Code prompt caching: https://www.claudecodecamp.com/p/how-prompt-caching-actually-works-in-claude-code
- awesome-claude-code: https://github.com/hesreallyhim/awesome-claude-code
