# Multi-Tool Parity

RDF emits governance, commands, and skills for several AI coding tools from one
canonical source. Reach (Wave 2) recasts the tool set around **three first-class
citizens** — Claude Code, Codex CLI, and Antigravity CLI — plus **one frozen
legacy tier**, Gemini CLI (enterprise). Design rationale lives in
`docs/specs/2026-07-15-scale-reach-design.md` §13.

## 1. Matrix

| Tool | Command surface | Skill surface (`.agents/skills/`) | Context file | Hooks | Generate target |
|------|-----------------|-----------------------------------|--------------|-------|-----------------|
| Claude Code | `.claude/commands/*.md` + intent `description:` frontmatter | commands ARE skills natively | `CLAUDE.md` (NOT AGENTS.md) | `hooks.json` (manual merge) | `claude-code` |
| Codex CLI | `.agents/skills/<cmd>/SKILL.md` (native scan) | shared `.agents/skills/` | own `AGENTS.md` (codex adapter) | deferred (`openai.yaml`, §13.7) | `codex` |
| Antigravity CLI | skills (fuzzy-matched slash) | shared `.agents/skills/` | `AGENTS.md` + `GEMINI.md` | deferred (`.agents/hooks.json`, §13.7) | `antigravity` (composite) |
| Gemini CLI (enterprise) | `.gemini/commands/*.toml` | via `agy plugin import gemini` | `GEMINI.md` | — | `gemini-cli` |

Tiers: the first three rows are first-class; Gemini CLI is **legacy / frozen**
(kept for enterprise paid-API users, changed only for the TOML-escaping fix).

## 2. The `.agents/skills/` shared convention

`.agents/skills/` is a **workspace-level shared directory** at the repo root —
one tree that Codex, Antigravity, and every AAIF-compliant client read. Because
it is shared, it is emitted exactly **once** by a dedicated adapter:

```
rdf generate agent-skills     # emits .agents/skills/<cmd>/SKILL.md
```

It is NOT duplicated into per-tool output trees. Each emitted `SKILL.md` carries
`name` + `description` frontmatter only (`name` equals the command basename and
the parent directory name, per the AAIF constraint); optional AAIF fields
(`license`, `metadata`, `allowed-tools`) are deliberately not emitted (§13.4).

Deploy is per-artifact, into a workspace root:

```
rdf deploy --project-root /path/to/workspace agent-skills
```

This symlinks `.agents/skills/` into the target workspace so `rdf generate
agent-skills` updates deployed skills in place (mirrors the Codex
`--project-root` pattern). There is deliberately **no `rdf deploy
antigravity`** target: `rdf generate antigravity` is a composite (skills +
`AGENTS.md`), but a composite deploy would only duplicate the `agent-skills`
`--project-root` path for no gain, and `AGENTS.md`/`GEMINI.md` are workspace
files the user places directly. Generate is a composite; deploy stays
per-artifact (§13.4).

## 3. Gemini `{{args}}` lossy edge

Gemini CLI command TOML uses `{{args}}` token substitution. RDF commands that
read their argument via `$ARGUMENTS` are translated and carry a NOTE in the
emitted TOML. Positional invocation forms are **not** tokenized: a command
invoked as `/r-build 3` receives the raw `3` and is not rewritten to a
`{{args}}` placeholder. Commands whose canonical body relies on positional
arguments therefore lose that argument on the Gemini surface — the NOTE flags
this so a Gemini CLI user knows to pass the argument through the `{{args}}`
form instead.

## 4. Legacy gemini-cli tier

Gemini CLI stopped serving free/Pro/Ultra tiers on 2026-06-18; enterprise and
paid-API users are unaffected and the OSS repo stays active. RDF keeps the
`gemini-cli` adapter **frozen** for those users: its `GEMINI.md` context and
command TOML are unchanged except the one TOML-escaping fix.

- **TOML `'''`-literal fix.** The canonical command body contains characters
  that basic TOML strings (`"..."`, `"""..."""`) interpret as escapes (regex
  `\b`, sed `\|`). Emitting those bodies into `'''`-literal multi-line strings —
  which do **not** process backslash escapes — makes the output parse strictly.
- **Migration source.** `agy plugin import gemini` converts
  `.gemini/commands/*.toml` INTO Antigravity skills, so strictly-valid TOML is
  the migration source. Fixing the escaping directly serves Antigravity
  adoption — a frozen legacy artifact that doubles as the transition input.

## 5. Deferred surfaces (probe-gated)

The following ship only after a live-docs probe confirms a stable schema, per
the audit lesson that runtime-observed facts get an engineer-validation pass
before code. Cross-reference spec §13.7:

- Antigravity hooks (`<workspace>/.agents/hooks.json`) — schema undocumented.
- Antigravity subagents (markdown) — schema actively churning.
- Antigravity plugins (`~/.gemini/antigravity-cli/plugins/<name>/plugin.json`).
- Codex `agents/openai.yaml` per-skill metadata — Codex-specific, optional.
- Global/user-level `~/.agents/skills/` scanning — unverified.
- SKILL.md optional AAIF fields (`license`, `metadata`, `allowed-tools`).
- MCP server work — a standing §3 non-goal.
