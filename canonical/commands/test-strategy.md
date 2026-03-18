Analyze the current staged and unstaged changes to recommend which tests to
run. Read the project's CLAUDE.md for available test targets and OS matrix.

## 1. Classify the change scope

Run `git diff --name-only` and `git diff --cached --name-only` to get all
modified files. Categorize each file:

| Category | File patterns | Examples |
|----------|--------------|---------|
| DOCS | README.md, CHANGELOG*, *.md, man/*, docs/* | comment-only edits |
| CONFIG | conf.*, internals.conf, compat.conf, .ca.def | defaults, mappings |
| CORE | functions*, bfd.lib.sh, maldet, apf, firewall | logic, control flow |
| CLI | main entry point case dispatcher | arg handling, help text |
| INSTALL | install.sh, uninstall.sh, importconf, cron* | paths, permissions |
| TEST | tests/*.bats, tests/helpers/*, Makefile | test infrastructure |
| CI | .github/*, Dockerfile*, run-tests.sh | CI/Docker changes |

## 2. Determine test tier

Based on the highest-impact category present in the diff:

**Tier 0 — Lint only** (DOCS only, no code changes)
```
bash -n <project shell files>
shellcheck <project shell files>
```
Skip test execution entirely. Report: `Tier 0: docs-only change, lint sufficient.`

**Tier 1 — Primary OS** (CONFIG, CLI, single-file CORE change)
```
make -C tests test          # Debian 12 (parallel)
```
Report: `Tier 1: single-scope change, Debian 12 sufficient.`

**Tier 2 — Primary + RHEL** (multi-file CORE, INSTALL, or compat-sensitive)
```
make -C tests test           # Debian 12
make -C tests test-rocky9    # Rocky 9
```
Report: `Tier 2: cross-file change, Debian 12 + Rocky 9 recommended.`

**Tier 3 — Full matrix** (CI changes, Dockerfile edits, cross-OS logic, new
features touching portability-sensitive code)
```
make -C tests test-all-parallel
```
Report: `Tier 3: infrastructure or portability change, full matrix recommended.`

**Tier 4 — Full matrix + deep legacy** (changes touching CentOS 6 / Ubuntu
12.04 compatibility: bash 4.1 floor, iptables-legacy, vault repos)
```
make -C tests test-all-parallel
make -C tests test-deep-legacy-parallel
```
Report: `Tier 4: deep legacy impact, full matrix + deep legacy recommended.`

## 3. Scope refinement

If only specific test files are relevant (e.g., a change to trust parsing
only needs trust-related .bats files), suggest targeted execution:
```
./tests/run-tests.sh /opt/tests/<specific>.bats
```

If the diff touches a function, grep tests/ for that function name to identify
which .bats files exercise it.

## 4. Output

```
## Test Strategy

Files changed: <N> (<categories>)
Tier: <0-4> — <rationale>

### Recommended
<exact make/run-tests commands to execute>

### Targeted (optional, faster)
<specific .bats files that cover the changed code>

### Skip rationale (if Tier 0)
<why tests aren't needed>
```

## Rules
- Do NOT execute tests — only recommend what to run
- If in doubt between tiers, recommend the higher tier
- If the project has no tests/ directory, report that and suggest lint only
- Account for the user's preference: "Don't run full tests after trivial changes"
