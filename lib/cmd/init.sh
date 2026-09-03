#!/usr/bin/env bash
# lib/cmd/init.sh — rdf init subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_init_usage() {
    cat <<'USAGE'
Usage: rdf init <path> [options]

Initialize a project with RDF conventions. Creates CLAUDE.md from profile
governance templates, sets up .git/info/exclude, creates .rdf/ directory
structure with reference docs from detected profiles.

Arguments:
  path                  Project directory to initialize

Options:
  --type PROFILES       Force profile(s): comma-separated list of profile names
                        (e.g., shell, rust,infrastructure, python,database)
                        (default: auto-detect from project signals)
  --tools LIST          claude-code (default), agent-skills, agents-md, codex,
                        antigravity (comma-separated; agents-md and the
                        composites require a git repository)
  --version X.Y.Z       Initial version string (default: from VERSION file or 0.1.0)
  --no-memory           Skip MEMORY.md placeholder creation
  --github              Create labels + repo project board via gh CLI
  --batch               Process multiple directories (path is parent dir)
  --dry-run             Show what would be created without writing

Examples:
  rdf init ~/projects/my-project
  rdf init ~/projects/my-project --type shell --github
  rdf init ~/projects/my-project --type rust,infrastructure
  rdf init ~/projects --batch --type minimal
  rdf init ~/projects/inactive --batch --dry-run
USAGE
}

# Known profile names for validation (excludes 'core' — always implicit)
_KNOWN_PROFILES="shell python go rust typescript perl php node frontend database infrastructure minimal rfxn-workspace"

# _has_files path pattern — git ls-files (tracked+untracked) in git repos, find(1) otherwise; rc 0 if any match
# Capture rather than `| grep -q`: grep -q quits after ~96K, and under `pipefail`
# the producer's SIGPIPE (141) then suppresses the whole detection on big repos.
_has_files() {
    local path="$1"
    local pattern="$2"
    local listing

    if [[ -d "${path}/.git" ]]; then
        # --cached --others --exclude-standard: tracked + untracked-but-not-ignored —
        # a repo initialised before its first commit still detects its sources
        listing="$(git -C "$path" ls-files --cached --others --exclude-standard -- "$pattern" 2>/dev/null)" || return 1  # stderr/rc: not a git repo is safe
        [[ -n "$listing" ]] && return 0
    else
        # Non-git fallback: find with maxdepth for top-level patterns,
        # recursive for deeper searches. Use -quit for early exit.
        listing="$(find "$path" -maxdepth 3 -name "$pattern" -print -quit 2>/dev/null)" || return 1  # stderr/rc: permission errors safe to ignore
        [[ -n "$listing" ]] && return 0
    fi
    return 1
}

# Check if project has non-declaration .ts files (exclude .d.ts-only projects)
_has_real_ts_files() {
    local path="$1"
    local listing

    if [[ -d "${path}/.git" ]]; then
        # --cached --others --exclude-standard mirrors _has_files: an untracked
        # app.ts in a not-yet-committed repo still activates the profile
        listing="$(git -C "$path" ls-files --cached --others --exclude-standard -- '*.ts' 2>/dev/null | grep -v '\.d\.ts$')" || return 1  # stderr/rc: not a git repo, or every .ts is a declaration
        [[ -n "$listing" ]] && return 0
    else
        listing="$(find "$path" -maxdepth 3 -name '*.ts' -not -name '*.d.ts' -print -quit 2>/dev/null)" || return 1  # stderr/rc: permission errors safe to ignore
        [[ -n "$listing" ]] && return 0
    fi
    return 1
}

# Check if package.json contains a frontend framework dependency
_has_frontend_dep() {
    local path="$1"
    local pkg="${path}/package.json"
    [[ -f "$pkg" ]] || return 1

    # Check for react, vue, svelte, next, nuxt, angular, astro, solid
    # in dependencies or devDependencies (grep is sufficient — no jq needed)
    grep -qE '"(react|vue|svelte|next|nuxt|@angular/core|astro|solid-js)"' "$pkg" 2>/dev/null  # stderr: binary file warnings safe to ignore
}

# Auto-detect project profiles from file signals
# Returns comma-separated profile names (e.g., "shell,python,database")
# Returns "minimal" if no language signals match
# No jq — all detection is bash file-existence checks and grep
_detect_profiles() {
    local path="$1"
    local profiles=""
    local has_language=0

    # --- Priority 1: Language profiles (any match activates) ---

    # shell: files/ dir with executables, *.sh, *.bats
    if [[ -d "${path}/files" ]] || _has_files "$path" "*.sh" \
            || _has_files "$path" "*.bats"; then
        profiles="${profiles:+${profiles},}shell"
        has_language=1
    fi

    # python: pyproject.toml, requirements.txt, *.py
    if [[ -f "${path}/pyproject.toml" ]] || [[ -f "${path}/requirements.txt" ]] \
            || [[ -f "${path}/setup.py" ]] || _has_files "$path" "*.py"; then
        profiles="${profiles:+${profiles},}python"
        has_language=1
    fi

    # go: go.mod, *.go
    if [[ -f "${path}/go.mod" ]] || _has_files "$path" "*.go"; then
        profiles="${profiles:+${profiles},}go"
        has_language=1
    fi

    # rust: Cargo.toml, *.rs
    if [[ -f "${path}/Cargo.toml" ]] || _has_files "$path" "*.rs"; then
        profiles="${profiles:+${profiles},}rust"
        has_language=1
    fi

    # typescript: tsconfig.json, non-.d.ts *.ts files
    if [[ -f "${path}/tsconfig.json" ]] || _has_real_ts_files "$path"; then
        profiles="${profiles:+${profiles},}typescript"
        has_language=1
    fi

    # perl: cpanfile, Makefile.PL, *.pl, *.pm
    if [[ -f "${path}/cpanfile" ]] || [[ -f "${path}/Makefile.PL" ]] \
            || _has_files "$path" "*.pl" || _has_files "$path" "*.pm"; then
        profiles="${profiles:+${profiles},}perl"
        has_language=1
    fi

    # php: composer.json, *.php
    if [[ -f "${path}/composer.json" ]] || _has_files "$path" "*.php"; then
        profiles="${profiles:+${profiles},}php"
        has_language=1
    fi

    # node: package.json is the sole activation gate — a stray
    # webpack.config.js in a non-JS repo must not activate; suppressed
    # when typescript already matched (TS repos all have package.json)
    if [[ -f "${path}/package.json" ]] \
            && [[ ",${profiles}," != *",typescript,"* ]]; then
        profiles="${profiles:+${profiles},}node"
        has_language=1
    fi

    # --- Priority 2: Framework profiles (independent activation) ---

    # frontend: package.json with react/vue/next dep, *.tsx, *.jsx
    if _has_frontend_dep "$path" || _has_files "$path" "*.tsx" \
            || _has_files "$path" "*.jsx"; then
        profiles="${profiles:+${profiles},}frontend"
    fi

    # database: need 2+ of (*.sql, migrations/, schema.prisma)
    local db_signals=0
    if _has_files "$path" "*.sql"; then
        db_signals=$((db_signals + 1))
    fi
    if [[ -d "${path}/migrations" ]]; then
        db_signals=$((db_signals + 1))
    fi
    if [[ -f "${path}/schema.prisma" ]] || [[ -f "${path}/prisma/schema.prisma" ]]; then
        db_signals=$((db_signals + 1))
    fi
    if [[ -d "${path}/alembic" ]] || [[ -f "${path}/alembic.ini" ]]; then
        db_signals=$((db_signals + 1))
    fi
    if [[ $db_signals -ge 2 ]]; then
        profiles="${profiles:+${profiles},}database"
    fi

    # --- Priority 3: Infrastructure (only if a language matched) ---

    if [[ $has_language -eq 1 ]]; then
        if _has_files "$path" "*.tf" || [[ -f "${path}/Dockerfile" ]] \
                || [[ -d "${path}/k8s" ]] || [[ -d "${path}/kubernetes" ]] \
                || [[ -d "${path}/ansible" ]] || [[ -f "${path}/docker-compose.yml" ]]; then
            profiles="${profiles:+${profiles},}infrastructure"
        fi
    fi

    # Fallback: no signals matched
    if [[ -z "$profiles" ]]; then
        echo "minimal"
        return 0
    fi

    echo "$profiles"
}

# Resolve version from project directory
_resolve_version() {
    local path="$1"
    local explicit="${2:-}"

    # Explicit --version wins
    if [[ -n "$explicit" ]]; then
        echo "$explicit"
        return 0
    fi

    # VERSION file
    if [[ -f "${path}/VERSION" ]]; then
        local v
        v="$(< "${path}/VERSION")"
        v="${v%%[[:space:]]}"
        echo "$v"
        return 0
    fi

    # files/<project-name> VERSION= line
    local name
    name="$(basename "$path")"
    if [[ -f "${path}/files/${name}" ]]; then
        local v
        # grep may exit 1 if no match — safe to ignore here
        v="$(grep -m1 '^VERSION=' "${path}/files/${name}" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
        if [[ -n "$v" ]]; then
            echo "$v"
            return 0
        fi
    fi

    echo "0.1.0"
}

# Ensure .git/info/exclude has all required entries
_setup_git_exclude() {
    local path="$1"
    local dry_run="$2"

    local exclude_file="${path}/.git/info/exclude"
    if [[ ! -d "${path}/.git" ]]; then
        rdf_warn "not a git repo — skipping .git/info/exclude: ${path}"
        return 0
    fi

    # Ensure directory exists
    if [[ ! -d "${path}/.git/info" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD CREATE: .git/info/"
        else
            command mkdir -p "${path}/.git/info"
        fi
    fi

    local existing=""
    if [[ -f "$exclude_file" ]]; then
        existing="$(< "$exclude_file")"
    fi

    local added=0
    local to_append=""
    if [[ "$existing" != *"RDF working files"* ]]; then
        to_append="${RDF_GIT_EXCLUDE_HEADER}"$'\n'
    fi
    for entry in "${RDF_GIT_EXCLUDE_ENTRIES[@]}"; do
        # Check if entry already present (exact line match)
        if ! echo "$existing" | grep -qxF "$entry"; then
            to_append="${to_append}${entry}"$'\n'
            added=$((added + 1))
        fi
    done

    if [[ $added -gt 0 ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD ADD ${added} entries to .git/info/exclude"
        else
            # Append with a blank line separator if file is non-empty
            if [[ -n "$existing" ]] && [[ "${existing: -1}" != $'\n' ]]; then
                echo "" >> "$exclude_file"
            fi
            echo "" >> "$exclude_file"
            printf '%s' "$to_append" >> "$exclude_file"
            rdf_log "  added ${added} entries to .git/info/exclude"
        fi
    else
        rdf_log "  .git/info/exclude already complete"
    fi
}

# Generate CLAUDE.md by merging governance templates from detected profiles
# Merge strategy: core template first, then each profile template.
# Same ## heading -> concatenate content under that heading with a
# <!-- from: {profile} --> marker. Unique headings -> append in order.
_generate_claude_md() {
    local path="$1"
    local profiles="$2"
    local version="$3"
    local dry_run="$4"

    local name
    name="$(basename "$path")"

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD CREATE: CLAUDE.md (profiles=${profiles})"
        return 0
    fi

    # Collect template files: core first, then each detected profile
    local template_files=""
    local core_template="${RDF_HOME}/profiles/core/governance-template.md"
    if [[ -f "$core_template" ]]; then
        template_files="$core_template"
    else
        rdf_warn "core governance template not found: ${core_template}"
    fi

    local profile
    for profile in ${profiles//,/ }; do
        # 'minimal' means no additional profiles beyond core
        [[ "$profile" == "minimal" ]] && continue
        local tmpl="${RDF_HOME}/profiles/${profile}/governance-template.md"
        if [[ -f "$tmpl" ]]; then
            template_files="${template_files:+${template_files} }${tmpl}"
        else
            rdf_warn "governance template not found for profile '${profile}': ${tmpl}"
        fi
    done

    if [[ -z "$template_files" ]]; then
        # No templates found at all — write a minimal stub
        rdf_warn "no governance templates found — generating minimal CLAUDE.md"
        cat > "${path}/CLAUDE.md" <<MINIMAL
# ${name} -- Project CLAUDE.md

**Version:** ${version}

## Project Structure

\`\`\`
(TODO: document project structure)
\`\`\`
MINIMAL
        rdf_log "  created CLAUDE.md (minimal fallback)"
        return 0
    fi

    # Build merged output using section-heading merge
    # Strategy: read each template, split by ## headings, merge by heading name
    # Uses parallel indexed arrays (bash 4.1+ safe, no declare -A)
    # Merge is done inline — no eval with body content (body may contain
    # shell metacharacters from code examples in governance templates)
    local heading_names=()    # ordered unique heading names
    local heading_bodies=()   # content body for each heading index

    local current_file
    for current_file in $template_files; do
        local current_profile_name
        # Extract profile name from path: .../profiles/{name}/governance-template.md
        current_profile_name="$(basename "$(dirname "$current_file")")"

        local current_heading=""
        local current_body=""
        local is_first_heading=1
        local line

        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "## "* ]]; then
                # Save previous heading+body if any
                if [[ -n "$current_heading" ]]; then
                    # Inline merge: search heading_names for match
                    local _idx _found=0
                    for _idx in "${!heading_names[@]}"; do
                        if [[ "${heading_names[$_idx]}" == "$current_heading" ]]; then
                            _found=1
                            break
                        fi
                    done
                    if [[ $_found -eq 1 ]]; then
                        heading_bodies[$_idx]="${heading_bodies[$_idx]}<!-- from: ${current_profile_name} -->"$'\n'"${current_body}"
                    else
                        heading_names+=("$current_heading")
                        heading_bodies+=("$current_body")
                    fi
                fi
                current_heading="$line"
                current_body=""
                is_first_heading=0
            elif [[ $is_first_heading -eq 1 ]]; then
                # Skip preamble (# title, > blockquote) — we generate our own header
                continue
            else
                current_body="${current_body}${line}"$'\n'
            fi
        done < "$current_file"

        # Save the last heading
        if [[ -n "$current_heading" ]]; then
            local _idx _found=0
            for _idx in "${!heading_names[@]}"; do
                if [[ "${heading_names[$_idx]}" == "$current_heading" ]]; then
                    _found=1
                    break
                fi
            done
            if [[ $_found -eq 1 ]]; then
                heading_bodies[$_idx]="${heading_bodies[$_idx]}<!-- from: ${current_profile_name} -->"$'\n'"${current_body}"
            else
                heading_names+=("$current_heading")
                heading_bodies+=("$current_body")
            fi
        fi
    done

    # Write merged output
    {
        # Project-specific header
        echo "# ${name} -- Project CLAUDE.md"
        echo ""
        echo "**Version:** ${version} | **Profiles:** ${profiles}"
        echo ""

        local i
        for i in "${!heading_names[@]}"; do
            echo "${heading_names[$i]}"
            printf '%s' "${heading_bodies[$i]}"
        done
    } > "${path}/CLAUDE.md"

    rdf_log "  created CLAUDE.md (profiles=${profiles}, sections=${#heading_names[@]})"
}

# Copy reference docs from all detected profiles that have a reference/ dir
_copy_reference_docs() {
    local path="$1"
    local profiles="$2"
    local dry_run="$3"

    local ref_dest="${path}/.rdf/governance/reference"

    # Always copy core reference docs
    local all_profiles="core"
    if [[ "$profiles" != "minimal" ]]; then
        all_profiles="core,${profiles}"
    fi

    local has_refs=0
    local profile
    for profile in ${all_profiles//,/ }; do
        local ref_dir="${RDF_HOME}/profiles/${profile}/reference"
        if [[ -d "$ref_dir" ]]; then
            has_refs=1
            break
        fi
    done

    if [[ $has_refs -eq 0 ]]; then
        return 0
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD COPY: reference docs from profiles to .rdf/governance/reference/"
        return 0
    fi

    command mkdir -p "$ref_dest"
    local copied=0
    for profile in ${all_profiles//,/ }; do
        local ref_dir="${RDF_HOME}/profiles/${profile}/reference"
        if [[ -d "$ref_dir" ]]; then
            command cp -a "${ref_dir}/." "${ref_dest}/"
            copied=$((copied + 1))
        fi
    done

    if [[ $copied -gt 0 ]]; then
        rdf_log "  copied reference docs from ${copied} profile(s)"
    fi
}

# _contrib_stack_text profiles — line 1: CONTRIBUTING code-standards clause,
# line 2: its test command. Shell wins when present; otherwise the first
# language profile in _detect_profiles order.
_contrib_stack_text() {
    local profiles=",${1},"
    local lang
    # shellcheck disable=SC2016  # backticks are literal markdown, not substitution
    for lang in shell python go rust typescript perl php node; do
        [[ "$profiles" == *",${lang},"* ]] || continue
        case "$lang" in
            shell)      printf '%s\n%s\n' 'All shell scripts pass `bash -n` and `shellcheck`; tests use the BATS framework' '`make -C tests test`' ;;
            python)     printf '%s\n%s\n' "Code passes the project's linter (e.g. ruff/flake8)" '`pytest`' ;;
            go)         printf '%s\n%s\n' 'Code passes `go vet` and `gofmt -l`' '`go test ./...`' ;;
            rust)       printf '%s\n%s\n' 'Code passes `cargo clippy`' '`cargo test`' ;;
            typescript) printf '%s\n%s\n' "Code passes the project's lint script (\`npm run lint\`)" '`npm test`' ;;
            node)       printf '%s\n%s\n' "Code passes the project's lint script (\`npm run lint\`)" '`npm test`' ;;
            perl)       printf '%s\n%s\n' 'Code passes `perl -c`' '`prove`' ;;
            php)        printf '%s\n%s\n' 'Code passes `php -l`' '`composer test`' ;;
        esac
        return 0
    done
    printf '%s\n%s\n' 'Follow the conventions in CLAUDE.md' "run the project's test suite"
}

# Generate SECURITY.md and CONTRIBUTING.md from reference/templates/ with
# {{VARIABLE}} substitution. Skips if files already exist or templates missing.
_generate_companion_files() {
    local path="$1"
    local profiles="$2"
    local dry_run="$3"

    local name
    name="$(basename "$path")"

    # Resolve org from git remote (fallback: project name)
    local org="$name"
    if [[ -d "${path}/.git" ]]; then
        local remote_url
        remote_url="$(git -C "$path" remote get-url origin 2>/dev/null || echo "")"  # stderr: no remote is safe to ignore
        if [[ -n "$remote_url" ]]; then
            # Extract org from github.com/ORG/repo or git@github.com:ORG/repo
            local extracted
            extracted="$(echo "$remote_url" \
                | sed 's|.*github\.com[:/]\([^/]*\)/.*|\1|')"
            if [[ -n "$extracted" ]] && [[ "$extracted" != "$remote_url" ]]; then
                org="$extracted"
            fi
        fi
    fi

    # Contact: repo-LOCAL git identity only — plain `git config` falls
    # through to the operator's global user.email, which would leak the
    # machine owner's personal address into the target repo
    local contact_email
    contact_email="$(git -C "$path" config --local user.email 2>/dev/null || echo "")"  # non-git dir (exit 128) / unset key (exit 1) → generic fallback below
    # Fallback must NOT point at the public issue tracker — the template's
    # preceding line forbids public issues for vulnerabilities
    [[ -z "$contact_email" ]] && contact_email="this repository's private vulnerability reporting (GitHub Security tab -> Report a vulnerability), or the maintainer listed in the repository metadata"

    # License: detect from LICENSE head; phrase completes "under the {{LICENSE}}."
    local license="terms in the LICENSE file"
    if [[ -f "${path}/LICENSE" ]]; then
        local license_head
        license_head="$(command head -5 "${path}/LICENSE")"
        case "$license_head" in
            *"MIT License"*)                license="MIT License" ;;
            *"Apache License"*)             license="Apache License 2.0" ;;
            *"GNU GENERAL PUBLIC LICENSE"*)
                case "$license_head" in
                    *"Version 3"*) license="GNU GPL v3" ;;
                    *"Version 2"*) license="GNU GPL v2" ;;
                esac ;;
        esac
    fi
    local tmpl_dir="${RDF_HOME}/reference/templates"

    # SECURITY.md
    local sec_tmpl="${tmpl_dir}/SECURITY.md"
    local sec_dest="${path}/SECURITY.md"
    if [[ -f "$sec_dest" ]]; then
        rdf_log "  SECURITY.md already exists — skipping"
    elif [[ ! -f "$sec_tmpl" ]]; then
        rdf_log "  SECURITY.md template not found — skipping"
    elif [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD CREATE: SECURITY.md (project=${name}, contact=${contact_email})"
    else
        sed -e "s|{{PROJECT}}|${name}|g" \
            -e "s|{{CONTACT_EMAIL}}|${contact_email}|g" \
            "$sec_tmpl" > "$sec_dest"
        rdf_log "  created SECURITY.md"
    fi

    # CONTRIBUTING.md
    local con_tmpl="${tmpl_dir}/CONTRIBUTING.md"
    local con_dest="${path}/CONTRIBUTING.md"
    if [[ -f "$con_dest" ]]; then
        rdf_log "  CONTRIBUTING.md already exists — skipping"
    elif [[ ! -f "$con_tmpl" ]]; then
        rdf_log "  CONTRIBUTING.md template not found — skipping"
    elif [[ "$dry_run" -eq 1 ]]; then
        rdf_log "  WOULD CREATE: CONTRIBUTING.md (project=${name}, org=${org})"
    else
        local repo_url="${remote_url:-}"
        [[ -z "$repo_url" ]] && repo_url="<your-repository-url>"
        local stack code_standards test_command
        stack="$(_contrib_stack_text "$profiles")"
        code_standards="${stack%%$'\n'*}"
        test_command="${stack##*$'\n'}"
        sed -e "s|{{PROJECT}}|${name}|g" \
            -e "s|{{ORG}}|${org}|g" \
            -e "s|{{LICENSE}}|${license}|g" \
            -e "s|{{REPO_URL}}|${repo_url}|g" \
            -e "s|{{CODE_STANDARDS}}|${code_standards}|g" \
            -e "s|{{TEST_COMMAND}}|${test_command}|g" \
            "$con_tmpl" > "$con_dest"
        rdf_log "  created CONTRIBUTING.md"
    fi
}

# Initialize a single project
_init_one() {
    local path="$1"
    local profiles="$2"
    local version="$3"
    local no_memory="$4"
    local do_github="$5"
    local dry_run="$6"
    local tools="$7"

    local name
    name="$(basename "$path")"

    _init_check_tools_preconditions "$path" "$tools"

    rdf_log "initializing: ${name} (profiles=${profiles}, version=${version})"

    # 1. CLAUDE.md from governance template merge
    if [[ -f "${path}/CLAUDE.md" ]]; then
        rdf_log "  CLAUDE.md already exists — skipping (use rdf doctor to check drift)"
    else
        _generate_claude_md "$path" "$profiles" "$version" "$dry_run"
    fi

    # 2. .git/info/exclude
    _setup_git_exclude "$path" "$dry_run"

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

    # 3b. Documentation level
    if [[ ! -f "${rdf_dir}/docs-level" ]]; then
        # Infer default: products (files/<name> or bin/<name>) → level-2, libraries → floor
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

    # 4. Reference docs from detected profiles
    _copy_reference_docs "$path" "$profiles" "$dry_run"

    # 4b. Companion files: SECURITY.md, CONTRIBUTING.md
    _generate_companion_files "$path" "$profiles" "$dry_run"

    # 4c. Tool targets beyond the implicit claude-code default
    _init_apply_tools "$path" "$tools" "$dry_run"

    # 5. MEMORY.md placeholder (unless --no-memory)
    if [[ "$no_memory" -eq 0 ]] && [[ ! -f "${path}/MEMORY.md" ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            rdf_log "  WOULD CREATE: MEMORY.md (placeholder)"
        else
            cat > "${path}/MEMORY.md" <<MEMEOF
# ${name} -- Project Memory

## Project Status
- **Version:** ${version}
- **Profiles:** ${profiles}
- **Status:** initialized via rdf init

## Session Log
MEMEOF
            rdf_log "  created MEMORY.md placeholder"
        fi
    fi

    # 6. GitHub scaffolding (labels + project board)
    if [[ "$do_github" -eq 1 ]]; then
        if ! command -v gh >/dev/null 2>&1; then  # stderr: command -v noise safe to ignore
            rdf_warn "gh CLI not found — skipping GitHub scaffolding"
        elif [[ ! -d "${path}/.git" ]]; then
            rdf_warn "not a git repo — skipping GitHub scaffolding"
        else
            local repo
            repo="$(git -C "$path" remote get-url origin 2>/dev/null \
                | sed 's|.*github.com[:/]||; s|\.git$||' || echo "")"  # stderr: no remote is handled below
            if [[ -z "$repo" ]]; then
                rdf_warn "cannot detect GitHub repo from origin — skipping"
            elif [[ "$dry_run" -eq 1 ]]; then
                rdf_log "  WOULD RUN: rdf github setup --repo ${repo}"
            else
                # Source github.sh and call setup
                # shellcheck disable=SC1090,SC1091
                source "${RDF_LIBDIR}/cmd/github.sh"
                _github_setup --repo "$repo"
            fi
        fi
    fi

    rdf_log "init complete: ${name}"
}

# Validate a comma-separated profile list. Returns 0 if all valid, dies on invalid.
_validate_profiles() {
    local profiles="$1"
    local profile
    for profile in ${profiles//,/ }; do
        # Legacy alias: --type lib maps to shell
        if [[ "$profile" == "lib" ]]; then
            rdf_warn "profile 'lib' is deprecated — mapping to 'shell'"
            continue
        fi
        local valid=0
        local known
        for known in $_KNOWN_PROFILES; do
            if [[ "$profile" == "$known" ]]; then
                valid=1
                break
            fi
        done
        if [[ $valid -eq 0 ]]; then
            rdf_die "invalid profile: ${profile} — valid profiles: ${_KNOWN_PROFILES}"
        fi
    done
}

# _init_validate_tools list — split/expand/dedupe --tools; dies on an empty or unknown token; echoes newline list
# Space-delimited string accumulator, not arrays: expanding an empty array under
# `set -u` is an unbound-variable error on the bash 3.2 / 4.1 floors.
_init_validate_tools() {
    local list="$1"
    local token expanded item out=""

    if [[ -z "$list" ]]; then
        rdf_die "unknown --tools value:  (allowed: claude-code, agent-skills, agents-md, codex, antigravity)"
    fi

    while IFS= read -r token; do
        token="${token#"${token%%[![:space:]]*}"}"
        token="${token%"${token##*[![:space:]]}"}"
        if [[ -z "$token" ]]; then
            rdf_die "empty --tools value in list: ${list} (allowed: claude-code, agent-skills, agents-md, codex, antigravity)"
        fi
        case "$token" in
            claude-code)       expanded="claude-code" ;;
            agent-skills)      expanded="agent-skills" ;;
            agents-md)         expanded="agents-md" ;;
            codex|antigravity) expanded="agent-skills agents-md" ;;
            *) rdf_die "unknown --tools value: ${token} (allowed: claude-code, agent-skills, agents-md, codex, antigravity)" ;;
        esac
        for item in $expanded; do
            case " $out " in
                *" $item "*) ;;
                *) out="${out:+$out }$item" ;;
            esac
        done
    done <<< "${list//,/$'\n'}"

    for item in $out; do
        printf '%s\n' "$item"
    done
}

# _init_tools_contains tools token — rc 0 when the expanded newline list holds token
_init_tools_contains() {
    local t
    while IFS= read -r t; do
        [[ "$t" == "$2" ]] && return 0
    done <<< "$1"
    return 1
}

# _init_check_tools_preconditions path tools — die before any write when a
# requested surface cannot be produced for this path
_init_check_tools_preconditions() {
    local path="$1"
    local tools="$2"

    # amd_compose reads the project's git tree; on a non-git path it dies after
    # governance and companion files are already on disk
    if _init_tools_contains "$tools" "agents-md" \
            && ! git -C "$path" rev-parse --show-toplevel >/dev/null 2>&1; then  # stderr: "not a repository" is the condition under test
        rdf_die "--tools agents-md requires a git repository: ${path}"
    fi
}

# _init_apply_tools path tools dry_run — deploy agent-skills/agents-md targets after governance write
_init_apply_tools() {
    local path="$1"
    local tools="$2"
    local dry_run="$3"
    local t sk_output skipped_before

    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        case "$t" in
            claude-code) : ;;
            agent-skills)
                if [[ "$dry_run" -eq 1 ]]; then
                    rdf_log "  would symlink .agents/skills"
                    continue
                fi
                sk_output="${RDF_ADAPTERS}/agent-skills/output"
                if [[ ! -d "$sk_output" ]] || [[ -z "$(ls -A "$sk_output" 2>/dev/null)" ]]; then  # 2>/dev/null: empty-on-missing is the intended regen trigger
                    # shellcheck disable=SC1090,SC1091
                    source "${RDF_LIBDIR}/cmd/generate.sh"
                    _generate_adapter "agent-skills/adapter.sh" "sk_generate_all"
                fi
                # shellcheck disable=SC1090,SC1091
                source "${RDF_LIBDIR}/cmd/deploy.sh"
                skipped_before="$_DEPLOY_SKIPPED"
                _deploy_agent_skills "$dry_run" 0 "$path"
                if [[ "$_DEPLOY_SKIPPED" -gt "$skipped_before" ]]; then
                    rdf_warn "  .agents/skills was not deployed — resolve the existing path, then run 'rdf deploy agent-skills --project-root ${path} --force'"
                    _INIT_SKIPPED=$((_INIT_SKIPPED + 1))
                fi
                ;;
            agents-md)
                if [[ -e "${path}/AGENTS.md" ]]; then
                    rdf_log "  AGENTS.md already exists — skipping"
                elif [[ "$dry_run" -eq 1 ]]; then
                    rdf_log "  would write AGENTS.md"
                else
                    # shellcheck disable=SC1090,SC1091
                    [[ -n "${_RDF_ADAPTER_COMMON_LOADED:-}" ]] || source "${RDF_LIBDIR}/adapter_common.sh"
                    # shellcheck disable=SC1090,SC1091
                    source "${RDF_ADAPTERS}/agents-md/adapter.sh"
                    amd_compose "$path" "${path}/AGENTS.md"
                fi
                ;;
        esac
    done <<< "$tools"
}

# Incremented when a tool surface was requested but left undeployed
_INIT_SKIPPED=0

cmd_init() {
    local path=""
    local type=""
    local tools="claude-code"
    local version=""
    local no_memory=0
    local do_github=0
    local batch=0
    local dry_run=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                [[ $# -lt 2 ]] && rdf_die "--type requires a value"
                type="$2"; shift 2 ;;
            --tools)
                [[ $# -lt 2 ]] && rdf_die "--tools requires a value"
                tools="$2"; shift 2 ;;
            --version)
                [[ $# -lt 2 ]] && rdf_die "--version requires a value"
                version="$2"; shift 2 ;;
            --no-memory) no_memory=1; shift ;;
            --github)    do_github=1; shift ;;
            --batch)     batch=1; shift ;;
            --dry-run)   dry_run=1; shift ;;
            help|--help|-h) _init_usage; return 0 ;;
            -*)          rdf_die "unknown option: $1 — run 'rdf init help'" ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"; shift
                else
                    rdf_die "unexpected argument: $1 — run 'rdf init help'"
                fi
                ;;
        esac
    done

    [[ -z "$path" ]] && rdf_die "missing path — run 'rdf init help'"

    _INIT_SKIPPED=0
    local tools_expanded
    tools_expanded="$(_init_validate_tools "$tools")"

    # Resolve to absolute path
    if [[ ! -d "$path" ]]; then
        rdf_die "directory not found: $path"
    fi
    path="$(cd "$path" && pwd)" || rdf_die "cannot resolve path: $path"

    # jq preflight — hooks and the statusline degrade without it (non-fatal)
    if ! command -v jq >/dev/null 2>&1; then  # stderr: command -v noise safe to ignore
        rdf_warn "jq not found on PATH — hooks and statusline degrade until installed (apt/dnf install jq, or brew install jq)"
    fi

    # Validate --type if explicit (now accepts comma-separated profiles)
    if [[ -n "$type" ]]; then
        _validate_profiles "$type"
        # Normalize legacy alias: lib -> shell
        type="${type//lib/shell}"
    fi

    if [[ "$batch" -eq 1 ]]; then
        # Batch mode: iterate subdirectories
        rdf_log "batch init: scanning ${path}..."

        # Create workspace-level .rdf/ (flat — agent-feed.log, session-log.jsonl)
        if [[ ! -d "${path}/.rdf" ]]; then
            if [[ "$dry_run" -eq 1 ]]; then
                rdf_log "  WOULD CREATE: workspace .rdf/"
            else
                command mkdir -p "${path}/.rdf"
                rdf_log "  created workspace .rdf/"
            fi
        fi

        local count=0

        for subdir in "${path}"/*/; do
            [[ -d "$subdir" ]] || continue
            local subname
            subname="$(basename "$subdir")"

            # Skip hidden directories and non-project dirs
            [[ "$subname" == .* ]] && continue

            # Auto-detect profiles per project unless --type forced
            local proj_profiles="$type"
            if [[ -z "$proj_profiles" ]]; then
                proj_profiles="$(_detect_profiles "$subdir")"
            fi

            local proj_version
            proj_version="$(_resolve_version "$subdir" "$version")"

            _init_one "$subdir" "$proj_profiles" "$proj_version" "$no_memory" "$do_github" "$dry_run" "$tools_expanded"
            count=$((count + 1))
        done

        rdf_log "batch init complete: ${count} projects processed"
    else
        # Single project mode
        if [[ -z "$type" ]]; then
            type="$(_detect_profiles "$path")"
            rdf_log "auto-detected profiles: ${type}"
        fi

        local resolved_version
        resolved_version="$(_resolve_version "$path" "$version")"

        _init_one "$path" "$type" "$resolved_version" "$no_memory" "$do_github" "$dry_run" "$tools_expanded"
    fi

    if [[ "$_INIT_SKIPPED" -gt 0 ]]; then
        rdf_warn "init finished with ${_INIT_SKIPPED} undeployed tool surface(s)"
        return 1
    fi
}
