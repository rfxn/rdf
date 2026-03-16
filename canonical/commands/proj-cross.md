Cross-project analysis for rfxn projects. Reads MEMORY.md, PLAN.md, AUDIT.md,
and CLAUDE.md from all projects under /root/admin/work/proj/ to identify
shared patterns, duplicate effort, and alignment opportunities.

## Projects to scan
- advanced-policy-firewall (APF)
- linux-malware-detect (LMD)
- brute-force-detection (BFD)
- gpubench (if CLAUDE.md exists)

## Analysis domains

### 1. Open work overlap
Compare open PLAN.md items across projects. Flag:
- Same class of fix needed in multiple projects (e.g., "copyright year update")
- Shared infrastructure improvements (test parallelism, CI matrix, Dockerfile patterns)
- Deferred items that could be batched across projects

### 2. Audit finding patterns
If AUDIT.md exists in multiple projects, compare:
- Same DEDUP_CLASS appearing across projects
- Shared false positives (should be in parent CLAUDE.md)
- Common severity distribution patterns

### 3. Convention drift
Compare key patterns across project CLAUDE.md files:
- Commit message format consistency
- Verification checklist completeness
- Test infrastructure parity (parallelism, CI targets)
- Variable naming conventions

### 4. Shared library drift
Check canonical shared libraries for version and content drift:

**tlog_lib.sh:**
- Compare `TLOG_LIB_VERSION` across:
  - `tlog_lib/files/tlog_lib.sh` (canonical)
  - `brute-force-detection/files/tlog_lib.sh`
  - `linux-malware-detect/files/internals/tlog_lib.sh`
- Compute `sha256sum` of all three copies — warn if checksums differ
  (even at same version, detects project-specific edits)
- Compare `files/tlog` wrapper across all three projects similarly
- Flag any project-specific references that leaked into the library

### 5. MEMORY.md lessons
Read all MEMORY.md "Mistakes Made" / "Lessons Learned" sections. Flag:
- Lessons from one project applicable to others
- Anti-patterns documented in one but not enforced in parent CLAUDE.md

## Output
```
# Cross-Project Analysis

## Shared open work (batch opportunities)
<items that can be done across projects simultaneously>

## Convention drift
<differences that should be aligned>

## Shared library drift
<version mismatches, checksum differences, leaked project-specific code>

## Lessons to propagate
<lessons from one project that should be in parent CLAUDE.md>

## Recommendations
<numbered action items>
```
