# Implementation Plan: `.rdf/` Directory Migration

**Goal:** Consolidate all per-project RDF state into `{project}/.rdf/` — one invisible
dot-directory replacing the scattered `.claude/governance/` + `work-output/` + CC auto-memory
paths. Zero `.claude/governance/` references remain in canonical content after completion.

**Architecture:** CLI tooling updated first (additive, backward-compat), then migration
command created, then all canonical content updated to use `.rdf/` paths, then regeneration
+ project migration + verification.

**Tech Stack:** Bash (4.1+ floor), Markdown canonical files, `rdf generate claude-code`

**Spec:** `docs/specs/2026-03-20-rdf-dotdir-migration-design.md`

**Phases:** 7

---

## Conventions

**Commit message format** (RDF — free-form descriptive):
```
{Description}

[New] description
[Change] description
[Remove] description
```

**CRITICAL:**
- Never `git add -A` or `git add .` — stage files explicitly by name
- Never commit PLAN.md, CLAUDE.md, MEMORY.md, .claude/
- All edits to `canonical/` — deploy via `rdf generate claude-code`
- After each phase: deploy and verify with `bash bin/rdf generate claude-code`
- Use `command cp`/`command mv`/`command rm` in project source code
- Use `/usr/bin/cp`/`/usr/bin/rm` in Bash tool calls

**Path replacement rules:**
- `.claude/governance/` → `.rdf/governance/` (governance reads)
- Bare `work-output/` → `.rdf/work-output/` (session state)
- `/root/.claude/projects/{encoded}/memory/` → `.rdf/memory/` (auto-memory)
- DO NOT change `~/.claude/agents/`, `~/.claude/commands/`, `~/.claude/scripts/`,
  `~/.claude/settings.json` — these are CC deployment paths, correctly tool-specific

---

## File Map

### New Files
| File | Est. Lines | Purpose |
|------|-----------|---------|
| `lib/cmd/migrate.sh` | ~150 | `rdf migrate` subcommand |

### Modified Files — CLI
| File | Changes |
|------|---------|
| `lib/cmd/init.sh` | Exclude entries, create `.rdf/` structure |
| `lib/cmd/doctor.sh` | Check `.rdf/`, legacy detection |
| `lib/cmd/refresh.sh` | Memory path from `.rdf/memory/` |
| `bin/rdf` | Add `migrate)` case, update help text |
| `state/rdf-state.sh` | Governance + work-output paths |

### Modified Files — Canonical Agents (4)
| File | Refs to change |
|------|---------------|
| `canonical/agents/dispatcher.md` | 1 governance, 2 work-output |
| `canonical/agents/engineer.md` | 1 governance |
| `canonical/agents/qa.md` | 1 governance |
| `canonical/agents/uat.md` | 1 governance |

### Modified Files — Canonical Commands (~28)
| File | Change types |
|------|-------------|
| `canonical/commands/r-init.md` | ~20 governance, exclude list |
| `canonical/commands/r-build.md` | 8 governance, 1 work-output |
| `canonical/commands/r-review.md` | 8 governance |
| `canonical/commands/r-test.md` | 5 governance |
| `canonical/commands/r-verify.md` | 6 governance |
| `canonical/commands/r-spec.md` | 2 governance, 4 work-output |
| `canonical/commands/r-status.md` | 2 governance, 7 work-output |
| `canonical/commands/r-save.md` | 3 work-output, 1 memory |
| `canonical/commands/r-ship.md` | 1 governance, 3 work-output |
| `canonical/commands/r-refresh.md` | 4 governance, 1 work-output |
| `canonical/commands/r-mode.md` | 2 governance |
| `canonical/commands/r-audit.md` | 1 governance |
| `canonical/commands/r-util-chg-dedup.md` | 1 governance |
| `canonical/commands/r-util-chg-gen.md` | 1 governance |
| `canonical/commands/r-util-ci-gen.md` | 1 governance |
| `canonical/commands/r-util-code-modernize.md` | 1 governance |
| `canonical/commands/r-util-code-scan.md` | 1 governance |
| `canonical/commands/r-util-doc-gen.md` | 1 governance |
| `canonical/commands/r-util-lib-release.md` | 1 governance |
| `canonical/commands/r-util-lib-sync.md` | 1 governance |
| `canonical/commands/r-util-mem-compact.md` | 1 governance |
| `canonical/commands/r-util-test-dedup.md` | 1 governance |
| `canonical/commands/r-util-mem-audit.md` | 1 memory |

### Modified Files — Templates, Reference, Schemas
| File | Change |
|------|--------|
| `canonical/commands/templates/governance-architecture.md` | `.user-modified` path |
| `canonical/commands/templates/governance-anti-patterns.md` | Same |
| `canonical/commands/templates/governance-conventions.md` | Same |
| `canonical/commands/templates/governance-constraints.md` | Same |
| `canonical/commands/templates/governance-verification.md` | Same |
| `canonical/commands/templates/governance-index.md` | `.claude/governance/` refs |
| `canonical/reference/framework.md` | Governance + work-output paths |
| `canonical/reference/session-safety.md` | work-output paths |
| `canonical/reference/memory-standards.md` | Memory path |
| `canonical/scripts/subagent-stop.sh` | work-output paths |
| `schemas/governance-index.md` | Schema paths |

### Modified Files — Documentation
| File | Change |
|------|--------|
| `profiles/core/governance-template.md` | `.claude/` → `.rdf/` in exclude example |
| `CLAUDE.md` | Exclude list reference |
| `CHANGELOG` | New entries |
| `CHANGELOG.RELEASE` | New entries |

**Note:** `README.md` and `RDF.md` were audited — their `.claude` refs are all
CC deployment paths (`~/.claude/agents/`, `~/.claude/commands/`), which are
correctly tool-specific and must NOT change. No updates needed.

**Test files:** RDF does not have BATS tests for CLI commands or canonical content.
Testing is manual verification + shellcheck + verification greps.
`tests/migrate.bats` is planned for a future phase.

### Deleted Files
| File | Reason |
|------|--------|
| `canonical/commands-v2-archived/` | Dead — v2 fully archived |
| `canonical/agents-v2-archived/` | Dead — v2 fully archived |
| `adapters/claude-code/agent-meta-v2.json` | Dead — v2 metadata |

## Phase Dependencies

All phases sequential — no parallelization.

CLI tooling (Phase 1) → migrate command (Phase 2) → canonical agents (Phase 3)
→ canonical commands (Phase 4) → templates/reference (Phase 5) → docs/cleanup (Phase 6)
→ regenerate/migrate/verify (Phase 7)

---

### Phase 1: Update CLI tooling

Update `init.sh`, `doctor.sh`, `refresh.sh`, `bin/rdf`, and `state/rdf-state.sh`
so RDF creates `.rdf/` structure on new projects, checks `.rdf/` health, resolves
memory from `.rdf/memory/`, and has a `migrate` dispatch entry.

**Files:**
- Modify: `lib/cmd/init.sh` (exclude entries + directory creation)
- Modify: `lib/cmd/doctor.sh` (artifact checks + legacy detection)
- Modify: `lib/cmd/refresh.sh` (memory path resolution)
- Modify: `bin/rdf` (add migrate case + help text)
- Modify: `state/rdf-state.sh` (governance + work-output paths)

- **Mode**: serial-agent
- **Risk**: medium
- **Type**: feature
- **Gates**: G1+G2
- **Accept**: `rdf init /tmp/test-proj` creates `.rdf/{governance,work-output,memory,scopes}`;
  `rdf doctor` checks `.rdf/` structure and detects legacy `.claude/governance/`;
  `_resolve_memory_path()` returns `.rdf/memory/` path;
  `rdf help` shows migrate command; all shell files pass `bash -n` and `shellcheck`
- **Test**: `bash -n lib/cmd/init.sh lib/cmd/doctor.sh lib/cmd/refresh.sh bin/rdf state/rdf-state.sh`
- **Edge cases**: EC2 (empty `.rdf/` — idempotent init), EC7 (preserve custom exclude entries)

- [ ] **Step 1: Update `_GIT_EXCLUDE_ENTRIES` in init.sh**

  Old (lines 123-133):
  ```bash
  _GIT_EXCLUDE_ENTRIES=(
      "# RDF working files (managed by rdf init)"
      "CLAUDE.md"
      "PLAN*.md"
      "AUDIT.md"
      "REGR.md"
      "MEMORY.md"
      ".claude/"
      "audit-output/"
      "work-output/"
  )
  ```

  New:
  ```bash
  _GIT_EXCLUDE_ENTRIES=(
      "# RDF working files (managed by rdf init)"
      "CLAUDE.md"
      "PLAN*.md"
      "AUDIT.md"
      "MEMORY.md"
      ".rdf/"
  )
  ```

  Removes `REGR.md` (unused in 3.0), `.claude/`, `audit-output/`, `work-output/`.
  Adds `.rdf/` which covers governance, work-output, memory, and scopes.

- [ ] **Step 2: Update `_init_one()` directory creation in init.sh**

  Old (lines 285-293):
  ```bash
      # 3. work-output/ directory
      if [[ ! -d "${path}/work-output" ]]; then
          if [[ "$dry_run" -eq 1 ]]; then
              rdf_log "  WOULD CREATE: work-output/"
          else
              command mkdir -p "${path}/work-output"
              rdf_log "  created work-output/"
          fi
      fi
  ```

  New:
  ```bash
      # 3. .rdf/ directory structure
      local rdf_dir="${path}/.rdf"
      if [[ ! -d "$rdf_dir" ]]; then
          if [[ "$dry_run" -eq 1 ]]; then
              rdf_log "  WOULD CREATE: .rdf/{governance,work-output,memory,scopes}"
          else
              command mkdir -p "${rdf_dir}/governance" "${rdf_dir}/work-output" "${rdf_dir}/memory" "${rdf_dir}/scopes"
              rdf_log "  created .rdf/{governance,work-output,memory,scopes}"
          fi
      else
          # Ensure subdirectories exist (idempotent)
          if [[ "$dry_run" -eq 0 ]]; then
              for subdir in governance work-output memory scopes; do
                  [[ -d "${rdf_dir}/${subdir}" ]] || command mkdir -p "${rdf_dir}/${subdir}"
              done
          fi
      fi
  ```

  Also update usage text line 12 — change "creates work-output/ directory" to
  "creates .rdf/ directory structure".

- [ ] **Step 3: Update `_check_artifacts()` in doctor.sh**

  Old (lines 69-74):
  ```bash
      # work-output/
      if [[ -d "${path}/work-output" ]]; then
          _add_result "artifacts" "$_OK" "work-output/ present"
      else
          _add_result "artifacts" "$_WARN" "work-output/ missing"
      fi
  ```

  New:
  ```bash
      # .rdf/ structure
      if [[ -d "${path}/.rdf" ]]; then
          _add_result "artifacts" "$_OK" ".rdf/ present"
          for subdir in governance work-output memory; do
              if [[ -d "${path}/.rdf/${subdir}" ]]; then
                  _add_result "artifacts" "$_OK" ".rdf/${subdir}/ present"
              else
                  _add_result "artifacts" "$_WARN" ".rdf/${subdir}/ missing"
              fi
          done
      else
          _add_result "artifacts" "$_WARN" ".rdf/ missing — run 'rdf init' or 'rdf migrate'"
      fi
  ```

  Old exclude entry check (line 81):
  ```bash
              for entry in "CLAUDE.md" "PLAN*.md" "MEMORY.md" ".claude/" "work-output/"; do
  ```

  New:
  ```bash
              for entry in "CLAUDE.md" "PLAN*.md" "MEMORY.md" ".rdf/"; do
  ```

  Add legacy detection at end of `_check_artifacts()` (before the closing `}`):
  ```bash
      # Legacy state detection
      if [[ -d "${path}/.claude/governance" ]]; then
          _add_result "artifacts" "$_WARN" ".claude/governance/ still exists — run 'rdf migrate'"
      fi
      if [[ -d "${path}/work-output" ]] && [[ ! -L "${path}/work-output" ]]; then
          _add_result "artifacts" "$_WARN" "work-output/ at project root — run 'rdf migrate'"
      fi
  ```

- [ ] **Step 4: Update `_check_memory()` in doctor.sh**

  Old (lines 170-177):
  ```bash
          local safe_path="${path//\//-}"
          local auto_memory="/root/.claude/projects/${safe_path}/memory/MEMORY.md"
          if [[ -f "$auto_memory" ]]; then
              _add_result "memory" "$_OK" "MEMORY.md in auto-memory location"
          else
              _add_result "memory" "$_WARN" "no MEMORY.md found"
          fi
  ```

  New:
  ```bash
          if [[ -L "${path}/.rdf/memory" ]] && [[ ! -e "${path}/.rdf/memory" ]]; then
              _add_result "memory" "$_WARN" ".rdf/memory/ is a dangling symlink — recreate with 'rdf migrate'"
          elif [[ -f "${path}/.rdf/memory/MEMORY.md" ]]; then
              _add_result "memory" "$_OK" "MEMORY.md in .rdf/memory/"
          else
              _add_result "memory" "$_WARN" "no MEMORY.md found"
          fi
  ```

- [ ] **Step 5: Update `_resolve_memory_path()` in refresh.sh**

  Old (lines 39-44):
  ```bash
  _resolve_memory_path() {
      local project_path="$1"
      local safe_path="${project_path//\//-}"
      local memory_dir="/root/.claude/projects/${safe_path}/memory"
      echo "${memory_dir}/MEMORY.md"
  }
  ```

  New:
  ```bash
  _resolve_memory_path() {
      local project_path="$1"
      echo "${project_path}/.rdf/memory/MEMORY.md"
  }
  ```

- [ ] **Step 6: Update `bin/rdf`**

  Add help text after line 29 (after "doctor" line):
  ```
    migrate    Migrate project from .claude/ + work-output/ to .rdf/
  ```

  Add case after line 53 (after the doctor case):
  ```bash
      migrate)  shift; source "${RDF_LIBDIR}/cmd/migrate.sh"; cmd_migrate "$@" ;;
  ```

- [ ] **Step 7: Update `state/rdf-state.sh`**

  Change governance path detection (lines 185-186):
  Old:
  ```bash
      elif [[ -f "${_project_path}/.claude/governance/index.md" ]]; then
          _gov_path="${_project_path}/.claude/governance/index.md"
  ```
  New:
  ```bash
      elif [[ -f "${_project_path}/.rdf/governance/index.md" ]]; then
          _gov_path="${_project_path}/.rdf/governance/index.md"
  ```

  Change work-output paths (lines 161-162, 224, 235-241):
  Replace all `${_project_path}/work-output` with `${_project_path}/.rdf/work-output`
  across the entire file. This covers:
  - Line 161: `if [[ -d "${_project_path}/work-output" ]]`
  - Line 162: `find "${_project_path}/work-output"` (work-output file listing)
  - Line 224: session-log.jsonl path
  - Lines 235-241: spec-progress.md and ship-progress.md paths

- [ ] **Step 8: Verify**

  ```bash
  bash -n lib/cmd/init.sh lib/cmd/doctor.sh lib/cmd/refresh.sh bin/rdf state/rdf-state.sh
  # expect: exit 0, no output

  grep -c "\.rdf/" lib/cmd/init.sh
  # expect: >= 3

  grep -c "\.claude/governance" lib/cmd/init.sh
  # expect: 0

  grep -c "\.rdf/" lib/cmd/doctor.sh
  # expect: >= 4

  grep -c "\.rdf/memory/" lib/cmd/refresh.sh
  # expect: 1

  grep "migrate" bin/rdf | head -3
  # expect: help text line + case line
  ```

- [ ] **Step 9: Commit**

  ```bash
  git add lib/cmd/init.sh lib/cmd/doctor.sh lib/cmd/refresh.sh bin/rdf state/rdf-state.sh
  git commit -m "$(cat <<'EOF'
  Update CLI tooling for .rdf/ directory structure

  [Change] init.sh: create .rdf/{governance,work-output,memory,scopes} instead of work-output/
  [Change] init.sh: simplify git exclude to CLAUDE.md, PLAN*.md, AUDIT.md, MEMORY.md, .rdf/
  [Change] doctor.sh: check .rdf/ structure, detect legacy .claude/governance/ and work-output/
  [Change] doctor.sh: resolve memory from .rdf/memory/ instead of CC auto-memory path
  [Change] refresh.sh: resolve memory path from .rdf/memory/
  [Change] bin/rdf: add migrate command dispatch and help text
  [Change] rdf-state.sh: read governance from .rdf/governance/, work-output from .rdf/work-output/
  [Remove] init.sh: REGR.md, audit-output/, .claude/, work-output/ from exclude entries
  EOF
  )"
  ```

---

### Phase 2: Create `lib/cmd/migrate.sh`

New migration subcommand that moves existing projects from `.claude/governance/` +
`work-output/` to `.rdf/` structure with copy-verify-delete safety.

**Files:**
- Create: `lib/cmd/migrate.sh`

- **Mode**: serial-agent
- **Risk**: medium
- **Type**: feature
- **Gates**: G1+G2
- **Accept**: `rdf migrate --dry-run .` shows expected operations;
  `rdf migrate` on a project with `.claude/governance/` moves files to `.rdf/governance/`;
  `bash -n lib/cmd/migrate.sh` passes; conflict detection exits code 3
- **Test**: `bash -n lib/cmd/migrate.sh`, manual dry-run verification
- **Edge cases**: EC1 (conflict detection), EC3 (CC not installed), EC7 (custom excludes),
  EC8 (not a git repo), EC10 (idempotent re-run)

- [ ] **Step 1: Write `lib/cmd/migrate.sh`**

  Create the file with these functions (from spec section 5.1):

  ```bash
  #!/usr/bin/env bash
  # lib/cmd/migrate.sh — rdf migrate subcommand
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # Sourced by bin/rdf — do not execute directly

  _migrate_usage() {
      cat <<'USAGE'
  Usage: rdf migrate [options] [path]

  Migrate project from .claude/governance/ + work-output/ to .rdf/

  Arguments:
    path        Project directory (default: cwd)

  Options:
    --dry-run   Show changes without modifying
    --all       Migrate all projects in workspace

  Exit codes:
    0   Migration successful
    1   Migration failed (check /tmp/rdf-migrate-{project}.log)
    2   Nothing to migrate (already .rdf/ or fresh project)
    3   Conflict detected (both .claude/governance/ and .rdf/governance/ exist)
  USAGE
  }

  # Convert absolute path to CC auto-memory path-encoded directory name
  # /root/admin/work/proj/rdf → -root-admin-work-proj-rdf
  _encode_project_path() {
      local abs_path="$1"
      local encoded="${abs_path//\//-}"
      echo "$encoded"
  }

  _migrate_governance() {
      local project_path="$1"
      local dry_run="$2"
      local log_file="$3"

      local src="${project_path}/.claude/governance"
      local dst="${project_path}/.rdf/governance"

      if [[ ! -d "$src" ]]; then
          rdf_log "  [—] no .claude/governance/ to migrate"
          return 0
      fi

      # Conflict check handled by _migrate_one() before this function is called

      local file_count
      file_count="$(find "$src" -type f 2>/dev/null | wc -l)"
      file_count="${file_count##* }"

      if [[ "$dry_run" -eq 1 ]]; then
          rdf_log "  WOULD MOVE: .claude/governance/ → .rdf/governance/ (${file_count} files)"
          return 0
      fi

      command mkdir -p "$dst"
      command cp -a "${src}/." "$dst/" 2>/dev/null || {
          echo "FAIL: cp governance" >> "$log_file"
          rdf_die "failed to copy governance files"
      }

      # Verify copy
      local dst_count
      dst_count="$(find "$dst" -type f 2>/dev/null | wc -l)"
      dst_count="${dst_count##* }"
      if [[ "$dst_count" -ne "$file_count" ]]; then
          echo "FAIL: governance count mismatch src=${file_count} dst=${dst_count}" >> "$log_file"
          rdf_die "governance copy verification failed: expected ${file_count} files, got ${dst_count}"
      fi

      command rm -rf "$src"
      echo "OK: governance ${file_count} files" >> "$log_file"
      rdf_log "  [✓] governance: .claude/governance/ → .rdf/governance/ (${file_count} files)"
  }

  _migrate_workoutput() {
      local project_path="$1"
      local dry_run="$2"
      local log_file="$3"

      local src="${project_path}/work-output"
      local dst="${project_path}/.rdf/work-output"

      if [[ ! -d "$src" ]]; then
          rdf_log "  [—] no work-output/ to migrate"
          return 0
      fi

      local file_count
      file_count="$(find "$src" -type f 2>/dev/null | wc -l)"
      file_count="${file_count##* }"

      if [[ "$dry_run" -eq 1 ]]; then
          rdf_log "  WOULD MOVE: work-output/ → .rdf/work-output/ (${file_count} files)"
          return 0
      fi

      command mkdir -p "$dst"
      if [[ "$file_count" -gt 0 ]]; then
          command cp -a "${src}/." "$dst/" 2>/dev/null || {
              echo "FAIL: cp work-output" >> "$log_file"
              rdf_die "failed to copy work-output files"
          }
      fi

      command rm -rf "$src"
      echo "OK: work-output ${file_count} files" >> "$log_file"
      rdf_log "  [✓] work-output: work-output/ → .rdf/work-output/ (${file_count} files)"
  }

  _setup_memory_symlink() {
      local project_path="$1"
      local dry_run="$2"
      local log_file="$3"

      local rdf_memory="${project_path}/.rdf/memory"
      local encoded
      encoded="$(_encode_project_path "$project_path")"
      local cc_memory="/root/.claude/projects/${encoded}/memory"

      if [[ -L "$rdf_memory" ]]; then
          rdf_log "  [—] .rdf/memory/ symlink already exists"
          return 0
      fi

      if [[ "$dry_run" -eq 1 ]]; then
          if [[ -d "$cc_memory" ]]; then
              rdf_log "  WOULD SYMLINK: .rdf/memory/ → ${cc_memory}"
          else
              rdf_log "  WOULD CREATE: .rdf/memory/ (real directory — CC not detected)"
          fi
          return 0
      fi

      # Remove existing real directory if empty (from rdf init)
      if [[ -d "$rdf_memory" ]] && [[ ! "$(ls -A "$rdf_memory" 2>/dev/null)" ]]; then
          command rmdir "$rdf_memory"
      fi

      if [[ -d "$cc_memory" ]]; then
          command ln -s "$cc_memory" "$rdf_memory"
          echo "OK: memory symlink → ${cc_memory}" >> "$log_file"
          rdf_log "  [✓] memory: .rdf/memory/ → ${cc_memory}"
      else
          command mkdir -p "$rdf_memory"
          echo "OK: memory real dir (CC not detected)" >> "$log_file"
          rdf_log "  [✓] memory: .rdf/memory/ (real directory — CC not detected)"
      fi
  }

  _update_excludes() {
      local project_path="$1"
      local dry_run="$2"

      local exclude="${project_path}/.git/info/exclude"
      if [[ ! -f "$exclude" ]]; then
          rdf_log "  [—] no .git/info/exclude"
          return 0
      fi

      if [[ "$dry_run" -eq 1 ]]; then
          rdf_log "  WOULD UPDATE: .git/info/exclude"
          return 0
      fi

      # Remove old RDF entries, preserve everything else
      local old_entries=(".claude/" "work-output/" "audit-output/" "REGR.md")
      local tmp
      tmp="$(mktemp)"
      local removed=0
      while IFS= read -r line || [[ -n "$line" ]]; do
          local skip=0
          for old in "${old_entries[@]}"; do
              if [[ "$line" == "$old" ]]; then
                  skip=1
                  removed=$((removed + 1))
                  break
              fi
          done
          [[ "$skip" -eq 0 ]] && echo "$line" >> "$tmp"
      done < "$exclude"

      # Add .rdf/ if not present
      if ! grep -qxF '.rdf/' "$tmp"; then
          echo '.rdf/' >> "$tmp"
      fi

      command cp "$tmp" "$exclude"
      command rm "$tmp"
      rdf_log "  [✓] .git/info/exclude updated (removed ${removed} old entries)"
  }

  _migrate_one() {
      local project_path="$1"
      local dry_run="$2"
      local name
      name="$(basename "$project_path")"

      if [[ ! -d "${project_path}/.git" ]]; then
          rdf_warn "${name}: not a git repo — skipping"
          return 1
      fi

      # Check for conflict state (EC1)
      if [[ -d "${project_path}/.claude/governance" ]] && \
         [[ -d "${project_path}/.rdf/governance" ]] && \
         [[ "$(ls -A "${project_path}/.rdf/governance" 2>/dev/null)" ]]; then
          rdf_warn "${name}: conflict — both .claude/governance/ and .rdf/governance/ exist"
          return 3
      fi

      # Nothing to migrate? (EC10)
      if [[ ! -d "${project_path}/.claude/governance" ]] && \
         [[ ! -d "${project_path}/work-output" ]]; then
          if [[ -d "${project_path}/.rdf" ]]; then
              rdf_log "${name}: already migrated — nothing to do"
              return 2
          else
              rdf_log "${name}: fresh project — use 'rdf init' instead"
              return 2
          fi
      fi

      local log_file="/tmp/rdf-migrate-${name}.log"
      echo "=== rdf migrate: ${name} ===" > "$log_file"
      echo "timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$log_file"

      if [[ "$dry_run" -eq 1 ]]; then
          rdf_log "[dry-run] would migrate ${name} to .rdf/ structure:"
      else
          rdf_log "migrating ${name} to .rdf/ structure..."
      fi

      # Ensure .rdf/ exists
      if [[ "$dry_run" -eq 0 ]]; then
          command mkdir -p "${project_path}/.rdf/governance" \
              "${project_path}/.rdf/work-output" \
              "${project_path}/.rdf/scopes"
          rdf_log "  [✓] .rdf/ created"
      else
          rdf_log "  WOULD CREATE: .rdf/"
      fi

      _migrate_governance "$project_path" "$dry_run" "$log_file"
      _migrate_workoutput "$project_path" "$dry_run" "$log_file"
      _setup_memory_symlink "$project_path" "$dry_run" "$log_file"
      _update_excludes "$project_path" "$dry_run"

      # Clean up empty .claude/ directory
      if [[ "$dry_run" -eq 0 ]] && [[ -d "${project_path}/.claude" ]]; then
          if [[ ! "$(ls -A "${project_path}/.claude" 2>/dev/null)" ]]; then
              command rmdir "${project_path}/.claude"
              rdf_log "  [✓] removed empty .claude/"
          fi
      fi

      if [[ "$dry_run" -eq 1 ]]; then
          rdf_log "no files modified (dry run)"
      else
          rdf_log "migration complete — run 'rdf doctor' to verify"
      fi
  }

  cmd_migrate() {
      local path=""
      local dry_run=0
      local migrate_all=0

      while [[ $# -gt 0 ]]; do
          case "$1" in
              --dry-run)  dry_run=1; shift ;;
              --all)      migrate_all=1; shift ;;
              help|--help|-h) _migrate_usage; return 0 ;;
              -*)         rdf_die "unknown option: $1 — run 'rdf migrate help'" ;;
              *)
                  if [[ -z "$path" ]]; then
                      path="$1"; shift
                  else
                      rdf_die "unexpected argument: $1"
                  fi
                  ;;
          esac
      done

      if [[ "$migrate_all" -eq 1 ]]; then
          local workspace="${path:-/root/admin/work/proj}"
          [[ -d "$workspace" ]] || rdf_die "workspace not found: $workspace"
          workspace="$(cd "$workspace" && pwd)" || exit 1

          local count=0
          local errors=0
          for subdir in "${workspace}"/*/; do
              [[ -d "$subdir" ]] || continue
              [[ -d "${subdir}/.git" ]] || continue
              local subname
              subname="$(basename "$subdir")"
              [[ "$subname" == .* ]] && continue

              _migrate_one "$subdir" "$dry_run" || {
                  local rc=$?
                  [[ $rc -eq 2 ]] || errors=$((errors + 1))
              }
              count=$((count + 1))
          done

          rdf_log "migration scan complete: ${count} projects, ${errors} errors"
      else
          path="${path:-$(pwd)}"
          [[ -d "$path" ]] || rdf_die "directory not found: $path"
          path="$(cd "$path" && pwd)" || exit 1
          _migrate_one "$path" "$dry_run"
      fi
  }
  ```

- [ ] **Step 2: Verify**

  ```bash
  bash -n lib/cmd/migrate.sh
  # expect: exit 0

  shellcheck lib/cmd/migrate.sh
  # expect: clean or only SC1091 (sourced lib)

  grep -c 'command cp\|command rm\|command mkdir\|command rmdir\|command ln' lib/cmd/migrate.sh
  # expect: >= 8 (no bare cp/mv/rm)

  grep -c 'cd ' lib/cmd/migrate.sh
  # expect: 0 or all have || guard
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add lib/cmd/migrate.sh
  git commit -m "$(cat <<'EOF'
  Add rdf migrate command for .rdf/ directory migration

  [New] lib/cmd/migrate.sh: migrate projects from .claude/ + work-output/ to .rdf/
  [New] Copy-verify-delete safety with per-project log files
  [New] CC auto-memory symlink setup (.rdf/memory/ → CC memory dir)
  [New] --dry-run and --all flags for safe batch migration
  [New] Conflict detection (exit code 3), idempotent re-run (exit code 2)
  EOF
  )"
  ```

---

### Phase 3: Update canonical agents

Replace `.claude/governance/` with `.rdf/governance/` in all 4 agent files,
and `work-output/` with `.rdf/work-output/` in dispatcher.md.

**Files:**
- Modify: `canonical/agents/dispatcher.md`
- Modify: `canonical/agents/engineer.md`
- Modify: `canonical/agents/qa.md`
- Modify: `canonical/agents/uat.md`

- **Mode**: serial-context
- **Risk**: low
- **Type**: refactor
- **Gates**: G1
- **Accept**: `grep -r '\.claude/governance/' canonical/agents/` returns 0 hits;
  `grep -r '\.rdf/governance/' canonical/agents/` returns 4 hits;
  dispatcher.md has `.rdf/work-output/`
- **Test**: `grep -r '\.claude/governance/' canonical/agents/ | wc -l` → 0;
  `grep -c '\.rdf/governance/' canonical/agents/*.md` → 4
- **Edge cases**: none

- [ ] **Step 1: Update all 4 agents — governance path**

  In each file, replace `.claude/governance/` with `.rdf/governance/`:

  | File | Line | Old | New |
  |------|------|-----|-----|
  | `canonical/agents/dispatcher.md` | 14 | `Read .claude/governance/index.md` | `Read .rdf/governance/index.md` |
  | `canonical/agents/engineer.md` | 14 | `Read .claude/governance/index.md` | `Read .rdf/governance/index.md` |
  | `canonical/agents/qa.md` | 13 | `Read .claude/governance/index.md` | `Read .rdf/governance/index.md` |
  | `canonical/agents/uat.md` | 14 | `Read .claude/governance/index.md` | `Read .rdf/governance/index.md` |

- [ ] **Step 2: Update dispatcher.md — work-output path**

  Line 67: `work-output/` → `.rdf/work-output/`
  Line 87: `work-output/` → `.rdf/work-output/`

  These are in "Red/Green Decision" and "Constraints" sections:
  - "update PLAN.md, write status to .rdf/work-output/, next phase"
  - "Write structured status to .rdf/work-output/ after each phase"

- [ ] **Step 3: Verify and deploy**

  ```bash
  grep -r '\.claude/governance/' canonical/agents/
  # expect: 0 hits

  grep -c '\.rdf/governance/' canonical/agents/dispatcher.md canonical/agents/engineer.md \
    canonical/agents/qa.md canonical/agents/uat.md
  # expect: 1 each

  grep -c '\.rdf/work-output/' canonical/agents/dispatcher.md
  # expect: 2

  bash bin/rdf generate claude-code 2>&1 | tail -3
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add canonical/agents/dispatcher.md canonical/agents/engineer.md \
        canonical/agents/qa.md canonical/agents/uat.md
  git commit -m "$(cat <<'EOF'
  Update canonical agents for .rdf/ governance and work-output paths

  [Change] dispatcher.md: .claude/governance/ → .rdf/governance/, work-output/ → .rdf/work-output/
  [Change] engineer.md: .claude/governance/ → .rdf/governance/
  [Change] qa.md: .claude/governance/ → .rdf/governance/
  [Change] uat.md: .claude/governance/ → .rdf/governance/
  EOF
  )"
  ```

---

### Phase 4: Update canonical commands

Replace all `.claude/governance/`, bare `work-output/`, and CC auto-memory path
references across ~28 command files. Three change types applied per-file in a
single pass.

**Files:**
- Modify: 28 command files (see File Map)

- **Mode**: serial-agent
- **Risk**: medium
- **Type**: refactor
- **Gates**: G1+G2
- **Accept**: `grep -r '\.claude/governance/' canonical/commands/` returns 0 (excluding templates/);
  `grep -r 'work-output/' canonical/commands/ | grep -v '\.rdf/work-output/'` returns 0;
  `grep -r '/root/\.claude/projects/' canonical/commands/` returns 0
- **Test**: `grep -r '\.claude/governance/' canonical/commands/ --include='*.md' | grep -v templates/ | wc -l` → 0;
  `grep -r 'work-output/' canonical/commands/ | grep -v '\.rdf/' | wc -l` → 0
- **Edge cases**: none

- [ ] **Step 1: Simple governance-only commands (13 files)**

  Each file has exactly 1 `.claude/governance/` reference. Apply `replace_all`
  of `.claude/governance/` → `.rdf/governance/` in each:

  | File | Line |
  |------|------|
  | `canonical/commands/r-audit.md` | 15 |
  | `canonical/commands/r-util-chg-dedup.md` | 11 |
  | `canonical/commands/r-util-chg-gen.md` | 10 |
  | `canonical/commands/r-util-ci-gen.md` | 9 |
  | `canonical/commands/r-util-code-modernize.md` | 10 |
  | `canonical/commands/r-util-code-scan.md` | 11 |
  | `canonical/commands/r-util-doc-gen.md` | 11 |
  | `canonical/commands/r-util-lib-release.md` | 9 |
  | `canonical/commands/r-util-lib-sync.md` | 10 |
  | `canonical/commands/r-util-mem-compact.md` | 10 |
  | `canonical/commands/r-util-test-dedup.md` | 10 |
  | `canonical/commands/r-ship.md` | 12 |
  | `canonical/commands/r-mode.md` | 26, 52 |

- [ ] **Step 2: r-init.md (~20 governance refs + exclude list)**

  Apply `replace_all` of `.claude/governance/` → `.rdf/governance/` across
  the entire file. This covers lines 3, 10, 68, 348, 356, 358, 360, 362,
  364, 593, and all other occurrences.

  Also update the `--force` option description (line 10):
  `--force` — delete existing `.rdf/governance/` and regenerate

  Also update the error handling section (lines 749-754) to reference
  `.rdf/governance/` instead of `.claude/governance/`.

  Also update the Git Exclusion section (line 720):
  "verify `.rdf/` is in `.git/info/exclude`" (already correct from spec).

- [ ] **Step 3: r-build.md (8 governance + 1 work-output)**

  Apply `replace_all` of `.claude/governance/` → `.rdf/governance/`.
  This covers the GOVERNANCE block (lines 77-82) and the governance read
  (line 51) and mode check (line 60).

  Also line 97: `work-output/` → `.rdf/work-output/`

- [ ] **Step 4: r-review.md (8 governance)**

  Apply `replace_all` of `.claude/governance/` → `.rdf/governance/`.
  Covers lines 49, 69-71, 85-88 (governance file references in dispatch
  payloads and constraint references).

- [ ] **Step 5: r-test.md (5 governance) and r-verify.md (6 governance)**

  Apply `replace_all` of `.claude/governance/` → `.rdf/governance/` in both files.
  These files have governance context blocks in their dispatch payloads.

- [ ] **Step 6: r-spec.md (2 governance + 4 work-output)**

  Apply `replace_all` of `.claude/governance/` → `.rdf/governance/` (2 refs).
  Apply `replace_all` of `work-output/` → `.rdf/work-output/` for all
  bare work-output references (lines 13, 68, 224, 291, 556).

  > Self-correction note: be careful not to change `work-output/` inside
  > already-prefixed `.rdf/work-output/` strings. Process governance first,
  > then work-output.

- [ ] **Step 7: r-status.md (2 governance + 7 work-output)**

  Apply `replace_all` of `.claude/governance/` → `.rdf/governance/` (lines 10, 40).
  Apply `replace_all` of bare `work-output/` → `.rdf/work-output/` (lines 29-30,
  101, 111, 116, 142, 193).

- [ ] **Step 8: r-save.md (3 work-output + 1 memory)**

  Apply `replace_all` of bare `work-output/` → `.rdf/work-output/` (lines 131,
  192, 214 — spec-progress.md ref, session-log.jsonl path, directory creation).

  Change memory path (line 153 / section 3 header):
  Old: `Locate the project's MEMORY.md in the Claude auto-memory directory:`
       `/root/.claude/projects/{path-encoded}/memory/MEMORY.md`
  New: `Locate the project's MEMORY.md in the .rdf/memory/ directory:`
       `.rdf/memory/MEMORY.md`

- [ ] **Step 9: r-ship.md (work-output) and r-refresh.md (governance + work-output)**

  r-ship.md: apply `replace_all` of bare `work-output/` → `.rdf/work-output/`
  (lines 19, 26, 265).

  r-refresh.md: apply `replace_all` of `.claude/governance/` → `.rdf/governance/`
  (4 refs at lines 9, 37, 39, 86).
  Apply `replace_all` of bare `work-output/` → `.rdf/work-output/` (line 218).

- [ ] **Step 10: r-util-mem-audit.md (1 memory)**

  Old (line 13):
  ```
  `/root/.claude/projects/-root-admin-work-proj-{project}/memory/MEMORY.md`
  ```
  New:
  ```
  `.rdf/memory/MEMORY.md`
  ```

- [ ] **Step 11: Verify**

  ```bash
  # Zero .claude/governance/ refs in commands (excluding templates/)
  grep -r '\.claude/governance/' canonical/commands/ --include='*.md' | grep -v 'templates/' | wc -l
  # expect: 0

  # Zero bare work-output/ refs (all should be .rdf/work-output/)
  grep -r 'work-output/' canonical/commands/ --include='*.md' | grep -v '\.rdf/work-output/' | wc -l
  # expect: 0

  # Zero CC auto-memory path refs
  grep -r '/root/\.claude/projects/' canonical/commands/ | wc -l
  # expect: 0

  # Positive: .rdf/governance/ refs exist
  grep -rc '\.rdf/governance/' canonical/commands/ --include='*.md' | awk -F: '$2>0' | wc -l
  # expect: >= 20
  ```

- [ ] **Step 12: Commit**

  ```bash
  git add canonical/commands/r-init.md canonical/commands/r-build.md \
        canonical/commands/r-review.md canonical/commands/r-test.md \
        canonical/commands/r-verify.md canonical/commands/r-spec.md \
        canonical/commands/r-status.md canonical/commands/r-save.md \
        canonical/commands/r-ship.md canonical/commands/r-refresh.md \
        canonical/commands/r-mode.md canonical/commands/r-audit.md \
        canonical/commands/r-util-chg-dedup.md canonical/commands/r-util-chg-gen.md \
        canonical/commands/r-util-ci-gen.md canonical/commands/r-util-code-modernize.md \
        canonical/commands/r-util-code-scan.md canonical/commands/r-util-doc-gen.md \
        canonical/commands/r-util-lib-release.md canonical/commands/r-util-lib-sync.md \
        canonical/commands/r-util-mem-compact.md canonical/commands/r-util-test-dedup.md \
        canonical/commands/r-util-mem-audit.md
  git commit -m "$(cat <<'EOF'
  Update all canonical commands for .rdf/ paths

  [Change] .claude/governance/ → .rdf/governance/ across 22 command files
  [Change] Bare work-output/ → .rdf/work-output/ across 8 command files
  [Change] CC auto-memory path → .rdf/memory/ in r-save.md, r-util-mem-audit.md
  EOF
  )"
  ```

---

### Phase 5: Update templates, reference, schemas, scripts

Update governance templates, reference docs, schema, and the subagent-stop
hook script for `.rdf/` paths.

**Files:**
- Modify: `canonical/commands/templates/governance-architecture.md`
- Modify: `canonical/commands/templates/governance-anti-patterns.md`
- Modify: `canonical/commands/templates/governance-conventions.md`
- Modify: `canonical/commands/templates/governance-constraints.md`
- Modify: `canonical/commands/templates/governance-verification.md`
- Modify: `canonical/commands/templates/governance-index.md`
- Modify: `canonical/reference/framework.md`
- Modify: `canonical/reference/session-safety.md`
- Modify: `canonical/reference/memory-standards.md`
- Modify: `canonical/scripts/subagent-stop.sh`
- Modify: `schemas/governance-index.md`

- **Mode**: serial-context
- **Risk**: low
- **Type**: refactor
- **Gates**: G1
- **Accept**: `grep -r '\.claude/governance/' canonical/commands/templates/ canonical/reference/ schemas/` returns 0;
  `grep 'work-output/' canonical/reference/ canonical/scripts/subagent-stop.sh | grep -v '\.rdf/'` returns 0
- **Test**: `grep -r '\.claude/governance/' canonical/commands/templates/ canonical/reference/ schemas/ | wc -l` → 0;
  `bash -n canonical/scripts/subagent-stop.sh` → exit 0
- **Edge cases**: none

- [ ] **Step 1: Update 5 governance template files**

  Each has one `.user-modified` comment referencing `.claude/governance/`:

  Old (line 4 in each):
  ```
       .claude/governance/.user-modified -->
  ```
  New:
  ```
       .rdf/governance/.user-modified -->
  ```

  Apply to: `governance-architecture.md`, `governance-anti-patterns.md`,
  `governance-conventions.md`, `governance-constraints.md`,
  `governance-verification.md`.

- [ ] **Step 2: Update governance-index.md template**

  Old (lines 11, 16):
  ```
  These files are NOT in .claude/governance/ — they are the project's
  ...
  {One line per generated file in .claude/governance/.
  ```

  New:
  ```
  These files are NOT in .rdf/governance/ — they are the project's
  ...
  {One line per generated file in .rdf/governance/.
  ```

- [ ] **Step 3: Update framework.md**

  Apply `replace_all` of `.claude/governance/` → `.rdf/governance/` (lines 23-24).

  Apply `replace_all` of bare `work-output/` → `.rdf/work-output/` in:
  - Lines 44-46: state artifact locations
  - Lines 66-74: execution artifact locations
  - Lines 148, 192: handoff references

  Update the Exclusion Protocol section (lines 214-224):
  Old:
  ```
  CLAUDE.md
  PLAN*.md
  AUDIT.md
  MEMORY.md
  .claude/
  work-output/
  audit-output/
  ```
  New:
  ```
  CLAUDE.md
  PLAN*.md
  AUDIT.md
  MEMORY.md
  .rdf/
  ```

- [ ] **Step 4: Update session-safety.md**

  Apply `replace_all` of bare `work-output/` → `.rdf/work-output/` across
  all 7 references (lines 18, 48, 50, 53, 55, 73).

- [ ] **Step 5: Update memory-standards.md**

  Old (line 9):
  ```
  Each project's MEMORY.md (under `/root/.claude/projects/`) must maintain
  ```
  New:
  ```
  Each project's MEMORY.md (under `.rdf/memory/`) must maintain
  ```

- [ ] **Step 6: Update subagent-stop.sh**

  Old (lines 34-40):
  ```bash
  if [[ -d "./work-output" ]]; then
      feed_dir="./work-output"
  elif [[ -d "/root/admin/work/proj/work-output" ]]; then
      feed_dir="/root/admin/work/proj/work-output"
  else
      # Create parent-level work-output if nothing exists
      feed_dir="/root/admin/work/proj/work-output"
      mkdir -p "$feed_dir"
  fi
  ```

  New:
  ```bash
  if [[ -d "./.rdf/work-output" ]]; then
      feed_dir="./.rdf/work-output"
  elif [[ -d "/root/admin/work/proj/.rdf/work-output" ]]; then
      feed_dir="/root/admin/work/proj/.rdf/work-output"
  else
      # Create parent-level .rdf/work-output if nothing exists
      feed_dir="/root/admin/work/proj/.rdf/work-output"
      mkdir -p "$feed_dir"
  fi
  ```

- [ ] **Step 7: Update schemas/governance-index.md**

  Old (lines 6, 47, 49):
  ```
  `.claude/governance/index.md` in the target project.
  ...
  (CLAUDE.md, AGENTS.md, etc.) — these are NOT in .claude/governance/
  ...
  .claude/governance/
  ```

  New (replace all `.claude/governance/` → `.rdf/governance/`):
  ```
  `.rdf/governance/index.md` in the target project.
  ...
  (CLAUDE.md, AGENTS.md, etc.) — these are NOT in .rdf/governance/
  ...
  .rdf/governance/
  ```

- [ ] **Step 8: Verify and deploy**

  ```bash
  grep -r '\.claude/governance/' canonical/commands/templates/ canonical/reference/ schemas/
  # expect: 0 hits

  grep 'work-output/' canonical/reference/framework.md canonical/reference/session-safety.md \
    canonical/scripts/subagent-stop.sh | grep -v '\.rdf/work-output/'
  # expect: 0 hits

  grep '/root/\.claude/projects/' canonical/reference/memory-standards.md
  # expect: 0 hits

  bash -n canonical/scripts/subagent-stop.sh
  # expect: exit 0

  bash bin/rdf generate claude-code 2>&1 | tail -3
  ```

- [ ] **Step 9: Commit**

  ```bash
  git add canonical/commands/templates/governance-architecture.md \
        canonical/commands/templates/governance-anti-patterns.md \
        canonical/commands/templates/governance-conventions.md \
        canonical/commands/templates/governance-constraints.md \
        canonical/commands/templates/governance-verification.md \
        canonical/commands/templates/governance-index.md \
        canonical/reference/framework.md \
        canonical/reference/session-safety.md \
        canonical/reference/memory-standards.md \
        canonical/scripts/subagent-stop.sh \
        schemas/governance-index.md
  git commit -m "$(cat <<'EOF'
  Update templates, reference docs, schemas, and scripts for .rdf/ paths

  [Change] 5 governance templates: .user-modified path → .rdf/governance/
  [Change] governance-index.md template: .claude/governance/ → .rdf/governance/
  [Change] framework.md: governance, work-output, and exclusion paths updated
  [Change] session-safety.md: work-output/ → .rdf/work-output/
  [Change] memory-standards.md: CC auto-memory path → .rdf/memory/
  [Change] subagent-stop.sh: work-output/ → .rdf/work-output/
  [Change] schemas/governance-index.md: .claude/governance/ → .rdf/governance/
  EOF
  )"
  ```

---

### Phase 6: Documentation, profiles, dead code removal

Update project documentation, profile templates, and delete v2 archived
content that is no longer reachable.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `profiles/core/governance-template.md`
- Modify: `CHANGELOG`
- Modify: `CHANGELOG.RELEASE`
- Delete: `canonical/commands-v2-archived/` (entire directory)
- Delete: `canonical/agents-v2-archived/` (entire directory)
- Delete: `adapters/claude-code/agent-meta-v2.json`

- **Mode**: serial-context
- **Risk**: low
- **Type**: refactor
- **Gates**: G1
- **Accept**: `grep -r '\.claude/governance/' profiles/` returns 0;
  v2-archived directories do not exist; agent-meta-v2.json does not exist
- **Test**: `ls canonical/commands-v2-archived/ canonical/agents-v2-archived/` fails;
  `ls adapters/claude-code/agent-meta-v2.json` fails
- **Edge cases**: none

- [ ] **Step 1: Update CLAUDE.md**

  Update the exclude list reference to match the new pattern.
  If CLAUDE.md references `.claude/` or `work-output/` in its exclude
  examples, update to `.rdf/`.

- [ ] **Step 2: Update profiles/core/governance-template.md**

  Old (line 13):
  ```
    .claude/) -- exclude via .git/info/exclude, not .gitignore
  ```
  New:
  ```
    .rdf/) -- exclude via .git/info/exclude, not .gitignore
  ```

- [ ] **Step 3: Update CHANGELOG and CHANGELOG.RELEASE**

  Add entries for the migration under the current version section:
  ```
  [New] rdf migrate: move projects from .claude/ + work-output/ to .rdf/
  [Change] All canonical content uses .rdf/governance/ instead of .claude/governance/
  [Change] work-output/ consolidated under .rdf/work-output/
  [Change] Memory resolved from .rdf/memory/ instead of CC auto-memory path
  [Change] rdf init creates .rdf/ structure instead of work-output/
  [Change] rdf doctor checks .rdf/ structure, detects legacy state
  [Remove] v2 archived commands and agents (canonical/{commands,agents}-v2-archived/)
  [Remove] v2 agent metadata (agent-meta-v2.json)
  ```

- [ ] **Step 4: Delete v2 archives and stale metadata**

  ```bash
  # Delete v2 archived content
  /usr/bin/rm -rf canonical/commands-v2-archived/
  /usr/bin/rm -rf canonical/agents-v2-archived/
  /usr/bin/rm -f adapters/claude-code/agent-meta-v2.json
  ```

  Verify:
  ```bash
  ls canonical/commands-v2-archived/ 2>&1
  # expect: "No such file or directory"

  ls canonical/agents-v2-archived/ 2>&1
  # expect: "No such file or directory"

  ls adapters/claude-code/agent-meta-v2.json 2>&1
  # expect: "No such file or directory"
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add CLAUDE.md profiles/core/governance-template.md CHANGELOG CHANGELOG.RELEASE
  git rm -r canonical/commands-v2-archived/ canonical/agents-v2-archived/
  git rm adapters/claude-code/agent-meta-v2.json
  git commit -m "$(cat <<'EOF'
  Update documentation, profiles, and remove v2 dead code

  [Change] CLAUDE.md: update exclude list reference to .rdf/
  [Change] profiles/core/governance-template.md: .claude/ → .rdf/ in exclude example
  [Change] CHANGELOG, CHANGELOG.RELEASE: add .rdf/ migration entries
  [Remove] canonical/commands-v2-archived/ — v2 commands fully archived
  [Remove] canonical/agents-v2-archived/ — v2 agents fully archived
  [Remove] adapters/claude-code/agent-meta-v2.json — v2 metadata
  EOF
  )"
  ```

---

### Phase 7: Regenerate, migrate active projects, verify, push

Full deployment cycle: regenerate adapter output from updated canonical
content, migrate all workspace projects to `.rdf/` structure, run
comprehensive verification, push.

**Files:**
- None modified — operational verification only

- **Mode**: serial-context
- **Risk**: medium
- **Type**: config
- **Gates**: G1+G2
- **Accept**: `rdf generate claude-code` succeeds; `rdf doctor --all` shows no FAIL;
  zero `.claude/governance/` refs in canonical/; all verification commands pass;
  CC deployment symlinks intact
- **Test**: full verification suite from spec section 10b
- **Edge cases**: EC6 (active dispatch during migration — warn only)

- [ ] **Step 1: Full regeneration**

  ```bash
  bash bin/rdf generate claude-code 2>&1 | tail -5
  # expect: successful generation with updated file counts
  ```

- [ ] **Step 2: Migrate all workspace projects**

  ```bash
  bash bin/rdf migrate --dry-run --all 2>&1
  # expect: shows WOULD MOVE operations for each project with .claude/governance/

  bash bin/rdf migrate --all 2>&1
  # expect: [✓] lines for each project, exit 0
  ```

- [ ] **Step 3: Run full verification suite**

  ```bash
  # Goal 2: zero .claude/governance/ refs in canonical
  grep -r '\.claude/governance/' canonical/ | wc -l
  # expect: 0

  # Goal 3: zero bare work-output/ refs (all .rdf/work-output/)
  grep -r 'work-output/' canonical/ | grep -v '\.rdf/work-output/' | grep -v 'r-sync.md' | wc -l
  # expect: 0

  # Goal 4: zero CC auto-memory path refs
  grep -r '/root/\.claude/projects/' canonical/ | wc -l
  # expect: 0

  # Goal 9: only CC-specific .claude refs remain
  grep -r '\.claude' canonical/ | grep -v 'r-sync.md' | grep -v 'scripts/' | \
    grep -v 'v2-archived' | grep -v '\.rdf/' | wc -l
  # expect: 0

  # Goal 10: CC deployment intact
  ls -la /root/.claude/commands /root/.claude/agents /root/.claude/scripts
  # expect: symlinks pointing to adapter output/
  ```

- [ ] **Step 4: Doctor check**

  ```bash
  bash bin/rdf doctor --all 2>&1 | tail -10
  # expect: all OK, 0 FAIL, no .claude/governance/ warnings
  ```

- [ ] **Step 5: Push**

  ```bash
  git push
  ```

---
