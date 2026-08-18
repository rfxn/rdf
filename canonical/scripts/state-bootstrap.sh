#!/usr/bin/env bash
# canonical/scripts/state-bootstrap.sh — SessionStart hook: deliver
# ~/.rdf/state helpers on plugin installs. Checkout deploys symlink helpers
# via rdf deploy and are detected + skipped. Copies only when the plugin
# VERSION differs from the last bootstrap stamp. Startup must never fail.

set -euo pipefail
trap 'exit 0' EXIT   # SessionStart errors must not disrupt startup — force exit 0 on any failure

root="${0%/adapters/*}"
[[ -d "${root}/state" && -f "${root}/VERSION" ]] || exit 0

state_dst="${HOME:-/tmp}/.rdf/state"

# A symlinked helper means a checkout deploy owns this dir — never overwrite.
[[ -L "${state_dst}/rdf-bus.sh" ]] && exit 0

version="$(command cat "${root}/VERSION")"
if [[ -f "${state_dst}/.rdf-version" ]] \
    && [[ "$(command cat "${state_dst}/.rdf-version")" == "$version" ]]; then
    exit 0
fi

command mkdir -p "${state_dst}/git-hooks"
for src in "${root}/state/"*.sh; do
    [[ -f "$src" ]] || continue
    dst="${state_dst}/$(command basename "$src")"
    [[ -L "$dst" ]] && continue   # never replace a checkout symlink
    command cp "$src" "$dst"
    command chmod +x "$dst"
done
if [[ -f "${root}/state/git-hooks/pre-commit" && ! -L "${state_dst}/git-hooks/pre-commit" ]]; then
    command cp "${root}/state/git-hooks/pre-commit" "${state_dst}/git-hooks/pre-commit"
    command chmod +x "${state_dst}/git-hooks/pre-commit"
fi
printf '%s\n' "$version" > "${state_dst}/.rdf-version"
printf '%s\n' "$root" > "${state_dst}/.rdf-source"
exit 0
