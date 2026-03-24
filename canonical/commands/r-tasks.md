# /r-tasks — Task List Status

Display the current task list state. Use this when a long-running
command seems stuck, or to check progress at any time.

This is a read-only status poke — it does not modify tasks.

## Protocol

### 1. Read Task List

Call `TaskList` to get all current tasks with their status.

### 2. Render Status

Display tasks as a formatted task list with timing context:

```
### Task Progress
- [x] Ingest existing convention files
- [x] Scan codebase: languages, frameworks, structure
- [ ] **Detect tooling and infrastructure** *(in-progress)*
- [ ] Generate supplementary governance
- [ ] Validate and spot-check accuracy

**Progress:** 2/5 complete | **Current:** Detect tooling and infrastructure
```

Task styling:
- `[x]` + plain text = *completed*
- `[ ]` + **bold** + *(in-progress)* italic = currently running
- `[ ]` + plain text = *pending*
- `[ ]` + ~~strikethrough~~ + *(blocked)* italic = blocked by dependency

### 3. Summary Line

Below the task list, show a one-line summary:

```
**Progress:** {completed}/{total} complete | **Current:** {in-progress task subject}
```

If no tasks are in progress: `**Progress:** {completed}/{total} complete | **Current:** none`
If no tasks exist: `No active tasks.`

## Rules
- Read-only — never modify task state
- Call TaskList exactly once — do not poll or retry
- Keep output under 15 lines
- If TaskList returns empty, display "No active tasks" and stop
