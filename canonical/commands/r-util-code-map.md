Structural map of a source file — classes, functions, methods with
line ranges. Reduces context cost when an agent needs one symbol from
a large file by letting it read only the relevant line range.

## Arguments
- `$ARGUMENTS` — required: a file path, optionally followed by a
  symbol name. Forms:
  - `path/to/file.py` — full map of the file
  - `path/to/file.py <symbol>` — locate a single class/function/method
  - `path/to/file.py --threshold N` — override the 500-line default
    (files below the threshold are returned verbatim; no map)

## When to Use

Call this before `Read` on any source file over 500 lines. The map is
typically 20–40 lines. The agent then reads the specific line range it
needs with `Read offset=... limit=...` — often 70–85% fewer tokens than
a full-file read.

Do NOT call for:
- Small files (< 500 lines) — just `Read` directly
- Non-source files (markdown, JSON, YAML, SQL, data) — no symbol
  structure to extract
- Files you need end-to-end (refactor passes, full reviews, whole-file
  rewrites) — the map adds tokens without saving any

## Setup

Read `.rdf/governance/index.md` if present, to identify:
- Project language (informs which extractor to use)
- Project-specific source conventions from governance/conventions.md
- Ignore list from governance/ignore.md (skip files under those paths)

The threshold is configurable per project via
`governance/conventions.md` (key: `code-map-threshold`). Absent that,
default is 500 lines.

## Step 1: Threshold Check

Read the target file size:

```bash
wc -l <path>
```

If lines < threshold, emit a one-line notice and stop:

```
<path> (<N> lines) — below threshold, Read directly
```

## Step 2: Extractor Selection

Dispatch on file extension. Each extractor must produce the same
output shape (Step 3). Prefer language-native AST when available;
fall back to grep-based structural extraction otherwise.

### Python (`.py`)

Use `python3 -c` with the `ast` module:

```bash
python3 -c "
import ast, sys
src = open('<path>').read()
tree = ast.parse(src)
for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        kind = 'async def' if isinstance(node, ast.AsyncFunctionDef) else 'def'
        end = getattr(node, 'end_lineno', node.lineno)
        print(f'{kind} {node.name} L:{node.lineno}-{end} ({end - node.lineno + 1})')
    elif isinstance(node, ast.ClassDef):
        end = getattr(node, 'end_lineno', node.lineno)
        print(f'class {node.name} L:{node.lineno}-{end} ({end - node.lineno + 1})')
        for c in node.body:
            if isinstance(c, (ast.FunctionDef, ast.AsyncFunctionDef)):
                ck = 'async def' if isinstance(c, ast.AsyncFunctionDef) else 'def'
                ce = getattr(c, 'end_lineno', c.lineno)
                print(f'  {ck} {c.name} L:{c.lineno}-{ce} ({ce - c.lineno + 1})')
"
```

Fidelity: high. `ast.end_lineno` is accurate on Python 3.8+.

### Shell (`.sh`, `.bash`)

Grep for function definitions and compute end lines by scanning for
the matching closing brace at column 0:

```bash
awk '
/^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([[:space:]]*\)[[:space:]]*\{?[[:space:]]*$/ {
  name = $1; sub(/\(.*/, "", name); start = NR; next
}
/^\}[[:space:]]*$/ && start {
  printf "function %s L:%d-%d (%d)\n", name, start, NR, NR - start + 1
  start = 0
}' <path>
```

Fidelity: medium. Covers the common `name() { ... }` and `function
name { ... }` forms; nested functions and single-line functions may be
missed. Acceptable for RDF's own shell-heavy code and for APF/BFD/LMD.

### TypeScript / JavaScript (`.ts`, `.tsx`, `.js`, `.jsx`)

Prefer `ctags` if available:

```bash
command -v ctags >/dev/null && ctags -x --sort=no --fields=ne <path>
```

Fallback to grep:

```bash
grep -nE '^(export[[:space:]]+)?(async[[:space:]]+)?(function|class|interface|type|const[[:space:]]+[a-zA-Z_]+[[:space:]]*=[[:space:]]*(async[[:space:]]+)?\()' <path>
```

Fidelity: medium with ctags, low with grep fallback (no end lines
without ctags).

### Go (`.go`)

```bash
grep -nE '^(func|type)[[:space:]]' <path>
```

Fidelity: low. Use `gopls` or tree-sitter for better output when
installed.

### Rust (`.rs`)

```bash
grep -nE '^(pub[[:space:]]+)?(fn|struct|enum|trait|impl|mod)[[:space:]]' <path>
```

Fidelity: low without tree-sitter.

### C / C++ (`.c`, `.cc`, `.cpp`, `.h`, `.hpp`)

Prefer `ctags`:

```bash
ctags -x --sort=no --c-kinds=fcdesv <path> 2>/dev/null
```

Fidelity: medium-to-high with ctags.

### Ruby (`.rb`)

```bash
grep -nE '^(class|module|def)[[:space:]]' <path>
```

### Tree-sitter (any language, if installed)

If `tree-sitter` CLI is available and the project has a grammar
configured, prefer it over the language-specific fallbacks above.
Emit the same output shape. Absence of tree-sitter is the common
case — do not require it.

### Unknown extension

Emit a minimal outline:

```bash
wc -l <path>
head -30 <path>
```

## Step 3: Output Shape

Every extractor must emit this exact format so downstream consumers
(other skills, agents) can parse it:

```
<path> (<total-lines> lines)

  <kind> <name>                L:<start>-<end>   (<size> lines)
    <kind> <name>              L:<start>-<end>   (<size> lines)
  ...
```

Where `<kind>` is one of: `class`, `def`, `async def`, `function`,
`struct`, `enum`, `trait`, `impl`, `mod`, `interface`, `type`.
Nested children (methods inside classes) are indented two spaces.

When invoked with a symbol filter (`$ARGUMENTS` had a second token),
emit only the matching entry:

```
<path>:<qualified-name> L:<start>-<end> (<size> lines)
```

Qualified name uses `.` separator for member access
(`ClassName.method_name`).

If the symbol is not found:

```
<symbol> not found in <path>
```

## Step 4: Read Hint

After the map, emit a one-line suggestion so the caller can act:

```
Read with offset=<start> limit=<size> to load only <target>
```

When no specific target is requested, suggest the largest single
symbol — that is usually where a focused read is most valuable.

## Rules

- Read-only — do not modify any files
- Emit line ranges only; do not include source content
- If the file fails to parse (syntax error), emit the error on its
  own line and fall through to the grep-based extractor for the
  language — do not error out
- Never exceed 100 lines of output; if the file has more symbols,
  truncate with `... (N more symbols)` and suggest a symbol filter
- If the target path falls under a prefix listed in
  `.rdf/governance/ignore.md`, emit a one-line notice (`<path> —
  ignored by governance/ignore.md`) and stop; do not parse the file

## Composability

Other skills and commands invoke `/r-util-code-map` as a primitive:

- `/r-util-code-scan` — narrow pattern scans to symbols known to
  contain matches
- `/r-util-test-scope` — rank candidate test files by symbol graph
- `/r-util-doc-gen` — target specific functions by line range
- `/r-audit` (via reviewer subagents) — pre-read maps for large
  source files before full-content scans

Agents working in long-running sessions should call this before any
`Read` on a file over the threshold — the map token cost is recovered
on the first focused read and compounds on subsequent reads of the
same file.
