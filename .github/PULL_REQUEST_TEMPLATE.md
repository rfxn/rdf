<!-- See CONTRIBUTING.md for the canonical → generated workflow and shell standards. -->

## What & why

<!-- What does this change and what problem does it solve? -->

## Changes

- [Fix] / [New] / [Change] / [Remove] …

## Checklist

- [ ] Content edits were made in `canonical/` (not generated output) and
      `bin/rdf generate claude-code` was re-run
- [ ] `bin/rdf doctor` reports zero FAIL
- [ ] `make -C tests test` passes (added a regression test for behavior changes)
- [ ] `bash -n` + `shellcheck` clean on changed shell files
- [ ] Portable across bash 3.2 / 4.1 and non-GNU coreutils where applicable
- [ ] `CHANGELOG` and `CHANGELOG.RELEASE` updated
