# Codex Dock User Intention

Date: 2026-06-01

## Intention

When you open Codex Dock, it should show the same current Codex reality you are
living in right now.

Newest real work should be at the top. Opening a thread should show what is
actually happening in that thread now. If new work happens while that thread is
open, the visible thread should update without making you back out, reopen,
toggle filters, restart services, or guess whether the view is stale.

Filters should only narrow the view in ways the user intentionally chose. They
should never hide current work by default, explain away missing recent work, or
make old work look like the current truth.

No cache, relay shortcut, client projection, pinned-card rule, archived-row
path, SQLite row, simulator state, diagnostic endpoint, test fixture, or
fallback path should be able to become a second truth that hides current Codex
work.

`Live` must mean the visible app state is current or actively converging with
Codex. If the app cannot prove that, it should say the real state plainly:
stale, reconnecting, delayed, failed, partial, or not connected.

Tests must prove the real path over time from Codex source data, through the
relay, through Swift state, into the visible iPhone simulator UI. Static
snapshots are not enough for an app whose main promise is that current work
keeps updating.

Net: Codex Dock is supposed to be a trustworthy live window into Codex. If the
user is actively working in Codex right now, the app should show that work
right now. If it cannot, the app must say so plainly instead of hiding the gap.

## Related Docs

- [Codex Dock trustworthy live window intention](CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md)
- [Codex Dock intended live user experience](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01.md)
- [Codex Dock live user experience north star](CODEX_DOCK_LIVE_USER_EXPERIENCE_NORTH_STAR_2026-06-01.md)
- [Codex Dock live truth intention](CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md)
- [Codex Dock intended live user experience worklog](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01_WORKLOG.md)
- [Codex Dock live update architecture and testing reference](CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md)
- [Codex Dock live update architecture and testing worklog](CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md)
- [Codex Dock protocol and update architecture reference](CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md)
- [Codex Dock relay data contract and lease drift audit](CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md)
- [Codex Dock client card and thread detail complexity audit](CODEX_DOCK_CLIENT_CARD_AND_THREAD_DETAIL_COMPLEXITY_AUDIT_2026-05-31.md)
- [Codex Dock live filter simulator audit worklog](CODEX_DOCK_LIVE_FILTER_SIM_AUDIT_WORKLOG_2026-06-01.md)
- [Codex Dock phone vs Codex state audit worklog](CODEX_DOCK_PHONE_VS_CODEX_STATE_AUDIT_WORKLOG_2026-05-31.md)
- [Codex Dock thread types and states reference](CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md)
