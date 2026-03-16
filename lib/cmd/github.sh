#!/usr/bin/env bash
# lib/cmd/github.sh — rdf github subcommand
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_github_usage() {
    cat <<'USAGE'
Usage: rdf github <subcommand> [options]

GitHub Issues + Projects integration.

Subcommands:
  setup [--repo owner/repo]          Create labels + repo project
  sync-labels [--org org]            Sync label taxonomy across repos
  ecosystem-init [--org org]         Create org-level ecosystem project
  ecosystem-add <owner/repo>         Add repo to ecosystem project

Examples:
  rdf github setup --repo rfxn/rdf
  rdf github sync-labels --org rfxn
  rdf github ecosystem-init --org rfxn
  rdf github ecosystem-add rfxn/apf
USAGE
}

# Label taxonomy from spec section 5.1
# Format: "name;color;description"
_LABEL_TAXONOMY=(
    "type:phase;5319E7;Phase tracking issue"
    "type:task;0075CA;Concrete pullable work unit"
    "type:bug;D73A4A;Defect"
    "type:enhancement;A2EEEF;Feature or improvement"
    "type:audit-finding;E4E669;Promoted from audit pipeline"
    "type:docs;0E8A16;Documentation only"
    "type:debt;FBCA04;Tech debt / modernization"
    "domain:core;C5DEF5;Framework core"
    "domain:sys;BFD4F2;Systems engineering"
    "domain:sec;F9D0C4;Security"
    "domain:fe;D4C5F9;Frontend"
    "domain:infra;FEF2C0;CI build infrastructure"
    "domain:cross-project;E6E6E6;Spans multiple repos"
    "P1:critical;B60205;Blocking / critical path"
    "P2:important;FF9F1C;Important not blocking"
    "P3:backlog;BFDADC;Nice to have / deferred"
    "blocked;000000;Waiting on dependency"
    "needs-design;D876E3;Requires spec before work"
    "needs-qa;FBCA04;Ready for QA review"
    "release-gate;B60205;Must resolve before release"
)

# Project v2 custom fields for repo-level Development Project
# Format: "name;type;options" (options = comma-separated for SINGLE_SELECT)
_PROJECT_FIELDS=(
    "Status;SINGLE_SELECT;Backlog,Ready,In Progress,In Review,Done"
    "Phase;SINGLE_SELECT;Phase 1,Phase 2,Phase 3,Phase 4,Phase 5,Phase 6,Phase 7,Phase 8"
    "Effort;SINGLE_SELECT;XS,S,M,L,XL"
    "Assignee Role;SINGLE_SELECT;mgr,sys-eng,sys-qa,sys-uat,sec-eng,fe-qa"
)

# Create or update labels on a repo
_github_create_labels() {
    local repo="$1"
    rdf_log "syncing labels on ${repo}..."

    for entry in "${_LABEL_TAXONOMY[@]}"; do
        IFS=';' read -r name color desc <<< "$entry"
        if gh label create "$name" --repo "$repo" --color "$color" --description "$desc" 2>/dev/null; then
            rdf_log "  created: ${name}"
        else
            # Label exists — update it (edit may fail if identical, safe to ignore)
            gh label edit "$name" --repo "$repo" --color "$color" --description "$desc" 2>/dev/null || true
            rdf_log "  exists: ${name}"
        fi
    done
}

# Create repo-level Development Project with custom fields
_github_create_project() {
    local repo="$1"
    local owner="${repo%%/*}"
    local repo_name="${repo##*/}"
    local title="${repo_name} Development"

    rdf_log "creating project: ${title}..."

    # Check if project already exists
    local existing
    existing="$(gh project list --owner "$owner" --format json 2>/dev/null | jq -r ".projects[] | select(.title == \"${title}\") | .number" || echo "")"

    local project_number
    if [[ -n "$existing" ]]; then
        rdf_log "  project already exists: #${existing}"
        project_number="$existing"
    else
        project_number="$(gh project create --title "$title" --owner "$owner" --format json 2>/dev/null | jq -r '.number')"
        rdf_log "  created project #${project_number}"
    fi

    # Create custom fields
    for entry in "${_PROJECT_FIELDS[@]}"; do
        IFS=';' read -r name type options <<< "$entry"
        local opts_json=""
        if [[ "$type" == "SINGLE_SELECT" ]]; then
            opts_json="$(echo "$options" | tr ',' '\n' | jq -R . | jq -sc 'map({name: .})')"
            gh project field-create "$project_number" --owner "$owner" \
                --name "$name" --data-type "SINGLE_SELECT" \
                --single-select-options "$opts_json" 2>/dev/null || \
                rdf_log "  field exists or error: ${name}"
        else
            gh project field-create "$project_number" --owner "$owner" \
                --name "$name" --data-type "$type" 2>/dev/null || \
                rdf_log "  field exists or error: ${name}"
        fi
    done

    rdf_log "project setup complete for ${repo}"
    rdf_log "NOTE: Board views must be created manually in GitHub web UI"
    rdf_log "  Required views: Kanban (default), Phase Board, Active Work, Roadmap, Backlog"
}

# Subcommand: setup
_github_setup() {
    local repo=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            *) rdf_die "unknown option: $1" ;;
        esac
    done

    if [[ -z "$repo" ]]; then
        # Try to detect from git remote
        repo="$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||' || echo "")"
        [[ -z "$repo" ]] && rdf_die "cannot detect repo — use --repo owner/name"
    fi

    rdf_require_bin gh
    _github_create_labels "$repo"
    _github_create_project "$repo"
}

# Subcommand: sync-labels
_github_sync_labels() {
    local org="rfxn"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --org) org="$2"; shift 2 ;;
            *) rdf_die "unknown option: $1" ;;
        esac
    done

    rdf_require_bin gh

    # Get all repos in org
    local repos
    repos="$(gh repo list "$org" --json name --jq '.[].name' 2>/dev/null)"
    if [[ -z "$repos" ]]; then
        rdf_die "no repos found for org: $org"
    fi

    while IFS= read -r repo_name; do
        _github_create_labels "${org}/${repo_name}"
    done <<< "$repos"

    rdf_log "label sync complete across ${org} repos"
}

# Subcommand: ecosystem-init
_github_ecosystem_init() {
    local org="rfxn"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --org) org="$2"; shift 2 ;;
            *) rdf_die "unknown option: $1" ;;
        esac
    done

    rdf_require_bin gh

    local title="rfxn Ecosystem"
    local existing
    existing="$(gh project list --owner "$org" --format json 2>/dev/null | jq -r ".projects[] | select(.title == \"${title}\") | .number" || echo "")"

    if [[ -n "$existing" ]]; then
        rdf_log "ecosystem project already exists: #${existing}"
        return 0
    fi

    local project_number
    project_number="$(gh project create --title "$title" --owner "$org" --format json 2>/dev/null | jq -r '.number')"
    rdf_log "created ecosystem project #${project_number}"

    # Ecosystem-specific fields
    local eco_fields=(
        "Status;SINGLE_SELECT;Backlog,Ready,In Progress,In Review,Done"
        "Project;SINGLE_SELECT;RDF,APF,BFD,LMD,Sigforge,Libraries"
        "Priority;SINGLE_SELECT;P1,P2,P3"
        "Effort;SINGLE_SELECT;XS,S,M,L,XL"
    )

    for entry in "${eco_fields[@]}"; do
        IFS=';' read -r name type options <<< "$entry"
        local opts_json
        opts_json="$(echo "$options" | tr ',' '\n' | jq -R . | jq -sc 'map({name: .})')"
        gh project field-create "$project_number" --owner "$org" \
            --name "$name" --data-type "SINGLE_SELECT" \
            --single-select-options "$opts_json" 2>/dev/null || \
            rdf_log "  field exists or error: ${name}"
    done

    rdf_log "ecosystem project setup complete"
}

# Subcommand: ecosystem-add
_github_ecosystem_add() {
    local repo="${1:-}"
    [[ -z "$repo" ]] && rdf_die "usage: rdf github ecosystem-add <owner/repo>"

    local org="${repo%%/*}"
    rdf_require_bin gh

    local title="rfxn Ecosystem"
    local project_number
    project_number="$(gh project list --owner "$org" --format json 2>/dev/null | jq -r ".projects[] | select(.title == \"${title}\") | .number" || echo "")"

    [[ -z "$project_number" ]] && rdf_die "ecosystem project not found — run 'rdf github ecosystem-init' first"

    # Add all open issues from repo to ecosystem project
    local issues
    issues="$(gh issue list --repo "$repo" --state open --json url --jq '.[].url' 2>/dev/null)"

    local count=0
    while IFS= read -r issue_url; do
        [[ -z "$issue_url" ]] && continue
        gh project item-add "$project_number" --owner "$org" --url "$issue_url" 2>/dev/null || true
        count=$((count + 1))
    done <<< "$issues"

    rdf_log "added ${count} issues from ${repo} to ecosystem project"
}

cmd_github() {
    case "${1:-}" in
        setup)          shift; _github_setup "$@" ;;
        sync-labels)    shift; _github_sync_labels "$@" ;;
        ecosystem-init) shift; _github_ecosystem_init "$@" ;;
        ecosystem-add)  shift; _github_ecosystem_add "$@" ;;
        help|--help|-h) _github_usage ;;
        "")             rdf_die "missing subcommand — run 'rdf github help'" ;;
        *)              rdf_die "unknown subcommand: $1 — run 'rdf github help'" ;;
    esac
}
