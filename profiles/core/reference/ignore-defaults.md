# Ignore Defaults

> Seed content for `.rdf/governance/ignore.md`. Loaded by /r-init
> (first-time generation) and /r-refresh (merge mode, user-modified
> additions preserved).

The content below is the default body. When an existing `ignore.md`
is present, /r-refresh appends any missing defaults under a
`# Added by /r-refresh` heading rather than overwriting.

## Default Body

```
# Excluded Paths

> Paths that agents and grep-based tooling should skip.
> .gitignore-style glob syntax. Comments begin with #.

# Build / dependency trees
node_modules/
vendor/
dist/
build/
target/

# Python / virtualenvs
__pycache__/
.venv/
venv/
*.pyc

# RDF working state (never contains source)
.rdf/work-output/

# Generated spec/plan state (user-local)
docs/specs/
```

## Merge Behavior

- First-time (no existing ignore.md): write the default body verbatim.
- Existing file: diff entries; if any default is missing, append a
  new section `# Added by /r-refresh` with just the missing entries.
  Never remove user-added entries.
- If an existing entry matches a default (exact string match), do
  nothing — it's covered.

## Scope

Agents read this file during setup and pass the path list to
`grep --exclude-dir=` / `--exclude=` flags when running searches.
No automatic tooling enforces it in 3.6 — enforcement is advisory
and graduates to tool-level checks in 3.7 if field adoption is
strong.
