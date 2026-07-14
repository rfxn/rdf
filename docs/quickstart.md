# Quickstart — RDF on Your Repo in 5 Minutes

No rfxn context required. You need `git`, `bash` 4.1+, `jq`, and an AI
coding runtime (Claude Code, Gemini CLI, or Codex). Examples below use
Claude Code.

## 1. Install RDF (once per machine)

```bash
git clone https://github.com/rfxn/rdf.git ~/rdf && cd ~/rdf
bin/rdf generate claude-code    # build adapter output from canonical sources
bin/rdf deploy claude-code      # symlink into ~/.claude/ (regeneration auto-updates)
```

Verify:

```bash
bin/rdf doctor
# expect: 0 FAIL — WARNs are fine on a fresh install
```

## 2. Initialize your project

Point `rdf init` at any repo. It auto-detects the stack and scaffolds
governance:

```bash
bin/rdf init ~/projects/my-app
```

Real output from a plain Flask project:

```
rdf: auto-detected profiles: python
rdf: initializing: my-app (profiles=python, version=0.1.0)
rdf:   created CLAUDE.md (profiles=python, sections=18)
rdf:   added 5 entries to .git/info/exclude
rdf:   created .rdf/{governance,work-output,memory,scopes}
rdf:   copied reference docs from 2 profile(s)
rdf:   created SECURITY.md
rdf:   created CONTRIBUTING.md
rdf:   created MEMORY.md placeholder
rdf: init complete: my-app
```

What you now have:

| Artifact | Purpose |
|----------|---------|
| `CLAUDE.md` | Project conventions the AI must follow (stack-specific) |
| `.rdf/governance/` | Domain reference docs pulled from matching profiles |
| `.rdf/memory/`, `.rdf/work-output/` | Session state + agent output (never committed) |
| `SECURITY.md`, `CONTRIBUTING.md` | Community-health starters (edit to taste) |

Force a stack instead of auto-detect with `--type` (e.g.
`--type rust,infrastructure`); preview with `--dry-run`.

## 3. Start a session

Open your project in Claude Code and run:

```
/r-start
```

You get a project dashboard: version, branch, plan progress, in-flight
work, warnings. From there the pipeline is four commands:

```
/r-spec     design: research + brainstorm -> spec + adversarial review
/r-plan     decompose spec into a phased plan
/r-build    execute phases via TDD with quality gates
/r-ship     preflight -> verify -> release
```

Small change? Skip the pipeline — governance and quality gates apply to
normal sessions too. Run `/r-verify` for a QA pass or `/r-review` for an
adversarial review of any diff.

## 4. Keep it healthy

```bash
bin/rdf doctor ~/projects/my-app   # convention drift, stale state, sync health
```

## Where next

- [README — full command reference](../README.md#4-usage)
- [Demo walkthrough — a real production change end-to-end](demo-walkthrough.md)
- [ROADMAP](../ROADMAP.md)

Something break in the first five minutes? That's a bug —
[open an issue](https://github.com/rfxn/rdf/issues/new/choose).
