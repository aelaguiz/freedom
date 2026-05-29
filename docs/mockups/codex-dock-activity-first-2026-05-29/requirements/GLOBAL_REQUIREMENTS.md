# Global Requirements

Source package: `docs/mockups/codex-dock-activity-first-2026-05-29`

## Product Model

- `G-001` The Dock MUST be an explicit session index over Codex work across hosts, branches, repos, statuses, and time.
- `G-002` The Dock MUST NOT present itself as a predictive assistant that guesses the user's current workflow from weak signals.
- `G-003` The default Dock view MUST answer what changed most recently across all configured hosts.
- `G-004` The Dock MUST support known-target lookup by host, branch, repo, status, and text search.
- `G-005` The Dock MUST be designed for thousands of sessions, not a small demo list.
- `G-006` The Dock MUST preserve user trust by showing literal state and visible filters instead of unexplained ranking.

## Navigation And Information Architecture

- `G-010` App-level tabs MUST remain stable and limited to top-level destinations such as `Dock`, `Archive`, and `Relay`.
- `G-011` Dock lenses MUST be Dock-internal controls, not new app-level tabs.
- `G-012` The required Dock lenses are `Newest`, `Host`, and `Branch`.
- `G-013` `Filters` MUST be available as a Dock-internal surface or equivalent control.
- `G-014` `Newest` MUST be the default selected Dock lens on app open.
- `G-015` `Host` mode MUST answer what is happening on a specific machine.
- `G-016` `Branch` mode MUST answer where the thread for a branch is across hosts.
- `G-017` Switching lenses MUST preserve the user's current search text and explicit filters unless the user clears them.
- `G-018` The selected lens MUST be visually and accessibly clear.
- `G-019` The legacy `Branch`/`Newest` sort segmented control MUST be retired as a separate primary control; `Newest`, `Host`, and `Branch` are Dock lenses, while sort belongs in the filter/sort surface.

## Header

- `G-020` The Dock header MUST show the title `Dock`.
- `G-021` The Dock header MUST show compact global connectivity, for example `Online 2/2` or `Checking 2 hosts`.
- `G-022` Host health MUST be compact in the Dock header or host lens, not a large pinned content block above the list.
- `G-023` Search MUST get a full-width row or equivalent system search placement on iPhone.
- `G-024` Search MUST NOT be squeezed into a narrow control beside sort, status, or idle controls.
- `G-025` The search placeholder SHOULD state the searchable dimensions, for example `Search sessions, repo, branch, host`.
- `G-026` The header MUST expose `Newest`, `Host`, `Branch`, and `Filters` or their equivalent controls.
- `G-027` The header MUST show active filters in a visible summary row, chips, or tokens.
- `G-028` Header controls MUST not crowd or truncate primary labels on iPhone 17 portrait.
- `G-029` Add-host affordances MUST NOT be large primary Dock-header controls unless the current user task is host setup.
- `G-029A` Header host-count pills MAY appear as compact shortcuts when they do not crowd search or session rows.
- `G-029B` If header host-count pills appear, tapping them MUST apply the corresponding host filter or open the host lens with that host clearly selected.

## Search

- `G-030` Search MUST be global by default.
- `G-031` Search MUST match session title, repo or working directory, branch, host display name, latest summary, status, and thread id fragment when those fields are available.
- `G-032` Search MUST compose with filters.
- `G-033` Search results MUST preserve newest-first ordering unless the user chose another explicit sort.
- `G-034` Active search state MUST be visible and clearable.
- `G-035` Search MUST support examples equivalent to `main`, `home main`, `Amir-M5 dock`, `codex-client host settings`, `feature/animation`, and a thread id fragment.
- `G-036` Search SHOULD update results as the user types; debounce is allowed for performance, but the user MUST NOT need to submit a separate search command for normal filtering.

## Filters And Facets

- `G-040` Filters MUST be explicit and reversible.
- `G-041` Filters MUST include host.
- `G-042` Filters MUST include branch.
- `G-043` Filters MUST include status.
- `G-044` Filters MUST include repo or working directory where repo metadata exists.
- `G-045` Filters MUST include source scope such as human vs agent when the data supports it.
- `G-046` Filters MUST include idle visibility.
- `G-047` Filters MUST include archive visibility when archived sessions can appear in Dock results.
- `G-048` Counts SHOULD be shown on filters or summary state when practical.
- `G-049` Counts MUST NOT look final while the app is still loading.
- `G-050` The user MUST be able to tell what is currently hidden.
- `G-051` Branch lookup MUST NOT be available only through free-text search; branch MUST exist as a real facet or lens.
- `G-052` Filter reset or clear MUST be available from the filter surface or active-filter summary.
- `G-053` If both a header filter icon and a `Filters` lens/control are visible, both MUST open the same filter surface and reflect the same active filter state.
- `G-054` The product MUST NOT maintain separate filter models for the header icon and `Filters` control.

## Rows

- `G-060` Every Dock row MUST be understandable without remembering a section header far above it.
- `G-061` Every Dock row MUST show title when available.
- `G-062` Every Dock row MUST show status when available.
- `G-063` Every Dock row MUST show last activity time when available.
- `G-064` Every Dock row MUST show host when more than one host exists.
- `G-065` Every Dock row MUST show branch when available.
- `G-066` Every Dock row MUST show repo or working directory when available.
- `G-067` Every Dock row SHOULD show a short latest-summary snippet when loaded content exists.
- `G-068` Every Dock row MAY show local label, rail color, or icon if it improves scanning without replacing textual identity.
- `G-069` Status MUST be a small chip or secondary cue, not the primary organizing principle unless the user chose a status filter.
- `G-070` Row tap targets MUST open the corresponding thread detail.
- `G-071` Row text MUST avoid incoherent clipping or overlap on iPhone 17 portrait.

## Host Identity

- `G-080` Dock scan paths MUST use short display names such as `Amir-M5` and `Home`.
- `G-081` Raw endpoint strings MUST stay in Relay settings, diagnostics, details, or tooltips, not primary row text.
- `G-082` Host identity MUST remain visible in rows when branch grouping removes host from the section title.
- `G-083` Host status failures MUST attach to the affected host or host group.
- `G-084` Offline hosts MUST NOT block scanning or using online hosts.

## Status Vocabulary

- `G-090` The allowed visible Dock status labels are `Running`, `Idle`, `Not loaded`, `Error`, and `Unknown`, plus explicit future statuses approved by product.
- `G-091` The Dock MUST NOT show `Limited`.
- `G-092` `Not loaded` MUST mean the app has a row or history reference but does not currently know enough loaded thread detail to summarize it.
- `G-093` `Not loaded` MUST NOT imply rate limiting, broken access, user blocking, or a provider failure.
- `G-094` `Not loaded` MUST be visually neutral.
- `G-095` `Error` MUST be used only when an actual error is known.
- `G-096` `Unknown` MUST be used only when status is unavailable and `Not loaded` is not precise enough.

## Removed Primary Status Concepts

- `G-100` `Needs me` MUST NOT be a primary tab.
- `G-101` `Needs me` MUST NOT be a top section.
- `G-102` `Needs me` MUST NOT be a default ranking primitive.
- `G-103` `Needs me` MAY exist only in a secondary or debug path until the signal is reliable, explicit, inspectable, and useful.
- `G-104` If the concept returns later, it SHOULD use a more literal label such as `Needs input`.
- `G-105` `Running` MUST NOT be a primary tab if live data shows it is often zero or unreliable.
- `G-106` `Running` MAY be a status filter when reliable.
- `G-107` `Agents` MUST NOT be a giant primary count tab.
- `G-108` Agent/source scope MUST live in filters when the data supports it.

## Sorting

- `G-120` Newest-first ordering MUST sort by last visible activity.
- `G-121` Tie-breakers MUST be deterministic.
- `G-122` Host groups MUST sort by newest visible row unless the user explicitly pins or reorders hosts.
- `G-123` Branch groups MUST sort by newest visible row.
- `G-124` Rows inside host and branch groups MUST sort newest-first unless the user chose another explicit sort.
- `G-125` Sort labels MUST be literal enough that the user can distinguish last activity from created date.

## Loading, Empty, And Partial States

- `G-130` Loading state MUST show which configured hosts are being checked when host config is known.
- `G-131` Loading state MUST NOT show final-looking zero-count filter tabs.
- `G-132` Loading state SHOULD keep search and lens controls visible so the surface is stable.
- `G-133` Long loading MUST be treated as a first-class state, not a brief spinner-only gap.
- `G-134` Partial loading MUST allow loaded hosts or rows to appear before every host finishes.
- `G-135` Empty states MUST state which filters or hidden states caused emptiness.
- `G-136` Empty states MUST provide a clear action to clear filters when filters caused the empty result.
- `G-137` Host failures MUST be local to the affected host or scope, not a global mystery state.
- `G-138` Host failure UI MUST include explicit failure copy when a failure reason is known.
- `G-139` Host failure UI MUST provide retry when retry is possible.
- `G-140` Host failure UI MUST provide a path to Relay settings or host diagnostics.

## Noise And Hidden State

- `G-150` Idle visibility MUST be explicit.
- `G-151` Hidden idle state MUST be visible in chips, toggles, or summary copy.
- `G-152` Archived visibility MUST be explicit when archived sessions can be included.
- `G-153` `Not loaded` visibility MUST be explicit if hidden or filtered.
- `G-154` The UI MUST NOT hide rows without explaining why.
- `G-155` The UI MUST NOT auto-predict the active host, active branch, active repo, or important thread.
- `G-156` Pinning MAY exist only as explicit user intent and MUST behave as a visible filter.

## Accessibility And Verification

- `G-170` Header, search, lens controls, filter controls, host groups, branch groups, rows, status chips, and bottom tabs MUST have accessibility labels or identifiers sufficient for automated verification.
- `G-171` Accessibility labels MUST use the same product vocabulary as visible labels, including `Not loaded` and excluding `Limited`.
- `G-172` Accessibility state MUST distinguish selected lens, selected filter chips, toggle values, expanded groups, collapsed groups, and row status.
- `G-173` Accessibility output during loading MUST describe checking/loading state and configured hosts, not stale zero counts.
- `G-174` Automated tests SHOULD cover the default lens, row host metadata, loading copy, killed terms, and filter availability.
