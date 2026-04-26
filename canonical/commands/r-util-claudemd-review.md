# /r-util-claudemd-review — CLAUDE.md Conversation-Driven Review

Analyze recent conversations to find improvements for CLAUDE.md files,
and audit existing CLAUDE.md content for prose drift and memory-bound
state contamination. Read-only report — no modifications.

Adapted from ykdojo/claude-code-tips review-claudemd skill, with RDF
discipline filters added.

## Scope

Two layers reviewed in every run:

1. **Global** — `~/.claude/CLAUDE.md`
2. **Project** — every `CLAUDE.md` reachable from CWD upward to the
   workspace root (typical rfxn layout: project root + workspace
   parent + global). Ignore vendored copies inside `node_modules/`,
   `.git/`, or other dependency directories.

If CWD is the workspace root with multiple project subdirectories,
process each project's CLAUDE.md tree; do not merge cross-project
findings.

## Step 1: Locate Conversation History

```bash
PROJECT_PATH="$(pwd | sed 's|/|-|g; s|^-||')"
CONVO_DIR="$HOME/.claude/projects/-${PROJECT_PATH}"
[ -d "$CONVO_DIR" ] || { echo "No conversation history at $CONVO_DIR"; exit 1; }
ls -lt "$CONVO_DIR"/*.jsonl | head -20
```

If `$CONVO_DIR` does not exist, ask the user to run from a
directory that has been used as a Claude Code workspace.

## Step 2: Extract Recent Conversations

Extract the 15–20 most recent conversations (excluding the current
session) to a scratch directory:

```bash
SCRATCH="$(mktemp -d -t claudemd-review-XXXXXX)"

# CURRENT_SESSION_ID is the active conversation; skip it.
CURRENT_SESSION_ID="${CLAUDE_SESSION_ID:-}"

for f in $(ls -t "$CONVO_DIR"/*.jsonl | head -20); do
  base="$(basename "$f" .jsonl)"
  [ -n "$CURRENT_SESSION_ID" ] && [ "$base" = "$CURRENT_SESSION_ID" ] && continue
  jq -r '
    if .type == "user" then
      "USER: " + (.message.content // "")
    elif .type == "assistant" then
      "ASSISTANT: " + ((.message.content // []) | map(select(.type == "text") | .text) | join("\n"))
    else
      empty
    end
  ' < "$f" 2>/dev/null | grep -v "^ASSISTANT: $" > "$SCRATCH/${base}.txt"
done

ls -lhS "$SCRATCH"
```

## Step 3: Dispatch Parallel Sonnet Subagents

Launch parallel `general-purpose` agents (Sonnet) to analyze the
conversations. Batch by file size:

- Large (>100 KB): 1–2 conversations per agent
- Medium (10–100 KB): 3–5 per agent
- Small (<10 KB): 5–10 per agent

Each agent receives this prompt:

```
Read these files in this order:
1. Global CLAUDE.md: ~/.claude/CLAUDE.md
2. Project CLAUDE.md(s): <list of project paths discovered in Scope>
3. Conversation transcripts: <list of $SCRATCH/*.txt batched for this agent>

Analyze the conversations against EVERY CLAUDE.md file. For each
finding, classify as exactly one of:

  ADD-LOCAL     — pattern that should be in the project CLAUDE.md
  ADD-GLOBAL    — pattern that should be in the global CLAUDE.md
  REINFORCE     — existing instruction that was violated; reword stronger
  REMOVE        — existing instruction that is outdated, unused, or contradicted
  REWORD        — existing instruction that misled or confused

For each finding emit ONE bullet in this exact shape:

  [ACTION] scope=<global|project:<name>> | <terse imperative rule> | evidence: <file:line | session-id snippet>

DISCIPLINE FILTERS — your suggested rule text MUST satisfy ALL of:

  D1. No prose paragraphs. Imperative one-liners only. If a rule
      cannot be expressed in one sentence, it is two rules.
  D2. No memory-bound state. Forbidden in rule text:
        - line counts ("a 500-line file", "20 tests")
        - test counts, file counts, function counts
        - version numbers (3.1.1, v2.4)
        - commit hashes, branch names
        - phase status ("phase 3 complete")
        - file inventories ("we have 14 commands")
        - directory listings, dependency lists
      Volatile state belongs in MEMORY.md, derived from source — never CLAUDE.md.
  D3. No restated framework defaults. If the rule duplicates a
      Claude Code built-in or an existing parent CLAUDE.md rule,
      drop it.
  D4. No tone or sentiment ("be careful", "remember to") — state
      the rule directly: "X must Y" or "Never Z".

Reject your own findings that violate D1–D4 before reporting.

Output format: bullets only. No headers, no prose summary, no
preamble. Empty output is acceptable if nothing meets the bar.
```

## Step 4: Aggregate Findings

Combine all subagent outputs. Deduplicate by collapsing bullets that
share the same `[ACTION] scope= rule` prefix. Sort within each
section by ACTION class (ADD-LOCAL, ADD-GLOBAL, REINFORCE, REMOVE,
REWORD).

## Step 5: Audit Existing CLAUDE.md for D1–D4 Violations

This is the RDF-specific addition. Independently scan every
CLAUDE.md file in scope for D1–D4 anti-patterns:

```bash
for cmd in ~/.claude/CLAUDE.md $(find . -maxdepth 3 -name CLAUDE.md -not -path '*/node_modules/*' -not -path '*/.git/*'); do
  printf '\n=== %s ===\n' "$cmd"

  # D1: prose paragraphs (lines >180 chars often indicate prose drift; multi-sentence bullets)
  awk 'length > 180 { printf "D1:%d: long line (%d ch)\n", NR, length }' "$cmd"
  grep -nE '\.[[:space:]]+[A-Z][a-z]+.*\.[[:space:]]+[A-Z]' "$cmd" | sed 's/^/D1-multisent:/'

  # D2: memory-bound state
  grep -nE '\b[0-9]+ (tests|test cases|lines|files|commands|agents|skills|phases)\b' "$cmd" | sed 's/^/D2-count:/'
  grep -nE '\bv?[0-9]+\.[0-9]+\.[0-9]+\b' "$cmd" | sed 's/^/D2-version:/'
  grep -nE '\b[a-f0-9]{7,40}\b' "$cmd" | sed 's/^/D2-hash:/'
  grep -niE 'phase [0-9]+ (complete|done|in.progress|pending)' "$cmd" | sed 's/^/D2-phase:/'

  # D4: tone/sentiment
  grep -niE '^\s*-?\s*(be careful|remember to|please|make sure to|don.t forget)\b' "$cmd" | sed 's/^/D4-tone:/'
done
```

Each hit is a candidate REMOVE or REWORD. Hand-verify before flagging
— some matches are legitimate (e.g., `2>/dev/null` rule citing a
hash-prefixed example). Discard a candidate if the matched line is:

- Inside a fenced code block (` ``` ` ... ` ``` `)
- A literal example demonstrating the anti-pattern
- A regex pattern definition

## Step 6: Output Report

Write findings to stdout. Do not modify any CLAUDE.md file. The
report is the deliverable.

```
# CLAUDE.md Review — <date>

## Conversation-Derived Findings (Step 4)

<bullets from aggregation, sorted by ACTION>

## Discipline Violations in Existing Content (Step 5)

| File | Line | Violation | Suggested action |
|------|-----:|-----------|------------------|
| ~/.claude/CLAUDE.md | 47 | D2-version: "v3.1.1" cited inline | REMOVE — derive version from VERSION file |
| ./CLAUDE.md | 124 | D1: 220-char prose paragraph | REWORD as imperative one-liner |
| ... | | | |

## Recommended Edits

For each finding, present a 2-3 line patch suggestion. Do not apply
any edit automatically. Ask the user which findings to draft as
edits.
```

## Notes

- The skill never edits CLAUDE.md. Edits are user-driven via a
  follow-up exchange.
- Conversation transcripts may contain private workflow detail.
  Scratch directory is `mktemp`-isolated and deleted at session end
  unless the user asks to retain it.
- D1–D4 filters compose with the parent rfxn CLAUDE.md's existing
  rule: "Volatile data does not belong in any CLAUDE.md — derive
  from source." This skill operationalizes that rule against the
  written content.

## Arguments

- `$ARGUMENTS` — optional:
  - `--global-only` — analyze only `~/.claude/CLAUDE.md`
  - `--project-only` — analyze only project-tree CLAUDE.md files
  - `--no-conversations` — skip Steps 1–4; run only the Step 5
    discipline audit (faster, no subagent dispatch)
  - `--limit N` — process N most recent conversations (default 20)

Default behavior: full Steps 1–6 across global + project scope.
