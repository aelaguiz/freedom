---
title: "Codex Dock - Activity-First Requirement Disposition"
date: 2026-05-29
status: active
doc_type: requirement_disposition
related:
  - docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md
  - docs/mockups/codex-dock-activity-first-2026-05-29/README.md
  - docs/mockups/codex-dock-activity-first-2026-05-29/requirements/GLOBAL_REQUIREMENTS.md
  - docs/mockups/codex-dock-activity-first-2026-05-29/requirements/TRACEABILITY_MATRIX.md
---

# Codex Dock Activity-First Requirement Disposition

This sidecar is part of the architecture plan package. It enumerates every formal requirement ID found in `docs/mockups/codex-dock-activity-first-2026-05-29/requirements/**` and assigns a V1 disposition so the implementation plan does not leave requirement IDs implicit.

Canonical implementation plan: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md`.

Disposition vocabulary:

- `Required planned in V1`: the behavior is required and has a named owner in the plan.
- `Required prohibition in V1`: the prohibited behavior is explicitly deleted or prevented.
- `Conditional planned in V1`: the behavior is required when the data/state exists.
- `Planned where data/layout makes it valid`: the behavior is a SHOULD and is carried unless the concrete data/layout makes it invalid.
- `Allowed or preserved when useful`: the behavior is a MAY and is not required for V1 completion unless a specific row says otherwise.
- `Out of V1`, `N/A in Dock V1`, or `Future only`: the plan has made an explicit scope decision.

Total formal requirement IDs enumerated: 394.

## GLOBAL_REQUIREMENTS.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `G-001` | Required planned in V1 | The Dock MUST be an explicit session index over Codex work across hosts, branches, repos, statuses, and time. | Sections 0-1 define product model; Phases 1-4 implement projection, UI, lenses, and filters. |
| `G-002` | Required prohibition in V1 | The Dock MUST NOT present itself as a predictive assistant that guesses the user's current workflow from weak signals. | Sections 0-1 define product model; Phases 1-4 implement projection, UI, lenses, and filters. |
| `G-003` | Required planned in V1 | The default Dock view MUST answer what changed most recently across all configured hosts. | Sections 0-1 define product model; Phases 1-4 implement projection, UI, lenses, and filters. |
| `G-004` | Required planned in V1 | The Dock MUST support known-target lookup by host, branch, repo, status, and text search. | Sections 0-1 define product model; Phases 1-4 implement projection, UI, lenses, and filters. |
| `G-005` | Required planned in V1 | The Dock MUST be designed for thousands of sessions, not a small demo list. | Sections 0-1 define product model; Phases 1-4 implement projection, UI, lenses, and filters. |
| `G-006` | Required planned in V1 | The Dock MUST preserve user trust by showing literal state and visible filters instead of unexplained ranking. | Sections 0-1 define product model; Phases 1-4 implement projection, UI, lenses, and filters. |
| `G-010` | Required planned in V1 | App-level tabs MUST remain stable and limited to top-level destinations such as `Dock`, `Archive`, and `Relay`. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-011` | Required planned in V1 | Dock lenses MUST be Dock-internal controls, not new app-level tabs. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-012` | Required planned in V1 | The required Dock lenses are `Newest`, `Host`, and `Branch`. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-013` | Required planned in V1 | `Filters` MUST be available as a Dock-internal surface or equivalent control. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-014` | Required planned in V1 | `Newest` MUST be the default selected Dock lens on app open. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-015` | Required planned in V1 | `Host` mode MUST answer what is happening on a specific machine. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-016` | Required planned in V1 | `Branch` mode MUST answer where the thread for a branch is across hosts. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-017` | Required planned in V1 | Switching lenses MUST preserve the user's current search text and explicit filters unless the user clears them. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-018` | Required planned in V1 | The selected lens MUST be visually and accessibly clear. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-019` | Required planned in V1 | The legacy `Branch`/`Newest` sort segmented control MUST be retired as a separate primary control; `Newest`, `Host`, and `Branch` are Dock lenses, while sort belongs in the filter/sort surface. | Sections 5.1-5.2 and Phases 2-4 own navigation/lenses/filter surface. |
| `G-020` | Required planned in V1 | The Dock header MUST show the title `Dock`. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-021` | Required planned in V1 | The Dock header MUST show compact global connectivity, for example `Online 2/2` or `Checking 2 hosts`. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-022` | Required planned in V1 | Host health MUST be compact in the Dock header or host lens, not a large pinned content block above the list. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-023` | Required planned in V1 | Search MUST get a full-width row or equivalent system search placement on iPhone. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-024` | Required prohibition in V1 | Search MUST NOT be squeezed into a narrow control beside sort, status, or idle controls. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-025` | Planned where data/layout makes it valid | The search placeholder SHOULD state the searchable dimensions, for example `Search sessions, repo, branch, host`. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-026` | Required planned in V1 | The header MUST expose `Newest`, `Host`, `Branch`, and `Filters` or their equivalent controls. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-027` | Required planned in V1 | The header MUST show active filters in a visible summary row, chips, or tokens. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-028` | Required prohibition in V1 | Header controls MUST not crowd or truncate primary labels on iPhone 17 portrait. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-029` | Required prohibition in V1 | Add-host affordances MUST NOT be large primary Dock-header controls unless the current user task is host setup. | Sections 5.2/5.5 and Phases 2 and 5 own header/search/connectivity layout. |
| `G-029A` | Out of V1 | Header host-count pills MAY appear as compact shortcuts when they do not crowd search or session rows. | Section 3.3 and Decision Log exclude optional host-count shortcut pills; host lookup uses Host lens, host filter, row identity, and compact connectivity. |
| `G-029B` | N/A in V1 | If header host-count pills appear, tapping them MUST apply the corresponding host filter or open the host lens with that host clearly selected. | This only applies if optional host-count pills appear; G-029A is excluded from V1. |
| `G-030` | Required planned in V1 | Search MUST be global by default. | Sections 5.2/6.5 and Phases 1, 2, and 4 own global search behavior and tests. |
| `G-031` | Required planned in V1 | Search MUST match session title, repo or working directory, branch, host display name, latest summary, status, and thread id fragment when those fields are available. | Sections 5.2/6.5 and Phases 1, 2, and 4 own global search behavior and tests. |
| `G-032` | Required planned in V1 | Search MUST compose with filters. | Sections 5.2/6.5 and Phases 1, 2, and 4 own global search behavior and tests. |
| `G-033` | Required planned in V1 | Search results MUST preserve newest-first ordering unless the user chose another explicit sort. | Sections 5.2/6.5 and Phases 1, 2, and 4 own global search behavior and tests. |
| `G-034` | Required planned in V1 | Active search state MUST be visible and clearable. | Sections 5.2/6.5 and Phases 1, 2, and 4 own global search behavior and tests. |
| `G-035` | Required planned in V1 | Search MUST support examples equivalent to `main`, `home main`, `Amir-M5 dock`, `codex-client host settings`, `feature/animation`, and a thread id fragment. | Sections 5.2/6.5 and Phases 1, 2, and 4 own global search behavior and tests. |
| `G-036` | Planned where data/layout makes it valid | Search SHOULD update results as the user types; debounce is allowed for performance, but the user MUST NOT need to submit a separate search command for normal filtering. | Sections 5.2/6.5 and Phases 1, 2, and 4 own global search behavior and tests. |
| `G-040` | Required planned in V1 | Filters MUST be explicit and reversible. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-041` | Required planned in V1 | Filters MUST include host. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-042` | Required planned in V1 | Filters MUST include branch. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-043` | Required planned in V1 | Filters MUST include status. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-044` | Required planned in V1 | Filters MUST include repo or working directory where repo metadata exists. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-045` | Conditional planned in V1 | Filters MUST include source scope such as human vs agent when the data supports it. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-046` | Required planned in V1 | Filters MUST include idle visibility. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-047` | N/A in Dock V1 | Filters MUST include archive visibility when archived sessions can appear in Dock results. | Archive rows stay in ArchiveStore and the Archive app tab; Dock filters must not expose a fake archive toggle. |
| `G-048` | Planned where data/layout makes it valid | Counts SHOULD be shown on filters or summary state when practical. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-049` | Required prohibition in V1 | Counts MUST NOT look final while the app is still loading. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-050` | Required planned in V1 | The user MUST be able to tell what is currently hidden. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-051` | Required prohibition in V1 | Branch lookup MUST NOT be available only through free-text search; branch MUST exist as a real facet or lens. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-052` | Required planned in V1 | Filter reset or clear MUST be available from the filter surface or active-filter summary. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-053` | Required planned in V1 | If both a header filter icon and a `Filters` lens/control are visible, both MUST open the same filter surface and reflect the same active filter state. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-054` | Required prohibition in V1 | The product MUST NOT maintain separate filter models for the header icon and `Filters` control. | Sections 5.3/6.5 and Phase 4 own DockFilterState, facets, counts, and clear behavior. |
| `G-060` | Required planned in V1 | Every Dock row MUST be understandable without remembering a section header far above it. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-061` | Conditional planned in V1 | Every Dock row MUST show title when available. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-062` | Conditional planned in V1 | Every Dock row MUST show status when available. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-063` | Conditional planned in V1 | Every Dock row MUST show last activity time when available. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-064` | Required planned in V1 | Every Dock row MUST show host when more than one host exists. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-065` | Conditional planned in V1 | Every Dock row MUST show branch when available. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-066` | Conditional planned in V1 | Every Dock row MUST show repo or working directory when available. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-067` | Planned where data/layout makes it valid | Every Dock row SHOULD show a short latest-summary snippet when loaded content exists. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-068` | Allowed or preserved when useful | Every Dock row MAY show local label, rail color, or icon if it improves scanning without replacing textual identity. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-069` | Required planned in V1 | Status MUST be a small chip or secondary cue, not the primary organizing principle unless the user chose a status filter. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-070` | Required planned in V1 | Row tap targets MUST open the corresponding thread detail. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-071` | Required planned in V1 | Row text MUST avoid incoherent clipping or overlap on iPhone 17 portrait. | Sections 5.3/6.3/6.6 and Phases 1-2 own row model, row projection, and row UI. |
| `G-080` | Required planned in V1 | Dock scan paths MUST use short display names such as `Amir-M5` and `Home`. | Sections 5.3/6.7 and Phases 1, 3, and 5 own host display names and host-local failure. |
| `G-081` | Required planned in V1 | Raw endpoint strings MUST stay in Relay settings, diagnostics, details, or tooltips, not primary row text. | Sections 5.3/6.7 and Phases 1, 3, and 5 own host display names and host-local failure. |
| `G-082` | Required planned in V1 | Host identity MUST remain visible in rows when branch grouping removes host from the section title. | Sections 5.3/6.7 and Phases 1, 3, and 5 own host display names and host-local failure. |
| `G-083` | Required planned in V1 | Host status failures MUST attach to the affected host or host group. | Sections 5.3/6.7 and Phases 1, 3, and 5 own host display names and host-local failure. |
| `G-084` | Required prohibition in V1 | Offline hosts MUST NOT block scanning or using online hosts. | Sections 5.3/6.7 and Phases 1, 3, and 5 own host display names and host-local failure. |
| `G-090` | Required planned in V1 | The allowed visible Dock status labels are `Running`, `Idle`, `Not loaded`, `Error`, and `Unknown`, plus explicit future statuses approved by product. | Sections 0.5/5.3 and Phases 1, 2, and 4 own status vocabulary and Not loaded semantics. |
| `G-091` | Required prohibition in V1 | The Dock MUST NOT show `Limited`. | Sections 0.5/5.3 and Phases 1, 2, and 4 own status vocabulary and Not loaded semantics. |
| `G-092` | Required planned in V1 | `Not loaded` MUST mean the app has a row or history reference but does not currently know enough loaded thread detail to summarize it. | Sections 0.5/5.3 and Phases 1, 2, and 4 own status vocabulary and Not loaded semantics. |
| `G-093` | Required prohibition in V1 | `Not loaded` MUST NOT imply rate limiting, broken access, user blocking, or a provider failure. | Sections 0.5/5.3 and Phases 1, 2, and 4 own status vocabulary and Not loaded semantics. |
| `G-094` | Required planned in V1 | `Not loaded` MUST be visually neutral. | Sections 0.5/5.3 and Phases 1, 2, and 4 own status vocabulary and Not loaded semantics. |
| `G-095` | Required planned in V1 | `Error` MUST be used only when an actual error is known. | Sections 0.5/5.3 and Phases 1, 2, and 4 own status vocabulary and Not loaded semantics. |
| `G-096` | Required planned in V1 | `Unknown` MUST be used only when status is unavailable and `Not loaded` is not precise enough. | Sections 0.5/5.3 and Phases 1, 2, and 4 own status vocabulary and Not loaded semantics. |
| `G-100` | Required prohibition in V1 | `Needs me` MUST NOT be a primary tab. | Sections 0.5/6.13 and Phases 1-2 own deletion of Needs me/old primary status concepts. |
| `G-101` | Required prohibition in V1 | `Needs me` MUST NOT be a top section. | Sections 0.5/6.13 and Phases 1-2 own deletion of Needs me/old primary status concepts. |
| `G-102` | Required prohibition in V1 | `Needs me` MUST NOT be a default ranking primitive. | Sections 0.5/6.13 and Phases 1-2 own deletion of Needs me/old primary status concepts. |
| `G-103` | Satisfied by stricter deletion | `Needs me` MAY exist only in a secondary or debug path until the signal is reliable, explicit, inspectable, and useful. | V1 removes Needs me from Dock primary/status/filter vocabulary entirely; no debug path is added. |
| `G-104` | Future only | If the concept returns later, it SHOULD use a more literal label such as `Needs input`. | If this concept returns later it needs a new explicit product decision; V1 removes Needs me. |
| `G-105` | Required prohibition in V1 | `Running` MUST NOT be a primary tab if live data shows it is often zero or unreliable. | Sections 0.5/6.13 and Phases 1-2 own deletion of Needs me/old primary status concepts. |
| `G-106` | Allowed or preserved when useful | `Running` MAY be a status filter when reliable. | Sections 0.5/6.13 and Phases 1-2 own deletion of Needs me/old primary status concepts. |
| `G-107` | Required prohibition in V1 | `Agents` MUST NOT be a giant primary count tab. | Sections 0.5/6.13 and Phases 1-2 own deletion of Needs me/old primary status concepts. |
| `G-108` | Conditional planned in V1 | Agent/source scope MUST live in filters when the data supports it. | Sections 0.5/6.13 and Phases 1-2 own deletion of Needs me/old primary status concepts. |
| `G-120` | Required planned in V1 | Newest-first ordering MUST sort by last visible activity. | Sections 5.3/6.5 and Phases 1, 3, and 4 own ordering and literal sort labels. |
| `G-121` | Required planned in V1 | Tie-breakers MUST be deterministic. | Sections 5.3/6.5 and Phases 1, 3, and 4 own ordering and literal sort labels. |
| `G-122` | Required planned in V1 | Host groups MUST sort by newest visible row unless the user explicitly pins or reorders hosts. | Sections 5.3/6.5 and Phases 1, 3, and 4 own ordering and literal sort labels. |
| `G-123` | Required planned in V1 | Branch groups MUST sort by newest visible row. | Sections 5.3/6.5 and Phases 1, 3, and 4 own ordering and literal sort labels. |
| `G-124` | Required planned in V1 | Rows inside host and branch groups MUST sort newest-first unless the user chose another explicit sort. | Sections 5.3/6.5 and Phases 1, 3, and 4 own ordering and literal sort labels. |
| `G-125` | Required planned in V1 | Sort labels MUST be literal enough that the user can distinguish last activity from created date. | Sections 5.3/6.5 and Phases 1, 3, and 4 own ordering and literal sort labels. |
| `G-130` | Required planned in V1 | Loading state MUST show which configured hosts are being checked when host config is known. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-131` | Required prohibition in V1 | Loading state MUST NOT show final-looking zero-count filter tabs. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-132` | Planned where data/layout makes it valid | Loading state SHOULD keep search and lens controls visible so the surface is stable. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-133` | Required planned in V1 | Long loading MUST be treated as a first-class state, not a brief spinner-only gap. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-134` | Required planned in V1 | Partial loading MUST allow loaded hosts or rows to appear before every host finishes. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-135` | Required planned in V1 | Empty states MUST state which filters or hidden states caused emptiness. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-136` | Required planned in V1 | Empty states MUST provide a clear action to clear filters when filters caused the empty result. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-137` | Required planned in V1 | Host failures MUST be local to the affected host or scope, not a global mystery state. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-138` | Required planned in V1 | Host failure UI MUST include explicit failure copy when a failure reason is known. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-139` | Required planned in V1 | Host failure UI MUST provide retry when retry is possible. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-140` | Required planned in V1 | Host failure UI MUST provide a path to Relay settings or host diagnostics. | Sections 5.2/5.5 and Phases 1 and 5 own loading, empty, partial, and failure states. |
| `G-150` | Required planned in V1 | Idle visibility MUST be explicit. | Sections 5.3/6.5 and Phases 4-5 own idle/hidden state and explicit visibility decisions. |
| `G-151` | Required planned in V1 | Hidden idle state MUST be visible in chips, toggles, or summary copy. | Sections 5.3/6.5 and Phases 4-5 own idle/hidden state and explicit visibility decisions. |
| `G-152` | N/A in Dock V1 | Archived visibility MUST be explicit when archived sessions can be included. | Archived sessions cannot appear in Dock results in V1; Archive remains the separate tab. |
| `G-153` | Required planned in V1 | `Not loaded` visibility MUST be explicit if hidden or filtered. | Sections 5.3/6.5 and Phases 4-5 own idle/hidden state and explicit visibility decisions. |
| `G-154` | Required prohibition in V1 | The UI MUST NOT hide rows without explaining why. | Sections 5.3/6.5 and Phases 4-5 own idle/hidden state and explicit visibility decisions. |
| `G-155` | Required prohibition in V1 | The UI MUST NOT auto-predict the active host, active branch, active repo, or important thread. | Sections 5.3/6.5 and Phases 4-5 own idle/hidden state and explicit visibility decisions. |
| `G-156` | Out of V1 | Pinning MAY exist only as explicit user intent and MUST behave as a visible filter. | Pinning is explicitly deferred; future pinning must be visible user intent. |
| `G-170` | Required planned in V1 | Header, search, lens controls, filter controls, host groups, branch groups, rows, status chips, and bottom tabs MUST have accessibility labels or identifiers sufficient for automated verification. | Sections 6.9/6.10/8 and Phases 2-6 own accessibility IDs and simulator/test proof. |
| `G-171` | Required planned in V1 | Accessibility labels MUST use the same product vocabulary as visible labels, including `Not loaded` and excluding `Limited`. | Sections 6.9/6.10/8 and Phases 2-6 own accessibility IDs and simulator/test proof. |
| `G-172` | Required planned in V1 | Accessibility state MUST distinguish selected lens, selected filter chips, toggle values, expanded groups, collapsed groups, and row status. | Sections 6.9/6.10/8 and Phases 2-6 own accessibility IDs and simulator/test proof. |
| `G-173` | Required planned in V1 | Accessibility output during loading MUST describe checking/loading state and configured hosts, not stale zero counts. | Sections 6.9/6.10/8 and Phases 2-6 own accessibility IDs and simulator/test proof. |
| `G-174` | Planned where data/layout makes it valid | Automated tests SHOULD cover the default lens, row host metadata, loading copy, killed terms, and filter availability. | Sections 6.9/6.10/8 and Phases 2-6 own accessibility IDs and simulator/test proof. |

## screens/01-newest-default.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S01-001` | Required planned in V1 | The screen MUST open with `Newest` selected by default. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-002` | Required planned in V1 | The first visible content after the Dock controls MUST be session rows, not large host status cards. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-003` | Required planned in V1 | The visible list MUST be a flat newest-first list across all included hosts. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-004` | Required planned in V1 | The selected `Newest` control MUST be visually and accessibly distinct from `Host`, `Branch`, and `Filters`. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-005` | Required planned in V1 | The header MUST show `Dock`, compact connectivity such as `Online 2/2`, full-width search, and Dock-internal lens controls. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-006` | Required planned in V1 | The search field MUST use a placeholder equivalent to `Search sessions, repo, branch, host`. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-007` | Conditional planned in V1 | Active filter summary MUST show at least host scope, branch scope, idle visibility, and result count when data is loaded. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-008` | Required planned in V1 | Default host scope MUST be `Any` unless the user explicitly filters or pins a host. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-009` | Required planned in V1 | Default branch scope MUST be `Any` unless the user explicitly filters or pins a branch. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-010` | Required planned in V1 | Idle visibility MUST be visible as `Idle: Off`, `Hide idle`, or equivalent when idle rows are hidden. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-011` | Required planned in V1 | Result count MUST describe visible results, not total cached or hidden rows. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-012` | Planned in V1 | The list MUST NOT show a `NEWEST` section header if it wastes vertical space; a header is allowed only if it improves accessibility or scanability. | Newest uses selected lens state and active summary; no visible NEWEST section header by default unless accessibility/scanability proves it helps without wasting vertical space. |
| `S01-020` | Conditional planned in V1 | Each row MUST show a meaningful title when available. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-021` | Required planned in V1 | Each row MUST show host when more than one host exists. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-022` | Conditional planned in V1 | Each row MUST show repo or working directory when available. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-023` | Conditional planned in V1 | Each row MUST show branch when available. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-024` | Required planned in V1 | Each row MUST show a small status chip such as `Idle`, `Running`, `Not loaded`, `Error`, or `Unknown`. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-025` | Conditional planned in V1 | Each row MUST show last activity time when available. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-026` | Planned where data/layout makes it valid | Each loaded row SHOULD show a short latest-summary snippet. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-027` | Allowed or preserved when useful | Rows MAY use colored rails or icons as scan aids, but text identity MUST remain sufficient without color. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-028` | Required planned in V1 | Rows MUST have a clear tap affordance or row navigation affordance. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-029` | Required planned in V1 | A `Not loaded` row MUST remain in the list unless the user hides `Not loaded` through an explicit filter. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-030` | Required prohibition in V1 | `Not loaded` MUST appear as a neutral status chip and MUST NOT be styled like an error. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-040` | Required planned in V1 | Rows MUST sort by newest last activity first. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-041` | Required prohibition in V1 | `Needs me` MUST NOT reorder rows. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-042` | Required prohibition in V1 | Host order MUST NOT split the default feed. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-043` | Required prohibition in V1 | Branch grouping MUST NOT split the default feed. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-044` | Required planned in V1 | Idle and not-loaded rows MUST follow the same sorting rules unless hidden by an explicit filter. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-060` | Required prohibition in V1 | The screen MUST NOT show `Needs me`. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-061` | Required prohibition in V1 | The screen MUST NOT show `Limited`. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-062` | Required prohibition in V1 | The screen MUST NOT show `All 0`, `Needs me 0`, `Running 0`, or `Agents 0` as primary controls. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-063` | Required prohibition in V1 | The screen MUST NOT show raw endpoint strings in row metadata. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |
| `S01-064` | Required prohibition in V1 | The screen MUST NOT make host health larger or more prominent than the newest session rows. | Sections 5.2/5.5 and Phases 2 and 6 own Newest default proof. |

## screens/02-host-lens.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S02-001` | Required planned in V1 | Selecting `Host` MUST switch Dock into host-grouped mode. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-002` | Required planned in V1 | The selected `Host` control MUST be visually and accessibly distinct. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-003` | Required planned in V1 | Host groups MUST be visible as compact section headers. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-004` | Required planned in V1 | Host headers MUST use short display names such as `Amir-M5` and `Home`. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-005` | Required prohibition in V1 | Host headers MUST NOT use raw endpoint strings as their primary label. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-006` | Required planned in V1 | Host headers MUST show connection state when known. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-007` | Conditional planned in V1 | Host headers MUST show visible session count when data is loaded. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-008` | Planned where data/layout makes it valid | Host headers SHOULD show newest visible activity time, for example `Updated 2m ago`. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-009` | Required planned in V1 | Host headers MUST support collapsed and expanded states. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-010` | Required planned in V1 | Host groups MUST sort by newest visible row unless the user explicitly pins or reorders hosts. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-011` | Required planned in V1 | Rows inside each host group MUST sort newest-first. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-012` | Required planned in V1 | Host groups MUST be visually nested without becoming giant pinned cards. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-013` | Permitted style detail | Host group containers MAY use subtle rails, indentation, separators, or tinted backgrounds to show nesting. | Subtle rails, indentation, separators, or tint are allowed, but not required; host lens must remain compact and scroll-efficient. |
| `S02-014` | Required planned in V1 | Host mode MUST remain scroll-efficient for thousands of sessions. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-015` | Conditional planned in V1 | Host headers MUST show running count when reliable running data exists. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-016` | Required planned in V1 | Host headers MUST show hidden idle state, for example `idle hidden`, when idle rows are hidden for that host. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-017` | Required planned in V1 | Host header metadata MUST stay compact enough that it does not push session rows out of the first viewport when rows exist. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-018` | Required planned in V1 | Offline hosts MUST remain visible in Host mode and MUST be collapsed by default when they have no current visible rows. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-020` | Required planned in V1 | Rows MUST be nested under the correct host group. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-021` | Planned where data/layout makes it valid | Rows SHOULD still include host metadata when it improves scanability or accessibility, even though host is in the header. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-022` | Conditional planned in V1 | Rows MUST include title, repo or working directory, branch, status, and last activity time when available. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-023` | Required planned in V1 | Row status chips MUST use approved labels such as `Idle` and `Not loaded`. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-024` | Required planned in V1 | Rows MUST retain a clear navigation affordance. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-025` | Required prohibition in V1 | Rows MUST not require endpoint knowledge to identify the machine. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-040` | Partially planned | Host headers MAY include refresh, filter, diagnostic, expand, or collapse actions. | Expand/collapse is required; failure UI provides Retry and Relay settings. Extra refresh/filter/diagnostic host-header actions are not required in V1. |
| `S02-041` | Required planned in V1 | Host-header actions MUST have accessible labels. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-042` | Required planned in V1 | The host header's expand/collapse control MUST be the primary way to collapse or expand the group. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-043` | Required planned in V1 | Tapping a host-name chip or explicit filter affordance MUST filter to that host. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-044` | Required prohibition in V1 | Tapping the host header background MUST NOT ambiguously alternate between filtering and expanding. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-045` | Out of V1 | Long-press host actions MAY exist for diagnostics or Relay settings. | Long-press host diagnostics are optional and not part of V1; visible Retry/Relay settings are required for failures. |
| `S02-046` | Required planned in V1 | Offline or failed host detail MUST be local to that host group. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-060` | Required prohibition in V1 | The host lens MUST NOT recreate the old detached host-summary-above-list pattern. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-061` | Required prohibition in V1 | The host lens MUST NOT show `Needs me` as a primary category. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-062` | Required prohibition in V1 | The host lens MUST NOT show `Limited`. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-063` | Required prohibition in V1 | The host lens MUST NOT place endpoint strings in the main scan path. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |
| `S02-064` | Required prohibition in V1 | Host status MUST NOT push all session rows below the first viewport when rows exist. | Sections 5.2/5.5 and Phase 3 own Host lens grouping, actions, and proof. |

## screens/03-branch-lens.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S03-001` | Required planned in V1 | Selecting `Branch` MUST switch Dock into branch-grouped mode. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-002` | Required planned in V1 | The selected `Branch` control MUST be visually and accessibly distinct. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-003` | Required planned in V1 | Branch groups MUST be visible as compact section headers. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-004` | Required planned in V1 | Branch group headers MUST show branch name. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-005` | Conditional planned in V1 | Branch group headers MUST show visible session count when data is loaded. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-006` | Conditional planned in V1 | Branch group headers MUST show newest visible activity time when available. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-007` | Required planned in V1 | Branch group headers MUST show which hosts have visible rows for that branch. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-008` | Required planned in V1 | Branch groups MUST support expanded and collapsed states. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-009` | Required planned in V1 | Branch groups MUST sort by newest visible row. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-010` | Required planned in V1 | Rows inside each branch group MUST sort newest-first. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-011` | Required planned in V1 | The branch lens MUST preserve active search and filters. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-012` | Conditional planned in V1 | The screen MUST show active filter summary or chips, including host scope, status scope, idle visibility, and visible total when data is loaded. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-020` | Required planned in V1 | Rows MUST include host because branch grouping removes host from the section title. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-021` | Conditional planned in V1 | Rows MUST include repo or working directory when available. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-022` | Conditional planned in V1 | Rows MUST include title, status, and last activity time when available. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-023` | Planned where data/layout makes it valid | Rows SHOULD include a short summary when loaded detail exists. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-024` | Required planned in V1 | Host chips or metadata MUST use short host display names. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-025` | Required prohibition in V1 | Rows MUST not rely on color or icon alone to communicate host. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-040` | Required planned in V1 | Branch search MUST support exact branch names such as `main`. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-041` | Required planned in V1 | Branch search MUST support partial branch fragments such as `dock`. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-042` | Required planned in V1 | Branch search MUST support slash branch names such as `feature/dock`. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-043` | Required planned in V1 | Branch search MUST support repo plus branch queries. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-044` | Required planned in V1 | Branch search MUST support host plus branch queries. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-045` | Required planned in V1 | Branch names MUST fit, wrap, or truncate gracefully without breaking controls. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-046` | Allowed or preserved when useful | Popular or recent branch chips MAY be shown as shortcuts. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-060` | Required prohibition in V1 | Branch mode MUST NOT be the default app-open state. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-061` | Required prohibition in V1 | Branch mode MUST NOT hide host identity in rows. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-062` | Required prohibition in V1 | Branch mode MUST NOT show `Needs me` as a primary category. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-063` | Required prohibition in V1 | Branch mode MUST NOT show `Limited`. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |
| `S03-064` | Required prohibition in V1 | Branch mode MUST NOT require free-text search as the only way to locate a branch. | Sections 5.2/5.5 and Phases 3-4 own Branch lens/search behavior. |

## screens/04-loading-not-loaded.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S04-001` | Required planned in V1 | During initial loading, the header MUST show a checking/loading connectivity state such as `Checking 2 hosts`. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-002` | Required planned in V1 | Loading state MUST show known configured hosts when host config is available. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-003` | Required planned in V1 | Known hosts MUST use short display names such as `Amir-M5` and `Home`. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-004` | Required planned in V1 | Each known host row MUST show its loading/checking state. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-005` | Conditional only | Host loading rows MAY show service scope, for example `Codex`, if accurate. | Service scope may appear only if accurate; V1 required loading identity is host display name plus checking/loading status. |
| `S04-006` | Required planned in V1 | Loading state MUST keep the Dock title, search row, lens controls, and bottom tabs stable. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-007` | Allowed, not default | Search MAY be disabled during loading, but it MUST remain visually understandable. | Search remains visually understandable; V1 preserves search behavior over loaded subsets when data is available. |
| `S04-008` | Planned where data/layout makes it valid | `Newest` SHOULD remain selected during loading because it is the default lens. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-009` | Rejected V1 equivalent chosen | Loading state SHOULD show skeleton rows when row content is not ready. | V1 uses per-host loading rows plus neutral loading copy instead of fake session skeleton rows that could look like real threads. |
| `S04-010` | Planned in V1 | Loading state MAY show already loaded rows mixed with skeleton or not-loaded rows if partial results exist. | Partial loaded rows may appear while other hosts are checking; fake skeleton session rows are not used. |
| `S04-011` | Required planned in V1 | Partial loading MUST allow one host to show results while another host is still checking. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-020` | Required planned in V1 | The UI MUST use `Not loaded` for rows whose thread detail is unavailable. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-021` | Required planned in V1 | The UI MUST include explanatory copy when the whole list or major scope is not loaded, for example `Sessions not loaded yet` and `Waiting for relay response`. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-022` | Required planned in V1 | `Not loaded` MUST be neutral copy, not an error, warning, or rate-limit message. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-023` | Allowed or preserved when useful | Skeleton rows with unknown content MAY show `Not loaded` status. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-024` | Required prohibition in V1 | Rows with loaded content MUST not be downgraded to `Not loaded`. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-025` | Required planned in V1 | A host transport failure MUST use host-local error state, not `Not loaded`, when an actual error is known. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-040` | Required prohibition in V1 | Loading state MUST NOT show `Limited`. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-041` | Required prohibition in V1 | Loading state MUST NOT imply Codex or OpenAI rate limits unless the app has explicit rate-limit evidence. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-042` | Required prohibition in V1 | Loading state MUST NOT show `All 0`, `Needs me 0`, `Running 0`, or `Agents 0` as final-looking primary tabs. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-043` | Required prohibition in V1 | Loading state MUST NOT show only one host when multiple configured hosts are known. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-044` | Required prohibition in V1 | Loading state MUST NOT make raw endpoint strings the dominant host identity. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |
| `S04-045` | Required prohibition in V1 | Loading state MUST NOT hide online host rows behind an offline host failure. | Sections 5.2/5.5 and Phases 1 and 5 own loading and Not loaded state. |

## screens/05-filters.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S05-001` | Required planned in V1 | Selecting `Filters` or the equivalent filter control MUST open the Dock filter surface. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-002` | Required planned in V1 | The filter surface MUST remain within the Dock context, not become a top-level app tab. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-003` | Required planned in V1 | The selected `Filters` control MUST be visually and accessibly distinct when the filter surface is active. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-004` | Required planned in V1 | The filter surface MUST show visible result summary, for example `1,178 shown`. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-005` | Required planned in V1 | The filter surface MUST show whether filters are currently applied. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-006` | Required planned in V1 | The filter surface MUST provide `Reset`, `Clear`, or equivalent. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-007` | N/A in V1 | If the surface uses staged changes, it MUST provide `Apply`. | The filter surface applies immediately; staged Apply is not used. |
| `S05-008` | Required prohibition in V1 | If the surface applies changes immediately, it MUST not show a misleading inactive `Apply` button. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-009` | Required planned in V1 | The filter surface MUST preserve the full-width global search field above or inside the filter context. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-010` | Required planned in V1 | If both the header filter icon and `Filters` lens/control are visible, they MUST open the same filter surface. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-011` | Required planned in V1 | If both the header filter icon and `Filters` lens/control are visible, active filter count or selected state MUST stay synchronized between them. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-020` | Required planned in V1 | Host filter MUST include `Any`. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-021` | Required planned in V1 | Host filter MUST include each configured host with short display names. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-022` | Planned where data/layout makes it valid | Host filter SHOULD show counts or availability when practical. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-023` | Required planned in V1 | Branch filter MUST include branch search. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-024` | Planned where data/layout makes it valid | Branch filter SHOULD show popular, recent, or matching branch chips. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-025` | Required planned in V1 | Branch filter MUST support selecting a branch chip. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-026` | Required planned in V1 | Status filter MUST include `Any`. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-027` | Conditional planned in V1 | Status filter MUST include `Running` when reliable data exists. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-028` | Required planned in V1 | Status filter MUST include `Idle`. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-029` | Required planned in V1 | Status filter MUST include `Not loaded`. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-030` | Required planned in V1 | Status filter MUST include `Error` when error rows exist. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-031` | Required planned in V1 | Repository filter MUST include available repos or working directories. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-032` | Required planned in V1 | Repository filter MUST include an all-repos state. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-033` | Conditional planned in V1 | Source filter MUST include human and agent scope when source data is available, even if the mockup labels this area as repository only. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-034` | Required planned in V1 | Sort controls MUST include newest last activity as the default. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-035` | Out of V1 | Sort controls MAY include created date. | Created-date sort is not exposed because SessionSummary has no distinct normalized created date. |
| `S05-036` | Out of V1 | Sort controls MAY include updated date only if it is clearly distinct from newest last activity. | Updated-date sort is not exposed separately from newest last activity in V1. |
| `S05-037` | Required planned in V1 | Visibility controls MUST include idle visibility. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-038` | N/A in Dock V1 | Visibility controls MUST include archive visibility when archived sessions can be shown. | Archived sessions cannot appear in Dock results in V1. |
| `S05-039` | Satisfied via status filter | Visibility controls MAY include not-loaded-only or show-not-loaded behavior if product chooses to expose it. | Not-loaded-only behavior is provided by selecting only Status: Not loaded; no second visibility owner is added. |
| `S05-040` | Required planned in V1 | If the user filters to `Not loaded` only, the results area MUST show explanatory copy that these sessions exist but Dock does not have loaded thread detail for them. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-041` | Required planned in V1 | If a `Not loaded`-only result section is shown, its section label MUST use `Not loaded`, not `Limited`. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-050` | Required planned in V1 | Filters MUST compose with search. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-051` | Required planned in V1 | Filters MUST compose with the selected lens. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-052` | Required planned in V1 | Applying a host filter MUST update newest, host, and branch views consistently. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-053` | Required planned in V1 | Applying a branch filter MUST update newest, host, and branch views consistently. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-054` | Required prohibition in V1 | Applying a status filter MUST not change the meaning of status labels. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-055` | Required planned in V1 | Reset MUST restore the default explicit state. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-056` | Conditional planned in V1 | Filter changes MUST update visible result count when practical. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-057` | Required planned in V1 | The active filter summary outside the filter surface MUST reflect applied filters after the surface closes. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-058` | Required planned in V1 | Filter controls MUST be touch-friendly while preserving dense information layout. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-070` | Required prohibition in V1 | Filters MUST NOT include `Needs me` as a default or primary filter. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-071` | Required prohibition in V1 | Filters MUST NOT show `Limited`. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-072` | Required prohibition in V1 | Filters MUST NOT hide branch behind search-only behavior. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-073` | Required prohibition in V1 | Filters MUST NOT use raw endpoint strings as host chip labels. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-074` | Required prohibition in V1 | Filters MUST NOT apply hidden constraints that are absent from summary state. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |
| `S05-075` | Required prohibition in V1 | Filters MUST NOT use ambiguous sort labels without a clear mapping to data fields. | Sections 5.2/5.3/6.5 and Phase 4 own filter surface behavior. |

## screens/06-branch-search-results.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S06-001` | Required planned in V1 | Entering a branch query such as `dock-ui` MUST show an active search state. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-002` | Required planned in V1 | Active search state MUST be visible as a chip, row, or equivalent summary, for example `Search: dock-ui`. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-003` | Required planned in V1 | Active search state MUST be clearable from the results screen. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-004` | Conditional planned in V1 | Branch search results MUST show visible result count when data is loaded. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-005` | Rejected V1 alternative | Branch search MAY flatten results into one newest-first result list even when the `Branch` lens is selected. | Branch search preserves the selected lens grouping rather than flattening sometimes. |
| `S06-006` | Planned in V1 | If branch search preserves groups instead of flattening, the UI MUST still make the active search state and result count obvious. | Because grouping is preserved, active search state and result count must remain obvious. |
| `S06-007` | Planned in V1 | The chosen branch-search presentation MUST be consistent and documented; it MUST NOT sometimes flatten and sometimes group without visible reason. | Chosen presentation is documented: global search filters rows and preserves the selected lens grouping. |
| `S06-008` | Partially planned / archive N/A | Branch search results MUST preserve active host, status, idle, repo, source, and archive filters. | Host, status, idle, repo, and source filters are preserved; archive filter is N/A because Dock V1 has no archived rows. |
| `S06-009` | Required planned in V1 | Branch search results MUST keep host visible on every row. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-010` | Required planned in V1 | Branch search results MUST keep branch visible on every row or in an active search token that is visually tied to the result list. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-020` | Required planned in V1 | Branch search MUST match exact branch names. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-021` | Required planned in V1 | Branch search MUST match branch fragments. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-022` | Required planned in V1 | Branch search MUST match slash-separated branch names. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-023` | Required planned in V1 | Branch search MUST support repo plus branch. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-024` | Required planned in V1 | Branch search MUST support host plus branch. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-025` | Planned in V1 | Branch search MUST support case-insensitive matching unless there is a product reason to expose case sensitivity. | Search matching must be case-insensitive unless a later product decision explicitly makes it case-sensitive. |
| `S06-026` | Required planned in V1 | Branch search MUST handle long branch names without breaking layout. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-030` | Conditional planned in V1 | Result rows MUST show title when available. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-031` | Required planned in V1 | Result rows MUST show host when more than one host exists. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-032` | Conditional planned in V1 | Result rows MUST show repo or working directory when available. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-033` | Conditional planned in V1 | Result rows MUST show branch when available. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-034` | Conditional planned in V1 | Result rows MUST show status when available. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-035` | Conditional planned in V1 | Result rows MUST show last activity time when available. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-036` | Planned where data/layout makes it valid | Result rows SHOULD show a short latest-summary snippet when loaded detail exists. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-037` | Required planned in V1 | Result rows MUST sort newest-first unless the user chose another explicit sort. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-040` | Required planned in V1 | Empty branch-search results MUST state the query and active filters that caused emptiness. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-041` | Required planned in V1 | Empty branch-search results MUST provide a clear action to clear the search or clear filters. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-042` | Required prohibition in V1 | Partial host failures MUST not hide matches from online hosts. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-043` | Required planned in V1 | Not-loaded matches MUST appear with `Not loaded` unless hidden by an explicit filter. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-044` | Required prohibition in V1 | Not-loaded matches MUST not imply rate limits. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-050` | Required prohibition in V1 | Branch search results MUST NOT show `Limited`. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-051` | Required prohibition in V1 | Branch search results MUST NOT show `Needs me` as a primary category. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-052` | Required prohibition in V1 | Branch search results MUST NOT rely on endpoint strings as host identity. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-053` | Required prohibition in V1 | Branch search MUST NOT be buried only inside the filter sheet. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |
| `S06-054` | Required prohibition in V1 | Branch search MUST NOT require the user to first select the correct host. | Sections 5.2/5.3/6.5 and Phase 4 own branch search results. |

## screens/07-host-offline-partial-failure.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S07-001` | Required planned in V1 | Offline host state MUST attach to the affected host. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-002` | Required planned in V1 | Offline host state MUST use the host display name, not the raw endpoint, as the primary label. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-003` | Required planned in V1 | Offline host state MUST show an explicit status such as `Offline`, `Error`, or `Checking`. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-004` | Required planned in V1 | If a failure reason is known, the UI MUST show concise failure copy, for example `Last check failed: connection timed out`. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-005` | Required planned in V1 | Offline host state MUST provide `Retry` when retry is possible. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-006` | Required planned in V1 | Offline host state MUST provide a path to `Relay settings`, host settings, or diagnostics. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-007` | Required planned in V1 | Offline host details MUST be collapsed by default when no current rows exist. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-008` | Required planned in V1 | Offline host details MUST be expandable when there is actionable detail. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-009` | Required planned in V1 | Offline host controls MUST have accessible labels. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-020` | Required planned in V1 | Online host rows MUST remain visible and usable when another host is offline. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-021` | Allowed or preserved when useful | The global connectivity chip MAY show partial state such as `Online 1/2`. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-022` | Required prohibition in V1 | Partial failure MUST NOT clear the entire Dock list. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-023` | Required prohibition in V1 | Partial failure MUST NOT produce final-looking zero counts for unaffected hosts. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-024` | Required planned in V1 | Search and filters MUST continue to work on available data during partial failure. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-025` | Required planned in V1 | Host, branch, and newest lenses MUST each preserve the local failure state while showing available rows. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-030` | Required planned in V1 | Use `Offline` when the host is known unreachable. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-031` | Required planned in V1 | Use `Error` when a concrete host or relay error is known. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-032` | Required planned in V1 | Use `Checking` while the app is still attempting to determine status. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-033` | Required planned in V1 | Use `Not loaded` only for missing thread detail, not for known host transport failure. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-034` | Required planned in V1 | Do not use `Limited`. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-040` | Required prohibition in V1 | Host failure MUST NOT appear as a global mystery banner without host attribution. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-041` | Required prohibition in V1 | Host failure MUST NOT imply OpenAI or Codex rate limits unless explicit rate-limit evidence exists. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-042` | Required prohibition in V1 | Host failure MUST NOT hide online hosts. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-043` | Required prohibition in V1 | Host failure MUST NOT force the user into Relay unless they choose the settings/diagnostics path. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-044` | Required prohibition in V1 | Host failure MUST NOT use raw endpoint strings as primary visible identity. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |
| `S07-045` | Required prohibition in V1 | Host failure MUST NOT resurrect `Needs me`, `Limited`, or primary zero-count tabs. | Sections 5.5 and Phases 3 and 5 own partial host failure behavior. |

## screens/08-filtered-empty.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S08-001` | Required planned in V1 | Empty results caused by filters MUST say no sessions match the current filters. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-002` | Required planned in V1 | Empty results caused by search MUST show the active search query. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-003` | Required planned in V1 | Empty results caused by host filter MUST show the active host filter. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-004` | Required planned in V1 | Empty results caused by branch filter MUST show the active branch filter. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-005` | Required planned in V1 | Empty results caused by idle visibility MUST show idle visibility state. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-006` | Required planned in V1 | Empty results caused by status filter MUST show the active status filter. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-007` | Required planned in V1 | Empty results caused by repo or source filter MUST show that active filter when applied. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-008` | Required planned in V1 | Empty state MUST provide a clear action to clear filters. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-009` | Planned where data/layout makes it valid | Empty state SHOULD provide a clear action to clear only search when search is active. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-010` | Required planned in V1 | Empty state MUST preserve the header, search field, lens controls, and bottom tabs. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-020` | Required planned in V1 | Clearing filters MUST restore default explicit state without changing app-level tab. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-021` | Required planned in V1 | Clearing search MUST preserve non-search filters unless the user chooses clear all. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-022` | Required planned in V1 | The selected lens MUST remain visible in empty state. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-023` | Required planned in V1 | Empty state MUST update when filters or search change. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-024` | Required prohibition in V1 | Empty state MUST not imply host failure unless a host failure is actually known. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-025` | Required prohibition in V1 | Empty state MUST not imply rate limiting. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-030` | Planned where data/layout makes it valid | Primary copy SHOULD be equivalent to `No sessions match these filters`. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-031` | Planned where data/layout makes it valid | Secondary copy SHOULD list active constraints compactly, for example `Host: Amir-M5`, `Branch: dock-ui`, and `Idle: Off`. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-032` | Planned where data/layout makes it valid | Clear action copy SHOULD be equivalent to `Clear filters`. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-033` | Required planned in V1 | Copy MUST use the same filter names as the rest of Dock. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-040` | Required prohibition in V1 | Empty state MUST NOT show `Limited`. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-041` | Required prohibition in V1 | Empty state MUST NOT show `Needs me` as a suggested default recovery path. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-042` | Required prohibition in V1 | Empty state MUST NOT hide which filter caused the empty result. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-043` | Required prohibition in V1 | Empty state MUST NOT clear filters automatically. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-044` | Required prohibition in V1 | Empty state MUST NOT navigate away from Dock automatically. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |
| `S08-045` | Required prohibition in V1 | Empty state MUST NOT use raw endpoint strings as primary host names. | Sections 5.5/6.5 and Phase 4 own filtered empty behavior. |

## screens/09-not-loaded-filter-results.md

| ID | Disposition | Requirement | Plan owner / proof path |
| --- | --- | --- | --- |
| `S09-001` | Required planned in V1 | Filtering to not-loaded rows MUST show a visible `Not loaded` state or section label. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-002` | Required planned in V1 | The screen MUST explain that these sessions exist in the list. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-003` | Required planned in V1 | The screen MUST explain that Dock does not have loaded thread detail for them. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-004` | Required planned in V1 | The screen MUST keep matching not-loaded rows visible unless another explicit filter hides them. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-005` | Required planned in V1 | The screen MUST show active filters and search state. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-006` | Required planned in V1 | The screen MUST provide a way to clear the not-loaded filter. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-007` | Conditional planned in V1 | The screen MUST preserve host, branch, repo, and last-known activity metadata when available. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-008` | Required planned in V1 | The screen MUST keep host identity visible for multi-host lists. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-009` | Required planned in V1 | The screen MUST keep the selected lens visible. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-020` | Required planned in V1 | Not-loaded rows MUST use the `Not loaded` status chip. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-021` | Conditional only | Not-loaded rows MAY use skeleton text only for unknown content. | Skeleton text may be used only for unknown content; V1 does not render fake session skeleton rows during loading. |
| `S09-022` | Required planned in V1 | Not-loaded rows MUST show known title or thread id fallback when title is unavailable. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-023` | Required planned in V1 | Not-loaded rows MUST show known host metadata. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-024` | Conditional planned in V1 | Not-loaded rows MUST show known branch metadata when available. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-025` | Required planned in V1 | Not-loaded rows MUST remain navigable if thread detail can be fetched after tap. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-030` | Planned where data/layout makes it valid | Explanation copy SHOULD be equivalent to `These sessions exist in the list, but Dock does not have loaded thread detail for them.` | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-031` | Required planned in V1 | Copy MUST be neutral. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-032` | Required prohibition in V1 | Copy MUST NOT imply rate limiting. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-033` | Required prohibition in V1 | Copy MUST NOT imply user action is required unless a concrete action is known. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-040` | Required prohibition in V1 | The screen MUST NOT show `Limited`. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-041` | Required prohibition in V1 | The screen MUST NOT use `Rate limited` unless explicit rate-limit evidence exists. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-042` | Required prohibition in V1 | The screen MUST NOT use `Needs me`. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-043` | Required prohibition in V1 | The screen MUST NOT show not-loaded rows as errors. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-044` | Required prohibition in V1 | The screen MUST NOT hide host or branch metadata that is already known. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |
| `S09-045` | Required prohibition in V1 | The screen MUST NOT use raw endpoint strings as primary host names. | Sections 5.3/5.5 and Phase 4 own Not loaded filter results. |

## Explicit V1 Decisions From The Matrix

- `S01-012`: Do not show a visible `NEWEST` section header by default; the selected lens and active summary provide the mode identity. A non-wasting accessibility-only/group label remains allowed if needed for VoiceOver clarity.
- `S06-005` through `S06-007`: Branch search preserves the selected lens grouping in V1. It does not sometimes flatten and sometimes group.
- `S06-025`: Branch/search matching is case-insensitive in V1 unless a later product decision explicitly makes it case-sensitive.
- `G-103`: `Needs me` is removed from V1 entirely rather than kept as a debug-only Dock concept.
- `G-029A`, `G-029B`, and `G-156`: optional host-count shortcut pills and pinning are out of V1.
- `G-047`, `G-152`, `S05-038`, and the archive part of `S06-008`: archive visibility is N/A in Dock V1 because archived sessions remain in `ArchiveStore` and the `Archive` tab.
- `S04-009`: fake session skeleton rows are rejected in V1; loading uses per-host loading rows and neutral copy.
