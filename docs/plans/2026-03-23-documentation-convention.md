# Implementation Plan: Documentation Convention

**Goal:** Add a cross-project documentation convention to RDF that defines
README structure, SVG asset specifications, badge standards, companion file
templates, and doctor enforcement — as a brand-agnostic product feature.

**Architecture:** New reference document (`documentation-standard.md`) plus
template files (`SECURITY.md`, `CONTRIBUTING.md`) in `rdf/reference/`. Doctor
gains a `readme` scope with level-gated checks. Init gains companion file
generation. Workspace gets a `brand.md` for rfxn-specific brand definitions.

**Tech Stack:** Bash 4.1+, RDF CLI (`rdf doctor`, `rdf init`), Markdown

**Spec:** docs/specs/2026-03-23-documentation-convention-design.md

**Phases:** 5

## Conventions

**Commit message format:** Free-form descriptive (RDF convention)
Tags: `[New]`, `[Change]`, `[Fix]`

**CRITICAL:** Never `git add -A` or `git add .` — stage files explicitly.

**Template placeholders:** `{{VARIABLE_NAME}}` double-brace syntax.

**`sed` delimiter:** Use `|` not `/` for template substitution to avoid
conflicts with path characters in values.

**Changelog batching:** Per parent CLAUDE.md exception clause, changelog
updates are batched into Phase 5. Phases 1-4 do not update CHANGELOG.

## File Map

### New Files

| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `reference/documentation-standard.md` | ~350 | README convention: section order, SVG specs, badge standards, levels | N/A (reference doc) |
| `reference/templates/SECURITY.md` | ~30 | SECURITY.md template with `{{PROJECT}}` placeholders | N/A (template) |
| `reference/templates/CONTRIBUTING.md` | ~40 | CONTRIBUTING.md template with placeholders | N/A (template) |
| `/root/admin/work/proj/reference/brand.md` | ~60 | rfxn brand definition (workspace, not committed to RDF) | N/A (workspace) |

### Modified Files

| File | Changes | Test File |
|------|---------|-----------|
| `lib/cmd/doctor.sh` | +`_check_readme()` function (~120 lines), `readme` scope in `_doctor_one()`, usage text | N/A (manual verification) |
| `lib/cmd/init.sh` | +companion file generation in `_init_one()`, +`.rdf/docs-level` creation | N/A (manual verification) |
| `CHANGELOG` | New version entry | N/A (docs) |
| `CHANGELOG.RELEASE` | Release entry | N/A (docs) |

## Phase Dependencies

- Phase 1: none
- Phase 2: none
- Phase 3: [1]
- Phase 4: [1, 2]
- Phase 5: [3, 4]

---

### Phase 1: Convention document and templates

Write the core reference document and companion file templates.

**Files:**
- Create: `reference/documentation-standard.md`
- Create: `reference/templates/SECURITY.md`
- Create: `reference/templates/CONTRIBUTING.md`

- **Mode**: serial-agent
- **Accept**: All 3 files exist; `grep -c 'Floor\|Level 2\|Level 3' reference/documentation-standard.md` returns >=10; `grep -c '{{PROJECT}}' reference/templates/SECURITY.md` returns >=2; `grep -c '{{PROJECT}}' reference/templates/CONTRIBUTING.md` returns >=2
- **Test**: Content verification via grep commands in accept criteria
- **Edge cases**: None — these are new standalone files

- [x] **Step 1: Create `reference/templates/` directory**

  ```bash
  mkdir -p reference/templates
  ```

- [x] **Step 2: Create `reference/templates/SECURITY.md`**

  Write the template with `{{PROJECT}}`, `{{CONTACT_EMAIL}}` placeholders.
  Exact content from spec Section 5.2.

- [x] **Step 3: Create `reference/templates/CONTRIBUTING.md`**

  Write the template with `{{PROJECT}}`, `{{ORG}}`, `{{LICENSE}}`
  placeholders. Exact content from spec Section 5.3.

- [x] **Step 4: Create `reference/documentation-standard.md`**

  The core convention document (~350 lines). Write per spec Section 5.1,
  covering all 10 subsections: documentation levels, README template,
  above-the-fold SVG specs, badge conventions, middle section rules,
  companion file requirements, asset directory convention, enforcement
  checks. Include the exact level requirements table, README section
  template, `<picture>` tag pattern, SVG dimension specs, and badge
  order definitions.

- [x] **Step 5: Verify**

  ```bash
  ls reference/documentation-standard.md reference/templates/SECURITY.md reference/templates/CONTRIBUTING.md
  # expect: all 3 files listed

  grep -c 'Floor\|Level 2\|Level 3' reference/documentation-standard.md
  # expect: >=10

  grep -c '{{PROJECT}}' reference/templates/SECURITY.md
  # expect: >=2

  grep -c '{{PROJECT}}' reference/templates/CONTRIBUTING.md
  # expect: >=2
  ```

- [x] **Step 6: Commit**

  ```bash
  git add reference/documentation-standard.md reference/templates/SECURITY.md reference/templates/CONTRIBUTING.md
  git commit -m "$(cat <<'EOF'
  [New] Documentation convention and companion file templates

  [New] reference/documentation-standard.md — README template, section ordering,
  SVG asset specs, badge conventions, documentation level system (floor/level-2/level-3)
  [New] reference/templates/SECURITY.md — template with {{PROJECT}} placeholders
  [New] reference/templates/CONTRIBUTING.md — template with {{PROJECT}}/{{ORG}}/{{LICENSE}} placeholders
  EOF
  )"
  ```

---

### Phase 2: Workspace brand definition

Create the rfxn-specific brand file in the workspace `reference/`
directory. This is NOT committed to the RDF repo.

**Files:**
- Create: `/root/admin/work/proj/reference/brand.md` (workspace file)

- **Mode**: serial-context
- **Accept**: `ls /root/admin/work/proj/reference/brand.md` shows file; `grep '#07080a' /root/admin/work/proj/reference/brand.md` matches
- **Test**: Content verification via grep
- **Edge cases**: Workspace `reference/` is not a git repo — no commit needed

- [x] **Step 1: Create `/root/admin/work/proj/reference/brand.md`**

  Write the rfxn brand definition covering: dark theme palette (#07080a bg,
  #161b22 surface, #4ade80 accent), light theme palette (#f8fafc bg,
  #16a34a accent), typography (JetBrains Mono, SVG Base64 WOFF2 embedding),
  project identities (APF firewall gate, BFD threshold line, LMD scan beam,
  Sigforge fingerprint mark), and SVG template notes (window chrome pattern,
  rounded rectangle nodes rx=6, drop shadow filter, background gradient).

- [x] **Step 2: Verify**

  ```bash
  ls /root/admin/work/proj/reference/brand.md
  # expect: file listed

  grep '#07080a' /root/admin/work/proj/reference/brand.md
  # expect: match found
  ```

  > No commit — workspace file, not version-controlled.

---

### Phase 3: Doctor readme scope

Add `_check_readme()` to `rdf doctor` with level-gated checks.

**Files:**
- Modify: `lib/cmd/doctor.sh` (+`_check_readme()`, scope dispatch, usage)

- **Mode**: serial-agent
- **Accept**: `grep -c '_check_readme' lib/cmd/doctor.sh` returns 3; `bash -n lib/cmd/doctor.sh` exits 0
- **Test**: `bash -n lib/cmd/doctor.sh`; manual `rdf doctor --scope readme`
- **Edge cases**: No README (early return after FAIL); no `.rdf/docs-level` (defaults to floor); unknown `docs_level` value (treated as floor); badge detection matches both shields.io and GitHub Actions URLs; `## 4. CLI Usage` matches as Usage (prefix match on `## 4.`)

- [x] **Step 1: Update usage text (line 19)**

  Old:
  ```
                        artifacts, drift, memory, plan, github, sync
  ```

  New:
  ```
                        artifacts, drift, memory, plan, github, sync, readme
  ```

- [x] **Step 2: Add `_check_readme()` function before `_resolve_version_for_doctor()` (before line 374)**

  Full function (~120 lines). Insert before the `_resolve_version_for_doctor()`
  function definition:

  ```bash
  # ── Check: readme ──
  _check_readme() {
      local path="$1"

      # Read documentation level from .rdf/docs-level (default: floor)
      local docs_level="floor"
      if [[ -f "${path}/.rdf/docs-level" ]]; then
          docs_level="$(< "${path}/.rdf/docs-level")"
          docs_level="${docs_level%%[[:space:]]}"
          case "$docs_level" in
              floor|level-2|level-3) ;;
              *) docs_level="floor" ;;
          esac
      fi

      # --- Floor checks (always run) ---

      if [[ ! -f "${path}/README.md" ]]; then
          _add_result "readme" "$_FAIL" "README.md missing"
          return 0
      fi

      local readme="${path}/README.md"
      local line_count
      line_count="$(wc -l < "$readme")"
      _add_result "readme" "$_OK" "README.md present (${line_count} lines)"

      # Badge row: shields.io or GitHub Actions badge
      if grep -qE 'shields\.io|github\.com/.*badge\.svg|img\.shields' "$readme" 2>/dev/null; then
          local badge_count
          badge_count="$(grep -cE 'shields\.io|github\.com/.*badge\.svg|img\.shields' "$readme" 2>/dev/null || echo "0")"
          _add_result "readme" "$_OK" "badge row detected (${badge_count} badges)"
      else
          _add_result "readme" "$_FAIL" "badge row not found (no shields.io or GitHub badge URLs)"
      fi

      if grep -qi '^## Quick Start' "$readme" 2>/dev/null; then
          _add_result "readme" "$_OK" "## Quick Start present"
      else
          _add_result "readme" "$_FAIL" "## Quick Start section missing"
      fi

      if grep -qi '^## .*License' "$readme" 2>/dev/null; then
          _add_result "readme" "$_OK" "## License present"
      else
          _add_result "readme" "$_FAIL" "## License section missing"
      fi

      local numbered_count
      numbered_count="$(grep -cE '^## [0-9]+\.' "$readme" 2>/dev/null || echo "0")"
      if [[ "$numbered_count" -gt 0 ]]; then
          _add_result "readme" "$_OK" "numbered sections (${numbered_count} found)"
      else
          _add_result "readme" "$_FAIL" "no numbered sections (## N. format expected)"
      fi

      if grep -qE '^## 3\.' "$readme" 2>/dev/null; then
          _add_result "readme" "$_OK" "## 3. Configuration present"
      else
          _add_result "readme" "$_FAIL" "## 3. section missing (Configuration expected)"
      fi

      if grep -qE '^## 4\.' "$readme" 2>/dev/null; then
          _add_result "readme" "$_OK" "## 4. Usage present"
      else
          _add_result "readme" "$_FAIL" "## 4. section missing (Usage expected)"
      fi

      if grep -qiE 'exit.code|exit.status' "$readme" 2>/dev/null && \
         grep -qE '^\|.*\|.*\|' "$readme" 2>/dev/null; then
          _add_result "readme" "$_OK" "exit codes table found"
      else
          _add_result "readme" "$_FAIL" "exit codes table not found in README"
      fi

      # --- Level 2 checks ---
      if [[ "$docs_level" == "level-2" ]] || [[ "$docs_level" == "level-3" ]]; then
          if grep -qi "^## What's New" "$readme" 2>/dev/null; then
              _add_result "readme" "$_OK" "What's New section present"
          else
              _add_result "readme" "$_FAIL" "What's New section missing (level-2 requirement)"
          fi

          if grep -qi '^## Contents' "$readme" 2>/dev/null; then
              _add_result "readme" "$_OK" "## Contents (ToC) present"
          else
              _add_result "readme" "$_FAIL" "## Contents section missing (level-2 requirement)"
          fi

          if grep -qi '^## .*Integration' "$readme" 2>/dev/null; then
              _add_result "readme" "$_OK" "## Integration present"
          else
              _add_result "readme" "$_FAIL" "## Integration section missing (level-2 requirement)"
          fi

          if [[ -f "${path}/SECURITY.md" ]]; then
              _add_result "readme" "$_OK" "SECURITY.md present"
          else
              _add_result "readme" "$_FAIL" "SECURITY.md missing (level-2 requirement)"
          fi

          if [[ -f "${path}/CONTRIBUTING.md" ]]; then
              _add_result "readme" "$_OK" "CONTRIBUTING.md present"
          else
              _add_result "readme" "$_FAIL" "CONTRIBUTING.md missing (level-2 requirement)"
          fi

          if [[ -f "${path}/assets/banner-dark.svg" ]]; then
              _add_result "readme" "$_OK" "assets/banner-dark.svg present"
          else
              _add_result "readme" "$_FAIL" "assets/banner-dark.svg missing (level-2 requirement)"
          fi
          if [[ -f "${path}/assets/banner-light.svg" ]]; then
              _add_result "readme" "$_OK" "assets/banner-light.svg present"
          else
              _add_result "readme" "$_FAIL" "assets/banner-light.svg missing (level-2 requirement)"
          fi

          if grep -q '<picture>' "$readme" 2>/dev/null; then
              _add_result "readme" "$_OK" "<picture> dark/light pattern present"
          else
              _add_result "readme" "$_FAIL" "<picture> tag missing in README (level-2 requirement)"
          fi
      fi

      # --- Level 3 checks ---
      if [[ "$docs_level" == "level-3" ]]; then
          if grep -qi '^## .*Troubleshooting' "$readme" 2>/dev/null; then
              _add_result "readme" "$_OK" "## Troubleshooting present"
          else
              _add_result "readme" "$_FAIL" "## Troubleshooting section missing (level-3 requirement)"
          fi

          local has_pipeline=0
          for f in "${path}"/assets/pipeline*.svg "${path}"/assets/architecture*.svg; do
              if [[ -f "$f" ]]; then
                  has_pipeline=1
                  break
              fi
          done
          if [[ $has_pipeline -eq 1 ]]; then
              _add_result "readme" "$_OK" "pipeline/architecture SVG present"
          else
              _add_result "readme" "$_FAIL" "pipeline/architecture SVG missing in assets/ (level-3 requirement)"
          fi

          local has_demo=0
          for f in "${path}"/assets/terminal-demo* "${path}"/assets/demo*; do
              if [[ -f "$f" ]]; then
                  has_demo=1
                  break
              fi
          done
          if [[ $has_demo -eq 1 ]]; then
              _add_result "readme" "$_OK" "terminal demo asset present"
          else
              _add_result "readme" "$_FAIL" "terminal demo asset missing in assets/ (level-3 requirement)"
          fi
      fi
  }
  ```

- [x] **Step 3: Add `readme` to `_doctor_one()` scope dispatch (lines 467-483)**

  Add `_check_readme "$path"` to the `""|all)` branch after
  `_check_sync "$path"`. Add `readme)    _check_readme "$path" ;;`
  case. Update the error message with `readme` in the valid scope list.

- [x] **Step 4: Verify**

  ```bash
  bash -n lib/cmd/doctor.sh && echo "OK"
  # expect: OK

  grep -c '_check_readme' lib/cmd/doctor.sh
  # expect: 3

  grep 'readme' lib/cmd/doctor.sh | wc -l
  # expect: >=5
  ```

- [x] **Step 5: Commit**

  ```bash
  git add lib/cmd/doctor.sh
  git commit -m "$(cat <<'EOF'
  [New] rdf doctor --scope readme: documentation convention enforcement

  [New] _check_readme() — level-gated README structure validation
  [New] readme scope in doctor: badges, sections, companion files, SVG assets
  [Change] Floor: badge row, Quick Start, License, numbered sections, Config/Usage, exit codes
  [Change] Level 2: What's New, Contents, Integration, SECURITY.md, CONTRIBUTING.md, banners
  [Change] Level 3: Troubleshooting, pipeline SVG, terminal demo
  EOF
  )"
  ```

---

### Phase 4: Init companion file generation

Extend `rdf init` to create `.rdf/docs-level`, `SECURITY.md`, and
`CONTRIBUTING.md` from templates.

**Files:**
- Modify: `lib/cmd/init.sh` (+docs-level, +companion file generation)

- **Mode**: serial-agent
- **Accept**: `grep -c 'docs-level\|SECURITY\|CONTRIBUTING' lib/cmd/init.sh` returns >=6; `bash -n lib/cmd/init.sh` exits 0
- **Test**: `bash -n lib/cmd/init.sh`; manual `rdf init --dry-run`
- **Edge cases**: SECURITY.md already exists (skip); CONTRIBUTING.md already exists (skip); git remote has no org (fallback to basename); `.rdf/docs-level` already exists (skip)

- [x] **Step 1: Add `_generate_companion_files()` function after `_copy_reference_docs()` (after line 482)**

  ~45-line function that:
  1. Resolves `org` from `git remote get-url origin` (fallback: `rfxn`)
  2. Sets `contact_email="proj@rfxn.com"`, `license="GNU GPL v2"`
  3. If SECURITY.md missing and template exists: `sed` substitute
     `{{PROJECT}}` and `{{CONTACT_EMAIL}}` using `|` delimiter, write
  4. If CONTRIBUTING.md missing and template exists: `sed` substitute
     `{{PROJECT}}`, `{{ORG}}`, `{{LICENSE}}` using `|` delimiter, write
  5. Guards: `[[ -f "${path}/SECURITY.md" ]]` skip, dry-run support

- [x] **Step 2: Add `.rdf/docs-level` creation in `_init_one()` (after line 524)**

  After the subdirectory creation block, add `docs-level` file creation
  with profile-aware inference. Products (projects with a `files/`
  directory matching their name — APF, BFD, LMD pattern) default to
  `level-2`; everything else defaults to `floor`:

  ```bash
      # 3b. Documentation level
      if [[ ! -f "${rdf_dir}/docs-level" ]]; then
          # Infer default: products → level-2, libraries → floor
          local default_level="floor"
          if [[ -f "${path}/files/${name}" ]] || [[ -f "${path}/bin/${name}" ]]; then
              default_level="level-2"
          fi
          if [[ "$dry_run" -eq 1 ]]; then
              rdf_log "  WOULD CREATE: .rdf/docs-level (${default_level})"
          else
              echo "$default_level" > "${rdf_dir}/docs-level"
              rdf_log "  created .rdf/docs-level (${default_level})"
          fi
      fi
  ```

- [x] **Step 3: Add companion file generation call in `_init_one()` (after line 527)**

  After `_copy_reference_docs` call, add:
  `_generate_companion_files "$path" "$dry_run"`

- [x] **Step 4: Verify**

  ```bash
  bash -n lib/cmd/init.sh && echo "OK"
  # expect: OK

  grep -c 'docs-level\|SECURITY\|CONTRIBUTING' lib/cmd/init.sh
  # expect: >=6

  grep -c '_generate_companion_files' lib/cmd/init.sh
  # expect: 2
  ```

- [x] **Step 5: Commit**

  ```bash
  git add lib/cmd/init.sh
  git commit -m "$(cat <<'EOF'
  [New] rdf init generates SECURITY.md, CONTRIBUTING.md, and .rdf/docs-level

  [New] _generate_companion_files() — creates SECURITY.md and CONTRIBUTING.md
  from reference/templates/ with {{PROJECT}}/{{ORG}} substitution via sed
  [New] .rdf/docs-level file created during init (default: floor)
  [Change] _init_one() calls companion file generation after reference docs
  EOF
  )"
  ```

---

### Phase 5: Changelog and verification

Update changelogs and run final verification across all changes.

**Files:**
- Modify: `CHANGELOG`
- Modify: `CHANGELOG.RELEASE`

- **Mode**: serial-context
- **Accept**: `head -5 CHANGELOG` shows documentation convention entry; `bash -n lib/cmd/doctor.sh lib/cmd/init.sh` exits 0
- **Test**: `bash -n` on both shell files; grep verification
- **Edge cases**: None

- [x] **Step 1: Update CHANGELOG**

  Prepend new entry matching existing format.

- [x] **Step 2: Update CHANGELOG.RELEASE**

  Mirror CHANGELOG entry.

- [x] **Step 3: Full verification**

  ```bash
  bash -n lib/cmd/doctor.sh && echo "doctor OK"
  # expect: doctor OK
  bash -n lib/cmd/init.sh && echo "init OK"
  # expect: init OK

  ls reference/documentation-standard.md reference/templates/SECURITY.md reference/templates/CONTRIBUTING.md
  # expect: all 3 files listed

  grep -c '_check_readme' lib/cmd/doctor.sh
  # expect: 3

  grep -c '_generate_companion_files' lib/cmd/init.sh
  # expect: 2
  ```

- [x] **Step 4: Commit**

  ```bash
  git add CHANGELOG CHANGELOG.RELEASE
  git commit -m "$(cat <<'EOF'
  [Change] Changelog: documentation convention (reference doc, templates, doctor, init)
  EOF
  )"
  ```

---
