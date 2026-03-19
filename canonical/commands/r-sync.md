You are running the /r:sync canonical source synchronization. This is
an RDF-internal command that pulls emergency edits made directly to
~/.claude/ back into the rdf canonical source tree.

## Context

RDF development follows a one-way flow:
1. Edit files in rdf/canonical/ (the source of truth)
2. Run `rdf generate claude-code` to deploy to ~/.claude/
3. If emergency edits are made directly to ~/.claude/, run /r:sync
   to pull them back

This command handles step 3 — the reverse flow.

## Arguments

$ARGUMENTS — optional flags:
- No args: sync all changed files
- `--dry-run`: show what would change without writing
- `--v3-only`: sync only v3 agent and command files
- `--diff`: show detailed diff for each changed file

## Procedure

### Step 1: Locate Sources
- RDF canonical root: the `canonical/` directory in the rdf project
- Deployed target: `~/.claude/` (agents, commands, scripts)
- Identify which adapter was used (default: claude-code)

### Step 2: Scan for Changes
Compare deployed files against canonical sources:

#### Agents (v3)
- Source: `~/.claude/agents/*.md`
- Target: `canonical/agents-v3/*.md`
- Processing: strip YAML frontmatter (--- delimited block) before
  comparison. Frontmatter is added by the adapter during generate
  and must be removed during sync.

#### Agents (v2, legacy)
- Source: `~/.claude/agents/*.md`
- Target: `canonical/agents/*.md`
- Processing: same frontmatter stripping

#### Commands (v3)
- Source: `~/.claude/commands/r-*.md` (r: prefixed commands)
- Target: `canonical/commands-v3/*.md`
- Processing: direct comparison (commands have no frontmatter)

#### Commands (v2, legacy)
- Source: `~/.claude/commands/*.md` (non-r: prefixed)
- Target: `canonical/commands/*.md`
- Processing: direct comparison

#### Scripts
- Source: `~/.claude/scripts/*.sh`
- Target: `canonical/scripts/*.sh`
- Processing: direct comparison

### Step 3: Report Changes
For each file with differences:
- Show the canonical path and deployed path
- If `--diff` flag: show unified diff
- If `--dry-run` flag: report only, do not write

### Step 4: Apply Changes
For each changed file (unless --dry-run):
- Strip frontmatter from agent files
- Trim leading blank lines from stripped content
- Write to canonical path
- Report: `updated: canonical/{type}/{filename}`

For unchanged files:
- Count but do not report individually

### Step 5: Summary

    ## Sync Report

    Direction: ~/.claude/ -> rdf/canonical/
    Adapter: claude-code

    Updated: {count} files
    Unchanged: {count} files

    ### Files Updated
    - canonical/{path} (agent/command/script)
    ...

    ### Next Steps
    - Review changes: `git diff canonical/`
    - If correct: commit with descriptive message
    - Run `rdf generate claude-code` to verify round-trip

## Frontmatter Stripping

Agent files deployed by `rdf generate` have YAML frontmatter:

    ---
    name: rdf-engineer
    description: Universal implementation engineer...
    model: opus
    ---
    (actual agent prompt content)

The sync command strips everything between the first `---` and the
second `---` (inclusive), keeping only the body content. Leading
blank lines after the frontmatter block are also trimmed.

## Constraints
- Never modify files in ~/.claude/ — sync is a pull operation
- Always strip frontmatter from agent files (never commit frontmatter
  to canonical)
- If a deployed file has no canonical counterpart, report it as
  "new file" and ask the user whether to import it
- If a canonical file has no deployed counterpart, ignore it (it may
  not have been generated for this adapter)
- The `rdf sync` CLI command handles the actual file operations —
  this skill can invoke it or replicate its logic for v3 paths
