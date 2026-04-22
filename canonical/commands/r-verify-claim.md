# /r-verify-claim — Evidence Verification Skill

Verify a falsifiable claim about the current state of the codebase,
a commit, or a file. Produces a structured triage report with probe
commands, results, and a PASS/FAIL/UNVERIFIABLE verdict.

Operates as a skill the model invokes on itself to produce evidence,
or a slash command the user types to sanity-check an asserted claim.

## Invocation

```
/r-verify-claim "free-text claim"
/r-verify-claim --commit <sha> "claim"
/r-verify-claim --grep <pattern> <path>
/r-verify-claim --from-finding <sentinel-N.md>
```

**Argument detection:**
- `--commit <sha>` anchors the claim to a specific commit
- `--grep <pattern> <path>` is a shortcut for pattern-absent/present classes
- `--from-finding <file>` extracts claim text from a sentinel finding file
- Plain string → free-text claim, classifier decides the probe class

## Claim Classifier

The classifier reads the claim text and assigns one of 5 closed-set
classes. Each class has a pre-written probe template.

| Class | Trigger phrases | Probe template |
|-------|----------------|----------------|
| `commit-landed` | "phase N landed", "commit X", "merged", "pushed" | `git log --oneline <range> \| grep -i "{text}"` |
| `pattern-absent` | "removed", "no longer", "cleaned up", "no <pattern>" | `grep -rn '{pattern}' {path}` expect empty |
| `pattern-present` | "added", "exists", "all N <things>", "now contains" | `grep -c '{pattern}' {path}` expect ≥ threshold |
| `file-unchanged` | "unchanged", "not modified", "preserved" | `git diff {ref} -- {path}` expect 0 lines |
| `behavior-observable` | anything else | user-provided command required; else UNVERIFIABLE |

If the claim does not map to a class, emit UNVERIFIABLE with
guidance to rephrase or provide an explicit `--grep` / `--commit`
anchor.

## Output Format

Produce a structured markdown report:

```
## Claim Verification

**Claim:** <claim text>
**Class:** <class-name>

### Probes

| # | Command | Expected | Actual | Result |
|---|---------|----------|--------|--------|
| 1 | `<cmd>` | <expectation> | <actual> | PASS|FAIL |

**Verdict:** PASS | FAIL | UNVERIFIABLE — <one-line summary>

**Evidence line for result file:**
  - "<claim>": <citation>

**Suggested next action:** <only on FAIL or UNVERIFIABLE>
```

## Examples

**Pattern-absent claim:**
```
$ /r-verify-claim "bare cp removed from lib/"

## Claim Verification
**Claim:** bare cp removed from lib/
**Class:** pattern-absent

### Probes
| # | Command | Expected | Actual | Result |
|---|---------|----------|--------|--------|
| 1 | `grep -rn '^\s*cp ' lib/` | no output | (empty) | PASS |

**Verdict:** PASS — claim holds as of HEAD.
**Evidence line:** - "bare cp removed from lib/": grep -rn '^\s*cp ' lib/ → (no output)
```

**Commit-landed (failure):**
```
$ /r-verify-claim "Phase 4 landed"

## Claim Verification
**Claim:** Phase 4 landed
**Class:** commit-landed

### Probes
| # | Command | Expected | Actual | Result |
|---|---------|----------|--------|--------|
| 1 | `git log --oneline origin/main..HEAD \| grep -i "phase 4"` | 1+ matches | (empty) | FAIL |

**Verdict:** FAIL — no commit matching "phase 4" found on HEAD.
**Suggested next action:** Either (a) the commit hasn't landed — re-check PLAN.md, or (b) the commit message doesn't contain "phase 4" — provide commit SHA with --commit <sha>.
```

## Integration

**Reviewer:** Challenge Mode persona invokes this before asserting
falsifiable MUST-FIX findings — see `canonical/agents/reviewer.md`
§Challenge Mode §Verification protocol.

**User:** Type `/r-verify-claim "…"` to sanity-check any claim before
acting on it.

**Other agents:** Engineer and QA may invoke this to produce the
evidence lines for their result files.

## Constraints

- Never write files. Never commit. Output is text only.
- Never invent commands the user didn't authorize — the classifier
  uses pre-written templates; `behavior-observable` requires the
  user to supply the command.
- Quote all path and pattern arguments when building commands to
  prevent shell-injection from claim text.
- If all probes for a class error out (tool failure, not claim
  falsification), emit UNVERIFIABLE with the error, not FAIL.
