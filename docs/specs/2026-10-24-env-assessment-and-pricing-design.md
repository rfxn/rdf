# Environment Assessment and Sourced Pricing

Status: built (challenge review answered in §8). Scope: one release.

## 1. Problem

1. RDF's only price table (`state/rdf-tokens.sh` `_tok_prices`, dated 2026-09-23)
   was incomplete and partly wrong: Claude Sonnet 5.5 was absent, so the
   longest-prefix lookup priced it as Sonnet 5 (cache reads $0.20, actual
   $0.10); Opus 4.5-4.7, Sonnet 4.x, Haiku 5.5, Mythos and retired models were
   absent; Haiku 5.5's over-100K prompt tier, fast mode (`usage.speed`) and US
   data residency (`usage.inference_geo`) were ignored. It cited no source.
2. Codex is a first-class deploy target, but nothing priced Codex usage. This
   host has ~885 Codex rollouts whose records carry per-response token counts.
3. Nothing told an operator that their environment lacks the pieces that make
   Claude Code cheaper or more capable (a code intelligence plugin and its
   language server, project tools, an adequate fd limit, sandbox dependencies,
   a current Claude Code). `rdf doctor --scope harness` covered routing knobs
   only, and its `BASH_MAX_OUTPUT_LENGTH` warning was wrong: since v2.1.261
   that variable sizes only the read-back window; `bashOutputMaxChars` sizes
   inline output.

## 2. Goals, non-goals, and the behavior each surface changes

- G1 Sourced, dated prices for every model RDF meets, one source of truth.
  Observable: `rdf tokens` totals match the vendors' list prices; unknown
  models show as unpriced instead of borrowing a sibling's price.
- G2 `rdf tokens --codex` reports Codex spend in the same report shapes.
  Observable: Codex sessions appear with model, Fast/Standard tier and cost.
- G3 `/r-start` names the missing pieces of an optimal environment in one
  segment of its existing warnings line, offline. Observable: a project with
  no language server for its primary language gets the fix in front of the
  operator at session start.
- G4 `/r-env` is the full read-only report with exact fixes; plain
  `rdf doctor` runs the assessment offline as its `env` scope. Observable:
  operators install the language server and plugin, raise a low hard fd limit,
  or update Claude Code from a concrete command.

Non-goals: installing anything or editing settings; scraping pricing pages in
shell; modeling subscription billing (reports stay API list-price
equivalents); Batch/Flex pricing (interactive tools never use them); an
`rdf env` CLI (doctor's scope and the state helper cover both call paths).

## 3. Pricing

`_tok_prices` in `state/rdf-tokens.sh` is one embedded JSON document (state
helpers ship by the `state/*.sh` glob, so a data file would not reach plugin
installs): `as_of`, `sources` (Anthropic and OpenAI pricing pages, Codex plans),
`anthropic`, `openai_long_over` (272000) and `openai`.

- Anthropic rows carry explicit `in`/`out`/`cw5`/`cw1h`/`cr` (cache-read
  multipliers differ: 0.025x Fable 5.1 and Mythos 5.1, 0.05x Opus 5.5 and
  Sonnet 5.5, 0.1x others), plus `long` (Haiku 5.5, over 100K prompt tokens
  counting cache reads and writes), `fast` (Opus 5.5, Opus 5, Opus 4.8; cache
  classes keep the model's own ratios on top of the fast input price) and
  `residency` (Claude 4.6+, 1.1x on `inference_geo: us`). One effective rate per
  turn, in the order long, fast, residency, feeds every cost class and the
  cache-rebuild extra.
- OpenAI rows: Standard rates (input, cached input, 30-minute cache write,
  output), `long` (over 272K input tokens, per request), `fast` (with its own
  `long`) and `until` for promotional prices (GPT-5.6 Sol through 2026-11-21).
  `gpt-5.3-codex` comes from the Codex group (no cache-write price: billed at
  input).
- Key match: the exact id, or the id plus a date (`-YYYYMMDD` or
  `-YYYY-MM-DD`), `@version` or `-vN` suffix; `[1m]` is stripped first.
  Implemented without jq regex builtins (jq 1.5 floor).
- `rdf tokens --pricing [--json]` prints the table with `as_of`, `age_days`,
  `expires` (earliest `until`) and the sources. Refresh is a reviewed edit:
  `/r-env --pricing` fetches the `.md` variants of both pages and lists the
  differences; the maintainer updates `_tok_prices` and `as_of`.

## 4. Codex usage (`rdf tokens --codex`)

- Root `${CODEX_HOME:-$HOME/.codex}/sessions`, files `rollout-*.jsonl`,
  mtime-prefiltered, then a `grep -F` pre-filter on the project cwd (or on the
  session id and `parent_thread_id`) before any JSON parse.
- A rollout's identity is its first `session_meta` (a spawned thread repeats
  its parent's after its own). Scope: `cwd` is the project path (logical or
  physical) or below it with a path boundary; `--session ID` takes the rollout
  with that id and the threads it spawned.
- Rows: `token_usage_record.payload.usage` per response, deduplicated by
  `response_id` across rollouts (its sum equals the final `token_count` total;
  verified on real rollouts). Rollouts without records fall back to
  differences of cumulative `token_count.total_token_usage` (a dropped total is
  a reset). Each row takes the model and tier of the latest `turn_context` /
  `event_msg thread_settings_applied`; `service_tier` `priority` or `fast`
  prices at Fast. A rollout with no model reports `unknown` (unpriced).
- Semantics: cached and cache-write tokens are subsets of `input_tokens`,
  reasoning of `output_tokens` (`total_tokens == input + output`). The 272K
  long rate applies only to per-response rows; a delta may sum requests.
- Output: sessions (main rollouts), subagent_runs (thread-spawn and review
  rollouts), api_turns, tokens, cost, shares, `by_model` by model and tier,
  unpriced models; same text / `--json` / `--summary` shapes, labeled Codex.
- Known gaps: the cache-write TTL Codex uses is not recorded (priced at the
  30-minute rate; every write seen so far was zero); web search calls are not
  priced; Codex scope includes subdirectories while Claude's is the exact
  project slug. The rollout format is undocumented and pinned by tests.

## 5. Environment assessment

### 5.1 Helper `state/rdf-env.sh`

`rdf-env.sh [--brief] [--json] [--offline] [--project-only] [--tool claude|codex|gemini] [project]`,
bash 3.2+, jq 1.5+, read-only, no cache file. JSON: `schema`, `mode`, `tool`,
`summary` (gap, warn, info, ignored), `findings` (`id`, `area`, `severity`,
`title`, `why`, `fix[]`), `facts`. Severity `gap` is a missing piece of the
optimal setup, `warn` a risk, `info` context; findings never change the exit
status. The tool comes from `CLAUDECODE=1`, `GEMINI_CLI` or `CODEX_SANDBOX*`,
else claude; Claude Code plugin checks run only for claude.

### 5.2 Checks and their evidence

| Area | Check | Mode | Severity | Evidence |
|---|---|---|---|---|
| code-intel | per primary language: language server on PATH, official plugin installed in the active config dir and enabled in the merged settings (user, project, local, managed) | brief | gap | code-intelligence.md; costs.md |
| code-intel | primary-language plugin missing from another RDF account | full | info | plugins install per config dir |
| tools | git present and >= 2.23 | brief | gap | `rdf-bus.sh` scope guard |
| tools | shellcheck for shell projects; bats unless `tests/infra` or `tests/Dockerfile` supplies a container harness; gh when origin is GitHub | brief | gap | RDF verification and rituals |
| limits | hard `nofile` < 4096 | brief | warn | Claude Code raises its soft limit to the hard one; changelog fd-exhaustion fixes |
| limits | `nproc` < 2048 | full | warn | subagents, tests and servers fork |
| claude | version behind the dist-tag of the configured `autoUpdatesChannel` | full, online | info | — |
| claude | `claude doctor` reports issues | full, online | warn | setup.md |
| config | settings parse; knob values; env variable names only; MCP server counts only | full | warn on parse error | privacy allowlist |
| config | `BASH_MAX_OUTPUT_LENGTH` > 30000 without `bashOutputMaxChars` | full | info | env-vars.md, tools-reference.md |
| config | `USE_BUILTIN_RIPGREP=0` without a system rg | full | warn | troubleshooting.md |
| config | CLAUDE.md files: > 200 lines info, > 4 MiB warn | full | info/warn | memory.md |
| config | auto-memory `MEMORY.md` > 200 lines or > 25 KB | full | warn | memory.md load limit |
| config | transcript disk use when `cleanupPeriodDays` > 90 | full | info | — |
| sandbox | Linux bwrap + socat (warn when `sandbox.enabled`), Ubuntu userns restriction | full | info/warn | sandboxing.md |
| system | RAM < 4 GB; free disk < 1 GB under HOME or the tmp dir | full | warn | setup.md; changelog disk-full fixes |
| tools | python3, ctags (TypeScript/C projects), node/npm when an npm-installed server is missing | full | info/gap | RDF helpers and code-map |
| codex | installed version behind npm latest | full, online | info | — |
| pricing | promotional price ended (warn), table > 90 days (warn), > 45 days (info) | full | warn/info | — |

Languages: manifest markers at depth <= 2 (`tsconfig.json`/`package.json`,
`pyproject.toml`/`setup.py`/`setup.cfg`/`requirements.txt`/`Pipfile`, `go.mod`,
`Cargo.toml`, `composer.json`, `pom.xml`/`build.gradle(.kts)`, `Gemfile`,
`Package.swift`, `*.csproj`/`*.sln`, `CMakeLists.txt`/`meson.build`/`compile_commands.json`,
`.luarc.json`) plus file counts from `git ls-files` (or a pruned `find` outside
git). Samples, fixtures, docs, examples, vendored, build, scratch and
`.gitattributes` `linguist-vendored`/`linguist-generated` paths never count. A
language is primary with a marker and >= 3 files, or, in a git repository only,
>= 50 files (shell >= 10).

Fixes come from a package map verified on 2026-10-24 against the dnf
(Fedora 40), Debian stable, Ubuntu noble (Launchpad), Homebrew, Alpine edge and
Arch indexes (EPEL noted for RHEL-family; Ubuntu noble has no rust-analyzer
package, so rust-analyzer uses `rustup`), and from each plugin README for
language servers. Plugin fixes use `claude plugin install|enable`, prefixed
with `CLAUDE_CONFIG_DIR=` for a non-default account.

Ignore list: finding ids in `~/.rdf/env-ignore` or `<project>/.rdf/env-ignore`
drop out of the counts (reported as `ignored`).

### 5.3 Integration

- `rdf-state.sh --full --env` (single-project `/r-start` only) embeds
  `{gap, warn, ignored, top[0..1]}` from `rdf-env.sh --brief --json`, under a
  5 s timeout where `timeout` exists, validated with jq before embedding;
  absent or failing helper gives `null`. Measured: about 0.2 s added.
- `/r-start` renders `Env {N} to fix: {title}; {title} — /r-env` inside its
  existing warnings line.
- `/r-env` runs the full helper once, adds the pricing comparison when asked or
  stale, renders a scorecard, findings with fixes, an optimal-setup checklist
  and a facts footer, and offers fixes without applying any.
- `rdf doctor`: `env` scope in the default set and as `--scope env`; offline;
  machine-wide checks run for the first project of an `--all` run only; gaps
  and warnings map to WARN, info is omitted, never FAIL; config and pricing
  findings stay with the memory/harness scopes and `/r-env`.
- `rdf doctor --scope harness`: only `bashOutputMaxChars` > 30000 warns;
  `BASH_MAX_OUTPUT_LENGTH` > 30000 is OK, "read-back window only".

## 6. Compatibility and risk

- bash 3.2 / 4.1: no associative arrays, `mapfile`, `${v,,}`; jq 1.5: no
  regex builtins, `--args` or `$ENV`.
- Brief: 0.14-0.4 s on this host's projects (no network, no `claude doctor`).
- Network only in full online mode, 5 s timeouts; failures degrade to unknown.
- Existing `rdf tokens` fixture expectations stay byte-identical; only
  real-world totals that include newly priced models move.

## 7. Tests

`tokens.bats`: Sonnet 5.5, Haiku 5.5 long tier, fast and residency, unpriced
newer ids, `--pricing --json`; Codex deltas, model switch and reset, cwd scope
against a sibling prefix, window baseline, per-response records with dedup,
Fast and long tiers, subagent and review rollouts, `--session` with children,
argument errors. `env.bats` (hermetic PATH): gap, enabled and disabled plugin,
language detection exclusions and the non-git marker rule, shell tools and the
container harness, tool gating and the ignore list, hard versus soft fd limit,
offline making no network or doctor call, channel-aware version info and
doctor issues, pricing expiry, memory index and the settings allowlist,
argument errors, the `rdf-state.sh --env` embed. `doctor.bats`: the Bash output
row, the env scope's filtering, first-project-only machine checks and failure
handling. Targeted mutants were run against each rule and killed.

## 8. Challenge review responses

| Finding | Response |
|---|---|
| M1 Codex records `service_tier: priority` | Accepted: tier tracked per row from `thread_settings_applied`; OpenAI rows carry Fast rates; `by_model` splits by tier |
| M2 prefix matching misprices dotted OpenAI ids | Accepted as a key-boundary rule (§3); `gpt-5.1-codex-max` reports unpriced; the reviewer's "≈ priced as X" fallback was declined: unpriced is visible, an approximation would be silent |
| M3 soft fd limit is the wrong measurement | Accepted: the hard limit is checked; the test separates soft from hard |
| M4 raw extensions give false gaps | Accepted: manifest markers, excluded paths, `.gitattributes`, the non-git rule and the ignore list (§5.2) |
| S1 per-response records | Accepted as primary source; deltas are the fallback |
| S2 subagent rollouts and cwd boundary | Accepted: first `session_meta`, subagent runs, `--session` children, boundary test. Filename lookup declined: rollout file names do not always carry the session id |
| S3 OpenAI long context and promotions | Accepted: `long` over 272K per request, `until` and `expires` |
| S4 one effective rate | Already so; the rebuild extra uses the effective cache-read rate |
| S5 fixture expectations | Accepted: unchanged and passing |
| S6 /r-start cost | Accepted: version lag and pricing left brief; `--env` gate; summary-only embed; validated JSON; 5 s cap where `timeout` exists |
| S7 which config dir | Accepted: active dir install plus merged enablement including managed settings |
| S8 overlap and surface | Accepted: doctor's env scope skips config and pricing; no `rdf env` CLI. The auto-memory index check stays in `/r-env`: doctor's memory scope reads the project's own `MEMORY.md`, a different file |
| S9 machine checks per project | Accepted: first project only; offline omits `claude doctor` |
| S10 privacy | Accepted: allowlisted facts, no cache file, npm GET carries no identifiers, `.md` pricing pages, privacy.md updated |
| S11 brief noise | Accepted: ignore list, container-harness rule for bats, pricing and jq out of brief |
| S12 delivery | Accepted: command, skill metadata, counts, docs; Codex/Gemini skip plugin checks |
| CONSIDER items | Web search pricing, cache-write TTL and scope differences documented (§4); inotify reported as a fact only; disk threshold 1 GB; `residency` kept as a precise per-model flag; el7 git noted in the fix text |
