# rfxn Workspace Governance Template

> Seed template for /r-init. R-fx Networks org overlay — opt-in only
> (never auto-detected). Requires core profile. Activate with
> `rdf init --type <lang>,rfxn-workspace` or `rdf profile install
> rfxn-workspace`.

## Cross-Project Coordination

- Shared libraries (tlog_lib, alert_lib, elog_lib, pkg_lib, geoip_lib,
  batsman) develop and test in their canonical repo first -- never edit a
  library copy inside a consuming project
- Release order: library first, then consumers -- update submodule pins in
  each consumer and run its test suite before committing the pin
- When a bug is root-caused to a shared library, verify all consuming
  projects before the session ends -- do not defer consumer verification
- See reference/cross-project.md for the library-to-consumer matrix and
  the integration test sequence

## Workspace Layout

- The workspace root is a non-git parent directory containing the project
  repos; workspace-level state lives in `<workspace>/.rdf/` (flat)
- Use `rdf init --batch` from the workspace root to initialize new
  project sets; per-project `.rdf/work-output/` takes precedence over
  workspace state for hooks and dispatch artifacts

## Org Tooling

- `scripts/comment-snapshot.sh` (this profile) runs comment-density
  metrics across the shared library set -- run from an RDF checkout
