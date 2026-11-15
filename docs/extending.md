---
title: Extending RDF
parent: Project
nav_order: 2
description: "Add a slash command, agent, governance profile or tool adapter to RDF, working from canonical sources."
---

# Extending RDF
{: .no_toc }

All content starts in `canonical/`. Never edit generated output, because
`rdf generate` overwrites it.

1. TOC
{:toc}

## Add a command

1. Create `canonical/commands/<name>.md` as pure markdown with no frontmatter.
2. Run `rdf generate claude-code && rdf deploy claude-code`. A new command needs the
   deploy step, because each skill is its own symlink.
3. Add it to [`docs/commands.md`](commands.md). `rdf doctor` fails until you do.
4. Update the counts in `WORKFORCE.md`, `RDF.md`, `canonical/reference/framework.md`,
   `docs/index.md` and the README banner. `rdf doctor` reports each one that drifted.

Commands use `/r-<name>` for lifecycle work and `/r-util-<subject>-<verb>` for
utilities.

## Add an agent

1. Create `canonical/agents/<name>.md`.
2. Add its metadata to `adapters/claude-code/agent-meta.json`:

   ```json
   "<name>": {
     "name": "rdf-<name>",
     "description": "...",
     "tools": ["Bash", "Read", "Glob", "Grep"],
     "model": "opus",
     "effort": "medium"
   }
   ```

3. Run `rdf generate claude-code` and check the frontmatter.

`model` is a Claude Code alias (`opus`, `sonnet`, `haiku`, `fable`, `inherit`) or a
`claude-*` id, and `effort` is `low` through `max`. An optional
`"variants": {"<key>": {"effort": "...", "description": "..."}}` emits
`rdf-<name>-<key>` from the same body at a different effort.

## Add a profile

1. Add an entry to `profiles/registry.json` and `profiles/registry.md`.
2. Create `profiles/<name>/governance-template.md` and a `reference/` directory.
3. Add detection rules to `profiles/detection-rules.md`.
4. Add the name to `_KNOWN_PROFILES` and a detection branch to `_detect_profiles` in
   `lib/cmd/init.sh`. `rdf init` reads those, not `detection-rules.md`.
5. Run `rdf profile install <name>`, then `rdf generate claude-code`.

## Add an adapter

1. Create `adapters/<tool>/adapter.sh` implementing `<prefix>_generate_all()`.
2. Add a case branch in `lib/cmd/generate.sh`.
3. Use `adapters/claude-code/adapter.sh` as your reference.

An adapter reads from `${RDF_CANONICAL}` and writes to its own `output/`. It never
modifies canonical.

## Onboard a project

```bash
rdf init /path/to/project --type shell --github
```

This creates `CLAUDE.md` from the governance template, `MEMORY.md` and the
`.git/info/exclude` entries, plus GitHub labels and a project board with `--github`.

## Before you open a PR

See [CONTRIBUTING.md](https://github.com/rfxn/rdf/blob/main/CONTRIBUTING.md) for shell
standards, tests and the commit format.
