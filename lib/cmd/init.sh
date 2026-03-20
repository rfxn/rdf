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
  --tools TOOLS         Comma-separated tool targets (default: claude-code)
  --version X.Y.Z       Initial version string (default: from VERSION file or 0.1.0)
  --no-memory           Skip MEMORY.md placeholder creation
  --github              Create labels + repo project board via gh CLI
  --batch               Process multiple directories (path is parent dir)
  --dry-run             Show what would be created without writing

Examples:
  rdf init /root/admin/work/proj/my-project
  rdf init /root/admin/work/proj/my-project --type shell --github
  rdf init /root/admin/work/proj/my-project --type rust,infrastructure
  rdf init /root/admin/work/proj --batch --type minimal
  rdf init /root/admin/work/proj/inactive --batch --dry-run
USAGE
}

# Known profile names for validation (excludes 'core' — always implicit)
_KNOWN_PROFILES="shell python go rust typescript perl php frontend database infrastructure minimal"

# Check if a project directory has files matching a glob pattern.
# Uses git ls-files in git repos, find(1) otherwise.
# Returns 0 (found) or 1 (not found).
_has_files() {
    local path="$1"
    local pattern="$2"

    if [[ -d "${path}/.git" ]]; then
        # git ls-files is fast and respects .gitignore
        # grep -q exits 0 on first match; git ls-files exits 0 even with no output
        git -C "$path" ls-files "$pattern" 2>/dev/null | grep -q . && return 0  # stderr: not a git repo is safe
    else
        # Non-git fallback: find with maxdepth for top-level patterns,
        # recursive for deeper searches. Use -quit for early exit.
        find "$path" -maxdepth 3 -name "$pattern" -print -quit 2>/dev/null | grep -q . && return 0  # stderr: permission errors safe to ignore
    fi
    return 1
}

# Check if project has non-declaration .ts files (exclude .d.ts-only projects)
_has_real_ts_files() {
    local path="$1"

    if [[ -d "${path}/.git" ]]; then
        # List all .ts files, exclude .d.ts, check if any remain
        git -C "$path" ls-files '*.ts' 2>/dev/null \
            | grep -v '\.d\.ts$' \
            | grep -q . && return 0  # stderr: not a git repo is safe
    else
        find "$path" -maxdepth 3 -name '*.ts' -not -name '*.d.ts' \
            -print -quit 2>/dev/null | grep -q . && return 0  # stderr: permission errors safe to ignore
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

# Standard .git/info/exclude entries for rfxn projects
_GIT_EXCLUDE_ENTRIES=(
    "# RDF working files (managed by rdf init)"
    "CLAUDE.md"
    "PLAN*.md"
    "AUDIT.md"
    "MEMORY.md"
    ".rdf/"
)

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
    for entry in "${_GIT_EXCLUDE_ENTRIES[@]}"; do
        # Skip comment lines for matching purposes
        if [[ "$entry" == "#"* ]]; then
            # Add the comment header only if the block hasn't been added before
            if [[ "$existing" != *"RDF working files"* ]] && [[ $added -eq 0 ]]; then
                to_append="${to_append}${entry}"$'\n'
            fi
            continue
        fi
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

# Initialize a single project
_init_one() {
    local path="$1"
    local profiles="$2"
    local version="$3"
    local no_memory="$4"
    local do_github="$5"
    local dry_run="$6"

    local name
    name="$(basename "$path")"

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

    # 4. Reference docs from detected profiles
    _copy_reference_docs "$path" "$profiles" "$dry_run"

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

# shellcheck disable=SC2034  # tools reserved for Phase 8
cmd_init() {
    local path=""
    local type=""
    local tools="claude-code"  # reserved for Phase 8 multi-tool support
    local version=""
    local no_memory=0
    local do_github=0
    local batch=0
    local dry_run=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)      type="$2"; shift 2 ;;
            --tools)     tools="$2"; shift 2 ;;
            --version)   version="$2"; shift 2 ;;
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

    # Resolve to absolute path
    if [[ ! -d "$path" ]]; then
        rdf_die "directory not found: $path"
    fi
    path="$(cd "$path" && pwd)" || rdf_die "cannot resolve path: $path"

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

            _init_one "$subdir" "$proj_profiles" "$proj_version" "$no_memory" "$do_github" "$dry_run"
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

        _init_one "$path" "$type" "$resolved_version" "$no_memory" "$do_github" "$dry_run"
    fi
}
