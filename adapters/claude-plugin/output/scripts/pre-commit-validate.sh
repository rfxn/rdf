#!/usr/bin/env bash
# Pre-commit validation hook for Claude Code
# Intercepts git commit commands and validates staged shell files
# Exit 0 = allow, Exit 2 = block (with reason on stderr)

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only validate git commit commands
if ! echo "$COMMAND" | grep -qE '^\s*git commit'; then
    exit 0
fi

# Skip amend-only commits (no new files to validate)
if echo "$COMMAND" | grep -qE -- '--amend\b.*--no-edit'; then
    exit 0
fi

errors=0
warnings=0

# Get staged files
staged=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
if [ -z "$staged" ]; then
    exit 0  # Nothing staged
fi

# Identify shell files from staged list
shell_files=""
while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue
    case "$file" in
        *.sh|*.bash)
            shell_files="$shell_files $file"
            ;;
        *)
            # Check shebang for extensionless files
            if head -1 "$file" 2>/dev/null | grep -qE '^#!.*(bash|sh)'; then
                shell_files="$shell_files $file"
            fi
            ;;
    esac
done <<< "$staged"

# Also check known shell files by path pattern
while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue
    case "$file" in
        files/maldet|files/internals/functions|files/internals/internals.conf)
            # Already matched or add to list
            if ! echo "$shell_files" | grep -qF "$file"; then
                shell_files="$shell_files $file"
            fi
            ;;
        install.sh|cron.daily|files/hookscan.sh|files/service/maldet.sh)
            if ! echo "$shell_files" | grep -qF "$file"; then
                shell_files="$shell_files $file"
            fi
            ;;
    esac
done <<< "$staged"

if [ -z "$shell_files" ]; then
    # No shell files staged — check CHANGELOG requirement only
    code_changed=false
    while IFS= read -r file; do
        case "$file" in
            CHANGELOG|CHANGELOG.RELEASE|CLAUDE.md|PLAN*.md|MEMORY.md|AUDIT.md|.claude/*)
                ;;
            *.md|*.txt)
                ;;
            *)
                code_changed=true
                ;;
        esac
    done <<< "$staged"

    if [ "$code_changed" = true ]; then
        if ! echo "$staged" | grep -qE '^CHANGELOG$'; then
            echo "WARNING: Code files changed but CHANGELOG not updated" >&2
            warnings=$((warnings + 1))
        fi
    fi

    # Warnings don't block
    exit 0
fi

# Run bash -n on each shell file
for file in $shell_files; do
    if ! bash -n "$file" 2>/tmp/cc-hook-bash-errors.txt; then
        echo "FAIL: bash -n $file" >&2
        cat /tmp/cc-hook-bash-errors.txt >&2
        errors=$((errors + 1))
    fi
done

# Run shellcheck if available
if command -v shellcheck >/dev/null 2>&1; then
    for file in $shell_files; do
        if ! shellcheck --severity=error "$file" 2>/tmp/cc-hook-sc-errors.txt; then
            echo "FAIL: shellcheck $file" >&2
            cat /tmp/cc-hook-sc-errors.txt >&2
            errors=$((errors + 1))
        fi
    done
fi

# Check anti-patterns in staged shell files
for file in $shell_files; do
    # Bare which usage
    if grep -nE '\bwhich\b' "$file" 2>/dev/null | grep -vE '^\s*#' | grep -q .; then
        echo "WARNING: bare 'which' in $file (use 'command -v')" >&2
        warnings=$((warnings + 1))
    fi
    # Backtick usage
    if grep -nE '`[^`]+`' "$file" 2>/dev/null | grep -vE '^\s*#' | grep -q .; then
        echo "WARNING: backtick usage in $file (use \$(...))" >&2
        warnings=$((warnings + 1))
    fi
done

# Check CHANGELOG updated when code files changed
code_changed=false
while IFS= read -r file; do
    case "$file" in
        CHANGELOG|CHANGELOG.RELEASE|CLAUDE.md|PLAN*.md|MEMORY.md|AUDIT.md|.claude/*|tests/*|*.md)
            ;;
        *)
            code_changed=true
            ;;
    esac
done <<< "$staged"

if [ "$code_changed" = true ]; then
    if ! echo "$staged" | grep -qE '^CHANGELOG$'; then
        echo "WARNING: Code files changed but CHANGELOG not updated" >&2
        warnings=$((warnings + 1))
    fi
fi

# Block on errors, allow on warnings
if [ "$errors" -gt 0 ]; then
    echo "Commit blocked: $errors validation error(s). Fix and retry." >&2
    exit 2
fi

if [ "$warnings" -gt 0 ]; then
    echo "Commit allowed with $warnings warning(s)" >&2
fi

exit 0
