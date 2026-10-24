# Read Discipline

Every file an agent reads stays in its context and is re-read on every later
turn until compaction or the end of the run, so a whole-file read early in a
long subagent run is paid for dozens of times. Locate first, then read only
the window the task needs.

## The ladder

1. **Locate before opening.** Use `grep -n`, glob, a map, or the LSP tool when
   it is active (below). Narrow searches with `-l` or `-c` first and cap
   output (`| head -50`); do not page through every match.
2. **Check the size of a file you have not seen** (`wc -l`). Under 400 lines,
   read it whole. At 400 lines or more, map it or read a window.
3. **Read a window of 200-250 lines** around the target. Widen deliberately,
   not by reflex.
4. **Read a whole file only when editing or reviewing across all of it.**

To map a file, use the LSP `documentSymbol` operation when the tool is
active; otherwise grep its definitions with line numbers
(`grep -nE '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' f.sh`,
`grep -nE '^[[:space:]]*(def|class) ' f.py`). From the main conversation,
`/r-util-code-map` does this per language. Subagents cannot invoke skills.

The 400-line threshold is the `/r-util-code-map` default; a project can
override it with `code-map-threshold` in `governance/conventions.md`.

## Code intelligence (LSP)

A code intelligence plugin connects Claude Code to a language server and
activates the `LSP` tool. When the tool is active:

- **Locate by symbol, not text.** Go to definition, find references, workspace
  symbol search, implementations, and call hierarchy replace a grep followed
  by reads of every candidate file.
- **`documentSymbol` is the map** for step 2.
- **Diagnostics arrive after each Edit or Write.** Fix type errors and
  missing imports from them instead of re-reading the file or running a build
  to find them. Tests still verify behavior.

Limits: the tool stays inactive until both the plugin and its language server
binary are installed; cloud sessions start no language servers; a call on a
file whose server cannot start returns an error, so fall back to grep.
Official plugins cover TypeScript and JavaScript (`typescript-lsp`), Python
(`pyright-lsp`), Go (`gopls-lsp`), Rust (`rust-analyzer-lsp`), PHP
(`php-lsp`), C/C++, C#, Java, Kotlin, Lua, Ruby, and Swift. There is no
official shell plugin, so shell projects stay on grep and maps.

RDF's code-reading agents (planner, engineer, qa, reviewer) list `LSP` in
their tools, so they use it wherever a plugin is installed.

## Grounding

- Anthropic, *Effective context engineering for AI agents*: keep lightweight
  identifiers (paths, queries) and load data just in time with glob, grep,
  head, and tail.
- SWE-agent (arXiv 2405.15793), SWE-bench Lite ablation: a 100-line file
  viewer resolved 18.0%, a 30-line one 14.3%, and whole files 12.7%.
  Summarized search resolved 18.0% against 12.0% for paging through matches,
  because agents inspected every match. Read it for direction, not magnitude:
  2024 models, one benchmark.
- Claude Code docs, *Manage costs effectively*: a single go-to-definition
  call replaces a grep followed by reading several candidate files.
- `docs/specs/2026-09-10-token-efficiency-research.md` section 3.5 measures
  full reads on this framework's own sessions.
