# Claude Code Agent Teams — API Research

> Researched 2026-03-16. Source: https://code.claude.com/docs/en/agent-teams
> Status: Experimental (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)
> Minimum version: Claude Code v2.1.32

## 1. Architecture

Agent Teams coordinate multiple Claude Code instances. One session is the
**team lead** (coordinator); others are **teammates** (independent workers).

Components:
- **Team lead**: main CC session, creates team, spawns teammates, coordinates
- **Teammates**: separate CC instances, own context windows, self-claim work
- **Task list**: shared work items with dependency tracking and file locking
- **Mailbox**: inbox-based messaging between any two agents

Storage:
- Team config: `~/.claude/teams/{team-name}/config.json`
- Task list: `~/.claude/tasks/{team-name}/{id}.json`
- Inboxes: `~/.claude/teams/{team-name}/inboxes/{agent-name}.json`

## 2. Tool Primitives

### TeamCreate
```json
{ "team_name": "rfxn-pipeline", "description": "rfxn engineering pipeline" }
```
Creates `~/.claude/teams/{team_name}/config.json` with members array.

### TaskCreate
```json
{
  "subject": "SE: Implement Phase N",
  "description": "Execute 7-step SE protocol for phase N...",
  "activeForm": "Implementing phase N"
}
```
Creates `~/.claude/tasks/{team_name}/{id}.json`. Fields: id, subject,
description, status (pending), owner (empty).

### TaskUpdate
```json
{ "taskId": "1", "status": "in_progress", "owner": "sys-eng" }
{ "taskId": "3", "addBlockedBy": ["1", "2"] }
```
States: pending, in_progress, completed. File locking prevents double-claims.
When a blocking task completes, blocked tasks auto-unblock.

### TaskList
No parameters. Returns all tasks with current status, subject, owner.

### Task (teammate spawn — extended with team_name)
```json
{
  "team_name": "rfxn-pipeline",
  "name": "sys-eng",
  "subagent_type": "general-purpose",
  "prompt": "You are the Senior Engineer...",
  "model": "opus",
  "run_in_background": true
}
```
Spawns a teammate that can access TaskList, SendMessage, and project context.

### SendMessage
```json
{ "type": "message", "recipient": "team-lead", "content": "Task complete.", "summary": "Done" }
{ "type": "broadcast", "name": "team-lead", "value": "Status update" }
{ "type": "shutdown_request", "target_agent_id": "sys-eng", "reason": "Pipeline complete" }
{ "type": "shutdown_response", "request_id": "shutdown-123", "approve": true }
{ "type": "plan_approval_response", "request_id": "plan-xyz", "approved": true }
```

### TeamDelete
No parameters. Removes team config and task directories. Fails if active
teammates exist (must shutdown first).

## 3. Delegate Mode

Activated via Shift+Tab in interactive mode. Restricts lead to:
- Task management (create, update, list)
- Communication (message, broadcast)
- Teammate lifecycle (spawn, shutdown)
- NO code writes, NO test execution, NO file modifications

Maps directly to EM's constraint: "You manage projects, you do NOT write code."

## 4. Hooks

### TeammateIdle
Fires when teammate is about to go idle. Exit code 2 sends feedback and keeps
teammate working. Use for auto-assigning follow-up work.

### TaskCompleted
Fires when task is being marked complete. Exit code 2 prevents completion and
sends feedback. Use for quality gates (lint, test pass requirements).

## 5. Teammate Environment Variables

Set automatically when spawned as teammate:
- CLAUDE_CODE_TEAM_NAME — team namespace
- CLAUDE_CODE_AGENT_ID — "name@team-name"
- CLAUDE_CODE_AGENT_NAME — agent name

## 6. Configuration

Enable in settings.json:
```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

Display modes: "auto" (default), "in-process", "tmux"
```json
{ "teammateMode": "in-process" }
```

## 7. Limitations (as of 2026-03-16)

- No session resumption for in-process teammates
- Task status can lag (teammates may forget to mark complete)
- One team per session, no nested teams
- Lead is fixed for session lifetime
- All teammates inherit lead's permission settings at spawn
- Split panes require tmux or iTerm2
- Shutdown can be slow (waits for current tool call)

## 8. Token Cost Model

Each teammate has its own context window. Cost scales linearly with team size.
3-teammate team uses approximately 3-4x single-session tokens.

Optimization: Use Sonnet for focused implementation teammates, Opus for lead
coordination and semantic-depth roles (sys-eng, sys-sentinel).
