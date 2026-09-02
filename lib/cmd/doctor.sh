#!/usr/bin/env bash
# lib/cmd/doctor.sh — rdf doctor subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_doctor_usage() {
    cat <<'USAGE'
Usage: rdf doctor [path] [options]

Check project health and convention compliance.

Arguments:
  path                  Project directory (default: current directory)

Options:
  --all                 Scan all workspace projects (path = workspace root)
  --scope SCOPE         Check specific category only:
                        artifacts, drift, memory, plan, github, sync,
                        install-mode, deps, catalogs, state-helpers,
                        content-drift, doc-stats, readme
  --json                Output results as JSON
  --quiet               Only show WARN and FAIL

Environment:
  RDF_WORKSPACE         Workspace root for --all. Defaults to the parent of the
                        RDF checkout; --all errors out when that resolves to
                        your home directory (checkout cloned into ~).

Examples:
  rdf doctor
  rdf doctor ~/projects/my-project
  rdf doctor --all
  RDF_WORKSPACE=~/projects rdf doctor --all
  rdf doctor --scope github
  rdf doctor --all --scope memory
USAGE
}

# Default workspace root — RDF_WORKSPACE, else the parent of RDF home
_WORKSPACE_ROOT="${RDF_WORKSPACE:-$(command dirname "${RDF_HOME}")}"

# Check result formatting
_OK="OK"
_WARN="WARN"
_FAIL="FAIL"

# Accumulate check results
_RESULTS=()      # "category|status|message" entries
_PASS_COUNT=0
_WARN_COUNT=0
_FAIL_COUNT=0

_add_result() {
    local category="$1"
    local status="$2"
    local message="$3"
    _RESULTS+=("${category}|${status}|${message}")
    case "$status" in
        "$_OK")   _PASS_COUNT=$((_PASS_COUNT + 1)) ;;
        "$_WARN") _WARN_COUNT=$((_WARN_COUNT + 1)) ;;
        "$_FAIL") _FAIL_COUNT=$((_FAIL_COUNT + 1)) ;;
    esac
}

# _is_framework_checkout path — true for the RDF checkout itself, which is not
# a governed project (no .rdf/, no init-written excludes)
_is_framework_checkout() {
    [[ -d "${1}/canonical" ]] && [[ -f "${1}/bin/rdf" ]]
}

# ── Check: artifacts ──
_check_artifacts() {
    local path="$1"

    # CLAUDE.md
    if [[ -f "${path}/CLAUDE.md" ]]; then
        _add_result "artifacts" "$_OK" "CLAUDE.md present"
    else
        _add_result "artifacts" "$_FAIL" "CLAUDE.md missing"
    fi

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
    elif _is_framework_checkout "$path"; then
        _add_result "artifacts" "$_OK" "framework checkout — project artifacts N/A"
    else
        _add_result "artifacts" "$_WARN" ".rdf/ missing — run 'rdf init' or 'rdf migrate'"
    fi

    # .git/info/exclude
    if [[ -d "${path}/.git" ]]; then
        local exclude="${path}/.git/info/exclude"
        if [[ -f "$exclude" ]]; then
            local missing=0
            for entry in "${RDF_GIT_EXCLUDE_ENTRIES[@]}"; do
                if ! grep -qxF "$entry" "$exclude"; then
                    missing=$((missing + 1))
                fi
            done
            if [[ $missing -eq 0 ]]; then
                _add_result "artifacts" "$_OK" ".git/info/exclude complete"
            else
                _add_result "artifacts" "$_WARN" ".git/info/exclude missing ${missing} entries"
            fi
        else
            _add_result "artifacts" "$_FAIL" ".git/info/exclude file missing"
        fi
    fi

    # Legacy state detection
    if [[ -d "${path}/.claude/governance" ]]; then
        _add_result "artifacts" "$_WARN" ".claude/governance/ still exists — run 'rdf migrate'"
    fi
    if [[ -d "${path}/work-output" ]] && [[ ! -L "${path}/work-output" ]]; then
        _add_result "artifacts" "$_WARN" "work-output/ at project root — run 'rdf migrate'"
    fi
}

# ── Check: drift ──
_check_drift() {
    local path="$1"

    if [[ ! -f "${path}/CLAUDE.md" ]]; then
        _add_result "drift" "$_FAIL" "CLAUDE.md missing — cannot check drift"
        return 0
    fi

    # Inheriting from a parent CLAUDE.md is only meaningful in a workspace
    # layout — a standalone project has no parent to reference
    local parent_ref
    parent_ref="$(command dirname "$path")/CLAUDE.md"
    if [[ ! -f "$parent_ref" ]]; then
        _add_result "drift" "$_OK" "standalone project — no parent CLAUDE.md"
    elif grep -qF "$parent_ref" "${path}/CLAUDE.md" || \
         grep -qi "inherits.*parent" "${path}/CLAUDE.md"; then
        _add_result "drift" "$_OK" "CLAUDE.md references parent conventions"
    else
        _add_result "drift" "$_WARN" "CLAUDE.md does not reference parent CLAUDE.md"
    fi

    # Check for stale version in CLAUDE.md — portable extraction without grep -P
    local claude_version=""
    claude_version="$(grep -oE '[Vv]ersion[: ]*[0-9]+\.[0-9]+\.[0-9]+' "${path}/CLAUDE.md" 2>/dev/null \
        | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")"
    if [[ -n "$claude_version" ]]; then
        local actual_version
        actual_version="$(_resolve_version_for_doctor "$path")"
        if [[ -n "$actual_version" ]] && [[ "$actual_version" != "unknown" ]] && \
           [[ "$claude_version" != "$actual_version" ]]; then
            _add_result "drift" "$_WARN" "CLAUDE.md version (${claude_version}) != actual (${actual_version})"
        fi
    fi

    # Check for prohibited old naming in CLAUDE.md (stale workforce/ references)
    if grep -q 'workforce/' "${path}/CLAUDE.md" 2>/dev/null; then
        _add_result "drift" "$_WARN" "CLAUDE.md contains stale 'workforce/' reference"
    else
        _add_result "drift" "$_OK" "CLAUDE.md has no stale workforce/ references"
    fi
}

# ── Check: memory ──
_check_memory() {
    local path="$1"
    local name
    name="$(basename "$path")"

    # Check project-local MEMORY.md
    if [[ -f "${path}/MEMORY.md" ]]; then
        _add_result "memory" "$_OK" "MEMORY.md present"

        # Staleness check: >7 days since modification
        local mem_mtime
        mem_mtime="$(stat -c %Y "${path}/MEMORY.md" 2>/dev/null || stat -f %m "${path}/MEMORY.md" 2>/dev/null || echo "0")"
        local now
        now="$(date +%s)"
        local age_days=0
        if [[ "$mem_mtime" -gt 0 ]]; then
            age_days=$(( (now - mem_mtime) / 86400 ))
        fi
        if [[ $age_days -gt 7 ]]; then
            _add_result "memory" "$_WARN" "MEMORY.md last updated ${age_days} days ago (>7d threshold)"
        else
            _add_result "memory" "$_OK" "MEMORY.md fresh (${age_days}d old)"
        fi

        # Line count check: 200-line cap
        local line_count
        line_count="$(wc -l < "${path}/MEMORY.md")"
        if [[ $line_count -gt 200 ]]; then
            _add_result "memory" "$_FAIL" "MEMORY.md over 200-line cap (${line_count} lines)"
        elif [[ $line_count -gt 180 ]]; then
            _add_result "memory" "$_WARN" "MEMORY.md near cap (${line_count}/200 lines)"
        fi
    else
        # Check .rdf/memory/ location
        if [[ -L "${path}/.rdf/memory" ]] && [[ ! -e "${path}/.rdf/memory" ]]; then
            _add_result "memory" "$_WARN" ".rdf/memory/ is a dangling symlink — recreate with 'rdf migrate'"
        elif [[ -f "${path}/.rdf/memory/MEMORY.md" ]]; then
            _add_result "memory" "$_OK" "MEMORY.md in .rdf/memory/"
        else
            _add_result "memory" "$_WARN" "no MEMORY.md found"
        fi
    fi
}

# ── Check: plan ──
_check_plan() {
    local path="$1"

    # Look for any PLAN*.md file
    local plan_files=()
    local f
    for f in "${path}"/PLAN*.md; do
        [[ -f "$f" ]] && plan_files+=("$f")
    done

    # Surface active-plan pointer state — runs before any early return so
    # canonical-only projects (plan in docs/plans/, no root PLAN.md) still
    # see pointer status.
    if [[ -n "${RDF_SESSION_ID:-}" && -f "${path}/.rdf/active-plan-${RDF_SESSION_ID}" ]]; then
        _add_result "plan-pointer" "$_OK" "session pointer present"
    elif [[ -f "${path}/.rdf/active-plan" ]]; then
        _add_result "plan-pointer" "$_OK" "un-suffixed pointer present"
    else
        _add_result "plan-pointer" "$_OK" "no pointer (legacy fallback or no plan)"
    fi

    if [[ ${#plan_files[@]} -eq 0 ]]; then
        _add_result "plan" "$_OK" "no PLAN*.md files (none expected if no active work)"
        return 0
    fi

    _add_result "plan" "$_OK" "${#plan_files[@]} PLAN file(s) found"

    # Check for stale IN_PROGRESS markers
    for f in "${plan_files[@]}"; do
        local fname
        fname="$(basename "$f")"
        local in_progress
        # grep -c always outputs a count; exits 1 when count is 0 — suppress exit code
        in_progress="$(grep -ciE 'IN.PROGRESS|ACTIVE|STARTED' "$f" 2>/dev/null || true)"
        # Guard against empty result (e.g., binary file)
        in_progress="${in_progress:-0}"
        if [[ "$in_progress" -gt 0 ]]; then
            # Check file age — if PLAN has active phases but hasn't been touched in >7d
            local plan_mtime
            plan_mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo "0")"
            local now
            now="$(date +%s)"
            local age_days=0
            if [[ "$plan_mtime" -gt 0 ]]; then
                age_days=$(( (now - plan_mtime) / 86400 ))
            fi
            if [[ $age_days -gt 7 ]]; then
                _add_result "plan" "$_WARN" "${fname}: ${in_progress} active phases, stale (${age_days}d)"
            else
                _add_result "plan" "$_OK" "${fname}: ${in_progress} active phases"
            fi
        fi
    done
}

# ── Check: github ──
_check_github() {
    local path="$1"

    # gh CLI required
    if ! command -v gh >/dev/null 2>&1; then
        _add_result "github" "$_WARN" "gh CLI not installed — skipping GitHub checks"
        return 0
    fi

    # Must be a git repo with an origin
    if [[ ! -d "${path}/.git" ]]; then
        _add_result "github" "$_WARN" "not a git repo — skipping GitHub checks"
        return 0
    fi

    local origin_url
    origin_url="$(git -C "$path" remote get-url origin 2>/dev/null || echo "")"  # no origin -> skip below
    if [[ "$origin_url" != *github.com* ]]; then
        _add_result "github" "$_WARN" "no GitHub remote — skipping"
        return 0
    fi
    local repo
    repo="$(echo "$origin_url" | sed 's|.*github.com[:/]||; s|\.git$||')"

    # Check for standardized labels
    local label_count
    label_count="$(gh label list --repo "$repo" --json name --jq 'length' 2>/dev/null || echo "0")"
    if [[ "$label_count" -eq 0 ]]; then
        _add_result "github" "$_WARN" "no labels on ${repo}"
    else
        # Check for our taxonomy labels specifically
        local has_type_phase
        has_type_phase="$(gh label list --repo "$repo" --json name --jq '.[] | select(.name == "type:phase") | .name' 2>/dev/null || echo "")"
        if [[ -n "$has_type_phase" ]]; then
            _add_result "github" "$_OK" "RDF label taxonomy present on ${repo}"
        else
            _add_result "github" "$_WARN" "RDF label taxonomy not found on ${repo} (${label_count} labels exist)"
        fi
    fi

    # Check for project board
    local owner="${repo%%/*}"
    local repo_name="${repo##*/}"
    local project_title="${repo_name} Development"
    local project_exists
    project_exists="$(gh project list --owner "$owner" --format json 2>/dev/null \
        | jq -r ".projects[] | select(.title == \"${project_title}\") | .number" 2>/dev/null || echo "")"
    if [[ -n "$project_exists" ]]; then
        _add_result "github" "$_OK" "project board '${project_title}' exists (#${project_exists})"
    else
        _add_result "github" "$_WARN" "no project board '${project_title}' found"
    fi
}

# ── Check: content-drift (RDF-specific) ──
# Verifies that deployed agent/command files match their canonical sources by
# comparing .rdf-hash sidecars (written by 'rdf generate claude-code') against
# a freshly computed hash of the deployed file body.
#
# Sidecar stores hash(canonical body at generate time).
# Doctor hashes the deployed file body (YAML frontmatter stripped for agents).
# Mismatch means the deployed file was modified after the last generate.
_check_content_drift() {
    local path="$1"

    local canonical_dir="${path}/canonical"
    local output_dir="${path}/adapters/claude-code/output"

    if [[ ! -d "$canonical_dir" ]]; then
        # Not the RDF project — content-drift check N/A
        return 0
    fi

    if [[ ! -d "$output_dir" ]]; then
        _add_result "content-drift" "$_WARN" "no generated output — run 'rdf generate claude-code'"
        return 0
    fi

    # Hashing goes through rdf_hash_stdin (portable across GNU/macOS/BSD); bail with a
    # WARN only if no SHA tool at all is present (macOS ships shasum, not sha256sum).
    if ! command -v sha256sum >/dev/null 2>&1 \
        && ! command -v shasum >/dev/null 2>&1 \
        && ! command -v sha1sum >/dev/null 2>&1; then
        _add_result "content-drift" "$_WARN" "no SHA tool found — cannot verify content drift"
        return 0
    fi

    local drift_count=0
    local missing_sidecar_count=0
    local checked_count=0
    local skills_tree_missing=0

    # _hash_deployed_body <deployed-file> — hash the frontmatter-stripped body
    # (single strip implementation: rdf_strip_frontmatter in rdf_common.sh).
    _hash_deployed_body() {
        rdf_strip_frontmatter "$1" | rdf_hash_stdin
    }

    # _drift_check_tree dir label — sidecar contract for a flat *.md tree
    # (reference docs); drift/sidecar/checked counters are the caller's locals.
    _drift_check_tree() {
        local dir="$1" label="$2" f b side stored actual
        for f in "${dir}"/*.md; do
            [[ -f "$f" ]] || continue
            b="$(basename "$f")"
            side="${f}.rdf-hash"
            if [[ ! -f "$side" ]]; then
                missing_sidecar_count=$((missing_sidecar_count + 1))
                continue
            fi
            stored="$(< "$side")"
            actual="$(_hash_deployed_body "$f")"
            if [[ "$stored" != "$actual" ]]; then
                _add_result "content-drift" "$_FAIL" \
                    "deployed file modified since last generate: ${label}/${b}"
                drift_count=$((drift_count + 1))
            fi
            checked_count=$((checked_count + 1))
        done
    }

    # Check agents: hash deployed body (frontmatter stripped) vs sidecar
    local dst_file sidecar basename_f
    for dst_file in "${output_dir}/agents"/*.md; do
        [[ -f "$dst_file" ]] || continue
        basename_f="$(basename "$dst_file" .md)"
        sidecar="${dst_file}.rdf-hash"

        if [[ ! -f "$sidecar" ]]; then
            missing_sidecar_count=$((missing_sidecar_count + 1))
            continue
        fi

        local stored_hash actual_hash
        stored_hash="$(< "$sidecar")"
        actual_hash="$(_hash_deployed_body "$dst_file")"

        if [[ "$stored_hash" != "$actual_hash" ]]; then
            _add_result "content-drift" "$_FAIL" \
                "deployed file modified since last generate: agents/${basename_f}.md"
            drift_count=$((drift_count + 1))
        fi
        checked_count=$((checked_count + 1))
    done

    # Check skills: hash deployed body (frontmatter stripped) vs sidecar
    if [[ -d "${output_dir}/skills" ]]; then
        local skill_file skill_dir
        for skill_file in "${output_dir}/skills"/*/SKILL.md; do
            [[ -f "$skill_file" ]] || continue
            skill_dir="$(basename "$(dirname "$skill_file")")"
            sidecar="${skill_file}.rdf-hash"

            if [[ ! -f "$sidecar" ]]; then
                missing_sidecar_count=$((missing_sidecar_count + 1))
                continue
            fi

            local stored_hash actual_hash
            stored_hash="$(< "$sidecar")"
            actual_hash="$(_hash_deployed_body "$skill_file")"

            if [[ "$stored_hash" != "$actual_hash" ]]; then
                _add_result "content-drift" "$_FAIL" \
                    "deployed file modified since last generate: skills/${skill_dir}"
                drift_count=$((drift_count + 1))
            fi
            checked_count=$((checked_count + 1))
        done
    else
        _add_result "content-drift" "$_WARN" "no skills tree — run 'rdf generate claude-code'"
        skills_tree_missing=1
    fi

    # Reference docs: the deployed copy under output/, and the sibling copy the
    # cc adapter writes into the skills tree (both carry .rdf-hash sidecars).
    _drift_check_tree "${output_dir}/reference" "reference"
    _drift_check_tree "${output_dir}/skills/reference" "skills/reference"

    if [[ $missing_sidecar_count -gt 0 ]]; then
        _add_result "content-drift" "$_WARN" \
            "${missing_sidecar_count} file(s) missing .rdf-hash sidecar — run 'rdf generate claude-code'"
    fi

    if [[ $drift_count -eq 0 ]] && [[ $checked_count -gt 0 ]]; then
        if [[ $skills_tree_missing -eq 1 ]]; then
            _add_result "content-drift" "$_OK" \
                "${checked_count} other deployed files match canonical sources"
        else
            _add_result "content-drift" "$_OK" \
                "all ${checked_count} deployed files match canonical sources"
        fi
    elif [[ $checked_count -eq 0 ]] && [[ $missing_sidecar_count -eq 0 ]]; then
        _add_result "content-drift" "$_WARN" "no files with sidecars found — run 'rdf generate claude-code'"
    fi
}

# ── Check: sync (RDF-specific) ──
_check_sync() {
    local path="${1%/}"   # --all yields a trailing slash; strip it so output_dir has no
                          # "//" that would fail the normalized-symlink string match below

    # Only meaningful for the RDF project itself
    local canonical_dir="${path}/canonical"
    local output_dir="${path}/adapters/claude-code/output"

    if [[ ! -d "$canonical_dir" ]]; then
        _add_result "sync" "$_OK" "not the RDF framework checkout — sync check N/A"
        return 0
    fi

    if [[ ! -d "$output_dir" ]]; then
        _add_result "sync" "$_WARN" "no generated output — run 'rdf generate claude-code'"
        return 0
    fi

    # Compare agent count
    local canon_agents=0
    local output_agents=0
    for f in "${canonical_dir}/agents"/*.md; do
        [[ -f "$f" ]] && canon_agents=$((canon_agents + 1))
    done
    for f in "${output_dir}/agents"/*.md; do
        [[ -f "$f" ]] && output_agents=$((output_agents + 1))
    done

    if [[ $canon_agents -ne $output_agents ]]; then
        _add_result "sync" "$_WARN" "agent count mismatch: canonical=${canon_agents}, output=${output_agents}"
    else
        _add_result "sync" "$_OK" "agent count matches (${canon_agents})"
    fi

    # Compare command count against skills/*/SKILL.md
    local canon_cmds=0
    local output_cmds=0
    for f in "${canonical_dir}/commands"/*.md; do
        [[ -f "$f" ]] && canon_cmds=$((canon_cmds + 1))
    done
    if [[ -d "${output_dir}/skills" ]]; then
        for f in "${output_dir}/skills"/*/SKILL.md; do
            [[ -f "$f" ]] && output_cmds=$((output_cmds + 1))
        done
        if [[ $canon_cmds -ne $output_cmds ]]; then
            _add_result "sync" "$_WARN" "command count mismatch: canonical=${canon_cmds}, output=${output_cmds}"
        else
            _add_result "sync" "$_OK" "command count matches (${canon_cmds})"
        fi
    else
        _add_result "sync" "$_WARN" "no skills tree — run 'rdf generate claude-code'"
    fi

    # Check symlink health: <target>/* -> output/ (honors RDF_TARGET override)
    local link_ok=0
    local link_fail=0
    local claude_base="${RDF_TARGET:-${HOME}/.claude}"

    # _sync_check_link link expected_target — shared OK/WARN bookkeeping for
    # the dir-surface, commands, and per-skill symlink checks below (dynamic
    # scoping: link_ok/link_fail are the caller's locals).
    _sync_check_link() {
        local link="$1" expected="$2" link_dest
        if [[ -L "$link" ]]; then
            link_dest="$(rdf_canonical_path "$link")"
            if [[ "$link_dest" == "$expected" ]]; then
                link_ok=$((link_ok + 1))
            else
                _add_result "sync" "$_WARN" "${link} points to wrong target: ${link_dest}"
                link_fail=$((link_fail + 1))
            fi
        elif [[ -d "$link" ]]; then
            _add_result "sync" "$_WARN" "${link} is a directory, not a symlink"
            link_fail=$((link_fail + 1))
        else
            _add_result "sync" "$_WARN" "${link} missing"
            link_fail=$((link_fail + 1))
        fi
    }

    local target
    while IFS= read -r target; do
        _sync_check_link "${claude_base}/${target}" "${output_dir}/${target}"
    done < <(rdf_cc_dir_surfaces)

    if [[ -d "${output_dir}/skills" ]]; then
        local skill_dir skill_name
        for skill_dir in "${output_dir}/skills"/*/; do
            [[ -d "$skill_dir" ]] || continue
            skill_name="$(basename "$skill_dir")"
            [[ "$skill_name" == "reference" ]] && continue   # shared reference/ is checked below, not as a skill
            _sync_check_link "${claude_base}/skills/${skill_name}" "${output_dir}/skills/${skill_name}"
        done
        # ../reference/*.md inside every SKILL.md resolves only when this entry exists
        if [[ -d "${output_dir}/skills/reference" ]]; then
            _sync_check_link "${claude_base}/skills/reference" "${output_dir}/skills/reference"
        fi
    fi

    # A lingering legacy commands symlink (pre-3.6.6 install, not yet re-deployed)
    # into RDF's own output tree — 'rdf deploy claude-code' prunes it on next run.
    if [[ -L "${claude_base}/commands" ]]; then
        local legacy_target legacy_root
        legacy_target="$(rdf_canonical_path "${claude_base}/commands")"
        legacy_root="$(rdf_canonical_path "$output_dir")"
        if [[ -n "$legacy_root" ]]; then   # an unresolvable output root would collapse the match to '*'
            case "$legacy_target" in
                "$legacy_root"|"$legacy_root"/*)   # path boundary: output-backup/ is not inside output/
                    _add_result "sync" "$_WARN" \
                        "${claude_base}/commands still symlinks into RDF output — re-run 'rdf deploy claude-code' to prune it"
                    ;;
            esac
        fi
    fi

    if [[ $link_fail -eq 0 ]] && [[ $link_ok -gt 0 ]]; then
        _add_result "sync" "$_OK" "all ${link_ok} symlinks correct"
    fi
}

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
        _add_result "readme" "$_WARN" "README.md missing"
        return 0
    fi

    local readme="${path}/README.md"
    local line_count
    line_count="$(wc -l < "$readme")"
    _add_result "readme" "$_OK" "README.md present (${line_count} lines)"

    # Badge row: shields.io or GitHub Actions badge
    if grep -qE 'shields\.io|github\.com/.*badge\.svg|img\.shields' "$readme" 2>/dev/null; then
        local badge_count
        badge_count="$(grep -cE 'shields\.io|github\.com/.*badge\.svg|img\.shields' "$readme" 2>/dev/null)" || badge_count=0
        _add_result "readme" "$_OK" "badge row detected (${badge_count} badges)"
    else
        _add_result "readme" "$_FAIL" "badge row not found (no shields.io or GitHub badge URLs)"
    fi

    if grep -qiE '^## ([0-9]+\. +)?Quick Start' "$readme" 2>/dev/null; then
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
    numbered_count="$(grep -cE '^## [0-9]+\.' "$readme" 2>/dev/null)" || numbered_count=0
    if [[ "$numbered_count" -gt 0 ]]; then
        _add_result "readme" "$_OK" "numbered sections (${numbered_count} found)"
    else
        _add_result "readme" "$_FAIL" "no numbered sections (## N. format expected)"
    fi

    if grep -qiE '^## ([0-9]+\. +)?Configuration' "$readme" 2>/dev/null; then
        _add_result "readme" "$_OK" "## Configuration present"
    else
        _add_result "readme" "$_FAIL" "## Configuration section missing"
    fi

    if grep -qiE '^## ([0-9]+\. +)?Usage' "$readme" 2>/dev/null; then
        _add_result "readme" "$_OK" "## Usage present"
    else
        _add_result "readme" "$_FAIL" "## Usage section missing"
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

# ── Check: deps (runtime dependencies for hooks/statusline) ──
# jq is optional but hooks and the statusline silently degrade without it.
# Missing jq is a WARN, never a FAIL — RDF core works without it.
_check_deps() {
    if command -v jq >/dev/null 2>&1; then
        local jq_version=""
        jq_version="$(jq --version 2>/dev/null || echo "unknown")"  # ancient jq lacks --version
        _add_result "deps" "$_OK" "jq present (${jq_version})"
    else
        _add_result "deps" "$_WARN" "jq not found — statusline context bar and hook JSON parsing degrade; install: apt/dnf install jq (or brew install jq)"
    fi
}

# ── Check: catalogs — adapter metadata catalogs vs canonical globs ──
# Missing agent-meta key = FAIL (generate refuses; sync-truncation armer);
# orphan entries = WARN. skill-meta is a curated subset — orphans only.
_check_catalogs() {
    local agents_dir="${RDF_CANONICAL}/agents"
    local agent_meta="${RDF_ADAPTERS}/claude-code/agent-meta.json"
    local skill_meta="${RDF_ADAPTERS}/agent-skills/skill-meta.json"
    if ! command -v jq >/dev/null 2>&1; then
        _add_result "catalogs" "$_WARN" "jq not found — catalog checks skipped"
        return 0
    fi
    local f b missing="" orphans=""
    if [[ -f "$agent_meta" ]]; then
        for f in "${agents_dir}"/*.md; do
            [[ -f "$f" ]] || continue
            b="$(command basename "$f" .md)"
            jq -e --arg a "$b" 'has($a)' "$agent_meta" >/dev/null 2>&1 \
                || missing="${missing:+${missing}, }${b}"   # jq -e false/parse-fail both count as missing
        done
        # Orphan scan considers only agent-shaped entries (object with .name) —
        # structural keys (nested command metadata, _-prefixed) are not agents.
        while IFS= read -r b; do
            [[ -f "${agents_dir}/${b}.md" ]] || orphans="${orphans:+${orphans}, }${b}"
        done < <(jq -r 'to_entries[] | select((.key | startswith("_") | not) and (.value | type == "object" and has("name"))) | .key' "$agent_meta" 2>/dev/null)  # unparseable meta → empty list (missing loop already flagged)
        if [[ -n "$missing" ]]; then
            _add_result "catalogs" "$_FAIL" "agent-meta.json missing agents: ${missing} — rdf generate will refuse"
        else
            _add_result "catalogs" "$_OK" "agent-meta.json covers all canonical agents"
        fi
        [[ -n "$orphans" ]] && _add_result "catalogs" "$_WARN" "agent-meta.json orphan entries (no canonical agent): ${orphans}"
    else
        _add_result "catalogs" "$_FAIL" "agent-meta.json not found: ${agent_meta}"
    fi
    if [[ -f "$skill_meta" ]]; then
        orphans=""
        while IFS= read -r b; do
            [[ -f "${RDF_CANONICAL}/commands/${b}.md" ]] || orphans="${orphans:+${orphans}, }${b}"
        done < <(jq -r 'keys[] | select(startswith("_") | not)' "$skill_meta" 2>/dev/null)  # _-prefixed = schema docs, not commands; unparseable meta → empty list
        if [[ -n "$orphans" ]]; then
            _add_result "catalogs" "$_WARN" "skill-meta.json orphan entries (no canonical command): ${orphans}"
        else
            _add_result "catalogs" "$_OK" "skill-meta.json keys all resolve to canonical commands"
        fi
    fi
    return 0
}

# ── Check: state-helpers — ~/.rdf/state delivery integrity ──
# Symlink → OK (or WARN if it points outside this checkout); real file →
# hash-compare against source (stale = FAIL, the 3.6.x silent-degradation
# class); absent → WARN with remediation.
_check_state_helpers() {
    local state_dst="${HOME}/.rdf/state"
    local src dst b stale="" absent="" foreign="" has_copy=0
    for src in "${RDF_HOME}/state/"*.sh; do
        [[ -f "$src" ]] || continue
        b="$(command basename "$src")"
        dst="${state_dst}/${b}"
        if [[ -L "$dst" ]]; then
            [[ "$(rdf_canonical_path "$dst")" == "$(rdf_canonical_path "$src")" ]] \
                || foreign="${foreign:+${foreign}, }${b}"
        elif [[ -f "$dst" ]]; then
            has_copy=1
            [[ "$(rdf_hash_stdin < "$dst")" == "$(rdf_hash_stdin < "$src")" ]] \
                || stale="${stale:+${stale}, }${b}"
        else
            absent="${absent:+${absent}, }${b}"
        fi
    done
    if [[ -n "$stale" ]]; then
        _add_result "state-helpers" "$_FAIL" "stale deployed copies: ${stale} — run 'rdf deploy --force claude-code' (checkout; backs up your copies) or restart your session (plugin)"
    fi
    [[ -n "$foreign" ]] && _add_result "state-helpers" "$_WARN" "symlinks point outside this checkout: ${foreign}"
    [[ -n "$absent" ]] && _add_result "state-helpers" "$_WARN" "helpers not deployed: ${absent} — run 'rdf deploy claude-code'"
    if [[ -z "$stale" && -z "$foreign" && -z "$absent" ]]; then
        _add_result "state-helpers" "$_OK" "all state helpers current"
    fi
    # Stamp comparison only means something while bootstrap copies exist —
    # deploy retires the stamps when symlinks take ownership.
    if [[ "$has_copy" -eq 1 && -f "${state_dst}/.rdf-version" ]] \
        && [[ "$(command cat "${state_dst}/.rdf-version")" != "$RDF_VERSION" ]]; then
        _add_result "state-helpers" "$_WARN" "bootstrap stamp $(command cat "${state_dst}/.rdf-version") != checkout ${RDF_VERSION} — restart your session to re-bootstrap"
    fi
    return 0
}

# ── Check: doc-stats (RDF-specific) ──
# Verifies the human-maintained inventory counts in WORKFORCE.md, RDF.md, and
# docs/index.md against live counts derived from the filesystem. Count drift
# (e.g. a new command added without updating the tables) becomes a FAIL so it
# cannot ship — doctor runs pre-push and in CI. Number extraction is pure-bash
# regex (BASH_REMATCH) to avoid a subprocess-per-field storm.
_check_doc_stats() {
    local path="$1"

    local canonical_dir="${path}/canonical"
    if [[ ! -d "$canonical_dir" ]]; then
        # Not the RDF project — doc-stats check N/A
        return 0
    fi

    # Live counts from the filesystem
    local total_cmds=0 util_cmds=0 life_cmds=0 agents=0 scripts=0 profiles=0 adapters=0 modes=0
    local f base
    for f in "${canonical_dir}/commands"/*.md; do
        [[ -f "$f" ]] || continue
        total_cmds=$((total_cmds + 1))
        base="${f##*/}"
        case "$base" in
            r-util-*) util_cmds=$((util_cmds + 1)) ;;
            *)        life_cmds=$((life_cmds + 1)) ;;
        esac
    done
    for f in "${canonical_dir}/agents"/*.md;  do [[ -f "$f" ]] && agents=$((agents + 1)); done
    for f in "${canonical_dir}/scripts"/*.sh; do [[ -f "$f" ]] && scripts=$((scripts + 1)); done
    for f in "${path}/profiles"/*/;          do
        [[ -d "$f" ]] || continue
        [[ "${f%/}" == */lite ]] && continue   # lite is a deploy source, not a governance profile
        profiles=$((profiles + 1))
    done
    for f in "${path}/adapters"/*/;          do [[ -d "$f" ]] && adapters=$((adapters + 1)); done
    for f in "${path}/modes"/*/;             do [[ -d "$f" ]] && modes=$((modes + 1)); done

    # Compare one claimed count against the live actual, emitting a result row.
    _doc_stat_cmp() {
        local file="$1" what="$2" claimed="$3" actual="$4"
        if [[ -z "$claimed" ]]; then
            _add_result "doc-stats" "$_WARN" "${file}: ${what} count not found (actual ${actual})"
        elif [[ "$claimed" != "$actual" ]]; then
            _add_result "doc-stats" "$_FAIL" "${file}: ${what} claims ${claimed}, actual ${actual}"
        else
            _add_result "doc-stats" "$_OK" "${file}: ${what} = ${actual}"
        fi
    }

    # WORKFORCE.md section-header counts
    local wf="${path}/WORKFORCE.md"
    if [[ -f "$wf" ]]; then
        local wf_life="" wf_util="" line
        while IFS= read -r line; do
            [[ "$line" =~ Lifecycle\ Commands\ \(([0-9]+)\) ]] && wf_life="${BASH_REMATCH[1]}"
            [[ "$line" =~ Utility\ Commands\ \(([0-9]+)\) ]] && wf_util="${BASH_REMATCH[1]}"
        done < <(grep -E 'Commands \([0-9]+\)' "$wf")
        _doc_stat_cmp "WORKFORCE.md" "lifecycle" "$wf_life" "$life_cmds"
        _doc_stat_cmp "WORKFORCE.md" "utility"   "$wf_util" "$util_cmds"

        # Primitives line: "**Total: A agents + B commands + C scripts = D primitives**"
        local pline wf_pa="" wf_pc="" wf_ps="" wf_pd=""
        pline="$(grep -m1 -E 'Total:.*[0-9]+ agents .* [0-9]+ primitives' "$wf")" || pline=""
        if [[ "$pline" =~ ([0-9]+)\ agents\ \+\ ([0-9]+)\ commands\ \+\ ([0-9]+)\ scripts\ =\ ([0-9]+)\ primitives ]]; then
            wf_pa="${BASH_REMATCH[1]}"; wf_pc="${BASH_REMATCH[2]}"
            wf_ps="${BASH_REMATCH[3]}"; wf_pd="${BASH_REMATCH[4]}"
        fi
        _doc_stat_cmp "WORKFORCE.md" "primitives agents"   "$wf_pa" "$agents"
        _doc_stat_cmp "WORKFORCE.md" "primitives commands" "$wf_pc" "$total_cmds"
        _doc_stat_cmp "WORKFORCE.md" "primitives scripts"  "$wf_ps" "$scripts"
        # D must equal A+B+C (self-consistency of the printed sum)
        if [[ -n "$wf_pd" ]]; then
            _doc_stat_cmp "WORKFORCE.md" "primitives total" "$wf_pd" \
                "$(( ${wf_pa:-0} + ${wf_pc:-0} + ${wf_ps:-0} ))"
        else
            _doc_stat_cmp "WORKFORCE.md" "primitives total" "" "0"
        fi
    fi

    # RDF.md scope line: "N commands under `/r-` namespace (X lifecycle + Y utility)"
    local rdf="${path}/RDF.md"
    if [[ -f "$rdf" ]]; then
        local rdf_total="" rdf_life="" rdf_util="" rline=""
        rline="$(grep -m1 -E '[0-9]+ commands under .*\([0-9]+ lifecycle \+ [0-9]+ utility\)' "$rdf")" || rline=""
        if [[ "$rline" =~ ([0-9]+)\ commands\ under.*\(([0-9]+)\ lifecycle\ \+\ ([0-9]+)\ utility\) ]]; then
            rdf_total="${BASH_REMATCH[1]}"
            rdf_life="${BASH_REMATCH[2]}"
            rdf_util="${BASH_REMATCH[3]}"
        fi
        _doc_stat_cmp "RDF.md" "commands"  "$rdf_total" "$total_cmds"
        _doc_stat_cmp "RDF.md" "lifecycle" "$rdf_life"  "$life_cmds"
        _doc_stat_cmp "RDF.md" "utility"   "$rdf_util"  "$util_cmds"
    fi

    # canonical/reference/framework.md command-naming counts:
    # "lifecycle commands (N)" / "utility commands (M)"
    local fw="${canonical_dir}/reference/framework.md"
    if [[ -f "$fw" ]]; then
        local fw_life="" fw_util="" fwline
        while IFS= read -r fwline; do
            [[ "$fwline" =~ lifecycle\ commands\ \(([0-9]+)\) ]] && fw_life="${BASH_REMATCH[1]}"
            [[ "$fwline" =~ utility\ commands\ \(([0-9]+)\) ]] && fw_util="${BASH_REMATCH[1]}"
        done < <(grep -E '(lifecycle|utility) commands \([0-9]+\)' "$fw")
        _doc_stat_cmp "framework.md" "lifecycle" "$fw_life" "$life_cmds"
        _doc_stat_cmp "framework.md" "utility"   "$fw_util" "$util_cmds"
    fi

    # docs/index.md banner: "A agents · B commands · C profiles · D adapters · E modes"
    local idx="${path}/docs/index.md"
    if [[ -f "$idx" ]]; then
        local iline idx_agents="" idx_cmds="" idx_profiles="" idx_adapters="" idx_modes=""
        iline="$(grep -m1 -E '[0-9]+ agents.*[0-9]+ modes' "$idx")" || iline=""
        [[ "$iline" =~ ([0-9]+)\ agents ]]   && idx_agents="${BASH_REMATCH[1]}"
        [[ "$iline" =~ ([0-9]+)\ commands ]] && idx_cmds="${BASH_REMATCH[1]}"
        [[ "$iline" =~ ([0-9]+)\ profiles ]] && idx_profiles="${BASH_REMATCH[1]}"
        [[ "$iline" =~ ([0-9]+)\ adapters ]] && idx_adapters="${BASH_REMATCH[1]}"
        [[ "$iline" =~ ([0-9]+)\ modes ]]    && idx_modes="${BASH_REMATCH[1]}"
        _doc_stat_cmp "docs/index.md" "agents"   "$idx_agents"   "$agents"
        _doc_stat_cmp "docs/index.md" "commands" "$idx_cmds"     "$total_cmds"
        _doc_stat_cmp "docs/index.md" "profiles" "$idx_profiles" "$profiles"
        _doc_stat_cmp "docs/index.md" "adapters" "$idx_adapters" "$adapters"
        _doc_stat_cmp "docs/index.md" "modes"    "$idx_modes"    "$modes"
    fi

    # README.md footer banner: "**A agents -- B commands -- C scripts -- D profiles -- E adapters -- F modes**"
    local rdme="${path}/README.md"
    if [[ -f "$rdme" ]]; then
        local fline rd_ag="" rd_cmd="" rd_scr="" rd_prof="" rd_adp="" rd_mod=""
        fline="$(grep -m1 -E '\*\*[0-9]+ agents .* [0-9]+ modes\*\*' "$rdme")" || fline=""
        [[ "$fline" =~ ([0-9]+)\ agents ]]   && rd_ag="${BASH_REMATCH[1]}"
        [[ "$fline" =~ ([0-9]+)\ commands ]] && rd_cmd="${BASH_REMATCH[1]}"
        [[ "$fline" =~ ([0-9]+)\ scripts ]]  && rd_scr="${BASH_REMATCH[1]}"
        [[ "$fline" =~ ([0-9]+)\ profiles ]] && rd_prof="${BASH_REMATCH[1]}"
        [[ "$fline" =~ ([0-9]+)\ adapters ]] && rd_adp="${BASH_REMATCH[1]}"
        [[ "$fline" =~ ([0-9]+)\ modes ]]    && rd_mod="${BASH_REMATCH[1]}"
        _doc_stat_cmp "README.md" "agents"   "$rd_ag"   "$agents"
        _doc_stat_cmp "README.md" "commands" "$rd_cmd"  "$total_cmds"
        _doc_stat_cmp "README.md" "scripts"  "$rd_scr"  "$scripts"
        _doc_stat_cmp "README.md" "profiles" "$rd_prof" "$profiles"
        _doc_stat_cmp "README.md" "adapters" "$rd_adp"  "$adapters"
        _doc_stat_cmp "README.md" "modes"    "$rd_mod"  "$modes"
    fi
}

# Version resolver for doctor (avoids sourcing init.sh dependency)
# ── Check: install-mode ──
# Detects how RDF is installed for this user: symlink deploy (~/.claude/
# skills/<n> -> adapter output), plugin install (rdf@rdf in the plugin
# manifest), both (WARN — duplicate skills), or neither.
_check_install_mode() {
    local manifest="${HOME}/.claude/plugins/installed_plugins.json"
    local base="${RDF_TARGET:-${HOME}/.claude}"
    local symlink_mode=0
    local plugin_mode=0

    # Only a link into RDF's own output tree counts — a user's own skill symlink
    # (pdf-reader -> ~/skills/pdf-reader) must not read as an RDF install.
    local d target rdf_skills="${RDF_ADAPTERS}/claude-code/output/skills/"
    for d in "${base}/skills"/*; do
        [[ -L "$d" ]] || continue
        target="$(command readlink "$d")"
        case "$target" in
            "${rdf_skills}"*) symlink_mode=1; break ;;
        esac
    done
    if [[ -f "$manifest" ]] \
        && jq -e '.plugins | has("rdf@rdf")' "$manifest" >/dev/null 2>&1; then  # absent or malformed manifest = not plugin-installed
        plugin_mode=1
    fi

    if [[ $symlink_mode -eq 1 && $plugin_mode -eq 1 ]]; then
        _add_result "install-mode" "$_WARN" "both symlink deploy and plugin install detected — /r-start and /rdf:r-start both active; remove one (rdf deploy help | /plugin uninstall rdf@rdf)"
    elif [[ $plugin_mode -eq 1 ]]; then
        _add_result "install-mode" "$_OK" "plugin install (rdf@rdf)"
    elif [[ $symlink_mode -eq 1 ]]; then
        _add_result "install-mode" "$_OK" "symlink deploy"
    else
        _add_result "install-mode" "$_OK" "no user-level RDF install (project-only usage)"
    fi
}

_resolve_version_for_doctor() {
    local path="$1"
    local name
    name="$(basename "$path")"

    if [[ -f "${path}/VERSION" ]]; then
        local v
        v="$(< "${path}/VERSION")"
        echo "${v%%[[:space:]]}"
    elif [[ -f "${path}/files/${name}" ]]; then
        # grep may exit 1 if no match — safe to fallback
        grep -m1 '^VERSION=' "${path}/files/${name}" 2>/dev/null \
            | cut -d= -f2 | tr -d '"' || echo "unknown"
    else
        echo "unknown"
    fi
}

# Print results for one project
_print_results() {
    local name="$1"
    local quiet="$2"
    local json_mode="$3"

    if [[ "$json_mode" -eq 1 ]]; then
        # JSON output handled by caller
        return 0
    fi

    echo ""
    echo "=== ${name} ==="
    echo ""

    local entry
    for entry in "${_RESULTS[@]}"; do
        local category status message
        IFS='|' read -r category status message <<< "$entry"

        # Skip OK in quiet mode
        if [[ "$quiet" -eq 1 ]] && [[ "$status" == "$_OK" ]]; then
            continue
        fi

        local icon=""
        case "$status" in
            "$_OK")   icon="  [OK]" ;;
            "$_WARN") icon="[WARN]" ;;
            "$_FAIL") icon="[FAIL]" ;;
        esac

        printf "  %-10s %s  %s\n" "[$category]" "$icon" "$message"
    done

    echo ""
    echo "  Summary: ${_PASS_COUNT} OK, ${_WARN_COUNT} WARN, ${_FAIL_COUNT} FAIL"
}

# Convert results to JSON object for one project
_results_to_json() {
    local name="$1"
    local path="$2"

    printf '{"project":"%s","path":"%s","ok":%d,"warn":%d,"fail":%d,"checks":[' \
        "$name" "$path" "$_PASS_COUNT" "$_WARN_COUNT" "$_FAIL_COUNT"

    local first=1
    local entry
    for entry in "${_RESULTS[@]}"; do
        local category status message
        IFS='|' read -r category status message <<< "$entry"
        [[ $first -eq 0 ]] && printf ","
        printf '{"category":"%s","status":"%s","message":"%s"}' \
            "$category" "$status" "$message"
        first=0
    done

    printf "]}"
}

# Reset state between projects
_reset_results() {
    _RESULTS=()
    _PASS_COUNT=0
    _WARN_COUNT=0
    _FAIL_COUNT=0
}

# Run all (or scoped) checks on a single project
_doctor_one() {
    local path="$1"
    local scope="$2"

    case "$scope" in
        ""|all)
            _check_artifacts "$path"
            _check_drift "$path"
            _check_memory "$path"
            _check_plan "$path"
            _check_github "$path"
            _check_sync "$path"
            _check_install_mode "$path"
            _check_deps
            _check_catalogs
            _check_state_helpers
            _check_content_drift "$path"
            _check_doc_stats "$path"
            _check_readme "$path"
            ;;
        artifacts)      _check_artifacts "$path" ;;
        drift)          _check_drift "$path" ;;
        memory)         _check_memory "$path" ;;
        plan)           _check_plan "$path" ;;
        github)         _check_github "$path" ;;
        sync)           _check_sync "$path" ;;
        install-mode)   _check_install_mode "$path" ;;
        deps)           _check_deps ;;
        catalogs)       _check_catalogs ;;
        state-helpers)  _check_state_helpers ;;
        content-drift)  _check_content_drift "$path" ;;
        doc-stats)      _check_doc_stats "$path" ;;
        readme)         _check_readme "$path" ;;
        *)         rdf_die "unknown scope: $scope — valid: artifacts, drift, memory, plan, github, sync, install-mode, deps, catalogs, state-helpers, content-drift, doc-stats, readme" ;;
    esac
}

cmd_doctor() {
    local path=""
    local scan_all=0
    local scope=""
    local json_mode=0
    local quiet=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)    scan_all=1; shift ;;
            --scope)  scope="$2"; shift 2 ;;
            --json)   json_mode=1; shift ;;
            --quiet)  quiet=1; shift ;;
            help|--help|-h) _doctor_usage; return 0 ;;
            -*)       rdf_die "unknown option: $1 — run 'rdf doctor help'" ;;
            *)
                if [[ -z "$path" ]]; then
                    path="$1"; shift
                else
                    rdf_die "unexpected argument: $1 — run 'rdf doctor help'"
                fi
                ;;
        esac
    done

    # Default path
    if [[ -z "$path" ]]; then
        if [[ "$scan_all" -eq 1 ]]; then
            # A checkout sitting directly in HOME (or /) makes the parent-of-
            # RDF_HOME guess the home directory itself — scanning it is wrong
            if [[ -z "$_WORKSPACE_ROOT" ]] || [[ "$_WORKSPACE_ROOT" == "$HOME" ]] \
                    || [[ "$_WORKSPACE_ROOT" == "/" ]]; then
                rdf_die "workspace root could not be inferred from ${RDF_HOME} — pass one: 'rdf doctor --all /path/to/workspace' or set RDF_WORKSPACE"
            fi
            path="${_WORKSPACE_ROOT}"
        else
            path="$(pwd)"
        fi
    fi

    # Resolve absolute path
    if [[ ! -d "$path" ]]; then
        rdf_die "directory not found: $path"
    fi
    path="$(cd "$path" && pwd)" || rdf_die "cannot resolve path: $path"

    if [[ "$scan_all" -eq 1 ]]; then
        # Cross-project scan: iterate git repos in workspace
        local total_ok=0
        local total_warn=0
        local total_fail=0
        local project_count=0
        local json_first=1

        [[ "$json_mode" -eq 1 ]] && printf "["

        for subdir in "${path}"/*/; do
            [[ -d "$subdir" ]] || continue
            [[ -d "${subdir}/.git" ]] || continue

            local name
            name="$(basename "$subdir")"
            # Skip hidden dirs and known non-project dirs
            [[ "$name" == .* ]] && continue
            [[ "$name" == "inactive" ]] && continue
            [[ "$name" == "old_plans" ]] && continue
            [[ "$name" == "reference" ]] && continue
            [[ "$name" == "redteam" ]] && continue
            [[ "$name" == "claude" ]] && continue

            _reset_results
            _doctor_one "$subdir" "$scope"

            if [[ "$json_mode" -eq 1 ]]; then
                [[ $json_first -eq 0 ]] && printf ","
                _results_to_json "$name" "$subdir"
                json_first=0
            else
                _print_results "$name" "$quiet" 0
            fi

            total_ok=$((total_ok + _PASS_COUNT))
            total_warn=$((total_warn + _WARN_COUNT))
            total_fail=$((total_fail + _FAIL_COUNT))
            project_count=$((project_count + 1))
        done

        # Workspace-level checks
        if [[ "$json_mode" -ne 1 ]]; then
            echo ""
            echo "=== workspace ==="
            echo ""
            if [[ -d "${path}/.rdf" ]]; then
                printf "  %-10s %s  %s\n" "[workspace]" "  [OK]" ".rdf/ present"
                total_ok=$((total_ok + 1))
            else
                printf "  %-10s %s  %s\n" "[workspace]" "[WARN]" ".rdf/ missing — run 'rdf init --batch' or 'rdf migrate --all'"
                total_warn=$((total_warn + 1))
            fi
            if [[ -d "${path}/work-output" ]]; then
                printf "  %-10s %s  %s\n" "[workspace]" "[WARN]" "work-output/ at workspace root — run 'rdf migrate --all'"
                total_warn=$((total_warn + 1))
            fi
        fi

        if [[ "$json_mode" -eq 1 ]]; then
            printf "]\n"
        else
            echo ""
            echo "---"
            echo "Cross-project: ${project_count} projects scanned"
            echo "Totals: ${total_ok} OK, ${total_warn} WARN, ${total_fail} FAIL"
        fi
    else
        # Single project
        local name
        name="$(basename "$path")"

        _reset_results
        _doctor_one "$path" "$scope"

        if [[ "$json_mode" -eq 1 ]]; then
            _results_to_json "$name" "$path"
            printf "\n"
        else
            _print_results "$name" "$quiet" 0
        fi
    fi

    # Exit code: 1 if any FAIL, 0 otherwise (WARN is advisory)
    if [[ $_FAIL_COUNT -gt 0 ]]; then
        return 1
    fi
    return 0
}
