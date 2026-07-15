# Implementation Plan: Comma-list Fixture (test data, M2 multi-path)

**Plan Version:** 3.6
**Phases:** 1
**Tier:** full

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|------:|---------|-----------|
| `a.sh` | ~5 | first path | `tests/unused.bats` |
| `b.sh` | ~5 | second path | `tests/unused.bats` |

## Phase Dependencies
- Phase 1: none

---

### Phase 1: Create both paths on one comma-list line

**Files:**
- Create: `a.sh`, `b.sh`

- **Goals:** 1
- **Edge cases**: none
