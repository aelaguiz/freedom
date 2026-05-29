# Screen Requirements: 07 Host Offline And Partial Failure

Source: `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md` section 15.

## Purpose

Host failures must be local, understandable, and actionable. One offline or failed host must not turn the Dock into a global mystery state or block scanning sessions from online hosts.

## Requirements

- `S07-001` Offline host state MUST attach to the affected host.
- `S07-002` Offline host state MUST use the host display name, not the raw endpoint, as the primary label.
- `S07-003` Offline host state MUST show an explicit status such as `Offline`, `Error`, or `Checking`.
- `S07-004` If a failure reason is known, the UI MUST show concise failure copy, for example `Last check failed: connection timed out`.
- `S07-005` Offline host state MUST provide `Retry` when retry is possible.
- `S07-006` Offline host state MUST provide a path to `Relay settings`, host settings, or diagnostics.
- `S07-007` Offline host details MUST be collapsed by default when no current rows exist.
- `S07-008` Offline host details MUST be expandable when there is actionable detail.
- `S07-009` Offline host controls MUST have accessible labels.

## Partial Failure Behavior

- `S07-020` Online host rows MUST remain visible and usable when another host is offline.
- `S07-021` The global connectivity chip MAY show partial state such as `Online 1/2`.
- `S07-022` Partial failure MUST NOT clear the entire Dock list.
- `S07-023` Partial failure MUST NOT produce final-looking zero counts for unaffected hosts.
- `S07-024` Search and filters MUST continue to work on available data during partial failure.
- `S07-025` Host, branch, and newest lenses MUST each preserve the local failure state while showing available rows.

## Error Vocabulary

- `S07-030` Use `Offline` when the host is known unreachable.
- `S07-031` Use `Error` when a concrete host or relay error is known.
- `S07-032` Use `Checking` while the app is still attempting to determine status.
- `S07-033` Use `Not loaded` only for missing thread detail, not for known host transport failure.
- `S07-034` Do not use `Limited`.

## Prohibited Content

- `S07-040` Host failure MUST NOT appear as a global mystery banner without host attribution.
- `S07-041` Host failure MUST NOT imply OpenAI or Codex rate limits unless explicit rate-limit evidence exists.
- `S07-042` Host failure MUST NOT hide online hosts.
- `S07-043` Host failure MUST NOT force the user into Relay unless they choose the settings/diagnostics path.
- `S07-044` Host failure MUST NOT use raw endpoint strings as primary visible identity.
- `S07-045` Host failure MUST NOT resurrect `Needs me`, `Limited`, or primary zero-count tabs.

## Acceptance Evidence

- Simulating one offline host shows local host error copy and leaves online-host rows visible.
- `Retry` and `Relay settings` or equivalent actions are visible and accessible for the failed host.
- Accessibility output names the failed host, its status, and the available action labels.
