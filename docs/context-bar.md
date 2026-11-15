---
title: Status Line
parent: Reference
nav_order: 6
permalink: /context-bar
description: "RDF's Claude Code status line: model, git state, project health, context window use, cache efficiency and session cost on two lines."
---

# Status line (context-bar.sh)

Status line script for Claude Code. Renders a two-line display showing model,
project, git state, project health, context window utilization, cache
efficiency, session cost, and last user message. Line 1 also shows the effort level
and the rdf account the session runs on.

Requires Claude Code 2.0.65+ and `jq`.

---

## Layout

Two output lines. Line 1 is the status bar. Line 2 is the conversation echo.

```
Line 1:  MODEL · EFFORT | 👤 ACCOUNT | 📁 DIR | 🔀 BRANCH GIT_STATUS | H:HEALTH | CONTEXT_BAR PCT/CAP | ⚡ CACHE COST RATE
Line 2:  💬 Last user message...
```

Segments are pipe-delimited. Optional segments (effort, account, git, health) are omitted
when data is unavailable.

### Segment Map

| # | Segment | Source | Always Present |
|---|---------|--------|----------------|
| 1 | Model name + effort | JSON `.model.display_name`, `.effort.level` | Model yes; effort only for models with effort levels |
| 2 | Account | `~/.rdf/accounts` row for `CLAUDE_CONFIG_DIR` | No (only for accounts registered with `rdf account`) |
| 3 | Directory | `basename` of JSON `.cwd` | Yes |
| 4 | Git branch + status | `git` commands against cwd | No (only in git repos) |
| 5 | Project health | Cache file in `$XDG_RUNTIME_DIR` | No (only when cache exists) |
| 6 | Context bar + percentage | Transcript token counts | Yes |
| 7 | Cache hit + cost | Transcript usage + JSON `.cost` | Yes (cache always; cost when available) |
| 8 | Last user message | Transcript `.message.content` | No (only after first user turn) |

---

## Visual Primitives

### Block Characters (Context Bar)

The context bar is a 10-character gauge. Each character represents 10% of
the context window. Three block states:

| Glyph | Name | Meaning | Color Role |
|-------|------|---------|------------|
| `█` | Full block | Segment >= 80% filled | `C_ACCENT` (theme color) |
| `▄` | Half block | Segment 30-79% filled | `C_ACCENT` (theme color) |
| `░` | Empty block | Segment < 30% filled | `C_BAR_EMPTY` (dark gray) |

A bar reading `████▄░░░░░` means ~45% context used. The threshold for each
character position is: full at `position * 10 + 8`, half at `position * 10 + 3`.

### Icons

| Icon | Segment | Purpose |
|------|---------|---------|
| `👤` | Account | rdf account name |
| `📁` | Directory | Visual anchor for project name |
| `🔀` | Git branch | Visual anchor for branch name |
| `⚡` | Cache hit | Prompt cache efficiency indicator |
| `💬` | Echo line | Last user message (line 2) |

### Separators

| Glyph | Context |
|-------|---------|
| ` \| ` | Between segments (pipe with spaces) |
| ` · ` | Between model and effort level |
| ` · ` | Between pending count and sync status within git segment |
| `↑` `↓` | Ahead/behind counts when branch has diverged |

---

## Color System

### Roles

Five color roles control the entire display:

| Role | ANSI Code | Purpose |
|------|-----------|---------|
| `C_ACCENT` | Theme-dependent | Model name, filled bar blocks |
| `C_GRAY` | `38;5;245` | Default text, separators, normal-range metrics |
| `C_BAR_EMPTY` | `38;5;238` | Empty context bar blocks |
| `C_WARN` | `38;5;178` | Yellow-orange for warning thresholds |
| `C_ALERT` | `38;5;167` | Red for alert/critical thresholds |

### Themes

Set `COLOR=` at the top of the script. Default: `blue`.

| Theme | ANSI Code | Accent Color |
|-------|-----------|--------------|
| `gray` | `38;5;245` | Monochrome (all text same gray) |
| `orange` | `38;5;173` | Warm copper |
| `blue` | `38;5;74` | Steel blue |
| `teal` | `38;5;66` | Muted teal |
| `green` | `38;5;71` | Forest green |
| `lavender` | `38;5;139` | Dusty purple |
| `rose` | `38;5;132` | Mauve rose |
| `gold` | `38;5;136` | Dark gold |
| `slate` | `38;5;60` | Blue-gray |
| `cyan` | `38;5;37` | Cool cyan |

Preview all themes: `bash claude/scripts/color-preview.sh`

### Threshold Coloring

Three metrics change color based on value:

| Metric | Gray (normal) | Yellow (warn) | Red (alert) |
|--------|---------------|---------------|-------------|
| Context % | <= 60% | 61-80% | > 80% |
| Cache hit % | >= 60% | 35-59% | < 35% |
| Cost $/turn | <= $0.25 | $0.26-$0.50 | > $0.50 |

Thresholds are inverted for cache hit (lower is worse) versus context and
cost (higher is worse).

---

## Segments in Detail

### 1. Model Name + Effort

Displays the active model's human-readable name.

Resolution order: `.model.display_name` > `.model.id` > `"?"`.

```
Opus 4.6
Sonnet 4.6
Haiku 4.5
```

Colored with `C_ACCENT`. The effort level follows in gray after ` · ` when the input
has `.effort.level` (Claude Code sends it only for models with effort levels, and
redraws the line when `/effort` changes it).

### 2. Account

The `rdf account` name for this session: the `~/.rdf/accounts` row whose directory
matches `CLAUDE_CONFIG_DIR` (unset matches the `@primary` row). It is read from the
registry, not `RDF_CLAUDE_ACCOUNT`, because a shell default for that variable can name
a different account than the one `claude` actually runs on. Omitted when there is no
registry or no matching row.

```
👤 work
👤 personal
```

### 3. Directory

The `basename` of the current working directory.

```
📁 linux-malware-detect
📁 apf-firewall
📁 workforce
```

### 4. Git Branch + Status

Only shown when cwd is inside a git repository with a branch checked out.
Composed of branch name and a status string.

**Pending count**: tracked changes only (staged + unstaged modified/deleted).
Untracked files are excluded. Uses `git status --porcelain -uno`.

**Sync status**: compares HEAD against the current branch's upstream tracking
ref. Sync time is derived from the remote tracking ref's reflog (last push/fetch
for that specific branch), not the global `FETCH_HEAD`.

#### Git Status Variants

Clean working tree (0 pending):

```
🔀 main synced 12m ago
🔀 2.0.1 synced
🔀 feature 3 ahead
🔀 main 2 behind
🔀 hotfix 3↑ 2↓
🔀 local no upstream
```

Dirty working tree (N pending):

```
🔀 main 3 pending · synced 5m ago
🔀 2.0.1 1 pending · 2 ahead
🔀 feature 7 pending · no upstream
```

#### Sync Time Format

| Age | Format |
|-----|--------|
| < 60 seconds | `<1m ago` |
| < 1 hour | `Nm ago` (e.g. `12m ago`) |
| < 1 day | `Nh ago` (e.g. `3h ago`) |
| >= 1 day | `Nd ago` (e.g. `14d ago`) |

### 5. Project Health

Read from a cache file at `${XDG_RUNTIME_DIR:-/tmp}/rfxn-health-${project}.cache`.
Written by `/r-status` (or legacy `/proj-health`). Omitted when no cache exists.

```
H:GREEN
H:YELLOW 0C 1M
H:RED 2C 5M
```

GREEN shows the rating only. YELLOW and RED append a detail string (field 5
of the pipe-delimited cache file).

### 6. Context Bar + Percentage

A 10-character block gauge followed by percentage and capacity.

```
██████████ 100%/200k          (full: context exhausted)
████████▄░ 85%/200k           (alert: red percentage)
██████░░░░ 62%/200k           (warn: yellow percentage)
██▄░░░░░░░ 23%/1000k          (normal: gray percentage)
▄░░░░░░░░░ ~2%/200k           (baseline estimate, no transcript yet)
```

The `~` prefix appears when no transcript data is available yet (conversation
start). The bar shows a baseline estimate of ~20k tokens (system prompt +
tools + memory).

Capacity suffix reflects the model's context window: `200k` for standard
models, `1000k` for 1M-context models.

### 7. Cache Hit + Session Cost

Cache efficiency and economics in one compact group.

```
⚡ 83%                          (cache only, no cost data)
⚡ 83% $1.42 $0.12/t            (full: cache + total + rate)
⚡ 45% $0.38 $0.08/t            (warn: yellow cache)
⚡ 22% $5.71 $0.62/t            (alert: red cache + red rate)
```

**Cache hit %** = `cache_read / (cache_read + cache_create + uncached_input)`.
Higher is better: it means more prompt cache reuse.

**Session cost** = cumulative `$.cost.total_cost_usd` from the JSON input.

**Cost rate** = windowed average over the last 5 turns. Uses a cost history
file in `$XDG_RUNTIME_DIR` keyed by transcript path hash. Falls back to
cumulative average (`total / turns`) when fewer than 2 history entries exist.

### 8. Last User Message (Line 2)

The most recent user message rendered as a single-line echo, truncated to
fit the same visual width as line 1. Filters out unhelpful messages
(`[Request interrupted`, `[Request cancelled`, empty strings).

```
💬 commit and push to our workforce/ repo
💬 let's document including the different visual primitives and output examples that our status bar emits fo...
```

---

## Full Output Examples

**Early conversation, rdf account, non-git directory:**
```
Opus 5.5 · xhigh | 👤 personal | 📁 notes | ░░░░░░░░░░ ~2%/1000k
```

**Mid conversation, uncommitted changes, healthy cache:**
```
Opus 5.5 · high | 👤 work | 📁 rdf | 🔀 main 33 pending · synced 16d ago | ████▄░░░░░ 44%/1000k | ⚡ 89% $2.14 $2.14/t
💬 add effort level to the right of model
```

**Model without effort levels, no rdf account registry:**
```
Haiku 5.5 | 📁 notes | █░░░░░░░░░ ~10%/200k
```

---

## Input Contract

The script reads JSON from stdin (piped by Claude Code). Required fields:

```json
{
  "model": {
    "display_name": "Opus 4.6",
    "id": "claude-opus-4-6"
  },
  "effort": {
    "level": "xhigh"
  },
  "cwd": "/root/admin/work/proj/linux-malware-detect",
  "context_window": {
    "context_window_size": 1000000
  },
  "transcript_path": "/tmp/claude/transcript-abc123.jsonl",
  "cost": {
    "total_cost_usd": 2.14
  }
}
```

| Field | Required | Fallback |
|-------|----------|----------|
| `model.display_name` | No | `model.id`, then `"?"` |
| `effort.level` | No | Effort omitted |
| `cwd` | No | Skips git + health segments |
| `context_window.context_window_size` | No | `200000` |
| `transcript_path` | No | Shows baseline estimate |
| `cost.total_cost_usd` | No | Cost segment omitted |

---

## Configuration

Edit the top of `context-bar.sh`:

```bash
COLOR="blue"    # Theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
```

Enable in Claude Code `settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/context-bar.sh"
  }
}
```

### External Dependencies

- `jq`: JSON parsing (transcript, input)
- `~/.rdf/accounts` and `CLAUDE_CONFIG_DIR`: account segment
- `git`: branch and sync status
- `md5sum`: cost history file keying
- `awk`: cost rate calculation
- `stat`: removed in the latest version (reflog used instead)
