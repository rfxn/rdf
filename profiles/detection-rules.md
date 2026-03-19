# Profile Auto-Detection Rules

> Used by /r:init during Phase 2 (codebase scan) to suggest profiles.
> Core profile is always active and not subject to detection.

## Detection Signals

### shell

Activate when ANY of:
- File extensions: `.sh`, `.bash` present in project root or `files/`
- Shebangs: `#!/bin/bash` or `#!/usr/bin/env bash` in project files
- Markers: `Makefile` with `shellcheck` targets
- Markers: `.bats` files in `tests/` directory
- Config: `.shellcheckrc` present

Confidence boost:
- `tests/infra/` directory (batsman submodule) -> high confidence
- `internals.conf` or `conf.d/` directory -> high confidence

### python

Activate when ANY of:
- File extensions: `.py` present in project root or `src/`
- Config: `pyproject.toml`, `setup.py`, `setup.cfg`, or `requirements.txt`
- Config: `pytest.ini`, `tox.ini`, or `[tool.pytest]` in pyproject.toml
- Markers: `venv/`, `.venv/`, or `Pipfile` present

Confidence boost:
- `src/{project}/` package directory -> high confidence
- `conftest.py` in project root -> medium confidence

### frontend

Activate when ANY of:
- File extensions: `.tsx`, `.jsx`, `.vue`, `.svelte` present
- Config: `package.json` with frontend framework dependency
  (react, vue, svelte, next, nuxt, angular, astro, solid)
- Config: `tsconfig.json` with `"jsx"` compiler option
- Markers: `playwright.config.*` or `cypress.config.*` present

Confidence boost (not activation alone):
- `.eslintrc*` or `eslint.config.*` present
- `src/components/` directory
- `public/` or `static/` directory

### database

Activate when 2+ of:
- File extensions: `*.sql` in project root, `migrations/`, or `db/`
- Config: `alembic/`, `alembic.ini` present
- Config: `schema.prisma`, `drizzle.config.*`, `knexfile.*`
- Markers: `docker-compose.yml` with postgres/mysql/redis/mongo services
- Dependencies: `sqlalchemy`, `django.db`, `sequelize`, `typeorm` in package config

### go

Activate when ANY of:
- Config: `go.mod` present
- File extensions: `*.go` in project root, `cmd/`, `internal/`, `pkg/`
- Markers: `Makefile` with `go build`/`go test` targets
- Config: `.golangci.yml` or `.golangci.yaml` present

## Mode Suggestions (not profile activations)

When security artifacts detected during /r:init:
- Directory: `redteam/` present
- File: `threat-model.md` or `security-audit.md` present
- Config: security-focused CI job (SAST, DAST, dependency scanning)

Suggest: `/r:mode security` for assessment work. Do not activate a profile.
