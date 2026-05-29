# Screen Requirements: 04 Loading And Not Loaded

Mockup: `../../outputs/04-loading-not-loaded.png`

## Purpose

Loading is a first-class state because the real Dock can take minutes to load thousands of rows. The UI must be honest about known hosts and unknown thread detail without implying rate limits.

## Requirements

- `S04-001` During initial loading, the header MUST show a checking/loading connectivity state such as `Checking 2 hosts`.
- `S04-002` Loading state MUST show known configured hosts when host config is available.
- `S04-003` Known hosts MUST use short display names such as `Amir-M5` and `Home`.
- `S04-004` Each known host row MUST show its loading/checking state.
- `S04-005` Host loading rows MAY show service scope, for example `Codex`, if accurate.
- `S04-006` Loading state MUST keep the Dock title, search row, lens controls, and bottom tabs stable.
- `S04-007` Search MAY be disabled during loading, but it MUST remain visually understandable.
- `S04-008` `Newest` SHOULD remain selected during loading because it is the default lens.
- `S04-009` Loading state SHOULD show skeleton rows when row content is not ready.
- `S04-010` Loading state MAY show already loaded rows mixed with skeleton or not-loaded rows if partial results exist.
- `S04-011` Partial loading MUST allow one host to show results while another host is still checking.

## Not Loaded Semantics

- `S04-020` The UI MUST use `Not loaded` for rows whose thread detail is unavailable.
- `S04-021` The UI MUST include explanatory copy when the whole list or major scope is not loaded, for example `Sessions not loaded yet` and `Waiting for relay response`.
- `S04-022` `Not loaded` MUST be neutral copy, not an error, warning, or rate-limit message.
- `S04-023` Skeleton rows with unknown content MAY show `Not loaded` status.
- `S04-024` Rows with loaded content MUST not be downgraded to `Not loaded`.
- `S04-025` A host transport failure MUST use host-local error state, not `Not loaded`, when an actual error is known.

## Prohibited Content

- `S04-040` Loading state MUST NOT show `Limited`.
- `S04-041` Loading state MUST NOT imply Codex or OpenAI rate limits unless the app has explicit rate-limit evidence.
- `S04-042` Loading state MUST NOT show `All 0`, `Needs me 0`, `Running 0`, or `Agents 0` as final-looking primary tabs.
- `S04-043` Loading state MUST NOT show only one host when multiple configured hosts are known.
- `S04-044` Loading state MUST NOT make raw endpoint strings the dominant host identity.
- `S04-045` Loading state MUST NOT hide online host rows behind an offline host failure.

## Acceptance Evidence

- A loading screenshot or accessibility dump shows known host rows and checking state.
- Loading text names what is being loaded or waited on.
- Accessibility output contains `Not loaded` where applicable and does not contain `Limited`.
- Accessibility output does not expose final-looking zero-count primary filter tabs while loading.
- A simulated one-host failure leaves other host rows visible or usable.
