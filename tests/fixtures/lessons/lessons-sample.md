# Lessons Learned

## Workflow
- designate one owner per shared file before launching parallel agents
- fanning out parallel agents: pick one owner per shared file at dispatch

## Testing
- update tests in the same phase as a source refactor or false-green
- always run the full test matrix before every commit
- never run the full matrix before commit; Debian12 and Rocky9 is the minimum
