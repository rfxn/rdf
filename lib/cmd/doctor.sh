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
                        artifacts, drift, memory, plan, github, sync
  --json                Output results as JSON
  --quiet               Only show WARN and FAIL

Examples:
  rdf doctor
  rdf doctor /root/admin/work/proj/brute-force-detection
  rdf doctor --all
  rdf doctor --scope github
  rdf doctor --all --scope memory
USAGE
}

# Default workspace root — parent of RDF home
_WORKSPACE_ROOT="/root/admin/work/proj"

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
    else
        _add_result "artifacts" "$_WARN" ".rdf/ missing — run 'rdf init' or 'rdf migrate'"
    fi

    # .git/info/exclude
    if [[ -d "${path}/.git" ]]; then
        local exclude="${path}/.git/info/exclude"
        if [[ -f "$exclude" ]]; then
            local missing=0
            for entry in "CLAUDE.md" "PLAN*.md" "MEMORY.md" ".rdf/"; do
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

    # Structural checks: does CLAUDE.md reference parent?
    local parent_ref="/root/admin/work/proj/CLAUDE.md"
    if grep -q "$parent_ref" "${path}/CLAUDE.md" 2>/dev/null || \
       grep -qi "inherits.*parent" "${path}/CLAUDE.md" 2>/dev/null; then
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
        mem_mtime="$(stat -c %Y "${path}/MEMORY.md" 2>/dev/null || echo "0")"
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
            plan_mtime="$(stat -c %Y "$f" 2>/dev/null || echo "0")"
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

    local repo
    repo="$(git -C "$path" remote get-url origin 2>/dev/null \
        | sed 's|.*github.com[:/]||; s|\.git$||' || echo "")"
    if [[ -z "$repo" ]]; then
        _add_result "github" "$_WARN" "no GitHub remote — skipping"
        return 0
    fi

    # Check for standardized labels
    local label_count
    label_count="$(gh label list --repo "$repo" --json name --jq 'length' 2>/dev/null || echo "0")"
    if [[ "$label_count" -eq 0 ]]; then
        _add_result "github" "$_FAIL" "no labels on ${repo}"
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

# ── Check: sync (RDF-specific) ──
_check_sync() {
    local path="$1"

    # Only meaningful for the RDF project itself
    local canonical_dir="${path}/canonical"
    local output_dir="${path}/adapters/claude-code/output"

    if [[ ! -d "$canonical_dir" ]]; then
        _add_result "sync" "$_OK" "not an RDF project — sync check N/A"
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

    # Compare command count
    local canon_cmds=0
    local output_cmds=0
    for f in "${canonical_dir}/commands"/*.md; do
        [[ -f "$f" ]] && canon_cmds=$((canon_cmds + 1))
    done
    for f in "${output_dir}/commands"/*.md; do
        [[ -f "$f" ]] && output_cmds=$((output_cmds + 1))
    done

    if [[ $canon_cmds -ne $output_cmds ]]; then
        _add_result "sync" "$_WARN" "command count mismatch: canonical=${canon_cmds}, output=${output_cmds}"
    else
        _add_result "sync" "$_OK" "command count matches (${canon_cmds})"
    fi

    # Check symlink health: /root/.claude/* -> output/
    local link_ok=0
    local link_fail=0
    for target in commands agents scripts; do
        local link="/root/.claude/${target}"
        if [[ -L "$link" ]]; then
            local link_dest
            link_dest="$(readlink -f "$link" 2>/dev/null || echo "")"
            if [[ "$link_dest" == "${output_dir}/${target}" ]]; then
                link_ok=$((link_ok + 1))
            else
                _add_result "sync" "$_WARN" "/root/.claude/${target} points to wrong target: ${link_dest}"
                link_fail=$((link_fail + 1))
            fi
        elif [[ -d "$link" ]]; then
            _add_result "sync" "$_WARN" "/root/.claude/${target} is a directory, not a symlink"
            link_fail=$((link_fail + 1))
        else
            _add_result "sync" "$_WARN" "/root/.claude/${target} missing"
            link_fail=$((link_fail + 1))
        fi
    done

    if [[ $link_fail -eq 0 ]] && [[ $link_ok -gt 0 ]]; then
        _add_result "sync" "$_OK" "all ${link_ok} symlinks correct"
    fi
}

# Version resolver for doctor (avoids sourcing init.sh dependency)
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
            ;;
        artifacts) _check_artifacts "$path" ;;
        drift)     _check_drift "$path" ;;
        memory)    _check_memory "$path" ;;
        plan)      _check_plan "$path" ;;
        github)    _check_github "$path" ;;
        sync)      _check_sync "$path" ;;
        *)         rdf_die "unknown scope: $scope — valid: artifacts, drift, memory, plan, github, sync" ;;
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
