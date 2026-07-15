# Implementation Plan: Mismatch Fixture (test data)

**Plan Version:** 3.6
**Phases:** 2
**Tier:** full

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|------:|---------|-----------|
| `lib/alpha.sh` | ~10 | alpha helper | `tests/unused.bats` |
| `lib/cmd/ghost.sh` | ~10 | orphan — no phase touches it | `tests/unused.bats` |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `lib/beta.sh` | tweak beta | `tests/unused.bats` |

## Phase Dependencies
- Phase 1: none
- Phase 2: [1]

---

### Phase 1: Create alpha

**Files:**
- Create: `lib/alpha.sh`

- **Goals:** 1
- **Edge cases**: none

### Phase 2: Modify beta

**Files:**
- Modify: `lib/beta.sh`

- **Goals:** 1
- **Edge cases**: none
