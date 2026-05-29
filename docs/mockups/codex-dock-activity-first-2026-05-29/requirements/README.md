# Codex Dock Activity-First Requirements

Date: 2026-05-29

This package decomposes the activity-first Dock strategy and generated mockups into implementable requirements.

## Source Artifacts

- Strategy doc: `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md`
- Mockup index: `docs/mockups/codex-dock-activity-first-2026-05-29/README.md`
- Default newest mockup: `../outputs/01-newest-default.png`
- Host lens mockup: `../outputs/02-host-lens.png`
- Branch lens mockup: `../outputs/03-branch-lens.png`
- Loading and not-loaded mockup: `../outputs/04-loading-not-loaded.png`
- Filters mockup: `../outputs/05-filters.png`

## File Map

- `GLOBAL_REQUIREMENTS.md` - product-wide requirements that apply across Dock screens.
- `screens/01-newest-default.md` - requirements for the default newest-first Dock view.
- `screens/02-host-lens.md` - requirements for the host-grouped Dock lens.
- `screens/03-branch-lens.md` - requirements for the branch-grouped Dock lens.
- `screens/04-loading-not-loaded.md` - requirements for loading, partial loading, and not-loaded states.
- `screens/05-filters.md` - requirements for the filter surface.
- `screens/06-branch-search-results.md` - requirements for branch-search result state from the strategy doc ASCII screen set.
- `screens/07-host-offline-partial-failure.md` - requirements for host-local offline/error state from the strategy doc empty and partial states.
- `screens/08-filtered-empty.md` - requirements for empty results caused by active search or filters.
- `screens/09-not-loaded-filter-results.md` - requirements for the not-loaded-only result state.
- `TRACEABILITY_MATRIX.md` - map from source evidence to requirement ids.

## Requirement Language

- `MUST` means the product is not acceptable without this behavior.
- `MUST NOT` means the product direction is explicitly killed.
- `SHOULD` means expected unless implementation evidence proves a better equivalent.
- `MAY` means allowed but not required.

## Product Scope

The Dock is a fast, explicit, high-information index over Codex sessions across multiple hosts. It is not a predictive assistant. The primary job is to answer:

```text
What changed most recently, where is it running, and how do I quickly narrow this giant list by host, branch, repo, or status?
```

The requirements assume a real data scale of thousands of sessions, including the observed iPhone 17 simulator state where the Dock loaded 6,494 rows across two configured relay hosts.

## Non-Requirements From The Mockups

The generated images are product-direction references, not pixel-perfect implementation specs.

- Exact sample thread titles are illustrative.
- Exact sample counts such as `1,178 shown`, `5,321 sessions`, and `6,499 total` are illustrative unless a requirement explicitly talks about count behavior.
- The iPhone status bar time, battery, and Dynamic Island are not Dock product requirements.
- The exact icon artwork may change if the semantic role and accessibility label remain clear.
- The exact card border radius, shadows, and color values may change if density, scanability, and state contrast are preserved.
- GPT-generated visual mistakes do not override the written strategy or requirements.

## Completion Gates

A future implementation is not complete until evidence proves all of these gates:

- The top-level README kill list remains true in the running UI.
- `GLOBAL_REQUIREMENTS.md` requirements are either implemented or explicitly deferred by product decision.
- Each generated mockup and strategy-doc screen state has an implementation or verified equivalent path.
- A live iPhone 17 simulator run shows `Newest` as the default Dock view.
- A live iPhone 17 simulator run shows a full-width search field, not the previous narrow search control.
- Multi-host rows visibly carry host identity in the row itself.
- Loading state uses known hosts and honest loading copy, not final-looking zero-count tabs.
- The visible Dock UX contains `Not loaded` and does not contain `Limited`.
- The primary Dock UX does not contain `Needs me`.
- Host, branch, status, repo/source, idle, and archive filters are visible and reversible where implemented.
- Accessibility identifiers or labels expose enough structure to verify header, lens, filters, host groups, branch groups, and rows without screenshots.

## Fresh Consult Requirement

This package is not considered done until a fresh read-only consult using Cursor Agent `composer-2.5-fast` returns `VERDICT: pass` or `VERDICT: pass-with-notes` for the question:

```text
Are these requirements exhaustively specified from the referenced mockups and UX plan docs, including global requirements, one file per screen, and the top-level kill list?
```

Any blocking consult finding must be patched or explicitly resolved before this requirements package can be treated as accepted.
