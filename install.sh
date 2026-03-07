#!/usr/bin/env bash
# install.sh — Deploy workforce Claude customizations to ~/.claude/
# Usage: ./install.sh [--dry-run] [--diff]
#
# Copies commands/, agents/, scripts/, and settings.json from claude/
# into ~/.claude/, creating directories as needed. Existing files are
# overwritten; files not present in the repo are left untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/claude"
TARGET_DIR="${HOME}/.claude"

DRY_RUN=0
DIFF_ONLY=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --diff)    DIFF_ONLY=1 ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--diff]"
            echo "  --dry-run  Show what would be copied without making changes"
            echo "  --diff     Show diff between repo and installed files"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "ERROR: Source directory not found: $SOURCE_DIR" >&2
    echo "Run this script from the workforce repo root." >&2
    exit 1
fi

# Diff mode — show what's different
if [[ "$DIFF_ONLY" -eq 1 ]]; then
    changes=0
    for dir in commands agents scripts; do
        if [[ -d "${SOURCE_DIR}/${dir}" ]]; then
            for file in "${SOURCE_DIR}/${dir}"/*; do
                [[ -f "$file" ]] || continue
                base="$(basename "$file")"
                target="${TARGET_DIR}/${dir}/${base}"
                if [[ ! -f "$target" ]]; then
                    echo "NEW: ${dir}/${base}"
                    changes=1
                elif ! diff -q "$file" "$target" >/dev/null 2>&1; then
                    echo "CHANGED: ${dir}/${base}"
                    diff -u "$target" "$file" --label "installed/${dir}/${base}" --label "repo/${dir}/${base}" || true
                    echo ""
                    changes=1
                fi
            done
        fi
    done
    # settings.json
    if [[ -f "${SOURCE_DIR}/settings.json" ]]; then
        if [[ ! -f "${TARGET_DIR}/settings.json" ]]; then
            echo "NEW: settings.json"
            changes=1
        elif ! diff -q "${SOURCE_DIR}/settings.json" "${TARGET_DIR}/settings.json" >/dev/null 2>&1; then
            echo "CHANGED: settings.json"
            diff -u "${TARGET_DIR}/settings.json" "${SOURCE_DIR}/settings.json" \
                --label "installed/settings.json" --label "repo/settings.json" || true
            changes=1
        fi
    fi
    if [[ "$changes" -eq 0 ]]; then
        echo "No differences found. Repo and installed files are in sync."
    fi
    exit 0
fi

# Install mode
copied=0
for dir in commands agents scripts; do
    if [[ -d "${SOURCE_DIR}/${dir}" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "mkdir -p ${TARGET_DIR}/${dir}"
        else
            mkdir -p "${TARGET_DIR}/${dir}"
        fi
        for file in "${SOURCE_DIR}/${dir}"/*; do
            [[ -f "$file" ]] || continue
            base="$(basename "$file")"
            if [[ "$DRY_RUN" -eq 1 ]]; then
                echo "cp ${dir}/${base} -> ${TARGET_DIR}/${dir}/${base}"
            else
                cp "$file" "${TARGET_DIR}/${dir}/${base}"
            fi
            copied=$((copied + 1))
        done
    fi
done

# settings.json
if [[ -f "${SOURCE_DIR}/settings.json" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "cp settings.json -> ${TARGET_DIR}/settings.json"
    else
        cp "${SOURCE_DIR}/settings.json" "${TARGET_DIR}/settings.json"
    fi
    copied=$((copied + 1))
fi

# Set executable on scripts
if [[ "$DRY_RUN" -eq 0 && -d "${TARGET_DIR}/scripts" ]]; then
    chmod 750 "${TARGET_DIR}/scripts"/*.sh 2>/dev/null || true
fi

echo "Deployed ${copied} files to ${TARGET_DIR}/"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "(dry run — no files were modified)"
fi
