#!/usr/bin/env bats
# tests/doc-truth.bats — BATS tests for rdf doctor --scope doc-truth
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
#
# Hermetic: fixture project trees under mktemp; sources doctor.sh check
# helpers directly. Harness pattern mirrors tests/doctor.bats.
#
# shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016,SC2088

RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export RDF_SRC

# Usage: _run_doc_truth <fn-name> <project_root> [extra-args...] — prints _RESULTS rows
_run_doc_truth() {
    local fn="$1"
    shift
    bash -c '
        set -euo pipefail
        rdf_src="$1"
        fn="$2"
        shift 2
        RDF_HOME="$(mktemp -d)"
        RDF_LIBDIR="${rdf_src}/lib"
        RDF_VERSION="0.0.0-test"
        source "${rdf_src}/lib/rdf_common.sh"
        rdf_init
        source "${rdf_src}/lib/cmd/doctor.sh"
        _reset_results
        "$fn" "$@"
        if [ "${#_RESULTS[@]}" -gt 0 ]; then
            printf "%s\n" "${_RESULTS[@]}"
        fi
    ' -- "$RDF_SRC" "$fn" "$@"
}

@test "doc-truth FAILs when README badge profile count drifts" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/profiles/core" "$fix/profiles/shell"
    touch "$fix/profiles/core/governance-template.md" "$fix/profiles/shell/governance-template.md"
    printf '{"profiles":{"core":{},"shell":{}}}\n' > "$fix/profiles/registry.json"
    printf '![Profiles](https://img.shields.io/badge/profiles-5-orange.svg)\n' > "$fix/README.md"
    run _run_doc_truth _doc_truth_profiles "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|README.md: profiles badge claims 5, actual 2"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when a profile dir is missing from registry.json" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/profiles/core" "$fix/profiles/extra"
    touch "$fix/profiles/core/governance-template.md" "$fix/profiles/extra/governance-template.md"
    printf '{"profiles":{"core":{}}}\n' > "$fix/profiles/registry.json"
    run _run_doc_truth _doc_truth_profiles "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|profiles/extra/: has governance-template.md but is not registered in registry.json"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when README badge adapter count drifts" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/adapters/foo" "$fix/adapters/bar"
    touch "$fix/adapters/foo/adapter.sh" "$fix/adapters/bar/adapter.sh"
    printf '![Adapters](https://img.shields.io/badge/adapters-5-purple.svg)\n' > "$fix/README.md"
    run _run_doc_truth _doc_truth_adapters "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|README.md: adapters badge claims 5, actual 2"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when a tests/*.bats file is missing from the Makefile" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/tests"
    touch "$fix/tests/a.bats" "$fix/tests/b.bats"
    printf 'test:\n\tbats tests/a.bats\n' > "$fix/tests/Makefile"
    run _run_doc_truth _doc_truth_tests "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|tests/Makefile: b.bats not wired into the test/lint targets"* ]]
    [[ "$output" != *"a.bats not wired"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when WORKFORCE claims a dispatch the command body lacks" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical/commands" "$fix/canonical/agents"
    printf 'You are the foo command. It does not dispatch anyone.\n' > "$fix/canonical/commands/r-foo.md"
    printf -- '### Lifecycle Commands (1)\n\n| Command | Slash | Dispatches | Purpose |\n|---------|-------|------------|---------|\n| r-foo | /r-foo | qa | Does a thing |\n\n### Utility Commands (0)\n' > "$fix/WORKFORCE.md"
    run _run_doc_truth _doc_truth_dispatch "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|WORKFORCE.md: r-foo claims dispatch of 'qa' but canonical/commands/r-foo.md never dispatches it"* ]]
    rm -rf "$fix"
}

@test "doc-truth WARNs when a command dispatches an agent WORKFORCE omits" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical/commands" "$fix/canonical/agents"
    printf 'You are the foo command. Dispatch the `rdf-qa` subagent.\n' > "$fix/canonical/commands/r-foo.md"
    touch "$fix/canonical/agents/qa.md"
    printf -- '### Lifecycle Commands (1)\n\n| Command | Slash | Dispatches | Purpose |\n|---------|-------|------------|---------|\n| r-foo | /r-foo | -- | Does a thing |\n\n### Utility Commands (0)\n' > "$fix/WORKFORCE.md"
    run _run_doc_truth _doc_truth_dispatch "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|WARN|canonical/commands/r-foo.md: dispatches qa but WORKFORCE.md row for r-foo omits it"* ]]
    [[ "$output" != *"|FAIL|"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when CONTRIBUTING claims a CI step ci.yml lacks" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/.github/workflows"
    printf 'CI (`.github/workflows/ci.yml`) runs:\n- `make -C tests test`\n- `rdf doctor --scope missing-step`\n' > "$fix/CONTRIBUTING.md"
    printf 'jobs:\n  tests:\n    steps:\n      - run: make -C tests test\n' > "$fix/.github/workflows/ci.yml"
    run _run_doc_truth _doc_truth_ci "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|CONTRIBUTING.md: CI claim 'rdf doctor --scope missing-step' not found in .github/workflows/ci.yml"* ]]
    [[ "$output" != *"'make -C tests test' not found"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when RDF.md cites a path that does not exist on disk" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/adapters/claude-code"
    touch "$fix/adapters/claude-code/adapter.sh"
    cat > "$fix/RDF.md" <<'RDFMD'
## Target Directory Structure

```
rdf/
|-- adapters/
|   |-- claude-code/
|   |   |-- adapter.sh               # real file
|   |   +-- ghost-meta.json          # deleted long ago
|   +-- gemini-cli/
```
RDFMD
    run _run_doc_truth _doc_truth_scan_tree "$fix" RDF.md 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|RDF.md: tree cites 'adapters/claude-code/ghost-meta.json' — no such file"* ]]
    [[ "$output" == *"doc-truth|FAIL|RDF.md: tree cites 'adapters/gemini-cli/' — no such directory"* ]]
    [[ "$output" != *"'adapters/claude-code/adapter.sh'"* ]]
    rm -rf "$fix"
}

@test "doc-truth: context-bar.md lives under docs/ and is linked from README" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/docs"
    printf '# context-bar.sh\n' > "$fix/docs/context-bar.md"
    printf '| **[docs/context-bar.md](docs/context-bar.md)** | Status line reference |\n' > "$fix/README.md"
    run _run_doc_truth _doc_truth_context_bar "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|OK|docs/context-bar.md present and linked from README.md"* ]]
    [[ "$output" != *"|FAIL|"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when context-bar.md is still at the repo root" {
    fix="$(mktemp -d)"
    printf '# context-bar.sh\n' > "$fix/context-bar.md"
    run _run_doc_truth _doc_truth_context_bar "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|context-bar.md still present at repo root — relocate to docs/context-bar.md"* ]]
    rm -rf "$fix"
}

@test "doc-truth passes on the live repo (no FAIL and no WARN rows)" {
    run _run_doc_truth _check_doc_truth "$RDF_SRC"
    [ "$status" -eq 0 ]
    [[ "$output" != *"|FAIL|"* ]]
    [[ "$output" != *"|WARN|"* ]]
    [[ "$output" == *"doc-truth|OK|README.md: profiles badge = "* ]]
    [[ "$output" == *"doc-truth|OK|README.md: adapters badge = "* ]]
    [[ "$output" == *"doc-truth|OK|RDF.md: "*" tree-cited paths exist on disk"* ]]
    [[ "$output" == *"doc-truth|OK|README.md: "*" tree-cited paths exist on disk"* ]]
    [[ "$output" == *"doc-truth|OK|CONTRIBUTING.md:"*"CI claims match .github/workflows/ci.yml"* ]]
}

@test "doc-truth is a no-op for projects without canonical/" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/profiles"
    printf '{"profiles":{}}\n' > "$fix/profiles/registry.json"
    run _run_doc_truth _check_doc_truth "$fix"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    rm -rf "$fix"
}

@test "doc-truth FAILs when a tree cites a glob instead of a concrete path" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical/commands"
    touch "$fix/canonical/commands/r-util-code-map.md"
    cat > "$fix/RDF.md" <<'RDFMD'
```
rdf/
|-- canonical/
|   |-- commands/
|   |   |-- r-util-*.md              # 16 utility commands
```
RDFMD
    run _run_doc_truth _doc_truth_scan_tree "$fix" RDF.md 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|RDF.md: canonical/ tree cites glob 'r-util-*.md' — cite a concrete path"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when a cited file exists only under a different parent" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/adapters/claude-code" "$fix/adapters/agents-md"
    touch "$fix/adapters/claude-code/adapter.sh" "$fix/adapters/agents-md/agent-meta.json"
    cat > "$fix/RDF.md" <<'RDFMD'
```
rdf/
|-- adapters/
|   |-- claude-code/
|   |   |-- adapter.sh
|   |   +-- agent-meta.json
```
RDFMD
    run _run_doc_truth _doc_truth_scan_tree "$fix" RDF.md 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|RDF.md: tree cites 'adapters/claude-code/agent-meta.json' — no such file"* ]]
    rm -rf "$fix"
}

@test "doc-truth checks README.md's directory tree the same way as RDF.md's" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/lib/cmd"
    touch "$fix/lib/rdf_common.sh"
    cat > "$fix/README.md" <<'READMEMD'
### Directory Structure

```
rdf/
|-- lib/
|   |-- rdf_common.sh                  # Shared helpers
|   |-- ghost.sh                       # deleted long ago
|   +-- cmd/                           # Subcommands
```
READMEMD
    run _run_doc_truth _doc_truth_scan_tree "$fix" README.md 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|README.md: tree cites 'lib/ghost.sh' — no such file"* ]]
    [[ "$output" != *"'lib/rdf_common.sh'"* ]]
    [[ "$output" != *"'lib/cmd/'"* ]]
    rm -rf "$fix"
}

@test "doc-truth tree scan is deterministic when many paths share a basename" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/adapters/claude-code"
    touch "$fix/adapters/claude-code/adapter.sh"
    i=1
    while [ "$i" -le 100 ]; do
        mkdir -p "$fix/adapters/noise-${i}"
        touch "$fix/adapters/noise-${i}/adapter.sh"
        i=$((i + 1))
    done
    cat > "$fix/RDF.md" <<'RDFMD'
```
rdf/
|-- adapters/
|   |-- claude-code/
|   |   +-- adapter.sh
```
RDFMD
    runs=0
    bad=0
    while [ "$runs" -lt 20 ]; do
        out="$(_run_doc_truth _doc_truth_scan_tree "$fix" RDF.md 1)"
        if [[ "$out" == *"|FAIL|"* ]]; then
            bad=$((bad + 1))
        fi
        if [[ "$out" != *"doc-truth|OK|RDF.md: 2 tree-cited paths exist on disk"* ]]; then
            bad=$((bad + 1))
        fi
        runs=$((runs + 1))
    done
    [ "$bad" -eq 0 ]
    rm -rf "$fix"
}

@test "doc-truth FAILs when the RDF.md profile tree drifts from registry.json" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical" "$fix/profiles/core" "$fix/profiles/shell" "$fix/profiles/python"
    touch "$fix/profiles/core/governance-template.md" "$fix/profiles/shell/governance-template.md" \
          "$fix/profiles/python/governance-template.md"
    printf '{"profiles":{"core":{},"shell":{},"python":{}}}\n' > "$fix/profiles/registry.json"
    cat > "$fix/RDF.md" <<'RDFMD'
```
rdf/
|-- profiles/
|   |-- core/
|   +-- shell/
```
RDFMD
    run _run_doc_truth _check_doc_truth "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|RDF.md: profile tree entries claims 2, actual 3"* ]]
    rm -rf "$fix"
}

@test "doc-truth FAILs when the RDF.md adapter tree drifts from adapters/" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical" "$fix/adapters/claude-code" "$fix/adapters/gemini-cli" "$fix/adapters/legacy"
    touch "$fix/adapters/claude-code/adapter.sh" "$fix/adapters/gemini-cli/adapter.sh"
    cat > "$fix/RDF.md" <<'RDFMD'
```
rdf/
|-- adapters/
|   |-- claude-code/
|   |-- gemini-cli/
|   +-- legacy/
```
RDFMD
    run _run_doc_truth _check_doc_truth "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|RDF.md: adapter tree entries claims 3, actual 2"* ]]
    rm -rf "$fix"
}

@test "doc-truth dispatch claim needs a dispatch verb, not incidental prose" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical/commands" "$fix/canonical/agents"
    touch "$fix/canonical/agents/reviewer.md"
    printf 'You are the mode command.\n\nNote: the reviewer agent uses the mode banner.\n' > "$fix/canonical/commands/r-mode.md"
    printf -- '### Lifecycle Commands (1)\n\n| Command | Slash | Dispatches | Purpose |\n|---------|-------|------------|---------|\n| r-mode | /r-mode | reviewer | Switch operational mode |\n\n### Utility Commands (0)\n' > "$fix/WORKFORCE.md"
    run _run_doc_truth _doc_truth_dispatch "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doc-truth|FAIL|WORKFORCE.md: r-mode claims dispatch of 'reviewer' but canonical/commands/r-mode.md never dispatches it"* ]]
    [[ "$output" != *"|WARN|"* ]]
    rm -rf "$fix"
}

@test "doc-truth accepts a dispatch-verb phrase without an rdf- prefix" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical/commands" "$fix/canonical/agents"
    touch "$fix/canonical/agents/reviewer.md"
    printf 'You are the mode command.\n\nDispatch the reviewer agent in challenge mode.\n' > "$fix/canonical/commands/r-mode.md"
    printf -- '### Lifecycle Commands (1)\n\n| Command | Slash | Dispatches | Purpose |\n|---------|-------|------------|---------|\n| r-mode | /r-mode | reviewer | Switch operational mode |\n\n### Utility Commands (0)\n' > "$fix/WORKFORCE.md"
    run _run_doc_truth _doc_truth_dispatch "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" != *"|FAIL|"* ]]
    [[ "$output" == *"doc-truth|OK|WORKFORCE.md: 1 lifecycle dispatch claims checked"* ]]
    rm -rf "$fix"
}

@test "doc-truth under-claim scan ignores fenced and indented code blocks" {
    fix="$(mktemp -d)"
    mkdir -p "$fix/canonical/commands" "$fix/canonical/agents"
    touch "$fix/canonical/agents/qa.md" "$fix/canonical/agents/engineer.md" "$fix/canonical/agents/uat.md"
    cat > "$fix/canonical/commands/r-foo.md" <<'FOOMD'
You are the foo command. Dispatch the `rdf-qa` subagent.

Agent files carry frontmatter:

    name: rdf-engineer
    model: opus

```
Dispatch the uat subagent   # illustrative transcript, not a dispatch
```
FOOMD
    printf -- '### Lifecycle Commands (1)\n\n| Command | Slash | Dispatches | Purpose |\n|---------|-------|------------|---------|\n| r-foo | /r-foo | qa | Does a thing |\n\n### Utility Commands (0)\n' > "$fix/WORKFORCE.md"
    run _run_doc_truth _doc_truth_dispatch "$fix"
    [ "$status" -eq 0 ]
    [[ "$output" != *"|WARN|"* ]]
    [[ "$output" != *"|FAIL|"* ]]
    rm -rf "$fix"
}
