#!/usr/bin/env bash
# lib/cmd/refresh.sh — rdf refresh subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_refresh_usage() {
    cat <<'USAGE'
Usage: rdf refresh [path] [options]

Agent-driven state file updates. Refreshes MEMORY.md, PLAN.md, and optionally
syncs GitHub issue state from current git reality.

Arguments:
  path               Project directory (default: current directory)

Options:
  --scope <scope>    Scope to refresh (default: all)
                       memory   Update MEMORY.md from git state
                       plan     Update PLAN.md phase statuses from git
                       github   Sync issue state with GitHub Issues
                       all      Run memory + plan + github
  --dry-run          Show what would change without writing
  --json             Output refresh results as JSON

Examples:
  rdf refresh
  rdf refresh /root/admin/work/proj/brute-force-detection
  rdf refresh --scope memory
  rdf refresh --scope github --dry-run
  rdf refresh --scope all
USAGE
}

# Resolve the MEMORY.md path for a given project
# Claude Code auto-memory lives under /root/.claude/projects/ with path-encoded dirs
# Args: $1 = absolute project path
# Output: absolute path to MEMORY.md (may not exist yet)
_resolve_memory_path() {
    local project_path="$1"
    echo "${project_path}/.rdf/memory/MEMORY.md"
}

# Collect git-based state summary for agent consumption
# Args: $1 = absolute project path
# Output: structured text block to stdout
_collect_git_context() {
    local project_path="$1"

    if ! git -C "$project_path" rev-parse --git-dir >/dev/null 2>&1; then
        echo "NOT_A_GIT_REPO"
        return 1
    fi

    local branch
    branch="$(git -C "$project_path" branch --show-current 2>/dev/null || echo "detached")"

    local version="unknown"
    if [[ -f "${project_path}/VERSION" ]]; then
        version="$(< "${project_path}/VERSION")"
        version="${version%%[[:space:]]}"
    elif [[ -f "${project_path}/files/$(basename "$project_path")" ]]; then
        # rfxn project pattern: version in main script file
        version="$(grep -m1 '^VERSION=' "${project_path}/files/$(basename "$project_path")" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
    fi

    local head_hash
    head_hash="$(git -C "$project_path" rev-parse --short HEAD 2>/dev/null || echo "none")"

    local dirty="clean"
    if ! git -C "$project_path" diff --quiet 2>/dev/null || \
       ! git -C "$project_path" diff --cached --quiet 2>/dev/null; then
        dirty="dirty"
    fi

    local uncommitted
    uncommitted="$(git -C "$project_path" status --porcelain 2>/dev/null | wc -l)"
    uncommitted="${uncommitted##* }"

    local recent_commits
    recent_commits="$(git -C "$project_path" log --oneline -10 2>/dev/null || echo "no commits")"

    local test_count="0"
    if [[ -d "${project_path}/tests" ]]; then
        test_count="$(grep -rc '@test' "${project_path}"/tests/*.bats 2>/dev/null | awk -F: '{s+=$2}END{print s}' || echo "0")"
    fi

    cat <<CONTEXT
PROJECT: $(basename "$project_path")
VERSION: ${version}
BRANCH: ${branch}
HEAD: ${head_hash}
DIRTY: ${dirty}
UNCOMMITTED_FILES: ${uncommitted}
TEST_COUNT: ${test_count}

RECENT_COMMITS:
${recent_commits}
CONTEXT
}

# Refresh MEMORY.md scope — agent-driven
# Collects git context, then outputs instructions for the agent
# Args: $1 = project path, $2 = dry_run (0|1)
_refresh_scope_memory() {
    local project_path="$1"
    local dry_run="${2:-0}"
    local memory_path
    memory_path="$(_resolve_memory_path "$project_path")"

    rdf_log "refresh scope: memory"
    rdf_log "project: $(basename "$project_path")"
    rdf_log "memory path: ${memory_path}"

    local git_context
    git_context="$(_collect_git_context "$project_path")" || {
        rdf_warn "not a git repo — skipping memory refresh"
        return 1
    }

    if [[ $dry_run -eq 1 ]]; then
        rdf_log "DRY RUN: would update ${memory_path}"
        rdf_log "git context collected:"
        echo "$git_context" >&2
        return 0
    fi

    # Output the context for agent consumption
    # The actual MEMORY.md update is performed by the agent dispatched via
    # the canonical /refresh command — this CLI just collects the data
    echo "$git_context"
}

# Refresh PLAN.md scope — agent-driven
# Scans git log for commit messages referencing phases, outputs update instructions
# Args: $1 = project path, $2 = dry_run (0|1)
_refresh_scope_plan() {
    local project_path="$1"
    local dry_run="${2:-0}"

    rdf_log "refresh scope: plan"

    if [[ ! -f "${project_path}/PLAN.md" ]]; then
        rdf_warn "no PLAN.md found — skipping plan refresh"
        return 0
    fi

    if ! git -C "$project_path" rev-parse --git-dir >/dev/null 2>&1; then
        rdf_warn "not a git repo — skipping plan refresh"
        return 1
    fi

    # Extract phase references from git log
    local phase_commits
    phase_commits="$(git -C "$project_path" log --oneline -50 2>/dev/null | grep -iE '(phase|p[0-9])' || true)"

    if [[ $dry_run -eq 1 ]]; then
        rdf_log "DRY RUN: would update ${project_path}/PLAN.md"
        if [[ -n "$phase_commits" ]]; then
            rdf_log "phase-referencing commits found:"
            echo "$phase_commits" >&2
        else
            rdf_log "no phase-referencing commits found"
        fi
        return 0
    fi

    # Output phase commit data for agent consumption
    if [[ -n "$phase_commits" ]]; then
        echo "PHASE_COMMITS:"
        echo "$phase_commits"
    else
        echo "PHASE_COMMITS: none"
    fi
}

# Refresh GitHub scope — deterministic, no LLM
# Syncs local plan state with GitHub Issues via gh CLI
# Args: $1 = project path, $2 = dry_run (0|1)
_refresh_scope_github() {
    local project_path="$1"
    local dry_run="${2:-0}"

    rdf_log "refresh scope: github"

    rdf_require_bin gh

    # Determine repo from git remote
    local repo_url
    repo_url="$(git -C "$project_path" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$repo_url" ]]; then
        rdf_warn "no git remote origin — skipping github refresh"
        return 1
    fi

    # Extract owner/repo from remote URL
    # Handles: git@github.com:owner/repo.git, https://github.com/owner/repo.git
    local owner_repo
    owner_repo="$(echo "$repo_url" | sed -E 's|.*github\.com[:/]||; s|\.git$||')"
    if [[ -z "$owner_repo" ]]; then
        rdf_warn "could not parse owner/repo from remote: ${repo_url}"
        return 1
    fi

    rdf_log "repo: ${owner_repo}"

    # Fetch open issues with type:phase and type:task labels
    local issues_json
    issues_json="$(gh issue list --repo "$owner_repo" --label "type:phase" --state all --json number,title,state,labels --limit 100 2>/dev/null || true)"
    local tasks_json
    tasks_json="$(gh issue list --repo "$owner_repo" --label "type:task" --state all --json number,title,state,labels --limit 200 2>/dev/null || true)"

    if [[ $dry_run -eq 1 ]]; then
        local phase_count task_count
        phase_count="$(echo "$issues_json" | jq 'length' 2>/dev/null || echo "0")"
        task_count="$(echo "$tasks_json" | jq 'length' 2>/dev/null || echo "0")"
        rdf_log "DRY RUN: found ${phase_count} phase issues, ${task_count} task issues"
        return 0
    fi

    # Cross-reference PLAN.md status with issue state
    # For each phase issue, check if the corresponding phase is marked COMPLETE in PLAN.md
    if [[ -f "${project_path}/PLAN.md" ]]; then
        local plan_content
        plan_content="$(< "${project_path}/PLAN.md")"

        # Parse phase issues and check for state mismatches
        local mismatches=0
        local synced=0

        if [[ -n "$issues_json" ]] && [[ "$issues_json" != "[]" ]]; then
            local issue_count
            issue_count="$(echo "$issues_json" | jq 'length')"
            local i=0
            while [[ $i -lt "$issue_count" ]]; do
                local issue_number issue_title issue_state
                issue_number="$(echo "$issues_json" | jq -r ".[$i].number")"
                issue_title="$(echo "$issues_json" | jq -r ".[$i].title")"
                issue_state="$(echo "$issues_json" | jq -r ".[$i].state")"

                # Extract phase number from title (e.g., "Phase 4: Title")
                local phase_num
                phase_num="$(echo "$issue_title" | grep -oE '[Pp]hase[[:space:]]+[0-9]+' | grep -oE '[0-9]+' || true)"

                if [[ -n "$phase_num" ]]; then
                    # Check PLAN.md for phase status
                    local plan_status="UNKNOWN"
                    if echo "$plan_content" | grep -qiE "phase[[:space:]]+${phase_num}.*COMPLETE|phase[[:space:]]+${phase_num}.*DONE"; then
                        plan_status="COMPLETE"
                    elif echo "$plan_content" | grep -qiE "phase[[:space:]]+${phase_num}.*IN.PROGRESS|phase[[:space:]]+${phase_num}.*ACTIVE"; then
                        plan_status="IN_PROGRESS"
                    elif echo "$plan_content" | grep -qiE "phase[[:space:]]+${phase_num}.*PENDING"; then
                        plan_status="PENDING"
                    fi

                    # Detect mismatches
                    if [[ "$plan_status" == "COMPLETE" ]] && [[ "$issue_state" == "OPEN" ]]; then
                        rdf_log "MISMATCH: Phase ${phase_num} (#${issue_number}) is COMPLETE in PLAN but OPEN on GitHub"
                        gh issue close "$issue_number" --repo "$owner_repo" --comment "Auto-closed by rdf refresh: Phase ${phase_num} marked COMPLETE in PLAN.md" 2>/dev/null || {
                            rdf_warn "failed to close issue #${issue_number}"
                        }
                        mismatches=$((mismatches + 1))
                    elif [[ "$plan_status" != "COMPLETE" ]] && [[ "$issue_state" == "CLOSED" ]]; then
                        rdf_log "MISMATCH: Phase ${phase_num} (#${issue_number}) is ${plan_status} in PLAN but CLOSED on GitHub"
                        gh issue reopen "$issue_number" --repo "$owner_repo" --comment "Auto-reopened by rdf refresh: Phase ${phase_num} is ${plan_status} in PLAN.md" 2>/dev/null || {
                            rdf_warn "failed to reopen issue #${issue_number}"
                        }
                        mismatches=$((mismatches + 1))
                    else
                        synced=$((synced + 1))
                    fi
                fi

                i=$((i + 1))
            done
        fi

        rdf_log "github sync: ${synced} in sync, ${mismatches} mismatches resolved"
    else
        rdf_log "no PLAN.md — listing issues only"
        echo "$issues_json" | jq -r '.[] | "#\(.number) [\(.state)] \(.title)"' 2>/dev/null || true
        echo "$tasks_json" | jq -r '.[] | "#\(.number) [\(.state)] \(.title)"' 2>/dev/null || true
    fi
}

cmd_refresh() {
    local project_path=""
    local scope="all"
    local dry_run=0
    local json_output=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                scope="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --json)
                json_output=1
                shift
                ;;
            help|--help|-h)
                _refresh_usage
                return 0
                ;;
            -*)
                rdf_die "unknown option: $1 — run 'rdf refresh help' for usage"
                ;;
            *)
                if [[ -z "$project_path" ]]; then
                    project_path="$1"
                else
                    rdf_die "unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    # Default to current directory
    if [[ -z "$project_path" ]]; then
        project_path="$(pwd)"
    fi

    # Resolve to absolute path
    project_path="$(cd "$project_path" && pwd)" || {
        rdf_die "invalid project path: ${project_path}"
    }

    # Validate scope
    case "$scope" in
        memory|plan|github|all) ;;
        *)
            rdf_die "unknown scope: ${scope} — valid: memory, plan, github, all"
            ;;
    esac

    rdf_log "refreshing project: $(basename "$project_path")"
    rdf_log "scope: ${scope}"

    local result_memory=0
    local result_plan=0
    local result_github=0

    # Run requested scopes
    case "$scope" in
        memory)
            _refresh_scope_memory "$project_path" "$dry_run" || result_memory=$?
            ;;
        plan)
            _refresh_scope_plan "$project_path" "$dry_run" || result_plan=$?
            ;;
        github)
            _refresh_scope_github "$project_path" "$dry_run" || result_github=$?
            ;;
        all)
            _refresh_scope_memory "$project_path" "$dry_run" || result_memory=$?
            _refresh_scope_plan "$project_path" "$dry_run" || result_plan=$?
            _refresh_scope_github "$project_path" "$dry_run" || result_github=$?
            ;;
    esac

    if [[ $json_output -eq 1 ]]; then
        local dry_str="false"
        if [[ $dry_run -eq 1 ]]; then
            dry_str="true"
        fi
        cat <<JSONEOF
{
  "project": "$(basename "$project_path")",
  "scope": "${scope}",
  "dry_run": ${dry_str},
  "results": {
    "memory": ${result_memory},
    "plan": ${result_plan},
    "github": ${result_github}
  }
}
JSONEOF
    else
        local overall=0
        if [[ $result_memory -ne 0 ]] || [[ $result_plan -ne 0 ]] || [[ $result_github -ne 0 ]]; then
            overall=1
        fi
        if [[ $overall -eq 0 ]]; then
            rdf_log "refresh complete"
        else
            rdf_warn "refresh completed with warnings"
        fi
    fi
}
