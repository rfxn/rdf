#!/usr/bin/env bash
# sync.sh — Pull live ~/.claude/ customizations back into the workforce repo
# Usage: ./sync.sh [--dry-run] [--diff]
#
# Copies commands/, agents/, scripts/, and settings.json from ~/.claude/
# back into the repo's claude/ directory. Run this before committing to
# capture any changes made directly to ~/.claude/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}/claude"
SOURCE_DIR="${HOME}/.claude"

DRY_RUN=0
DIFF_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --diff)    DIFF_ONLY=1 ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--diff]"
            echo "  --dry-run  Show what would be synced without making changes"
            echo "  --diff     Show diff between installed and repo files"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: ~/.claude/ not found" >&2
    exit 1
fi

# Diff mode — just show differences (delegates to install.sh --diff)
if [[ "$DIFF_ONLY" -eq 1 ]]; then
    exec "${SCRIPT_DIR}/install.sh" --diff
fi

# Sync mode — copy from ~/.claude/ to repo
synced=0
for dir in commands agents scripts; do
    src="${SOURCE_DIR}/${dir}"
    dst="${TARGET_DIR}/${dir}"
    if [[ -d "$src" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "mkdir -p ${dst}"
        else
            mkdir -p "$dst"
        fi
        for file in "${src}"/*; do
            [[ -f "$file" ]] || continue
            base="$(basename "$file")"
            # Only sync .md files from commands/agents, .sh from scripts
            case "$dir" in
                commands|agents) [[ "$base" == *.md ]] || continue ;;
                scripts)         [[ "$base" == *.sh ]] || continue ;;
            esac
            if [[ "$DRY_RUN" -eq 1 ]]; then
                echo "sync ${dir}/${base}"
            else
                cp "$file" "${dst}/${base}"
            fi
            synced=$((synced + 1))
        done
    fi
done

echo "Synced ${synced} files from ${SOURCE_DIR}/ to ${TARGET_DIR}/"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "(dry run — no files were modified)"
fi
