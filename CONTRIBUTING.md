# Contributing to RDF

Thanks for your interest in RDF (rfxn Development Framework). Contributions —
bug fixes, portability hardening, new adapters, documentation — are welcome.
This guide covers the one thing that trips up first-time contributors: RDF has
a **canonical → generated** architecture, so *where* you edit matters.

## Where to make changes

RDF is tool-agnostic. Agent and command content is authored once as pure
markdown and deployed to each harness (Claude Code, Gemini CLI, Codex, …) by a
generator. There are two kinds of source:

| You want to change… | Edit here | Then run |
|---------------------|-----------|----------|
| An agent, command, or reference doc | `canonical/` (markdown, no tool frontmatter) | `bin/rdf generate claude-code` |
| Framework tooling (CLI, libs, state helpers) | `bin/`, `lib/`, `state/` directly | — |
| Tests | `tests/*.bats` | `make -C tests test` |

**Never edit generated output** (`/root/.claude/…`, `adapters/*/output/`). It is
overwritten on every `rdf generate`. If you change anything under `canonical/`,
run `bin/rdf generate claude-code` in the same change so the deployed tree and
your source stay in sync — `bin/rdf doctor` must report zero FAIL before you
open a PR.

## Shell standards

RDF ships shell that must run on a wide OS matrix, so portability is a
first-class concern (see PR #1 for a model portability fix):

- Shebang `#!/usr/bin/env bash`; `set -euo pipefail` in every script
- Target bash 3.2 (macOS system bash) and 4.1 (CentOS 6) — avoid `${var,,}`,
  `mapfile -d`, `declare -n`, `declare -A` for global state, `readlink -f`
- Use `command <coreutil>` (e.g. `command cp`, `command rm`) for PATH-portable
  resolution across pre- and post-usr-merge distros — never bare or hardcoded
  `/usr/bin/` paths
- Double-quote all variables in command context; `command -v` for discovery
- Any `2>/dev/null` or `|| true` needs an inline comment on the same line
  explaining why the error is safe to ignore

## Testing

```bash
make -C tests test        # full BATS suite
bash -n <changed.sh>      # syntax
shellcheck <changed.sh>   # lint
bin/rdf doctor            # zero FAIL required
```

Every behavior change needs a regression test. Portability changes should add a
case that exercises the non-GNU / older-bash path (see `tests/portability.bats`).

## Commit and PR process

1. Fork `rfxn/rdf`, branch from `main` (`fix/<slug>` or `feat/<slug>`).
2. Commit style: free-form descriptive subject, body lines tagged `[New]`,
   `[Change]`, `[Fix]`, `[Remove]`. No AI-assistant attribution lines.
3. Update `CHANGELOG` and `CHANGELOG.RELEASE` for any code-changing commit.
4. Open a PR against `rfxn/rdf:main`. CI runs `bash -n`, `shellcheck`,
   `rdf doctor`, and the BATS suite on Ubuntu and macOS.

Questions or larger proposals: open an issue first so we can align on approach.

## License

By contributing you agree that your contributions are licensed under the
GNU GPL v2, consistent with the rest of the project.
