# Platform-Alignment Spike — Design Spec

**Date:** 2026-09-02 · **Tier:** spike (research — output is decisions, not a build plan) · **Status:** draft
**Pipeline:** spike → D1–D5 verdicts → per-item follow-on (`/r-spec` or `/r-plan`) · ROADMAP item 5 (`ROADMAP.md:62-66`)

## 1. Problem Statement

Claude Code moved under RDF 3.6.5 in four places that touch RDF's core seams:

1. **Workflows are GA** — deterministic JS orchestration (`agent()`, `parallel()`,
   `pipeline()`, `phase()`), plugin-distributable. RDF's phase loop, gate
   selection, retry bounds and finding-resolution live in 555 lines of prose
   (`canonical/agents/dispatcher.md`), driven turn-by-turn by a model. The prose
   has already failed once where a script could not: "M13 dispatch produced 5/5
   scope violations despite explicit prose instruction" (`dispatcher.md:183-185`).
2. **Skills supersede `commands/`** — `.claude/commands/*.md` still works but is
   the legacy form; RDF's CC adapter emits only that form
   (`adapters/claude-plugin/output/commands/`, `.claude-plugin/plugin.json:14`),
   so 0/37 generated commands carry `allowed-tools` and `/r-ship`, `/r-build`,
   `/r-save` lack `disable-model-invocation` (verified §2).
3. **`claude plugin eval` exists but is early-access-gated here** (§2). RDF's
   only behavioral harness is `tests/governance-contracts.bats` — grep-presence
   contracts that cannot detect meaning inversion (§5).
4. **Agent Teams remain experimental**; RDF has no ritual for deciding, per
   minor, whether a native capability replaces an RDF mechanism. The last such
   probe is dated 2026-03-16 (`docs/specs/agent-teams-research.md:3`).

Separately, OWASP published Agentic Skills Top 10 v1.0 (§7); RDF has never
mapped its posture to it.

## 2. Research Record (verbatim, this machine, 2026-09-02)

```
$ claude --version                      → 2.1.258 (Claude Code)
$ claude plugin eval --help             → available; "<eval dir>/**/case.yaml or prompt.md + graders/*.md";
                                          --runs (default case.runs ?? 3); --judge-model (default haiku);
                                          --threshold (default 1.0); --ablation with-without: "graders marked
                                          with-only, incl. `tool_used: Skill`, are a plugin-fired indicator";
                                          --max-cost-usd; --allow-tools; init --bare <name>
$ claude plugin eval . --case '__no_such_case__' --runs 1 --no-publish
  `plugin eval` is currently in early access          (exit 1)   ← GATED HERE
$ env | grep AGENT_TEAMS; grep AGENT_TEAMS ~/.claude/settings.json .claude/settings*.json
  (no output; exit 1 / 2)                                         ← Agent Teams not enabled
$ ls evals .claude/workflows              → neither exists
docs: workflows.md, skills.md, agent-teams.md, plugins-reference.md fetched (quotes inline below);
      plugin-evals.md → HTTP 404; code.claude.com/docs/llms.txt lists no "eval" or "skill-doctor" page
      → the eval suite format is NOT publicly documented; /skill-doctor is in-session only, unprobed
workflow-authoring skill loaded (requires CC ≥ 2.1.248): meta must be a pure literal; scripts have
      no filesystem/shell/env access; Date.now()/Math.random() throw; agent() may return null;
      agentType composes with schema; isolation:'worktree' per agent; ≤16 concurrent, ≤1000 agents/run
headless trigger probes (haiku, --max-turns 1, side-effect tools disallowed — see §4 for the command):
      "Start my session: reload project context and show me current health and open work."
        → tool_use Skill {"skill":"r-start"}   $0.0396  2.8 s  (cache-create 19,032 / read 7,567 tok)
      "I want to design a new feature ... turn that idea into an architecture spec."
        → tool_use Skill {"skill":"r-spec"}    $0.0334  6.0 s  (cache-create 15,038 / read 11,576 tok)
```

Contract-inversion demo (§5): `printf 'Tier Cap: the Security floor no longer applies; sentinel-full is
never required for scope:sensitive.\n' | grep -qE 'Security floor'` → PASS for all three regexes of
`tests/governance-contracts.bats:120-126`. Today's canonical text has no such inversion
(`grep -nE 'Security floor[^.]*\b(no longer|not|never|does not)\b[^.]*appl' canonical/agents/dispatcher.md
canonical/reference/tiers.md` → exit 1).

## 3. D1 — Workflow-backed `/r-build`

**Question.** Can a plugin-shipped workflow carry the dispatcher's phase loop deterministically?
**Answer.** The *loop* yes; the *gate arithmetic* mostly yes (pure string logic); the *I/O and
human touchpoints* no — the runtime forbids them: "No mid-run user input — Only agent permission
prompts can pause a run. For sign-off between stages, run each stage as its own workflow" and "No
direct filesystem or shell access from the workflow itself — Agents read, write, and run commands"
(workflows.md, Behavior and limits).

| Dispatcher responsibility | Today (cite) | Script-able? | A: prompt | B: hybrid | C: full workflow |
|---|---|---|---|---|---|
| Plan resolve + schema Rules 1-10 | `r-build.md:27-48` | no (file I/O) | skill | skill | agent (LLM re-does a deterministic job) |
| Consistency gate exit 0/1/2 | `r-build.md:56-67`, `state/rdf-consistency.sh:6-9` | no (shell) | skill | skill | agent |
| Tier read `rdf_active_tier` | `r-build.md:32-34`, `rdf-bus.sh:201` | no (file) | skill | skill → `args.tier` | agent |
| Scope classification | `dispatcher.md:216-261` | partly (extensions/count yes; "install scripts, CLI entry points, governance flags" need paths passed in) | dispatcher | script (`classifyScope`) + `args.governance` | script |
| Security floor `max(floor, min(scope, cap))` | `dispatcher.md:290-315`, `tiers.md:51-65` | yes | dispatcher | script (`securityFloor`, `deriveGates`) | script |
| Gate 1 evidence-line check | `dispatcher.md:191-200` | yes (regex) | dispatcher | script (`gate1`) | script |
| QA ∥ sentinel + dedupe ±5 lines | `dispatcher.md:377-395` | yes | dispatcher | script (`parallel`, `mergeFindings`) | script |
| Retry ≤3 / fix-refute ≤3 / EOP ≤2 | `dispatcher.md:400-401,498,413-414` | yes | dispatcher (prose counters) | script constants | script |
| Refutation 3-check | `dispatcher.md:491-497` | judgment | dispatcher | low-effort reviewer agent + schema | same |
| `blocking-concern` → ask user | `dispatcher.md:469-470` | **no** (no mid-run input) | dispatcher | script returns `NEEDS_USER`; skill asks | run aborts |
| Parallel batches, `Proceed? [Y/n]`, worktree `cd` | `r-build.md:136-145,255-267` | no (user input, `cd`) | skill | skill (out of workflow) | impossible |
| Worktree create/rebase/merge | `r-build.md:232-287` | agents only (`isolation:'worktree'` exists but merge needs shell) | skill | skill | agent |
| Commit (dispatcher, never engineer) | `dispatcher.md:544-550` | agent | dispatcher | low-effort commit agent | agent |
| Handoff/result files `phase-N-result-<SESSION>.md` | `dispatcher.md:22-26`, `rdf-bus.sh:46` | needs `RDF_SESSION_ID` | dispatcher | `args.sessionId` → QA writes | agent |
| Plan `Status:` write, task list | `r-build.md:147-165,383` | no | dispatcher / skill | skill (returned `skillMustDo`) | agent |

**Evidence for B specifically.** `docs/specs/support/rdf-build-workflow.prototype.js` (346 lines):
`node --check` clean; its pure functions parse the real 3.6.5 plan
(`docs/plans/2026-08-18-derfxn-drop-on-any-repo-plan.md`: 8 phases, 43 Files entries, Rule 3 rule on
all) and reproduce the gate matrix, including `bugfix` + `lib/auth-token.sh` → `gate2:true, gate3:full`
(floor wins) and `quick-plan` + `bin/rdf` → `gate3:lite, gate4:true`. The workflow is invoked only
from the skill (`whenToUse` says so; docs: bundled/plugin workflows "run only when you invoke it"),
which satisfies the opt-in rule. Resume is free within a session ("same script + same args → 100%
cache hit"). Plugin delivery is one directory: "Place the script in a `workflows/` directory at the
plugin root ... runs as `/acme-tools:release-audit`" (`plugin.json` `workflows` field, plugins-reference).

**Costs and risks of B.** (1) Workflows can be disabled per user or org (`disableWorkflows`,
`CLAUDE_CODE_DISABLE_WORKFLOWS=1`) and "are available on all paid plans" only → A must remain as
fallback, i.e. two execution paths through the seam class that broke 3.6.1–3.6.4. (2) Checkout deploys
need `~/.claude/workflows/` wiring in `lib/cmd/deploy.sh` (not a plugin concern). (3) Permission
prompts from engineer agents still pause runs in manual mode (unchanged from today). (4) The script
forces resolution of an ambiguity the prose tolerates: `tiers.md:41` (`min()` — never adds ceremony)
vs `tiers.md:47-48`/`dispatcher.md:307` ("bugfix — Gate 1 + a regression-only sentinel-lite") on a
`scope:focused` phase, whose scope→gate map has no Gate 3. The prototype follows `min()` (no sentinel);
the source must be fixed before any build ("Spec Contradictions Must Be Fixed at the Source").
(5) Plan `Status:` is unspecified: `plan-schema.md` Rule 2 lists no Status field, `r-build.md:82-87`
reads `Status: complete|in-progress`, and `state/rdf-state.sh:196-199` counts any `COMPLETE|DONE` line
— the current plan carries exactly one `- **Status**: pending`. A script needs one canonical form.

**Recommendation: B, as a gated spike, not a rewrite.** Ship `workflows/rdf-build-loop.js` behind
`/r-build --workflow` (default stays A) for one minor; run the same plan both ways and compare retry
discipline, findings resolved, tokens, and wall-clock; promote or delete on that evidence. C is
rejected: every deterministic pre-step becomes an LLM step and the user-confirmation points vanish.
Follow-on plan contents: fix (4) and (5) at the source; `deploy.sh` workflows dir; skill computes
`args` (tier, session, governance paths, base commit) — BATS-covered as a pure function of the plan;
A/B run on a real plan; contract test that the script's `SECURITY_INDICATORS` equals `reviewer.md:183-187`.
Effort: M (3–4 phases).

## 4. D2 — Trigger/activation evals

**Options.** (a) Wait for `claude plugin eval` access. (b) Local headless harness: `claude -p
--output-format stream-json`, assert the `Skill` tool fired with the expected `skill`. (c) Both —
author suites in the eval-CLI layout now (`evals/<case>/case.yaml`), run them through (b) until the
gate lifts, then switch the runner only.

**Evidence.** §2 probes: two of two expected skills fired, single turn, no side-effect tools. Headless
mode loads the same command catalog (cache-create 15–19K tokens = the 37-command + bundled-skill
listing). The `Workflow` keyword path is irrelevant here ("doesn't start a workflow ... a prompt
passed with `-p`"), so `-p` is safe for trigger checks. Cost model (measured haiku run + list prices
per the claude-api reference, cached 2026-06-24; 1-hour cache writes bill at 2× input):

| Model | per case-run (~17K ctx) | 37 positive + 10 negative cases × 3 runs |
|---|---|---|
| Haiku 4.5 (measured) | $0.033–0.040 | ≈ $5 |
| Sonnet 5 ($2/M in) | ≈ $0.07 | ≈ $10 |
| Opus 5 ($5/M in) | ≈ $0.17 | ≈ $24 |

Triggering is a property of the *session model*, so haiku is a cheap smoke signal, not the release
verdict; run the session-default model at `/r-ship` and haiku in CI.

**Go/No-Go: GO on (c), trigger = `/r-ship` preflight (session model) + optional CI job (haiku,
`continue-on-error`).** Non-goals: grading task *outcomes* (that is `tests/`), and any run without
`--max-turns 1` + `--disallowedTools` (a triggered `/r-save` would write state).

Example suite (`evals/trigger-r-start/case.yaml`, `evals/trigger-r-spec/case.yaml`). Field names follow
the September-2026 docs summary supplied to this spike and `claude plugin eval --help`; the docs page is
unreachable (§2), so the YAML shapes are **unverified** until access lifts:

```yaml
# evals/trigger-r-start/case.yaml
name: trigger-r-start
tags: [trigger, session]
plugins: [rdf]
runs: 3
max_turns: 1
timeout_seconds: 60
allowed_tools: [Skill, Read, Glob, Grep]
prompt: "Start my session: reload project context and show me current health and open work."
graders:
  - type: tool_used
    tool: Skill
    input_match: '"skill":\s*"r-start"'
  - type: baseline          # ablation: must NOT fire without the plugin
    expect: not_triggered
---
# evals/trigger-r-spec/case.yaml
name: trigger-r-spec
tags: [trigger, pipeline]
plugins: [rdf]
runs: 3
max_turns: 1
timeout_seconds: 90
allowed_tools: [Skill, Read, Glob, Grep]
prompt: "I want to design a new feature for this project: a configurable rate limiter for the CLI. Help me turn that idea into an architecture spec."
graders:
  - type: tool_used
    tool: Skill
    input_match: '"skill":\s*"r-spec"'
  - type: tool_used
    tool: Skill
    input_match: '"skill":\s*"r-plan"'
    expect: absent          # /r-plan must not pre-empt /r-spec on a fresh idea
```

Local harness core (the exact command that produced the §2 results; a future `state/rdf-trigger-eval.sh`
wraps it and reads the same `case.yaml` files):

```bash
printf '%s' "$prompt" | claude -p --output-format stream-json --verbose --max-turns 1 --model "$model" \
  --permission-mode default --disallowedTools Bash Write Edit MultiEdit NotebookEdit Agent Workflow \
  | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill'
# expect: r-start        (exit 1 from --max-turns is expected; grade on the jq line, not the exit code)
```

## 5. D3 — Contract harness hardening

**The gap.** `_contract` (`tests/governance-contracts.bats:21-25`) is `grep -qE` presence. Of the 21
tests on disk today (20 at 3.6.5 + one Makefile-wiring test added 2026-09-02), 17 are presence greps;
four are structural (`:59-64` header anchors, `:139-146` line-order, `:150-156` and `:160-167` loops).
The §2 demo shows the security-floor contract passing on its own negation.

**Options.** (1) *Negation guards*: keep the positive regex, add an absence regex for the negated form
on the same subject. Cheap; catches the obvious inversion; blind to paraphrase. (2) *Structural
assertions*: section order, formula literal in every restating file, cross-file equality of load-bearing
lists. Catches drift the model cannot paraphrase around; costs a few lines each. (3) *Retire in favor
of evals*: behavioral evals (§4) grade what the agent *does*. Correct in principle, but eval access is
gated, each run costs money, and the contracts run in <1 s on every CI push.

**Recommendation: (1)+(2) now, (3) never as a replacement.** Presence contracts stay as the cheap floor;
every contract whose subject has a natural negation gains a guard; every contract about a *rule with a
formula or list* gains the structural form. Two rewrites (one-liners dry-run against canonical in §2;
all currently pass):

```bash
@test "tier cap never drops the security pass on scope:sensitive" {
    local d="${RDF_SRC}/canonical/agents/dispatcher.md" t="${RDF_SRC}/canonical/reference/tiers.md" f
    # formula is stated verbatim in both restating files (tiers.md:57, dispatcher.md:298)
    for f in "$d" "$t"; do grep -qF 'max(security_floor, min(scope_gate, tier_cap))' "$f"; done
    # negation guard: no sentence disapplies the floor
    ! grep -qE 'Security floor[^.]*\b(no longer|not|never|does not)\b[^.]*appl' "$d" "$t"
    # order: the floor paragraph precedes the first tier bullet inside the Tier Cap section
    local cap floor bullet
    cap="$(grep -n '^### Tier Cap' "$d" | head -1 | cut -d: -f1)"
    floor="$(grep -n '^\*\*Security floor' "$d" | head -1 | cut -d: -f1)"
    bullet="$(grep -n '^- `full`' "$d" | head -1 | cut -d: -f1)"
    [ -n "$cap" ] && [ -n "$floor" ] && [ -n "$bullet" ] && [ "$cap" -lt "$floor" ] && [ "$floor" -lt "$bullet" ]
    # the indicator list is one list: reviewer.md (source), tiers.md and dispatcher.md (restatements)
    local want got
    want="$(grep -A3 'filename contains' "${RDF_SRC}/canonical/agents/reviewer.md" | grep -oE '`[a-z]+`' | tr -d '`' | sort -u | paste -sd,)"
    for f in "$d" "$t"; do
        got="$(grep -A3 'filename contains' "$f" | grep -oE '`[a-z]+`' | tr -d '`' | sort -u | paste -sd,)"
        [ "$got" = "$want" ] || { echo "indicator list drift in $f: $got != $want"; return 1; }
    done
}

@test "r-review-answer is advisory — does not block build/ship/merge" {
    local f="${RDF_SRC}/canonical/commands/r-review-answer.md"
    _contract commands/r-review-answer.md 'does not block'
    # negation guard: no sentence promotes it to a gate
    ! grep -qiE '(now|becomes|is) (a )?(blocking|hard) gate|must pass before|blocks? (/r-build|/r-ship|merge)' "$f"
}
```

Today's cross-file list equality: reviewer.md, tiers.md, dispatcher.md all yield
`auth,cert,cred,encrypt,hash,key,passwd,permission,secret,session,sign,token` (§2 dry-run). Follow-on:
one phase, rewrite the 17 presence contracts in place (no new file), suite stays deterministic and
LLM-free. Effort: S.

## 6. D4 — Per-minor platform re-triage gate at `/r-ship` preflight

**Checklist** (one line per capability; decision rule = *keep* RDF mechanism / *absorb* native
capability / *retire* RDF mechanism; each line records verdict, evidence, and the re-check trigger):

| Line | Decision rule | Verdict 2026-09-02 | Evidence |
|---|---|---|---|
| Workflows | absorb when GA on the user's plan and the RDF mechanism is a loop with no user input | absorb (gated spike, D1) | workflows.md GA; §3 |
| Agent Teams | absorb only when non-experimental, `-p` capable, worktree-isolated, nested | **keep dispatcher** (first case, below) | agent-teams.md; `agent-teams-research.md:118-126` |
| Skills frontmatter | absorb `skills/<name>/SKILL.md` + `disable-model-invocation` on side-effect commands + `allowed-tools` when the CC adapter can emit them from `skill-meta.json` | absorb — owned by the sibling spec `docs/specs/2026-09-02-skills-native-adapter-consolidation-design.md` (drafted concurrently; not duplicated here) | skills.md "Custom commands have been merged into skills"; 0/37 carry `allowed-tools` |
| Plugin components | absorb a component only when an RDF mechanism maps 1:1 (workflows yes; MCP/LSP/monitors/output-styles: no RDF equivalent) | keep | plugins-reference component table |
| Auto-memory | retire `~/.rdf/lessons-learned.md` only when a native *cross-project* store exists | keep | caller-supplied docs summary: none exists |
| `.claude/rules/` + `@import` | already absorbed (3.4.0 `--rules`) — verify each minor that `cc_generate_rules` output still loads | keep as-is | `adapters/claude-code/adapter.sh:276-277`, `tests/rules-deploy.bats` |
| Eval availability | switch the trigger-eval runner to `claude plugin eval` when the probe in §2 stops printing "early access" | local harness (D2) | §2 probe |
| Hazard | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` turns *named* subagents into teammates ("a named subagent launches as a teammate, so teams can form even when you didn't ask for one") | document "unset with RDF" | agent-teams.md |

**Recording — three options.** (a) A dated block in `docs/specs/CURRENT.md`: wrong artifact — CURRENT.md
is architecture state folded from the plan File Map (`r-ship.md:157-175`), not platform verdicts.
(b) `docs/platform-triage.md` ledger: newest dated block on top, one row per line above, columns
verdict / evidence / re-check trigger; `/r-ship` 1d greps the top block's version. (c) ROADMAP notes:
not machine-checkable. **Recommend (b).**

**Gate strength — three options.** Hard gate every release; minor-only (`x.y.0`) with patches skipped;
advisory. **Recommend minor-only**: preflight adds `1d. Platform triage` — `[x]` when the ledger's top
block matches the release's `MAJOR.MINOR`, `[ ]` + `> **Blocked**` otherwise, `*(skipped)*` on patch
releases. One grep, no subagent; matches `r-ship.md:69-85` display rules. Effort: S (ledger + 1d + a
contract test that 1d exists).

**First case — native Agent Teams vs RDF dispatcher. Verdict: keep the dispatcher; do not absorb.**
(1) "Agent teams are experimental and disabled by default" (agent-teams.md Warning); not enabled here
(§2). (2) "Spawning teammates also requires an interactive session. In non-interactive mode with the
`-p` flag ... Claude doesn't spawn teammates" → no headless/CI path; RDF's D2 harness and `/r-build`
resume both need `-p`. (3) Shared working tree: "Two teammates editing the same file leads to
overwrites" and worktrees are offered only as manual sessions "without automated team coordination";
RDF's parallel path is worktree-isolated with a pre-commit scope hook (`r-build.md:232-253,273`,
`state/git-hooks/pre-commit`, `plan-schema.md` Rule 8). (4) Gate machinery is hook-only
(`TeammateIdle`/`TaskCreated`/`TaskCompleted` exit 2) — no engineer→QA→reviewer chain, no evidence
grammar, no finding-resolution routing (`dispatcher.md:457-536`). (5) "No nested teams" and "Lead is
fixed" contradict `/r-build` → dispatcher → engineer nesting (`r-build.md:204-208`). (6) "Task status can
lag" is the exact failure the dispatcher's status files exist to prevent. Re-check triggers: the
experimental flag drops, `-p` support lands, or per-teammate worktree isolation ships.

## 7. D5 — OWASP Agentic Skills Top 10 posture

Primary source found: OWASP Agentic Skills Top 10, Version 1.0 (2026 Edition), Incubator project,
CC-BY-SA-4.0 — https://owasp.org/www-project-agentic-skills-top-10/ (fetched 2026-09-02; the
2026-08-17 release date appears only in secondary coverage). Item definitions quoted from the project page.

| Item | RDF posture | Evidence | Gap / action |
|---|---|---|---|
| AST01 Malicious Skills | good | GPL-2.0 source-visible plugin (`.claude-plugin/plugin.json:13`); repo-as-marketplace `marketplace.json` source `./`; CI `claude plugin validate . --strict` (`.github/workflows/ci.yml:110`) | none |
| AST02 Supply Chain Compromise | partial | vendored `canonical/scripts/setup.sh:158` `curl -sL "$REPO_URL/scripts/context-bar.sh"` — unpinned remote fetch, and the file is deployed (`~/.claude/scripts/setup.sh` present) | exclude vendored installers from deploy or pin a sha |
| AST03 Over-Privileged Skills | partial | 0/37 generated commands carry `allowed-tools`; `/r-ship`, `/r-build`, `/r-save` lack `disable-model-invocation`; qa/uat/reviewer are read-only by policy but keep `Bash` (`adapters/claude-code/agent-meta.json`) | emit `disable-model-invocation: true` for side-effect commands and `allowed-tools` from `skill-meta.json` (D4 skills line → sibling skills-native spec) |
| AST04 Insecure Metadata | good | frontmatter is generated from JSON catalogs (`adapters/claude-code/adapter.sh:13,129`); doctor `catalogs` scope (`lib/cmd/doctor.sh:695`); CI strict validate; CC sanitizes descriptions (skills.md) | none |
| AST05 Untrusted External Instructions | gap | `/r-spec` is research-driven (`canonical/commands/r-spec.md:4,85`) yet no canonical agent/command states that fetched content is data, not instruction (`grep -rni 'untrusted\|prompt injection' canonical/{agents,commands,reference}` → none) | one-line directive in planner/reviewer + `reference/framework.md` |
| AST06 Weak Isolation | good (write scope) | worktree isolation (`r-build.md:273`), pre-commit scope hook (232 lines), post-merge scope check (`dispatcher.md:124-187`); runtime sandboxing is the platform's | none beyond D1 keeping `isolation:'worktree'` |
| AST07 Update Drift | good | `plugin.json` `version` "pins the plugin to that version string ... If also set in the marketplace entry, plugin.json wins" (plugins-reference); `.rdf-hash` sidecars + doctor `content-drift`/`state-helpers` (`doctor.sh:319,743`) | none |
| AST08 Poor Scanning | partial | contract harness is presence-only (D3); pre-commit `suppression-no-comment` class (`state/git-hooks/pre-commit:133,148`); no scan of skill bodies for injection-shaped text | D3 rewrite; later a skill-body lint |
| AST09 No Governance | good | `rdf doctor` 13 `_check_*` scopes (`doctor.sh:61-927`), catalogs check, CHANGELOG protocol, MEMORY | none |
| AST10 Cross-Platform Reuse | partial | six adapters (`adapters/`); shared `.agents/skills/` SKILL.md; "Outside Claude Code, you can use only the fields in the Agent Skills spec" → `allowed-tools`/`disable-model-invocation` vanish on port; `docs/multi-tool-parity.md` exists but does not list security fields | parity doc gains a "security fields not portable" row |

Effort for the four actions: S (docs + adapter frontmatter, one phase, rides the D4 skills line).

## 8. Go / No-Go Summary

| Item | Verdict | Follow-on plan would contain | Effort |
|---|---|---|---|
| D1 workflow-backed `/r-build` | **Go — gated spike (option B)** | fix `tiers.md` bugfix/`min()` contradiction + define plan `Status:` form; `deploy.sh` workflows dir; `/r-build --workflow` arg derivation (BATS); A/B on one real plan; indicator-list contract | M (3–4 phases) |
| D2 trigger evals | **Go — local harness now, eval-CLI layout** | `state/rdf-trigger-eval.sh` reading `evals/*/case.yaml`; 37 positive + ~10 negative cases; `/r-ship` 1e line; optional CI job | S (1–2 phases) |
| D3 contract hardening | **Go** | rewrite 17 presence contracts with negation guards + structural checks in place | S (1 phase) |
| D4 re-triage gate | **Go — minor-only** | `docs/platform-triage.md` ledger seeded with §6; `/r-ship` 1d; contract test | S (1 phase) |
| D5 OWASP posture | **Go-lite** | AST02/03/05/10 actions above | S (1 phase, shares D4's adapter change) |

## 9. Non-goals

- No change to any file outside `docs/specs/` in this spike; the prototype is not wired into
  `adapters/claude-plugin/` or `plugin.json`, and no `workflows/` or `evals/` directory is created.
- No migration of the CC adapter from `commands/` to `skills/` here — sized in D4, executed later.
- No Agent Teams integration, no `/skill-doctor` probing (in-session, gated), no Antigravity/Codex work.
- No retirement of `tests/governance-contracts.bats`; no LLM-graded tests added to `make test`.
- No cost/quality benchmark of workflow vs prose dispatch — that is the D1 follow-on's deliverable.

## 10. Open Questions for Ryan

1. **Two `/r-build` paths for one minor.** D1's spike keeps the prose dispatcher as default and adds
   `--workflow`. Given the 3.6.1–3.6.4 seam history, is a dual path acceptable for one release, or
   should the workflow ship only as an unwired artifact until the A/B evidence exists?
2. **`disable-model-invocation` on `/r-ship`, `/r-build`, `/r-save`.** It stops the model from
   auto-running side-effect commands (AST03) but also removes them from Claude's own suggestions.
   Accept the discoverability loss?
3. **Gate strength for D4.** Minor-only blocking is recommended; advisory would never block a ship.
   Which?
