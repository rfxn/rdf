#!/bin/bash
# PostToolUse hook: advisory auto-lint after Edit/Write on shell files.
# Runs bash -n only (<0.1s). Always exits 0 (PostToolUse cannot block).
# Input: JSON on stdin with tool_input.file_path field.

set -euo pipefail

# Read tool event from stdin
input=$(cat)

# Extract file path from the JSON — try tool_input.file_path first,
# then fall back to tool_input.path
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

# If no file path extracted, exit silently
if [[ -z "${file_path:-}" ]]; then
    exit 0
fi

# Resolve to absolute path if relative
if [[ "$file_path" != /* ]]; then
    file_path="$(pwd)/$file_path"
fi

# Check if file exists
if [[ ! -f "$file_path" ]]; then
    exit 0
fi

# Determine if this is a shell file worth linting.
# Check explicit .sh extension first (fast path).
is_shell=false

case "$file_path" in
    *.sh|*.bash)
        is_shell=true
        ;;
    *.bats)
        # BATS test files — skip, they have special syntax
        exit 0
        ;;
    *.md|*.txt|*.json|*.yml|*.yaml|*.xml|*.html|*.css|*.js|*.py|*.conf|*.cfg)
        # Known non-shell extensions — skip
        exit 0
        ;;
    *)
        # No extension or unknown — check for bash shebang
        if head -1 "$file_path" 2>/dev/null | grep -qE '^#!\s*(/usr)?/bin/(env\s+)?bash'; then
            is_shell=true
        fi
        # Also check known rfxn shell files without extensions
        basename=$(basename "$file_path")
        case "$basename" in
            apf|bfd|maldet|internals.conf|conf.*|*.def)
                is_shell=true
                ;;
        esac
        ;;
esac

if [[ "$is_shell" != "true" ]]; then
    exit 0
fi

# Run bash -n (syntax check only — very fast)
if ! bash -n "$file_path" 2>/tmp/post-edit-lint-err.tmp; then
    echo ""
    echo "LINT WARNING: bash -n syntax error in $(basename "$file_path"):"
    cat /tmp/post-edit-lint-err.tmp
    echo ""
    rm -f /tmp/post-edit-lint-err.tmp
    exit 0
fi

rm -f /tmp/post-edit-lint-err.tmp

# Success — no output (keep it quiet on success)
exit 0
