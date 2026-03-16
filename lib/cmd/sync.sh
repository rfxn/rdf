#!/usr/bin/env bash
# lib/cmd/sync.sh — rdf sync subcommand (reverse flow)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by bin/rdf — do not execute directly

_sync_usage() {
    cat <<'USAGE'
Usage: rdf sync [options]

Pull changes from /root/.claude/ back to canonical sources.
Strips CC-specific YAML frontmatter from agent files.

Use this after making emergency edits to deployed files.

Options:
  --dry-run    Show what would change without writing
  --target     Adapter to sync from (default: claude-code)

Examples:
  rdf sync
  rdf sync --dry-run
USAGE
}

# Strip YAML frontmatter from a file, output body to stdout
# Frontmatter: starts and ends with "---" on its own line
_strip_frontmatter() {
    local file="$1"
    local frontmatter_count=0

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            frontmatter_count=$((frontmatter_count + 1))
            if [[ $frontmatter_count -le 2 ]]; then
                continue
            fi
        fi

        if [[ $frontmatter_count -ge 2 ]]; then
            echo "$line"
        fi
    done < "$file"
}

cmd_sync() {
    local dry_run=0
    local target="claude-code"
    local changed=0
    local unchanged=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            --target)  target="$2"; shift 2 ;;
            help|--help|-h) _sync_usage; return 0 ;;
            *) rdf_die "unknown option: $1" ;;
        esac
    done

    local output_dir="${RDF_ADAPTERS}/${target}/output"
    rdf_require_dir "$output_dir" "adapter output"

    rdf_log "syncing from ${target} adapter output to canonical..."

    # Sync agents — strip frontmatter
    if [[ -d "${output_dir}/agents" ]]; then
        for out_file in "${output_dir}/agents"/*.md; do
            [[ -f "$out_file" ]] || continue
            local basename_f
            basename_f="$(basename "$out_file")"
            local canon_file="${RDF_CANONICAL}/agents/${basename_f}"
            local body
            body="$(_strip_frontmatter "$out_file")"

            # Trim leading blank lines from body
            body="$(echo "$body" | sed '/./,$!d')"

            if [[ -f "$canon_file" ]]; then
                local current
                current="$(< "$canon_file")"
                if [[ "$body" == "$current" ]]; then
                    unchanged=$((unchanged + 1))
                    continue
                fi
            fi

            if [[ $dry_run -eq 1 ]]; then
                rdf_log "WOULD UPDATE: canonical/agents/${basename_f}"
            else
                echo "$body" > "$canon_file"
                rdf_log "updated: canonical/agents/${basename_f}"
            fi
            changed=$((changed + 1))
        done
    fi

    # Sync commands — direct copy (no frontmatter)
    if [[ -d "${output_dir}/commands" ]]; then
        for out_file in "${output_dir}/commands"/*.md; do
            [[ -f "$out_file" ]] || continue
            local basename_f
            basename_f="$(basename "$out_file")"
            local canon_file="${RDF_CANONICAL}/commands/${basename_f}"

            if [[ -f "$canon_file" ]] && diff -q "$out_file" "$canon_file" >/dev/null 2>&1; then
                unchanged=$((unchanged + 1))
                continue
            fi

            if [[ $dry_run -eq 1 ]]; then
                rdf_log "WOULD UPDATE: canonical/commands/${basename_f}"
            else
                command cp "$out_file" "$canon_file"
                rdf_log "updated: canonical/commands/${basename_f}"
            fi
            changed=$((changed + 1))
        done
    fi

    # Sync scripts — direct copy
    if [[ -d "${output_dir}/scripts" ]]; then
        for out_file in "${output_dir}/scripts"/*.sh; do
            [[ -f "$out_file" ]] || continue
            local basename_f
            basename_f="$(basename "$out_file")"
            local canon_file="${RDF_CANONICAL}/scripts/${basename_f}"

            if [[ -f "$canon_file" ]] && diff -q "$out_file" "$canon_file" >/dev/null 2>&1; then
                unchanged=$((unchanged + 1))
                continue
            fi

            if [[ $dry_run -eq 1 ]]; then
                rdf_log "WOULD UPDATE: canonical/scripts/${basename_f}"
            else
                command cp "$out_file" "$canon_file"
                rdf_log "updated: canonical/scripts/${basename_f}"
            fi
            changed=$((changed + 1))
        done
    fi

    local verb="updated"
    [[ $dry_run -eq 1 ]] && verb="would update"
    rdf_log "sync complete: ${changed} ${verb}, ${unchanged} unchanged"
}
