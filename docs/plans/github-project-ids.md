# GitHub Project Field IDs — RDF Development (#3)

Use with `gh project item-edit --project-id PVT_kwHOAB1a8s4BR4IB`

## Status Field
Field ID: `PVTSSF_lAHOAB1a8s4BR4IBzg_kwTI`

| Status | Option ID |
|--------|-----------|
| Backlog | `42fa2efc` |
| Ready | `22d84f46` |
| In Progress | `ae7b5d76` |
| In Review | `94d8b561` |
| Done | `7810ac14` |

## Phase Field
Field ID: `PVTSSF_lAHOAB1a8s4BR4IBzg_kwWI`

| Phase | Option ID |
|-------|-----------|
| Phase 1 | `ae01e7cf` |
| Phase 2 | `26349822` |
| Phase 3 | `d37c5145` |
| Phase 4 | `66fc75b5` |
| Phase 5 | `13e7c121` |
| Phase 6 | `55122520` |
| Phase 7 | `c4af1f86` |
| Phase 8 | `fc8d4376` |

## Effort Field
Field ID: `PVTSSF_lAHOAB1a8s4BR4IBzg_kwWM`

| Effort | Option ID |
|--------|-----------|
| XS | `739c4237` |
| S | `5355e3a4` |
| M | `33a0cc05` |
| L | `ede5b9da` |
| XL | `f1413fdc` |

## Assignee Role Field
Field ID: `PVTSSF_lAHOAB1a8s4BR4IBzg_kwWQ`

| Role | Option ID |
|------|-----------|
| mgr | `f6c36fef` |
| sys-eng | `3a90e178` |
| sys-qa | `1917855c` |
| sys-uat | `33fb5579` |
| sec-eng | `16af954c` |
| fe-qa | `e9c06d6f` |

---

# Ecosystem Project (#4)

Use with `gh project item-edit --project-id PVT_kwHOAB1a8s4BR4I_`

## Status Field (Ecosystem) — 5-State
Field ID: `PVTSSF_lAHOAB1a8s4BR4I_zg_kw-E`

| Status | Option ID | Use |
|--------|-----------|-----|
| Backlog | `949aba53` | Captured but not yet planned |
| Ready | `52a183fc` | Specced, plan exists, ready to start |
| In Progress | `f9ab04b3` | Actively executing |
| In Review | `92856676` | In QA/UAT gate |
| Done | `b0f7a623` | Complete |

## Project Field
Field ID: `PVTSSF_lAHOAB1a8s4BR4I_zg_kxBo`

| Project | Option ID |
|---------|-----------|
| RDF | `70a28736` |
| APF | `8cb0d846` |
| BFD | `ca58a0a3` |
| LMD | `e179148d` |
| Sigforge | `5f9fdb2b` |
| Libraries | `9d8116bc` |
| geoscope | `206f359a` |

## Priority Field (Ecosystem)
Field ID: `PVTSSF_lAHOAB1a8s4BR4I_zg_kxBs`

| Priority | Option ID |
|----------|-----------|
| P1 | `c7cc2ebf` |
| P2 | `fd91b4cb` |
| P3 | `8561d480` |

## Effort Field (Ecosystem)
Field ID: `PVTSSF_lAHOAB1a8s4BR4I_zg_kxDA`

| Effort | Option ID |
|--------|-----------|
| XS | `c62a87ce` |
| S | `07e1f61e` |
| M | `2c5fa499` |
| L | `8f23b79b` |
| XL | `a9cb09ca` |

## Start Date Field
Field ID: `PVTF_lAHOAB1a8s4BR4I_zg_nQjk`

Type: DATE — set to initiative/release start date.

## Target Date Field
Field ID: `PVTF_lAHOAB1a8s4BR4I_zg_nDqM`

Type: DATE — set to initiative/release end date.

## Roadmap View Configuration

The **Planning Roadmap** view uses:
- **Start date field:** Start Date
- **Target date field:** Target Date
- **Group by:** Project

---

## v2 Field Checklist — Required on Every Ecosystem Item

When adding an initiative, release, or phase issue to the ecosystem board,
set ALL of these fields:

| Field | Required | Notes |
|-------|----------|-------|
| **Status** | Yes | Backlog → Ready → In Progress → In Review → Done |
| **Project** | Yes | Which rfxn project (RDF, APF, BFD, LMD, etc.) |
| **Priority** | Yes | P1 (critical), P2 (important), P3 (backlog) |
| **Effort** | Yes | XS/S/M/L/XL — aggregate for the initiative/release/phase |
| **Start Date** | Yes for roadmap | When work begins (Roadmap bar start) |
| **Target Date** | Yes for roadmap | When work ends (Roadmap bar end) |

Items missing Start Date or Target Date will not appear on the Roadmap view.
Items missing Project will not group correctly on Cross-Project Board.

## Ecosystem Board Admission

All open issues from rfxn repos are admitted to the ecosystem board.
View filtering separates planned work from community triage:

- **Kanban/Roadmap views** — filtered to `type:initiative/release/phase/debt`
- **Triage view** — shows community issues (bugs, enhancements, unlabeled)
- **Cross-Project Board** — shows everything, grouped by project

Use `rdf github ecosystem-sync` to sync all open issues across repos.

Set **Project** and **Status=Backlog** on every new item. Set Priority
during triage. Start/Target Date and Effort required only for planned work.

After a release ships, remove its Done phase issues. Keep Done initiatives.

---

## v2 Labels (added 2026-03-16)

| Label | Color | Use |
|-------|-------|-----|
| `type:initiative` | #7057FF | Roadmap planning — directional, time-boxed |
| `type:release` | #1D76DB | Versioned release — parent for phase issues |

---

> **Note:** Task-level item IDs below are historical (v1 model). v2 tracks
> phase issues only. Task items have been removed from project boards.

## Phase 2 Task Issue → Item ID Map (historical)

| Issue | Item ID | Task |
|-------|---------|------|
| #23 | `PVTI_lAHOAB1a8s4BR4IBzgniOr8` | 2.1: agent-meta.json + command-meta.json |
| #24 | `PVTI_lAHOAB1a8s4BR4IBzgniOtM` | 2.2: hooks.json + plugin.json |
| #25 | `PVTI_lAHOAB1a8s4BR4IBzgniOuI` | 2.3: adapter.sh |
| #26 | `PVTI_lAHOAB1a8s4BR4IBzgniOvM` | 2.4: generate.sh + sync.sh |
| #27 | `PVTI_lAHOAB1a8s4BR4IBzgniOwQ` | 2.5: bin/rdf + rdf_common.sh |
| #28 | `PVTI_lAHOAB1a8s4BR4IBzgniOxg` | 2.6: rdf-state.sh + state.sh |
| #29 | `PVTI_lAHOAB1a8s4BR4IBzgniOyc` | 2.7: github.sh |
| #30 | `PVTI_lAHOAB1a8s4BR4IBzgniOzQ` | 2.8: symlink install |
| #31 | `PVTI_lAHOAB1a8s4BR4IBzgniO0U` | 2.9: state validation |

## Example: Move issue to Done

```bash
gh project item-edit --project-id PVT_kwHOAB1a8s4BR4IB \
  --id PVTI_lAHOAB1a8s4BR4IBzgniOr8 \
  --field-id PVTSSF_lAHOAB1a8s4BR4IBzg_kwTI \
  --single-select-option-id 7810ac14
gh issue close 23 --repo rfxn/rdf
```
