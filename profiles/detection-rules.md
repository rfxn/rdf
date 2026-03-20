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

### rust

Activate when ANY of:
- Config: `Cargo.toml` present
- File extensions: `*.rs` in project root, `src/`, or `tests/`
- Config: `rust-toolchain.toml` or `clippy.toml` present
- Markers: `Makefile` with `cargo build`/`cargo test` targets

Confidence boost:
- `src/main.rs` or `src/lib.rs` -> high confidence
- `benches/` directory -> medium confidence

### typescript

Activate when ANY of:
- Config: `tsconfig.json` present
- File extensions: non-declaration `*.ts` files (exclude `*.d.ts`-only projects)
- Dependencies: `typescript` in `package.json` devDependencies
- Config: `ts-node` or `tsx` in package.json scripts

Note: projects with ONLY `*.d.ts` files are type declaration packages,
not TypeScript projects -- do not activate.

Confidence boost:
- `src/` with `.ts` files -> high confidence
- `vitest.config.ts` or `jest.config.ts` -> medium confidence

### perl

Activate when ANY of:
- File extensions: `*.pl`, `*.pm` present (use `git ls-files` for subdirectory detection)
- Config: `cpanfile`, `Makefile.PL`, `Build.PL`, or `META.json` present
- Config: `.perlcriticrc` or `.perltidyrc` present
- Markers: `t/` directory with `*.t` test files

Confidence boost:
- `lib/` with `*.pm` files -> high confidence
- `cpanfile.snapshot` -> medium confidence

### php

Activate when ANY of:
- Config: `composer.json` present (sufficient alone)
- File extensions: `*.php` in project root, `app/`, or `src/`
- Config: `phpunit.xml`, `phpstan.neon`, or `psalm.xml` present
- Markers: `artisan` file (Laravel) or `bin/console` (Symfony)

Confidence boost:
- `artisan` file -> high confidence (Laravel)
- `vendor/` directory -> medium confidence

### infrastructure (priority 3)

Activate when a priority-1 language profile also matches AND any of:
- File extensions: `*.tf` or `*.tfvars` present
- Markers: `Dockerfile` or `docker-compose.yml` present
- Markers: `k8s/`, `kubernetes/`, or `kustomization.yaml` present
- Markers: `ansible/`, `playbooks/`, or `ansible.cfg` present
- Config: `terragrunt.hcl`, `packer.json`, or `pulumi.yaml` present

Note: infrastructure is priority-3 -- only activates when at least one
priority-1 language signal also matches. A standalone Dockerfile without
language files produces `minimal`, not `infrastructure`.

## Mode Suggestions (not profile activations)

When security artifacts detected during /r:init:
- Directory: `redteam/` present
- File: `threat-model.md` or `security-audit.md` present
- Config: security-focused CI job (SAST, DAST, dependency scanning)

Suggest: `/r:mode security` for assessment work. Do not activate a profile.
