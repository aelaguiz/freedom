# Traceability Matrix

This matrix maps source artifacts to requirements. It is intentionally redundant so review can find gaps quickly.

## Source Artifacts

- `UX`: `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md`
- `README`: `docs/mockups/codex-dock-activity-first-2026-05-29/README.md`
- `M01`: `../outputs/01-newest-default.png`
- `M02`: `../outputs/02-host-lens.png`
- `M03`: `../outputs/03-branch-lens.png`
- `M04`: `../outputs/04-loading-not-loaded.png`
- `M05`: `../outputs/05-filters.png`

## Global Requirement Coverage

| Requirement area | Requirement ids | Source anchors |
| --- | --- | --- |
| Product model | `G-001` through `G-006` | `UX` sections 0, 1, 3, 4; `README` Product Notes |
| App navigation | `G-010` through `G-019` | `UX` sections 2.3, 5; `M01` through `M05` |
| Header | `G-020` through `G-029B` | `UX` section 6; `M01` through `M05` |
| Search | `G-030` through `G-036` | `UX` sections 2.2, 6, 11; `M01`, `M05` |
| Filters and facets | `G-040` through `G-054` | `UX` sections 2.6, 11, 13, 16.5; `M05` |
| Rows | `G-060` through `G-071` | `UX` sections 2.4, 2.5, 7; `M01`, `M02`, `M03`, `M04` |
| Host identity | `G-080` through `G-084` | `UX` sections 4, 6, 7, 9, 15, 17; `M01`, `M02`, `M03`, `M04`, `M05` |
| Status vocabulary | `G-090` through `G-096` | `UX` section 12; `M01`, `M02`, `M03`, `M04`, `M05` |
| Removed primary statuses | `G-100` through `G-108` | `UX` sections 0, 2.8, 12, 17, 18; `README` Kill List |
| Sorting | `G-120` through `G-125` | `UX` sections 5, 8, 9, 10, 11; `M01`, `M02`, `M03`, `M05` |
| Loading and partial states | `G-130` through `G-137` | `UX` sections 2.8, 13, 15, 17; `M04` |
| Host offline/error affordances | `G-138` through `G-140` | `UX` section 15 |
| Noise and hidden state | `G-150` through `G-156` | `UX` sections 13, 14, 15, 17; `M01`, `M03`, `M05` |
| Accessibility and verification | `G-170` through `G-174` | `UX` sections 2.8, 19; user request to inspect via accessibility hooks |

## Screen Requirement Coverage

| Screen | Requirement ids | Primary sources |
| --- | --- | --- |
| Newest default | `S01-001` through `S01-064` | `UX` sections 5, 6, 7, 8, 16.1, 17, 19; `M01` |
| Host lens | `S02-001` through `S02-064` | `UX` sections 5, 7, 9, 16.2, 17, 19; `M02` |
| Branch lens | `S03-001` through `S03-064` | `UX` sections 5, 7, 10, 11, 16.3, 17, 19; `M03` |
| Loading and not loaded | `S04-001` through `S04-045` | `UX` sections 2.8, 12, 13, 15, 17, 19; `M04` |
| Filters | `S05-001` through `S05-075` | `UX` sections 2.2, 2.6, 11, 12, 13, 16.5, 17; `M05` |
| Branch search results | `S06-001` through `S06-054` | `UX` sections 10, 11, 16.4, 19 |
| Host offline partial failure | `S07-001` through `S07-045` | `UX` sections 15, 17, 19 |
| Filtered empty results | `S08-001` through `S08-045` | `UX` sections 15, 19 |
| Not-loaded filter results | `S09-001` through `S09-045` | `UX` sections 12, 15, 19 |

## Kill List Coverage

| Killed direction | Requirement coverage | Source anchors |
| --- | --- | --- |
| Primary `All`, `Needs me`, `Running`, `Agents` tab row | `G-100` through `G-108`, `S01-060` through `S01-062`, `S05-070` | `UX` sections 2.8, 12, 17, 18 |
| `Limited` label | `G-091`, `S01-061`, `S02-062`, `S03-063`, `S04-040`, `S05-071` | `UX` section 12; `README` Kill List |
| Rate-limit implication for unknown data | `G-092` through `G-094`, `S04-020` through `S04-025`, `S04-041` | `UX` section 12; user correction |
| Branch default | `G-014`, `S01-001`, `S03-060` | `UX` sections 2.8, 5, 8, 17 |
| Legacy Branch/Newest sort control | `G-019`; top-level README Kill List | `UX` sections 2.8, 5, 8, 17 |
| Pinned host cards above list | `G-022`, `S01-002`, `S02-060`, `S02-064` | `UX` sections 4, 6, 9, 17 |
| Raw endpoint scan path | `G-080` through `G-081`, `S01-063`, `S02-005`, `S03-024`, `S04-044`, `S05-073` | `UX` sections 2.8, 6, 7, 17 |
| Cramped search | `G-023` through `G-025`, `S01-006`, `S05-009` | `UX` sections 2.8, 6, 17 |
| Misleading loading counts | `G-049`, `G-130` through `G-133`, `S04-040` through `S04-043` | `UX` sections 2.8, 13, 17 |
| Predictive ranking | `G-002`, `G-006`, `G-155`, `S01-041` | `UX` sections 3, 12, 13, 17 |
| Branch search only as free text | `G-051`, `S03-040` through `S03-046`, `S05-023` through `S05-025`, `S05-072` | `UX` sections 10, 11 |
| Ambiguous branch-search results | `S06-001` through `S06-010`, `S06-050` through `S06-054` | `UX` section 16.4 |
| Separate filter models for duplicate entries | `G-053`, `G-054`, `S05-010`, `S05-011` | `M01` through `M05`; `UX` section 11 |
| Ambiguous host-header taps | `S02-042` through `S02-044` | `UX` section 9 |
| Missing source/agent filter when source exists | `G-045`, `S05-033` | `UX` sections 11, 12, 16.5 |
| Missing filtered-empty state | `G-135`, `G-136`, `S08-001` through `S08-045` | `UX` section 15 |
| Missing not-loaded-only explanation | `G-092` through `G-094`, `S05-040`, `S05-041`, `S09-001` through `S09-045` | `UX` sections 12, 15 |

## Open Questions Coverage

The strategy doc's open questions are not blockers, but each has a requirement boundary:

| Open question | Requirement boundary |
| --- | --- |
| Remove `Needs me` entirely or keep debug-only | Primary UX forbids it: `G-100` through `G-104`. |
| Hide idle forever or remember setting | Idle visibility must be explicit: `G-046`, `G-150`, `G-151`. |
| Persist pins across launches | Pinning is optional and explicit only: `G-156`. |
| Host header sort order | Default is newest visible row unless explicit pin/reorder: `G-122`, `S02-010`. |
| Not-loaded default visibility | `Not loaded` must be honest and explicit: `G-090` through `G-096`, `S04-020` through `S04-025`. |
