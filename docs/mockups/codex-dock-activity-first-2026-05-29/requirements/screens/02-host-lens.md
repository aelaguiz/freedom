# Screen Requirements: 02 Host Lens

Mockup: `../../outputs/02-host-lens.png`

## Purpose

The host lens answers what is happening on each machine while keeping session rows visually attached to their host.

## Requirements

- `S02-001` Selecting `Host` MUST switch Dock into host-grouped mode.
- `S02-002` The selected `Host` control MUST be visually and accessibly distinct.
- `S02-003` Host groups MUST be visible as compact section headers.
- `S02-004` Host headers MUST use short display names such as `Amir-M5` and `Home`.
- `S02-005` Host headers MUST NOT use raw endpoint strings as their primary label.
- `S02-006` Host headers MUST show connection state when known.
- `S02-007` Host headers MUST show visible session count when data is loaded.
- `S02-008` Host headers SHOULD show newest visible activity time, for example `Updated 2m ago`.
- `S02-009` Host headers MUST support collapsed and expanded states.
- `S02-010` Host groups MUST sort by newest visible row unless the user explicitly pins or reorders hosts.
- `S02-011` Rows inside each host group MUST sort newest-first.
- `S02-012` Host groups MUST be visually nested without becoming giant pinned cards.
- `S02-013` Host group containers MAY use subtle rails, indentation, separators, or tinted backgrounds to show nesting.
- `S02-014` Host mode MUST remain scroll-efficient for thousands of sessions.
- `S02-015` Host headers MUST show running count when reliable running data exists.
- `S02-016` Host headers MUST show hidden idle state, for example `idle hidden`, when idle rows are hidden for that host.
- `S02-017` Host header metadata MUST stay compact enough that it does not push session rows out of the first viewport when rows exist.
- `S02-018` Offline hosts MUST remain visible in Host mode and MUST be collapsed by default when they have no current visible rows.

## Row Requirements

- `S02-020` Rows MUST be nested under the correct host group.
- `S02-021` Rows SHOULD still include host metadata when it improves scanability or accessibility, even though host is in the header.
- `S02-022` Rows MUST include title, repo or working directory, branch, status, and last activity time when available.
- `S02-023` Row status chips MUST use approved labels such as `Idle` and `Not loaded`.
- `S02-024` Rows MUST retain a clear navigation affordance.
- `S02-025` Rows MUST not require endpoint knowledge to identify the machine.

## Host Actions

- `S02-040` Host headers MAY include refresh, filter, diagnostic, expand, or collapse actions.
- `S02-041` Host-header actions MUST have accessible labels.
- `S02-042` The host header's expand/collapse control MUST be the primary way to collapse or expand the group.
- `S02-043` Tapping a host-name chip or explicit filter affordance MUST filter to that host.
- `S02-044` Tapping the host header background MUST NOT ambiguously alternate between filtering and expanding.
- `S02-045` Long-press host actions MAY exist for diagnostics or Relay settings.
- `S02-046` Offline or failed host detail MUST be local to that host group.

## Prohibited Content

- `S02-060` The host lens MUST NOT recreate the old detached host-summary-above-list pattern.
- `S02-061` The host lens MUST NOT show `Needs me` as a primary category.
- `S02-062` The host lens MUST NOT show `Limited`.
- `S02-063` The host lens MUST NOT place endpoint strings in the main scan path.
- `S02-064` Host status MUST NOT push all session rows below the first viewport when rows exist.

## Acceptance Evidence

- A screenshot or accessibility dump shows `Host` selected.
- The tree contains host group headers with short names, counts, and expanded or collapsed state.
- Rows appear as descendants or visually nested children of host groups.
- Rows within a host are ordered newest-first.
- The visible primary text contains `Not loaded` where applicable and does not contain `Limited`.
