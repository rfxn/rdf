# Profile Auto-Detection Rules

> Used by /r:init during Phase 2 (codebase scan) to suggest profiles.
> Core profile is always active and not subject to detection.

## Detection Signals

### systems-engineering

Activate when ANY of:
- File extensions: `.sh`, `.bash` present in project root or `files/`
- Shebangs: `#!/bin/bash` or `#!/usr/bin/env bash` in project files
- Markers: `Makefile` with `shellcheck` targets
- Markers: `.bats` files in `tests/` directory
- Config: `.shellcheckrc` present

Confidence boost:
- `tests/infra/` directory (batsman submodule) -> high confidence
- `internals.conf` or `conf.d/` directory -> high confidence

### frontend

Activate when ANY of:
- File extensions: `.tsx`, `.jsx`, `.vue`, `.svelte` present
- Config: `package.json` with frontend framework dependency
  (react, vue, svelte, next, nuxt, angular)
- Config: `tsconfig.json` with `"jsx"` compiler option
- Markers: `.eslintrc*` or `eslint.config.*` present
- Markers: `playwright.config.*` or `cypress.config.*` present

Confidence boost:
- `src/components/` directory -> high confidence
- `public/` or `static/` directory -> medium confidence

### security

Activate when ANY of:
- Directory: `redteam/` present
- File: `threat-model.md` or `security-audit.md` present
- Config: security-focused CI job (SAST, DAST, dependency scanning)

Note: Security profile is also activated explicitly via
`/r:init --mode security-assessment` regardless of detection signals.

### python (future)

Activate when ANY of:
- File extensions: `.py` present in project root or `src/`
- Config: `pyproject.toml`, `setup.py`, `setup.cfg`, or `requirements.txt`
- Config: `pytest.ini`, `tox.ini`, or `[tool.pytest]` in pyproject.toml
- Markers: `venv/`, `.venv/`, or `Pipfile` present

### full-stack (future)

Activate when BOTH:
- Frontend detection signals present AND
- Backend detection signals present (python or other backend profile)
