# Skills-Native Adapter Consolidation — Design Spec

**Date:** 2026-09-02 · **Tier:** full · **Status:** approved (challenge review, 3 cycles, 2026-09-02)
**Pipeline:** spec → plan → build → ship
**Roadmap:** 2026-08 top-5 item 4 (adapter consolidation) + item 5 first case
(platform re-triage of the 3.6.0 "commands stay commands" decision) +
companion quick-plan scope: mechanical doc truth (§13).

Line references are as of `5069a4c` (3.6.5 + ROADMAP check-off + the
first-run-truth commit): `lib/rdf_common.sh` 192 lines (gained
`RDF_GIT_EXCLUDE_ENTRIES`), `lib/cmd/doctor.sh` 1226, `lib/cmd/deploy.sh`
379, `lib/cmd/init.sh` 836. Doctor function starts at that commit:
`_check_content_drift` 336, `_check_sync` 455, `_check_catalogs` 712,
`_check_doc_stats` 801, `_check_install_mode` 944.

## 1. Problem Statement

RDF emits the same content through six adapters that were written one at a
time. Measured today:

1. **Duplication.** ~190 literally identical lines (~20% of 956 adapter code
   lines), ~300 (~31%) counting prefix-only differences. The agent YAML
   frontmatter emitter exists twice (`adapters/claude-code/adapter.sh:43-84`
   vs `adapters/claude-plugin/adapter.sh:132-166`, 24/31 identical lines);
   the scripts copy loop four times (`claude-code:178-194`,
   `claude-plugin:169-185`, `codex:134-151`, `gemini-cli:200-216`); the
   atomic `.new/.old` swap five times (`claude-code:310-326`,
   `claude-plugin:281-289`, `codex:167-178`, `gemini-cli:225-246`,
   `agent-skills:59-76`); the command-description derivation
   (`skill-meta.json` → first non-heading line → fallback) three times
   (`claude-code:129-142`, `claude-plugin:53-67`, `agent-skills:15-24`).
   Every adapter bug has been fixed 2-5 times (3.6.1 mirror crack, 3.6.4
   agent-meta preflight added to two adapters, 3.6.5 reference emission added
   to three).

2. **Platform moved under the command surface.** Claude Code documents
   `.claude/commands/*.md` as still supported but merged into skills:
   "A file at `.claude/commands/deploy.md` and a skill at
   `.claude/skills/deploy/SKILL.md` both create `/deploy` and work the same
   way" (skills.md, 2026-09). Skills add `context: fork`, `argument-hint`,
   `user-invocable`, `paths`, and per-`<skill-name>` symlink support; a
   same-name skill silently wins over a command. RDF already emits SKILL.md
   for Codex/Antigravity (`adapters/agent-skills/adapter.sh`) but the two
   Claude surfaces still emit flat commands, so the three surfaces cannot
   share an emitter. The 3.6.0 decision "commands stay commands; SKILL.md is
   an additional emitted surface" (`docs/specs/2026-07-15-scale-reach-design.md:178`)
   is re-triaged here on that evidence.

3. **Codex adapter is dead weight with a defect.** `adapters/codex/adapter.sh:39`
   reads `profiles/<p>/governance.md`; zero such files exist (deleted
   `f1d9abc`, 2026-03-18), so every generated Codex AGENTS.md has an empty
   `## Project Governance` section. `.codex/config.toml` hardcodes
   `model = "o4-mini"` (`:120`). One BATS test (`tests/adapter.bats:582`),
   zero measured invocations across 10,453 transcripts. Codex reads
   `$REPO_ROOT/.agents/skills` and `$HOME/.agents/skills` natively
   (learn.chatgpt.com/docs/build-skills) and AGENTS.md (agents.md), which is
   exactly what the `antigravity` composite already emits.

4. **AGENTS.md output describes RDF, not the user's project.**
   `adapters/agents-md/sections.json:7` hardcodes "for the rfxn ecosystem
   (APF, BFD, LMD, Sigforge…)", `:41` "Bash 4.1+ floor (CentOS 6)" (false for
   RDF itself, whose floor is 3.2), and `:36` a hand-maintained command list.
   `rdf generate antigravity` in a consumer repo therefore emits an
   AGENTS.md about RDF (`docs/multi-tool-parity.md:71-73` admits it; README
   `:283-288` advertises the target without the caveat).

5. **`rdf init --tools` is a phantom flag.** Parsed (`lib/cmd/init.sh:727`),
   warned on non-default (`:747-750`), never consumed. `--tools claude-code`
   is accepted silently; help (`:22`) calls it unimplemented.

6. **Dead catalogs.** `adapters/claude-code/command-meta-v3.json` (282 lines)
   is assigned at `adapter.sh:12` and never read; `command-map-v3.md` is
   referenced only by a 3.0 plan; `adapters/gemini-cli/agent-meta.json` is a
   byte-identical copy of the cc catalog (gemini is frozen — left in place).

## 2. Goals

1. One shared library `lib/adapter_common.sh` provides agent frontmatter,
   agents loop, skills loop, scripts loop, reference loop, hash sidecars,
   description derivation, and the atomic swap; `adapters/claude-code`,
   `claude-plugin`, and `agent-skills` contain zero copies of those blocks.
   Measurable: `grep -c 'output_old' adapters/*/adapter.sh` → 0 for the three
   (gemini keeps its copy); the three adapters total ≤ 430 lines (from 721).
2. `rdf generate claude-code` and `claude-plugin` emit
   `skills/<name>/SKILL.md` for every canonical command (37 today) and no
   `commands/` directory; `rdf generate agent-skills` keeps the bounded
   skill-meta set. Bodies stay byte-identical to canonical (sidecar hash and
   `rdf sync` contract unchanged).
3. `rdf deploy claude-code` owns `~/.claude/skills/<name>` as per-skill
   directory symlinks, prunes its own stale skill symlinks, and removes a
   legacy `~/.claude/commands` symlink that points into the RDF output tree.
4. `rdf doctor` (sync, content-drift, install-mode), `rdf sync`,
   `state/rdf-overhead.sh`, and `state/context-audit.sh` all operate on the
   skills layout; none silently no-ops (each has a fail-closed test).
5. `.claude-plugin/plugin.json` declares
   `"skills": "./adapters/claude-plugin/output/skills"` and no `commands`
   key; `claude plugin validate . --strict` stays green in CI.
6. `codex` generate/deploy targets are served by the composite
   (agent-skills + agents-md); `adapters/codex/` is deleted.
7. `rdf generate agents-md` composes a project-scoped AGENTS.md from the
   target repo's own `CLAUDE.md` (default target: the RDF checkout, which
   regenerates the tracked self output); `sections.json` and the section
   extractor are deleted; no rfxn identifiers in the output for a non-rfxn
   repo.
8. `rdf init --tools` is real: comma list from
   `claude-code|agent-skills|agents-md|codex|antigravity`; unknown values
   exit 1; `agent-skills`/`agents-md` produce their artifacts in the repo.
9. (§13) `rdf doctor --scope doc-truth` mechanically checks profile counts
   across README badge / RDF.md / registry / dirs, test-suite wiring
   (every `tests/*.bats` in the Makefile), WORKFORCE.md dispatch claims
   against canonical command bodies, and CONTRIBUTING CI claims against
   `ci.yml`; all current drift fixed; scope count 13 → 14.
10. (§13) `WORKFORCE.md`, `RDF.md`, and `context-bar.md` are either
    doctor-checked or relocated under `docs/`; the never-dispatched
    `planner` claim and `/r-start → dispatcher` claim are corrected.

## 3. Non-Goals

- NOT right-sizing the command set (roadmap item 3, deferred by Ryan
  2026-09-02) — all 37 commands migrate as-is.
- NOT touching `adapters/gemini-cli/` (frozen legacy: no shared lib, keeps
  its own loops and `agent-meta.json`).
- NOT adding `context: fork`, `allowed-tools`, `argument-hint`, or
  `disable-model-invocation` to any generated skill — frontmatter stays
  `name` + `description` (plugin variant namespace-rewrites the description).
  Skill-level tuning is a later, per-command decision with usage data.
- NOT emitting Workflows, hooks, or MCP components for skills.
- NOT changing `~/.claude/agents|scripts|governance|reference` delivery
  (directory symlinks remain).
- NOT changing the agent-skills bounded set (10 keys in `skill-meta.json`).
- NOT retroactively cleaning `~/.claude/*.bak-phase2/` directories.
- NOT the eval/Workflow spike (separate spec,
  `docs/specs/2026-09-02-platform-alignment-spike-design.md`).

## 4. Architecture

### Codebase Inventory

| File | Lines | Key functions | Dependencies | Test file |
|------|------:|---------------|--------------|-----------|
| `adapters/claude-code/adapter.sh` | 344 | `_cc_agent_frontmatter`, `cc_generate_{agents,commands,scripts,reference,hooks,governance,rules,all}`, `_cc_is_lite_command`, `_cc_write_hash_sidecar` | `rdf_common.sh`, `agent-meta.json`, `skill-meta.json`, jq | `tests/adapter.bats`, `rdf-lite.bats`, `rules-deploy.bats` |
| `adapters/claude-plugin/adapter.sh` | 299 | `_cpl_rewrite_namespace_text`, `cpl_generate_{commands,agents,scripts,reference,hooks,all}`, `_cpl_agent_frontmatter`, `cpl_stamp_plugin_version` | cc `agent-meta.json`, `skill-meta.json`, `plugin.json`, jq | `tests/plugin-adapter.bats` |
| `adapters/agent-skills/adapter.sh` | 78 | `_sk_skill_description`, `sk_emit_skills`, `sk_generate_all` | `skill-meta.json`, jq | `tests/agent-skills.bats` |
| `adapters/agents-md/adapter.sh` | 152 | `_amd_extract_canonical_section`, `_amd_agent_roster`, `amd_generate_all` | `sections.json`, `CLAUDE.md.ref`, `framework.md` | `tests/agent-skills.bats:135` |
| `adapters/codex/adapter.sh` | 181 | `cdx_generate_{agents_md,config,scripts,all}` | `profiles/*/governance.md` (absent) | `tests/adapter.bats:582` |
| `lib/cmd/generate.sh` | 188 | `cmd_generate`, `_generate_adapter` | adapters | (via adapter tests) |
| `lib/cmd/deploy.sh` | 379 | `_deploy_symlink`, `_deploy_state_link`, `_deploy_state_helpers`, `_deploy_claude_code`, `_deploy_codex`, `_deploy_agent_skills`, `cmd_deploy` | `rdf_common.sh` | `tests/deploy.bats`, `rules-deploy.bats` |
| `lib/cmd/doctor.sh` | 1226 | `_check_content_drift` (336-452), `_check_sync` (455-533), `_check_catalogs` (712-754), `_check_doc_stats` (801-937), `_check_install_mode` (944-964), scope dispatch (tail) | `rdf_common.sh` | `tests/doctor.bats` |
| `lib/cmd/sync.sh` | 144 | `cmd_sync` (agents 47-80, commands 83-116, scripts 119-139) | `rdf_strip_frontmatter` | `tests/sync.bats`, `deploy.bats:128` |
| `lib/cmd/init.sh` | 836 | `cmd_init` (`--tools` at 716/727/747) | profiles, templates | `tests/cmd-migrate-init.bats` |
| `lib/rdf_common.sh` | 192 | `rdf_hash_stdin` (77-84), `rdf_strip_frontmatter` (90-98), `rdf_require_agent_meta`, `rdf_get_active_profiles` | — | `tests/strip.bats` |
| `state/rdf-overhead.sh` | ~130 | checkout resolver (26-34) via `readlink ~/.claude/commands` | — | `tests/overhead.bats` |
| `state/context-audit.sh` | ~430 | skills inventory (142-184) counting `commands/*.md` at maxdepth 1 | `rdf-state.sh` | `tests/state-injection.bats` |
| `.claude-plugin/plugin.json` | 32 | `commands` path (14), `agents` array (15-22) | — | `tests/plugin-adapter.bats:278` |
| `adapters/agent-skills/skill-meta.json` | 12 | 10 lifecycle triggers | — | `tests/doctor.bats:248` (catalogs) |

Dependency chain today: `bin/rdf` → `lib/rdf_common.sh` → `lib/cmd/generate.sh`
→ `_generate_adapter` sources one `adapters/<x>/adapter.sh` and calls its
`*_generate_all`. Deploy/doctor/sync never source adapters; they read the
output trees and the manifest directly.

### File Map

| File | Action | Est. lines | Purpose |
|------|--------|-----------:|---------|
| `lib/adapter_common.sh` | new | ~230 | shared emitters: `adp_agent_frontmatter`, `adp_emit_agents`, `adp_emit_skills`, `adp_skill_description`, `adp_copy_scripts`, `adp_copy_reference`, `adp_write_hash_sidecar`, `adp_stage_begin`/`adp_stage_commit`, `adp_names_all`/`adp_names_lite`/`adp_names_from_meta`, `adp_count` |
| `adapters/claude-code/adapter.sh` | modified | 344 → ~170 | thin: hooks, governance, rules, orchestration on the lib; skills output |
| `adapters/claude-plugin/adapter.sh` | modified | 299 → ~150 | thin: namespace filter, hooks transform, plugin stamping (adds `skills` key) |
| `adapters/agent-skills/adapter.sh` | modified | 78 → ~45 | thin: bounded set → `adp_emit_skills` |
| `adapters/agents-md/adapter.sh` | rewritten | 152 → ~95 | project composer `amd_compose <project_root> <dst>` + `amd_generate_all` |
| `adapters/agents-md/sections.json` | deleted | −46 | replaced by composer |
| `adapters/codex/adapter.sh` | deleted | −181 | served by composite |
| `adapters/codex/output/` | deleted | — | gitignored tree; remove from `.gitignore` |
| `adapters/claude-code/command-meta-v3.json` | deleted | −282 | never read |
| `adapters/claude-code/command-map-v3.md` | deleted | — | 3.0 plan artifact |
| `lib/cmd/generate.sh` | modified | +15/−25 | `codex` → composite; `agents-md --project-root`; usage text; `all` loses codex |
| `lib/cmd/deploy.sh` | modified | +70/−30 | `_deploy_skill_links`, `_deploy_prune_legacy_commands`, `_deploy_codex` → composite (`_deploy_agent_skills` + `_deploy_agents_md`), `agents-md` target |
| `lib/cmd/doctor.sh` | modified | +140/−20 | sync loop on the surface map; content-drift walks `skills/*/SKILL.md`; install-mode probes `skills/r-start`; new `doc-truth` scope (§13); scope table 13 → 14 |
| `lib/cmd/sync.sh` | modified | +8/−6 | commands loop reads `skills/*/SKILL.md` → `canonical/commands/<name>.md` |
| `lib/cmd/init.sh` | modified | +45/−6 | `--tools` parse/validate/dispatch |
| `lib/rdf_common.sh` | modified | +12 | `rdf_cc_dir_surfaces` (agents scripts governance reference) and `rdf_lite_commands` lists (single source for deploy + doctor + lib) |
| `state/rdf-overhead.sh` | modified | +4/−4 | resolver reads `~/.claude/agents` symlink (unchanged surface) instead of `commands` |
| `state/context-audit.sh` | modified | +10/−8 | skills inventory: `skills/*/SKILL.md` + legacy `commands/*.md` |
| `.claude-plugin/plugin.json` | modified | ±1 | `skills` key replaces `commands` |
| `.gitignore` | modified | −1 | drop `adapters/codex/output` |
| `.github/workflows/ci.yml` | modified | +2 | plugin job also runs `claude plugin validate adapters/claude-plugin/output/skills --strict` (SKILL.md frontmatter parse) |
| `tests/adapter-common.bats` | new | ~150 | lib contracts (byte-identity vs 3.6.5 fixtures, sidecar, stage/commit, lite filter) |
| `tests/doc-truth.bats` | new | ~110 | §13 scope |
| `tests/adapter.bats` | modified | ±40 | commands → skills paths; codex catalog test removed |
| `tests/plugin-adapter.bats` | modified | ±40 | skills paths; `skills` key; no sidecars in plugin tree |
| `tests/deploy.bats` | modified | ±60 | per-skill symlinks, prune, legacy commands removal, codex composite |
| `tests/doctor.bats` | modified | ±40 | sync loop, content-drift on skills, install-mode |
| `tests/sync.bats` | modified | +20 | skills reverse flow + fail-closed (no `skills/` dir → WARN, not silent 0) |
| `tests/rdf-lite.bats` | modified | ±15 | lite set by skill dir names |
| `tests/overhead.bats` | modified | ±15 | resolver via `agents` symlink |
| `tests/agent-skills.bats` | modified | ±20 | shared emitter; agents-md composer assertions |
| `tests/cmd-migrate-init.bats` | modified | +30 | `--tools` matrix + unknown-value exit 1 |
| `tests/state-injection.bats` | modified | +12 | context-audit skills-count assertion (skills tree + legacy commands both counted) |
| `tests/derfxn.bats` | modified | ±6 | drop the "README must not mention `--tools`" assertion; add "consumer AGENTS.md has no rfxn identifiers" |
| `tests/Makefile` | modified | +2 | register the two new files |
| `README.md`, `RDF.md`, `WORKFORCE.md`, `docs/index.md`, `docs/quickstart.md`, `docs/multi-tool-parity.md`, `CONTRIBUTING.md`, `canonical/commands/r-sync.md` | modified | ~120 total | skills wording, adapter table (5 adapters), `--tools`, data-flow diagram, parity matrix, WORKFORCE truth |
| `context-bar.md` | moved | → `docs/context-bar.md` | orphan doc linked from README docs table |
| `canonical/reference/tiers.md` | modified | ±1 | §13: line 41 restates the effective gate set with the security floor |
| `CHANGELOG`, `CHANGELOG.RELEASE`, `docs/specs/CURRENT.md` | modified | — | release bookkeeping (ship stage) |
| `ROADMAP.md` | modified | ~10 | §13 "built-in 11" wording; item 4/5 status; D1/D2 follow-ons (same phase as doc-truth) |

No-touch files: `adapters/gemini-cli/**`, `canonical/**` except `commands/r-sync.md`, `commands/r-ship.md` (spike D4 preflight line), and `reference/tiers.md`,
`profiles/**`, `adapters/claude-code/hooks/hooks.json`,
`adapters/claude-code/agent-meta.json`, `adapters/agent-skills/skill-meta.json`
(content), `state/rdf-state.sh`, `state/rdf-bus.sh`,
`canonical/scripts/state-bootstrap.sh` (delivers `~/.rdf/state/*.sh` only —
no command/skill paths; its version stamp refreshes the plugin-tier copy of
the overhead resolver on the next session, which is why §8 mentions it).

### Size Comparison

| Metric | Before | After |
|--------|-------:|------:|
| Adapter code lines (cc + cpl + agent-skills + agents-md + codex) | 1,054 | ~460 + 230 lib = ~690 |
| Copies of atomic swap (excluding gemini) | 4 | 1 |
| Copies of scripts loop (excluding gemini) | 3 | 1 |
| Copies of agent frontmatter emitter | 2 (+gemini) | 1 (+gemini) |
| Adapters | 6 | 5 |
| `~/.claude` surfaces on symlink deploy | 5 dir symlinks | 4 dir symlinks + N skill symlinks |
| Doctor scopes | 13 | 14 |
| Generated command surface | `commands/*.md` (37) | `skills/<n>/SKILL.md` (37) |
| Dead catalog bytes | 282 + ~40 lines | 0 |

### Dependency Tree

```
bin/rdf
└── lib/rdf_common.sh            (+ rdf_cc_dir_surfaces, rdf_lite_commands)
    ├── lib/adapter_common.sh    (NEW — sourced by generate.sh before any adapter)
    │   ├── adp_agent_frontmatter  <meta> <agent>
    │   ├── adp_emit_agents        <src> <dst> <meta> <filter_fn|-> <sidecar 0|1>
    │   ├── adp_skill_description  <name> <src> <meta>
    │   ├── adp_emit_skills        <src_dir> <skills_root> <meta> <filter_fn|-> <sidecar> <names_fn> <ref_src|->
    │   ├── adp_names_all          <src_dir> [meta]        (meta accepted-and-ignored)
    │   ├── adp_names_lite         <src_dir> [meta]        (meta accepted-and-ignored)
    │   ├── adp_names_from_meta    <src_dir> <meta>        (src_dir accepted-and-ignored)
    │   ├── adp_copy_scripts       <src> <dst>
    │   ├── adp_copy_reference     <src> <dst> <sidecar>
    │   ├── adp_write_hash_sidecar <canonical_src> <dst>
    │   ├── adp_stage_begin        <final_dir>   → echoes staging dir
    │   └── adp_stage_commit       <final_dir> <staging_dir>
    ├── lib/cmd/generate.sh
    │   ├── adapters/claude-code/adapter.sh    (cc_generate_all → lib + hooks/governance/rules)
    │   ├── adapters/claude-plugin/adapter.sh  (cpl_generate_all → lib with _cpl_rewrite filter + stamp)
    │   ├── adapters/agent-skills/adapter.sh   (sk_generate_all → adp_emit_skills bounded)
    │   ├── adapters/agents-md/adapter.sh      (amd_compose → project AGENTS.md)
    │   └── adapters/gemini-cli/adapter.sh     (frozen; untouched)
    ├── lib/cmd/deploy.sh   (reads output trees; rdf_cc_dir_surfaces + skills/)
    ├── lib/cmd/doctor.sh   (reads output trees + ~/.claude; same lists)
    ├── lib/cmd/sync.sh     (reads output/skills/*/SKILL.md)
    └── lib/cmd/init.sh     (--tools → sources deploy.sh + agents-md adapter)
state/rdf-overhead.sh       (readlink ~/.claude/agents → checkout root)
state/context-audit.sh      (skills/*/SKILL.md inventory)
```

### Key Changes

1. **Emitters move to a library.** Adapters become orchestration + their
   genuinely different parts (cc: hooks copy, governance, rules; plugin:
   namespace rewrite, hooks path transform, manifest stamping; agent-skills:
   bounded set). The filter is a function name passed by the caller and
   applied to the body stream (`-` = none), so the plugin's `/r-X → /rdf:r-X`
   rewrite stays plugin-owned.
2. **Skills layout.** `output/skills/<name>/SKILL.md` = `---\nname: <name>\n
   description: >\n  <trigger>\n---\n\n<canonical body>`. cc output adds
   `SKILL.md.rdf-hash` beside it (hash over the canonical body, exactly as
   today). Plugin output has no sidecars (`claude plugin validate` treats
   non-component files as warnings only inside `commands/`; skill dirs may
   hold supporting files, but the plugin tree stays sidecar-free to keep the
   CI drift diff minimal). All three skill trees also carry
   `skills/reference/*.md` so the canonical `../reference/*.md` links resolve
   from inside a skill dir (the pattern agent-skills established in 3.6.5
   for Codex/Antigravity). Verified 2026-09-02 on Claude Code 2.1.258: (a)
   `claude plugin validate <skills-dir> --strict` passes with a non-skill
   `reference/` subdirectory present; (b) a headless `claude -p` session in a
   project whose `.claude/skills/` holds `r-probe/SKILL.md` and
   `reference/tiers.md` lists `r-probe` among its skills, does not list
   `reference`, and writes nothing to stderr. A directory without SKILL.md
   is therefore silently skipped; Phase 2's gate repeats probe (b) against
   the generated tree.
3. **Lite set by name.** `rdf_lite_commands` = `r-spec r-plan r-build r-ship
   r-start r-save`; `adp_emit_skills` receives a names function (all / lite /
   skill-meta keys).
4. **Deploy owns per-skill symlinks.** `_deploy_skill_links`: for each
   `output/skills/<n>` create/replace `~/.claude/skills/<n>` (dry-run/force
   semantics of `_deploy_symlink`), then prune any `~/.claude/skills/*`
   symlink whose target is under `output/skills/` but no longer exists. Then
   `_deploy_prune_legacy_commands`: if `~/.claude/commands` is a symlink whose
   canonical target is under `${RDF_HOME}/adapters/claude-code/output/`,
   remove it and log; a real directory or a foreign symlink is left alone
   with a one-line notice. `~/.claude/skills` is created as a real directory
   if absent (never a symlink — user skills may live there).
5. **Surface lists live once.** `rdf_cc_dir_surfaces` (agents scripts
   governance reference) drives both the deploy loop and doctor's sync
   symlink-health loop; skills are checked by the same doctor loop via
   `skills/<lite-or-all first name>` presence + a per-skill target check.
6. **Fail-closed consumers.** `rdf sync` and doctor content-drift WARN
   explicitly when `output/skills` is absent ("no skills tree — run rdf
   generate") instead of iterating an empty glob; context-audit reports the
   skills count from `skills/*/SKILL.md`.
7. **Overhead resolver.** `state/rdf-overhead.sh` resolves the checkout from
   `readlink ~/.claude/agents` (a surface this spec does not touch), falling
   back to the `.rdf-source` stamp exactly as today.
8. **Codex = composite.** `rdf generate codex` runs agent-skills + agents-md
   (same as `antigravity`); `rdf deploy codex --project-root P` symlinks
   `P/.agents/skills` and copy-skips `P/AGENTS.md`. `~/.codex/config.toml` is
   no longer written (Codex reads skills without it).
9. **AGENTS.md composer.** `amd_compose <root> <dst>`: header
   (`# AGENTS.md — <repo name>`, generated-by line), the body of
   `<root>/CLAUDE.md` (or `<root>/.rdf/governance/index.md` when CLAUDE.md is
   absent, else a two-line stub), `## Agent Skills` pointer to
   `.agents/skills/`, `## Agent Roster` (canonical agents, first-line
   descriptions — unchanged helper), and a size warning above 32 KiB.
   Default root = `${RDF_HOME}` so `rdf generate agents-md` regenerates the
   tracked self output.
10. **`--tools`.** `rdf init --tools a,b` validates each token against the
    allowed set, expands `codex|antigravity` → `agent-skills,agents-md`,
    then after governance init runs `_deploy_agent_skills` (project root)
    and/or `amd_compose "$path" "$path/AGENTS.md"` (skip if AGENTS.md exists,
    like SECURITY.md). `claude-code` is accepted as a no-op. Help text and
    README document the value set.

### Dependency Rules

- `lib/adapter_common.sh` depends only on `lib/rdf_common.sh` and jq; it
  never references `RDF_ADAPTERS` paths, output dirs, or adapter-specific
  globals — every path is a parameter.
- Adapters never call each other; composites are wired in `generate.sh`.
- deploy/doctor/sync never source adapters; they consume output trees and
  the two lists in `rdf_common.sh`.
- Canonical bodies are never rewritten on disk; filters apply on the stream
  during emission only, so `rdf sync` and sidecar hashes keep matching.
- gemini-cli sources nothing new.

## 5. File Contents

### `lib/adapter_common.sh` (new)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `adp_write_hash_sidecar` | `(canonical_src, dst)` | write `${dst}.rdf-hash` = hash of canonical body | `rdf_hash_stdin` |
| `adp_require_hash_tool` | `()` | die when no sha256sum/shasum/sha1sum | — |
| `adp_agent_frontmatter` | `(meta, agent)` → stdout, rc 1 if absent | YAML: name, description, tools, disallowedTools, model | jq |
| `adp_emit_agents` | `(src_dir, dst_dir, meta, filter_fn, sidecar)` | frontmatter + filtered body per agent; plain copy when meta absent (warn); optional sidecar; logs count | `adp_agent_frontmatter`, `adp_write_hash_sidecar` |
| `adp_skill_description` | `(name, src, meta)` → stdout | skill-meta trigger → first non-heading line → `RDF command: <name>` | jq, sed |
| `adp_emit_skills` | `(src_dir, skills_root, meta, filter_fn, sidecar, names_fn, ref_src)` | `<root>/<name>/SKILL.md` with `name:`/`description:` frontmatter + filtered body; optional sidecar; copies `ref_src` into `<root>/reference` (`-` skips the copy); logs count | `adp_skill_description`, `adp_copy_reference` |
| `adp_names_all` | `(src_dir, [meta])` → stdout | all canonical command basenames; `meta` accepted-and-ignored so every names_fn takes the same pair | — |
| `adp_names_lite` | `(src_dir, [meta])` → stdout | intersection with `rdf_lite_commands`; `meta` accepted-and-ignored | `rdf_lite_commands` |
| `adp_names_from_meta` | `(src_dir, meta)` → stdout | non-`_comment` keys; `src_dir` accepted-and-ignored | jq |
| `adp_copy_scripts` | `(src_dir, dst_dir)` | copy `*.sh` + chmod +x; logs count | — |
| `adp_copy_reference` | `(src_dir, dst_dir, sidecar)` | copy `*.md`, optional sidecars | `adp_write_hash_sidecar` |
| `adp_stage_begin` | `(final_dir)` → echoes `<final>.new` | rm -rf + mkdir staging | — |
| `adp_stage_commit` | `(final_dir, staging_dir)` | `.old` rotate, mv, rm `.old` | — |
| `adp_count` | `(dir, glob)` → stdout | portable find-count with absent-dir → 0 | — |

Dependencies: `lib/rdf_common.sh` (`rdf_log`, `rdf_warn`, `rdf_die`,
`rdf_hash_stdin`, `rdf_lite_commands`), jq.

### `adapters/claude-code/adapter.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_cc_resolve_hash_cmd`, `_cc_write_hash_sidecar`, `_cc_agent_frontmatter`, `cc_generate_agents`, `_cc_is_lite_command`, `cc_generate_command_frontmatter`, `cc_generate_commands`, `cc_generate_scripts`, `cc_generate_reference` | local copies | deleted; calls into lib | 19-213 |
| `cc_generate_skills` | — | `adp_emit_skills canonical/commands output/skills skill-meta - 1 <names_fn> canonical/reference` where names_fn = `adp_names_lite` when `_CC_LITE=1` else `adp_names_all` | new |
| `cc_generate_hooks`, `cc_generate_governance`, `_cc_paths_frontmatter`, `cc_generate_rules` | unchanged | unchanged | 215-298 |
| `cc_generate_all` | inline staging + swap; counts `commands` | `adp_stage_begin/commit`; counts `skills/*/SKILL.md`; log "N skills" | 301-344 |
| `_CC_COMMAND_META` | dead assignment | removed | 12 |

### `adapters/claude-plugin/adapter.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_cpl_rewrite_namespace_text`, `_cpl_command_names_longest_first` | sed rewrite | unchanged; exposed as the filter fn | 21-47 |
| `cpl_generate_command_frontmatter`, `cpl_generate_commands`, `cpl_generate_agents`, `_cpl_agent_frontmatter`, `cpl_generate_scripts`, `cpl_generate_reference` | local copies | deleted; `cpl_generate_skills` = `adp_emit_skills … _cpl_rewrite_namespace_text 0 adp_names_all canonical/reference` with the description also passed through the filter; agents via `adp_emit_agents … _cpl_rewrite_namespace_text 0` | 53-202 |
| `cpl_generate_hooks` | jq path transform | unchanged | 209-233 |
| `cpl_stamp_plugin_version` | stamps `.version`, `.agents` | also sets `.skills = "./adapters/claude-plugin/output/skills"` and `del(.commands)` | 240-258 |
| `cpl_generate_all` | inline swap; counts commands | lib staging; counts skills | 261-299 |

### `adapters/agent-skills/adapter.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_sk_skill_description`, `sk_emit_skills` | local | deleted → `adp_emit_skills canonical/commands <root>/.agents/skills skill-meta - 0 adp_names_from_meta canonical/reference` | 15-53 |
| `sk_generate_all` | inline swap + reference copy | lib staging; reference handled by `adp_emit_skills` | 56-78 |

### `adapters/agents-md/adapter.sh` (rewritten)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_amd_agent_roster` | `()` | unchanged bullet list | — |
| `_amd_context_source` | `(root)` → path or empty | `CLAUDE.md` → `.rdf/governance/index.md` → empty | — |
| `amd_compose` | `(root, dst)` | header + context body + skills pointer + roster; 32 KiB warn; refuses `root` without `.git` unless it is `RDF_HOME` | `_amd_context_source`, `_amd_agent_roster` |
| `amd_generate_all` | `([root])` | `amd_compose "${root:-$RDF_HOME}" output/AGENTS.md` | `amd_compose` |

### `lib/cmd/deploy.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_deploy_claude_code` | 5 dir symlinks incl. `commands` | loop over `rdf_cc_dir_surfaces` + `_deploy_skill_links` + `_deploy_prune_legacy_commands` | 236-240 |
| `_deploy_skill_links` | — | per-skill `_deploy_symlink` + the shared `skills/reference` entry (linked, not counted as a skill); prune stale RDF-owned entries; ensure `~/.claude/skills` is a real dir | new |
| `_deploy_prune_legacy_commands` | — | remove `~/.claude/commands` only when its target is under the RDF output tree; log; count as OK | new |
| `_deploy_codex` | copies AGENTS.md + config.toml | `_deploy_agent_skills` + `_deploy_agents_md` (copy-skip `output/AGENTS.md` → `P/AGENTS.md`) | 274-298 |
| `_deploy_agents_md` | — | copy-skip project AGENTS.md; `--project-root` required | new |
| `cmd_deploy` | targets: claude-code, gemini-cli, codex, agent-skills | + `agents-md`, `antigravity` (alias of codex path); usage text | 326-370 |

### `lib/cmd/doctor.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_check_content_drift` | globs `output/commands/*.md` | walks `output/skills/*/SKILL.md` with `SKILL.md.rdf-hash` plus both sidecar reference trees (`output/reference`, `output/skills/reference`); WARN "no skills tree" when absent (and the aggregate OK row drops its "all" claim); message keys `skills/<n>`, `skills/reference/<f>` | commands loop inside 336-452 |
| `_check_sync` | count `canonical/commands` vs `output/commands`; symlink loop over 5 names | count vs `output/skills/*/SKILL.md`; loop over `rdf_cc_dir_surfaces`; per-skill symlink check (`~/.claude/skills/<n>` → `output/skills/<n>`) plus the `skills/reference` entry; WARN on a lingering `~/.claude/commands` symlink into RDF output | count + loop inside 455-533 |
| `_check_install_mode` | probes `-L ~/.claude/commands` | probes `-L ~/.claude/skills/r-start` (or any RDF-owned skill link) and, for the transition, the legacy commands link | 949 |
| `_check_doc_truth` | — | §13 | new |
| scope dispatch | 13 scopes | 14 (`doc-truth`), usage text | scope `case` at file tail |

### `lib/cmd/sync.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `cmd_sync` commands loop | `output/commands/*.md` → `canonical/commands/<b>` | `output/skills/*/SKILL.md` → `canonical/commands/<dir>.md`; skip `skills/reference`; WARN when `output/skills` absent | 83-116 |

### `lib/cmd/init.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| usage | "reserved — not yet implemented" | `--tools LIST  claude-code (default), agent-skills, agents-md, codex, antigravity (comma-separated)` | 22 |
| `cmd_init` `--tools` | warn if ≠ claude-code | `_init_validate_tools` (die on unknown), `_init_apply_tools` after governance write (skips in `--dry-run` with a "would write" line) | 716-750 |

### `state/rdf-overhead.sh`, `state/context-audit.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| overhead resolver | `readlink ~/.claude/commands` | `readlink ~/.claude/agents`; same `${_link%/adapters/*}` derivation; same stamp fallback + warning text updated | 26-34 |
| context-audit skills inventory | `commands/*.md` maxdepth 1 | `skills/*/SKILL.md` (global + project) plus legacy `commands/*.md`; canonical count unchanged | 142-184 |

## 5b. Examples

Generate (checkout):

```
$ bin/rdf generate claude-code
[rdf] generating Claude Code adapter output...
[rdf] generated 6 agent files
[rdf] generated 7 reference docs (skills tree)
[rdf] generated 37 skills
[rdf] generated 16 script files
[rdf] generated 7 reference docs
[rdf] generated hooks.json
[rdf] generated 3 governance files
[rdf] generated 3 rule files
[rdf] CC generation complete: 6 agents, 37 skills, 16 scripts, 3 rules, 7 reference docs
```

Output tree (before → after):

```
adapters/claude-code/output/            adapters/claude-code/output/
├── agents/                             ├── agents/
├── commands/                           ├── skills/
│   ├── r-start.md                      │   ├── r-start/
│   └── r-start.md.rdf-hash             │   │   ├── SKILL.md
├── scripts/                            │   │   └── SKILL.md.rdf-hash
├── reference/                          │   └── reference/*.md
├── governance/                         ├── scripts/
├── rules/                              ├── reference/
└── hooks.json                          ├── governance/
                                        ├── rules/
                                        └── hooks.json
```

Deploy on an existing 3.6.5 install:

```
$ bin/rdf deploy claude-code
[rdf] deploying Claude Code adapter to /home/u/.claude...
[rdf] replaced symlink: /home/u/.claude/agents -> .../output/agents
[rdf] replaced symlink: /home/u/.claude/scripts -> .../output/scripts
[rdf] replaced symlink: /home/u/.claude/governance -> .../output/governance
[rdf] replaced symlink: /home/u/.claude/reference -> .../output/reference
[rdf] skills: 37 linked, 0 pruned; reference linked (/home/u/.claude/skills/<name> -> .../output/skills/<name>)
[rdf] removed legacy commands symlink: /home/u/.claude/commands (skills supersede it)
[rdf] ... state helpers ...
[rdf] manual merge required: hooks.json (see 'rdf deploy help'; does not affect exit status)
[rdf] deploy complete: 51 items deployed
```

Failure case — a user-owned `~/.claude/skills/r-start` real directory:

```
$ bin/rdf deploy claude-code
[rdf] warning: /home/u/.claude/skills/r-start exists (not a symlink). Back it up and re-run, or use --force.
...
[rdf] warning: deploy complete: 50 deployed, 1 skipped (use --force to override)
$ echo $?
1
```

Consumer init with tools:

```
$ cd ~/src/flaskapp && rdf init --tools agent-skills,agents-md
[rdf] detected profiles: core, python
[rdf] ... governance written ...
[rdf] symlinked: /home/u/src/flaskapp/.agents/skills -> .../agent-skills/output/.agents/skills
[rdf] wrote AGENTS.md (composed from CLAUDE.md, 2,140 bytes)
$ rdf init --tools cursor
rdf: error: unknown --tools value: cursor (allowed: claude-code, agent-skills, agents-md, codex, antigravity)
$ echo $?
1
```

Plugin manifest delta:

```
-  "commands": "./adapters/claude-plugin/output/commands",
+  "skills": "./adapters/claude-plugin/output/skills",
```

Doctor doc-truth (§13):

```
$ bin/rdf doctor --scope doc-truth
[doc-truth]     [OK]   profiles: 14 dirs = 14 registry = README badge 14 = RDF.md tree 14
[doc-truth]     [OK]   tests: 24/24 tests/*.bats registered in tests/Makefile
[doc-truth]     [FAIL] WORKFORCE.md: r-plan claims dispatch of 'planner' but canonical/commands/r-plan.md never dispatches it
[doc-truth]     [OK]   CONTRIBUTING.md CI claims match .github/workflows/ci.yml
```

## 6. Conventions

- Library functions are `adp_*`, take every path as a parameter, and never
  read adapter globals. Filters are function names; `-` means none; the
  body is streamed `filter < src` (or `cat`), never rewritten on disk.
- Skill frontmatter is exactly:
  `---` / `name: <name>` / `description: >` / `  <one-line trigger>` / `---` /
  blank line / body. Agent frontmatter is unchanged from 3.6.5.
- Sidecar name: `<file>.rdf-hash` beside the emitted file (`SKILL.md.rdf-hash`).
- Deploy log verbs: `symlinked:` / `replaced symlink:` / `removed legacy` /
  `skills: N linked, M pruned; reference linked|skipped|absent` (the shared
  reference entry is linked but never counted as a skill); every skipped item increments
  `_DEPLOY_SKIPPED` (exit 1 contract from 3.6.5 stands).
- Doctor rows: `[scope] [OK|WARN|FAIL] message` through `_add_result`.
- Shell: `set -euo pipefail`, `command` coreutils prefix, bash 3.2 (no
  `mapfile -d`, no `declare -A` globals), same-line suppression comments on
  touched lines, one-line function headers.

## 7. Interface Contracts

| Surface | Before | After |
|---------|--------|-------|
| `rdf generate <target>` | claude-code, claude-plugin, gemini-cli, codex, agents-md, agent-skills, antigravity, all | same names; `codex` = composite; `agents-md [--project-root P]`; `all` runs cc, plugin, gemini, agents-md, agent-skills |
| `rdf deploy <target>` | claude-code, gemini-cli, codex, agent-skills | + `agents-md`, `antigravity`; `codex`/`antigravity` = skills symlink + AGENTS.md copy-skip; require `--project-root` |
| `rdf init --tools` | phantom | `claude-code|agent-skills|agents-md|codex|antigravity`, comma list; unknown → exit 1 |
| `rdf sync` | reads `output/commands` | reads `output/skills/*/SKILL.md` |
| `rdf doctor --scope` | 13 scopes | + `doc-truth` |
| cc output tree | `commands/` | `skills/<n>/SKILL.md` (+ sidecar), `skills/reference/` |
| plugin output tree | `commands/` | `skills/<n>/SKILL.md`, `skills/reference/` |
| plugin.json | `commands` | `skills` |
| `~/.claude` on symlink deploy | `commands` dir symlink | `skills/<n>` + `skills/reference` symlinks (38 entries); `commands` removed when RDF-owned |
| canonical/, hooks.json, agent-meta.json, skill-meta.json | — | unchanged |
| `RDF_TARGET` | honored for `~/.claude` surfaces | honored for skills too |

## 8. Migration Safety

**Upgrade (checkout, 3.6.5 → this).** `rdf generate claude-code && rdf deploy
claude-code`: the atomic swap replaces the output tree (the old `commands/`
disappears with it); deploy links skills, removes the now-dangling
`~/.claude/commands` symlink (target under RDF output), and leaves everything
else. Between generate and deploy, `~/.claude/commands` dangles for seconds —
identical to today's swap window. The deployed `~/.rdf/state/*.sh` are
symlinks into the checkout (3.6.4), so the overhead resolver updates in the
same step.

**Upgrade (plugin).** Plugin users receive the new tree on version bump;
skills replace commands under the same `/rdf:r-*` names (skill wins over a
same-name command; there is no same-name command in the new tree). The
bootstrap-delivered state helper copy is version-stamped and refreshed by
`state-bootstrap.sh` on the next SessionStart.

**Fresh install.** Quickstart unchanged in shape; `~/.claude/skills/` is
created as a real directory.

**Rollback.** `git checkout 3.6.5 && rdf generate claude-code && rdf deploy
claude-code` restores the `commands` symlink; the stale `~/.claude/skills/r-*`
symlinks then dangle (harmless, ignored) — the 3.6.5 deploy has no prune, so
the rollback note in CHANGELOG tells the user to `rm ~/.claude/skills/r-*`.

**Codex users.** `rdf generate codex` now needs no `~/.codex/config.toml`;
an existing file is left untouched (never written by us again).

**Test suite.** ~9 BATS files change assertions from `commands/x.md` to
`skills/x/SKILL.md`; two new files. Suite grows by roughly 25 tests.

**Uninstall.** N/A (RDF has no uninstall; `rdf deploy` help gains a
one-line "remove skills: `rm ~/.claude/skills/r-*`").

## 9. Dead Code and Cleanup

| Item | Evidence | Action |
|------|----------|--------|
| `_CC_COMMAND_META` / `command-meta-v3.json` | assigned `claude-code/adapter.sh:12`, never read | delete both |
| `command-map-v3.md` | referenced only by a 3.0 plan | delete |
| `adapters/agents-md/sections.json` + `_amd_extract_canonical_section` | replaced by composer | delete |
| `adapters/codex/` | composite supersedes; empty-governance defect | delete (+ `.gitignore` line, `deploy.sh` `_deploy_copy_skip` stays — reused by `_deploy_agents_md`) |
| `_cc_resolve_hash_cmd` re-probing what `rdf_hash_stdin` handles | `claude-code:19-27` | folded into `adp_require_hash_tool` (one copy) |
| `adapters/codex/.gitkeep` | goes with the codex directory | delete (other `.gitkeep`s sit in non-output dirs and stay) |
| `docs/multi-tool-parity.md:18` "commands ARE skills natively" | superseded | rewrite row |

## 10a. Test Strategy

| Goal | Test file | Test description |
|------|-----------|------------------|
| 1 | `tests/adapter-common.bats` | `@test "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture"`, `"adp_stage_commit rotates .old and leaves no staging dirs"`, `"adp_emit_skills applies the filter to body and description"`, `"no adapter except gemini defines output_old"` |
| 2 | `tests/adapter.bats`, `tests/plugin-adapter.bats`, `tests/rdf-lite.bats` | `"generator writes skills/<n>/SKILL.md for every canonical command and no commands/"`, `"SKILL.md body equals canonical body after frontmatter strip"`, `"sidecar hash matches canonical"`, `"plugin skills carry /rdf: rewrite in body and description"`, `"lite emits exactly the six lifecycle skills"`, `"agent-skills still emits only skill-meta keys"` |
| 3 | `tests/deploy.bats` | `"deploy links each skill as its own symlink"`, `"deploy prunes an RDF-owned skill symlink whose target vanished"`, `"deploy removes a legacy commands symlink into RDF output"`, `"deploy leaves a foreign ~/.claude/commands symlink alone"`, `"deploy skips a user-owned real skill dir and exits 1"`, `"RDF_TARGET applies to skills"` |
| 4 | `tests/doctor.bats`, `tests/sync.bats`, `tests/overhead.bats`, `tests/state-injection.bats` | `"content-drift FAILs on a corrupted SKILL.md and WARNs when skills/ is absent"`, `"sync-health checks per-skill links and warns on lingering commands link"`, `"install-mode detects symlink deploy via skills"`, `"sync pulls an edited SKILL.md back to canonical/commands"`, `"sync warns when output/skills is missing"`, `"overhead resolves the checkout via the agents symlink"`, `"context-audit counts skills"` |
| 5 | `tests/plugin-adapter.bats` | `"plugin.json has skills path, no commands key, and the path exists"`, `"plugin tree has no .rdf-hash"`; CI: `claude plugin validate . --strict` + skills dir validate |
| 6 | `tests/deploy.bats`, `tests/adapter.bats` | `"generate codex emits .agents/skills and AGENTS.md"`, `"deploy codex symlinks skills and copy-skips AGENTS.md"`, `"adapters/codex does not exist"` |
| 7 | `tests/agent-skills.bats`, `tests/derfxn.bats` | `"agents-md composes from a project CLAUDE.md"`, `"agents-md falls back to governance index then stub"`, `"consumer AGENTS.md contains no rfxn identifiers"`, `"self AGENTS.md regenerates byte-identical (tracked output)"` |
| 8 | `tests/cmd-migrate-init.bats` | `"init --tools unknown exits 1 with the allowed list"`, `"init --tools agent-skills,agents-md writes both artifacts"`, `"init --tools codex expands to the composite"`, `"init --dry-run --tools prints would-write lines"` |
| 9 | `tests/doc-truth.bats` | `"FAILs when README badge profile count drifts"`, `"FAILs when a tests/*.bats file is missing from the Makefile"`, `"FAILs when WORKFORCE claims a dispatch the command body lacks"`, `"FAILs when CONTRIBUTING claims a CI step ci.yml lacks"`, `"passes on the live repo"` |
| 10 | `tests/doc-truth.bats`, `tests/doctor.bats:79` | `"WORKFORCE.md has no planner dispatch claim"`, doc-stats live pass |

## 10b. Verification Commands

```bash
grep -c 'output_old' adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh
# expect: 0 for each
wc -l adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh | tail -1
# expect: total ≤ 430
bin/rdf generate claude-code >/dev/null && ls adapters/claude-code/output/skills | wc -l && test ! -d adapters/claude-code/output/commands && echo no-commands
# expect: 38 (37 skills + reference), no-commands
source lib/rdf_common.sh; for d in adapters/claude-code/output/skills/r-*/; do n=$(basename "$d"); diff <(rdf_strip_frontmatter "$d/SKILL.md") canonical/commands/"$n".md >/dev/null || echo "DRIFT $n"; done
# expect: no DRIFT lines (rdf_strip_frontmatter is the one strip implementation — lib/rdf_common.sh:90-98)
jq -r '.skills, (.commands // "absent")' .claude-plugin/plugin.json
# expect: ./adapters/claude-plugin/output/skills, absent
claude plugin validate . --strict | tail -1
# expect: ✔ Validation passed
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && bin/rdf deploy claude-code | grep -c 'skills: 37 linked'
# expect: 1
ls -la "$HOME/.claude/skills" | grep -c ' -> '
# expect: 38
mv adapters/claude-code/output/skills /tmp/skills.bak && bin/rdf sync --dry-run 2>&1 | grep -c 'no skills tree'; mv /tmp/skills.bak adapters/claude-code/output/skills
# expect: 1   (Goal 4 fail-closed: sync warns instead of iterating an empty glob)
bin/rdf doctor --scope content-drift 2>&1 | grep -c 'skills/'
# expect: ≥ 1 (content-drift reports skills rows; with the tree moved away it reports 'no skills tree' WARN)
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && bin/rdf deploy claude-code >/dev/null; bash state/rdf-overhead.sh 2>&1 | grep -c 'no ~/.claude/agents symlink'
# expect: 0   (resolver follows the agents symlink; the warning text names agents, not commands)
bash state/context-audit.sh . | jq '.skills.deployed.count'
# expect: 37
test ! -d adapters/codex && echo codex-gone
# expect: codex-gone
test -f docs/context-bar.md && ! test -f context-bar.md && grep -c 'docs/context-bar.md' README.md
# expect: 1   (Goal 10 relocation + README docs-table link)
grep -c 'planner' WORKFORCE.md; grep -cE '^\| r-start \|.*dispatcher' WORKFORCE.md
# expect: ≥ 1 (planner described as inline/direct-dispatch) / 0 (no r-start → dispatcher row)
bin/rdf generate agents-md >/dev/null && grep -c 'rfxn ecosystem\|CentOS 6' adapters/agents-md/output/AGENTS.md
# expect: 0
bin/rdf init --tools cursor /tmp/x 2>&1 | tail -1; echo $?
# expect: rdf: error: unknown --tools value: cursor ... / 1
bin/rdf doctor --scope doc-truth | grep -c FAIL
# expect: 0
bin/rdf doctor | tail -1
# expect: ... 0 FAIL
make -C tests test 2>&1 | tail -3
# expect: all ok, 0 not ok
```

## 11. Risks

1. **Overhead resolver breaks for plugin-tier users with an old bootstrap
   copy.** Mitigation: the resolver falls back to the `.rdf-source` stamp as
   today; `state-bootstrap.sh` refreshes the copy on the next session; test
   pins both paths.
2. **A user already has `~/.claude/skills/` with their own skills.**
   Mitigation: per-skill symlinks only; a real `~/.claude/skills` dir is
   reused, never replaced; name collisions skip with exit 1 (existing
   contract).
3. **Removing `~/.claude/commands` deletes a user's own commands.**
   Mitigation: removal only when the symlink target canonicalizes under
   `${RDF_HOME}/adapters/claude-code/output/`; real dirs and foreign
   symlinks untouched; tested both ways.
4. **Plugin `skills` key not honored at runtime despite validator
   acceptance.** Mitigation: plugins-reference documents `skills` as
   `string|array` relative to the plugin root; probe 2026-09-02 (Claude Code
   2.1.258) validated a manifest carrying it; post-ship smoke: install from
   the marketplace and `/rdf:r-status` in a fresh session before tagging.
5. **CI drift diff on committed plugin output.** The plugin output tree is
   tracked; the migration commit must include the regenerated tree, and CI's
   `git diff --exit-code` guards subsequent drift. Mitigation: phase gate
   runs `rdf generate claude-plugin && git status --porcelain
   adapters/claude-plugin/output` → empty.
6. **Byte-identity regressions from the extraction.** Mitigation: phase 1
   captures 3.6.5 output for agents/scripts/reference into test fixtures and
   asserts identity after the lib swap, before any layout change.
7. **`rdf sync` reverse-flow no-op after the layout change.** Mitigation:
   explicit WARN when `output/skills` is absent; test asserts the WARN text.
8. **Description with a colon or quote breaks YAML.** Same risk as today's
   frontmatter; skill-meta triggers are curated; `claude plugin validate`
   on the skills dir runs in CI and fails on unparsable frontmatter (probed).
9. **`--tools` writes into a repo that already has AGENTS.md.**
   Mitigation: copy-skip semantics (like SECURITY.md); logged.
10. **Reach-spec contract tests assert "commands stay commands".**
    Mitigation: `tests/governance-contracts.bats:150-156` asserts canonical
    has no frontmatter — unchanged; no contract asserts the output layout.
    Grep at plan time for `commands/` in contracts.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|----------|
| `~/.claude/skills/r-start` exists as a real dir | skip + exit 1 | `_deploy_symlink` existing contract |
| `~/.claude/commands` is a real directory of user commands | untouched, one notice line | `_deploy_prune_legacy_commands` checks `-L` + target prefix |
| `~/.claude/commands` symlink points to a foreign tree | untouched, notice | same |
| Canonical command removed after a deploy | its `~/.claude/skills/<n>` symlink dangles | prune loop removes RDF-owned dangling links; doctor sync WARNs if any remain |
| `output/skills` absent (generate not run) | deploy dies "run rdf generate"; sync/doctor WARN, not silent | preflight + explicit WARN rows |
| `RDF_TARGET` set | skills link under `$RDF_TARGET/skills` | same var as dir surfaces |
| `--lite` | six skills + reference only; hooks skipped | `adp_names_lite` |
| skill-meta key without canonical file | warn + skip (agent-skills), doctor catalogs FAIL | existing behavior retained in lib |
| Two symlink levels (`~/.claude` itself a symlink, as on the dev box) | works; `rdf_canonical_path` compares resolved paths | existing helper |
| Project has no CLAUDE.md and no governance index | AGENTS.md = header + stub + roster; WARN | `_amd_context_source` empty branch |
| `rdf init --tools agents-md` on a repo with AGENTS.md | skip with log | copy-skip |
| `rdf init --tools ""` | error (empty token) | validator |
| `rdf generate all` | codex no longer listed; exit 0 | `all` branch updated |
| Plugin install + symlink deploy on the same machine | duplicate `/r-*` and `/rdf:r-*` as today; advisory stays | unchanged warning text updated to say skills |
| macOS bash 3.2 | no arrays of names via `mapfile`; while-read loops | CI macOS leg |

## 12. Open Questions

None. (Product calls already taken 2026-09-02: cut over rather than dual
surface; codex → composite rather than freeze; all 37 commands migrate.)

## 13. Companion scope — mechanical doc truth (quick-plan tier)

Ryan selected "make doc truth mechanical" alongside this work; it ships in
the same plan as trailing phases so one sentinel and one release cover both.
Evidence (2026-09-02 audit, re-verified at `5069a4c`): README badge says 11
profiles, `RDF.md:224` says 11, `registry.json` has 13, `profiles/` has 14
dirs; `WORKFORCE.md:16,41,51` claim `/r-plan` dispatches a `planner`
subagent on opus — no command dispatches `rdf-planner`
(`grep -rn 'rdf-planner' canonical/commands` → 0); `WORKFORCE.md:13` vs
`:129` contradict on `/r-start`; `CONTRIBUTING.md:52-53` claims CI runs
doctor and shellcheck on macOS (only BATS does); `tiers.md:40-41` states the
effective gate set as `min(scope_gate, tier_cap)` while `:57` states
`max(security_floor, min(scope_gate, tier_cap))` — the first omits the floor.
The `tests/derfxn.bats` Makefile/CI gap found by the audit was closed by
`5069a4c` (and `tests/governance-contracts.bats:160` now guards that class in
CI); the doctor `test wiring` row below is the operator-facing runtime
counterpart and its FAIL path is exercised with a fixture, not the live repo.

### Design

`_check_doc_truth` in `lib/cmd/doctor.sh` (new scope `doc-truth`, ~120
lines) emits one row per claim class:

| Claim | Source of truth | Checked surfaces | Result |
|-------|-----------------|------------------|--------|
| profile count | `profiles/*/governance-template.md` dirs (excludes `lite`) and `registry.json` `.profiles \| length` | README `profiles-N` badge, `RDF.md` "N profiles"/tree entries, `docs/index.md` | FAIL on any mismatch |
| adapter count | `adapters/*/adapter.sh` | README `adapters-N` badge, footer, `docs/index.md` | FAIL |
| test wiring | `tests/*.bats` | every basename present in `tests/Makefile` | FAIL per missing file |
| dispatch claims | `WORKFORCE.md` rows **inside the `### Lifecycle Commands` section only** (from that heading to the next `^###`), matching the 4-column shape `^\| (r-[a-z-]+) \| /r-[a-z-]+ \| ([^|]*) \| [^|]+\|$` — the third cell split on `,`, each token stripped of whitespace, `*`, and a parenthesised annotation; `--`, `—`, `none`, or empty = claims nothing (the live table uses `--`, 12 rows) | for every token `a`: `grep -qE "\brdf-${a}\b|\b${a}[[:space:]]+agent\b" canonical/commands/<cmd>.md` | FAIL per false claim; a command file that dispatches an agent the row omits is a WARN (under-claim) |
| CI claims | `CONTRIBUTING.md` "CI runs" bullet list (backticked commands) | each appears in `.github/workflows/ci.yml` | FAIL per missing |

`doc-stats` (counts in README footer, WORKFORCE totals, index) is unchanged;
`doc-truth` is additive. Live-repo fixes in the same phase: badges,
`RDF.md` profile tree (+ lite, node, rfxn-workspace), `WORKFORCE.md`
(planner runs inline in `/r-spec`/`/r-plan` and is available for direct
dispatch; `/r-start` dispatches nothing), `CONTRIBUTING.md` CI paragraph,
`ROADMAP.md` "built-in 11" → derived wording, `context-bar.md` →
`docs/context-bar.md` + README docs-table link, `canonical/reference/tiers.md:41`
formula restated with the security floor (the spike spec's D3 contracts
assert the full formula in both restating files). `tests/doc-truth.bats`
covers each FAIL path with fixtures and one live-repo pass.
