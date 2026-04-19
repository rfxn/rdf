# RDF Adapter Tests

BATS tests for the `rdf generate claude-code` adapter round-trip.

## Running Tests

```bash
make -C tests test
```

## Requirements

- `bats` — Bats 1.x (system install, not batsman submodule)
- `jq` — used by the adapter during generation

Install:
```bash
apt install bats jq       # Debian/Ubuntu
brew install bats-core jq # macOS
```

## BATS Strategy Decision

This suite uses **system bats** rather than the batsman submodule used by
APF, LMD, and BFD. Rationale:

- RDF is governance/scripts, not a shipped Linux daemon — no multi-distro
  container matrix is needed.
- The CI workflow (`.github/workflows/ci.yml`) installs bats via `apt` on
  `ubuntu-latest`; the tests job activates once `tests/Makefile` exists.
- Keeps `tests/` light: no submodule overhead, no Docker dependency.
- Can upgrade to batsman submodule later if multi-distro coverage becomes
  a requirement.

## What Is Tested

`tests/adapter.bats` covers five properties:

1. Generator writes expected `commands/` and `agents/` trees under the
   output directory.
2. Canonical body content is preserved verbatim in deployed output.
3. `.rdf-hash` sidecar is emitted next to each deployed file (Phase 7
   regression).
4. Running the generator twice is idempotent — content and sidecar hashes
   are identical on the second run.
5. Drift detection: manually corrupting a deployed file causes
   `rdf doctor --scope content-drift` to exit non-zero and cite the
   corrupted file.

## Hermeticity

Tests use `mktemp -d` for all directories. Nothing is written to
`/root/.claude/` or `~/.rdf/`. Fixture canonical files live in
`tests/fixtures/canonical/` and contain a unique marker string
(`RDF_TEST_MARKER_*`) for grep-based assertions.
