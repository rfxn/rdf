# Implementation Plan: cross-account peer sessions (`rdf peers`, shared session registry)

**Goal:** Claude Code sessions on different `rdf account` accounts can find and message each
other with the built-in `ListAgents` / `SendMessage` tools, and any session or shell can see
what every live session on the machine is working on.

**Architecture:** Claude Code already has session-to-session messaging: delivery, inbox auth,
receipts, `notify_when_idle` and permission-mode holds. The only gap is discovery, which reads
`$CLAUDE_CONFIG_DIR/sessions/` alone. Sharing that directory through the existing
`rdf account` link mechanism closes the gap without a new protocol. A read-only `rdf peers`
view derives in-flight work from data that already exists: the registry, the shared transcripts
under `projects/`, and RDF progress files. Nothing new writes state.

**Tech Stack:** bash (3.2 macOS / 4.1 el6 floor), jq, BATS.

**Spec:** N/A (quick-plan; context folded below).

**Phases:** 3 (P1 and P2 run in parallel; P3 after both)

**Tier:** quick-plan

**Changelog:** controller-owned. Phases do not edit CHANGELOG or CHANGELOG.RELEASE.

## Context (probed 2026-11-14 on this host, Claude Code 2.1.322, peerProtocol 1)

- Registry entry per running session: `<config>/sessions/<pid>.json` (fields `pid`,
  `sessionId`, `cwd`, `name`, `status` busy|idle, `kind`, `startedAt`/`updatedAt` epoch ms,
  `procStart`, `version`, `messagingSocketPath`) plus `<pid>.<64hex>.key` (inbox auth, 0600).
- On Linux `procStart` equals field 22 (starttime) of `/proc/<pid>/stat`; it guards pid reuse.
- Every account's socket lives in one dir: `/run/user/<uid>/cc-socks/<pid>.sock` (macOS and
  others: `/tmp/cc-socks[-<uid>]`, `/private/tmp/cc-socks[-<uid>]`).
- Copying another account's `<pid>.json` + key into this account's `sessions/` made it list in
  `ListAgents`; a `SendMessage` from novi-personal reached an rfxn session and its reply came
  back (`reply_across_default_dirs`). Both sides ran in bypass mode.
- Delivery is gated by the `crossSessionInbound` setting (accept|hold|refuse). When it is
  unset, a sender in a different permission-mode class is held for the receiver's user to
  approve. A headless receiver has no approval surface, so held messages expire there.
- Transcripts are shared through `projects/` and carry `ai-title` (`.aiTitle`), `last-prompt`
  (`.lastPrompt`), `mode` (`.mode`: normal, bypass, ...), `session-owner`
  (`.accountUuid`, `.organizationUuid`) and `gitBranch` on message records. Path:
  `<primary>/projects/<slug>/<sessionId>.jsonl`, found by globbing `projects/*/<sid>.jsonl`.
- Account identity: `<config>/.claude.json` (primary: `~/.claude.json`) `.oauthAccount`
  `{accountUuid, organizationUuid}`. Two accounts can share `accountUuid` (same person, two
  orgs), so match on the pair.
- `CLAUDE_CODE_SESSION_ID` is set in a session's Bash tool env; RDF progress files are
  `.rdf/work-output/*-<RDF_SESSION_ID>.md`, and `RDF_SESSION_ID` is the CC session id.

## Phase 1: share `sessions/` across accounts [parallel]

**Files:** lib/cmd/account.sh, tests/account.bats

- Add `sessions` to `_ACCOUNT_SHARED`.
- `_account_link_into`, for the `sessions` entry only (other entries keep the current "kept
  own copy" behavior): when `dst` is a real directory, move each entry of it into `src`
  unless `src` already has that name (warn and keep that file), then `rmdir dst` and
  `ln -sn src dst`. A non-empty `dst` after the moves (a session started mid-link) is kept
  with a warning to re-run `rdf account link`. Never follow or move a symlink.
- When `src` (`~/.claude/sessions`) is missing, create it with mode 700 before linking, so new
  accounts always share it.
- No other behavior change. `rdf account primary` already skips shared entries.
  `_account_live` now sees every account's sessions, which matches its "quit every session"
  precondition.
- `rdf account list` counts include `sessions` automatically. No usage text change beyond
  the help line for `link` mentioning that it merges session registries.

**Accept:** account.bats green:
- `add <name>` links `sessions` to `~/.claude/sessions` (created 700 when absent)
- `link` on an account whose `sessions/` is a real dir moves its files into the shared
  dir, replaces it with the link, and keeps a same-name file already present in the shared
  dir with a warning (neither file lost)
- a `sessions` symlink pointing elsewhere is kept (existing "links to X" warning)
- `primary` swap tests still pass with `sessions` shared

## Phase 2: `rdf peers` read-only view [parallel]

**Files:** lib/cmd/peers.sh (new), bin/rdf (dispatch + usage line), lib/cmd/shell.sh
(completion words), tests/peers.bats (new), tests/Makefile (add peers.bats to `test`)

`rdf peers [<name>] [--here] [--json]`

- Registry dirs: `~/.claude` plus each registered account dir from `~/.rdf/accounts`
  (registry parse: reuse the row format `name<TAB>dir|@primary`; source account.sh helpers
  if that is clean, else a small local reader), plus `$CLAUDE_CONFIG_DIR` if set. Dedupe by
  physical path (`cd -P`), so linked dirs are read once.
- Live filter: `kill -0 pid`, and on Linux `procStart` must equal `/proc/<pid>/stat` field 22
  (parse after the last `)`). Skip non-numeric or unparsable entries silently.
- Per session: name, account, status, mode, age (from `startedAt`), project (`cwd` basename;
  full path in card and JSON), branch, title, last prompt.
  - account: (accountUuid, organizationUuid) from the transcript `session-owner` record,
    matched to each account's `.claude.json` `.oauthAccount`; else the account owning the
    registry dir it was found in when that dir is not the shared one; else `?`.
  - transcript fields: read only the last 2 MiB (`tail -c`), tolerate a torn first line
    (`jq -R 'fromjson? // empty'`); take the last `ai-title`, `last-prompt`, `mode`,
    `session-owner`, and last non-empty `gitBranch`.
  - The current session (`CLAUDE_CODE_SESSION_ID`) is marked `*` in the table.
- Default output: one table row per live session, newest first, columns
  `NAME ACCOUNT STATE MODE AGE PROJECT BRANCH TITLE`; title truncated to fit 120 columns.
  No live sessions → `no live Claude Code sessions` and exit 0.
- `<name>`: a card for the session whose `name` matches (exact, else unique prefix; ambiguous
  or none → exit 1 listing candidates). The card adds pid, full cwd, last prompt, the first
  300 chars of the last assistant text, up to 5 most recent distinct `file_path` values from
  `Edit`/`Write`/`MultiEdit`/`NotebookEdit` tool_use inputs, RDF progress files in
  `<cwd>/.rdf/work-output/` whose name ends `-<sessionId>.md`, and a final line
  `message it: SendMessage to "<name>"`.
- `--here`: only sessions whose `cwd` is the current git toplevel or below it (fall back to
  `$PWD` outside git).
- `--json`: a JSON array of objects with keys `name, account, pid, session_id, status, mode,
  started_at, cwd, branch, title, last_prompt, self` (card mode: one object plus
  `last_reply, recent_files, rdf_progress`).
- Footer hints (table mode only, stderr, at most two lines):
  - accounts whose `sessions` entry is not a link to `~/.claude/sessions`:
    `peer messaging across accounts is off for: <names> (run: rdf account link)`
  - live sockets in the cc-socks dirs owned by this uid whose `<pid>` has no registry entry
    in any scanned dir: `<n> live Claude Code sockets have no registry entry; Claude Code
    may have changed its session layout`
- Exit codes: 0 ok, 1 no match for `<name>`, 2 usage error (unknown flag).
- Every read is best-effort: a missing transcript, unreadable `.claude.json` or absent
  `/proc` leaves the field empty, never fails the command.

**Accept:** peers.bats green (hermetic `HOME=$(mktemp -d)`; live pids come from a
`sleep 300 &` started in setup and killed in teardown; fixture transcripts written by the
test):
- table lists a live entry and omits a dead pid; `*` marks `CLAUDE_CODE_SESSION_ID`
- Linux only (`skip` elsewhere): a live pid with a wrong `procStart` is omitted
- title, last prompt, mode, branch and account come from the fixture transcript; account
  pair matching tells two accounts with the same accountUuid apart
- `--json` is valid JSON with the listed keys; card JSON has `recent_files` and
  `rdf_progress`
- `<name>` card: exact match, unique prefix, ambiguous prefix → exit 1, no match → exit 1
- `--here` filters by git toplevel
- unlinked-account hint printed; absent when every account links `sessions`
- a torn first line in the transcript tail does not break parsing
- no registry dirs at all → `no live Claude Code sessions`, exit 0
- unknown flag → exit 2

## Phase 3: docs and session-safety pointer [serial, after P1 and P2]

**Files:** docs/accounts.md, docs/concurrent-sessions.md, docs/cli.md, RDF.md (CLI list and
tree if they list lib/cmd files), canonical/reference/session-safety.md, adapter output
regenerated (`rdf generate claude-code`, `rdf generate claude-plugin`, commit
`adapters/claude-plugin/output`)

- docs/accounts.md: "Sessions on every account see each other" section: what is shared,
  messaging with `ListAgents`/`SendMessage`, `rdf peers`, permission-mode holds and the
  `crossSessionInbound` setting (state the tradeoff, do not recommend `accept`), the data
  direction across orgs, scope (same machine, same user; Codex not covered), and that the
  mechanism rests on Claude Code's undocumented registry layout, with the `rdf peers` footer
  as the tripwire.
- docs/concurrent-sessions.md: "See what other sessions are doing" (`rdf peers --here`).
- docs/cli.md: `rdf peers` entry with flags and exit codes, matching `rdf help`.
- canonical/reference/session-safety.md: one line: before editing files another session may
  hold, `rdf peers --here` lists live sessions in this repo on any account; message one with
  `SendMessage`.
- No em dashes in new prose. Captured output in docs must come from a real run.

**Accept:** `make -C tests test` green; `rdf doctor` shows no new FAIL; doc-truth link test
green.

## Edge Cases

| Case | Behavior |
|------|----------|
| Session starts while `link` merges `sessions/` | dir non-empty after moves → kept, warned; re-run link |
| Same `<pid>.json` in both dirs (stale + live) | shared copy kept, warning names the file |
| Registry entry with recycled pid | Linux: procStart mismatch → omitted; elsewhere listed (kill -0 only) |
| Transcript not yet written (new session) | row shows registry fields, empty title |
| `~/.rdf/accounts` absent | scan `~/.claude` and `$CLAUDE_CONFIG_DIR` only |
| Claude Code moves its registry | `rdf peers` footer reports orphan sockets; messaging falls back to per-account, never misdelivers |
