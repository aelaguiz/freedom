# Codex Dock Trustworthy Live Window Intention

Date: 2026-06-01

## Intention

Codex Dock should be a trustworthy live window into the Codex work the user is
doing right now.

When the user opens the app, the newest real Codex activity should be at the
top. When the user opens a thread, the thread should show the current state of
that thread. If the thread changes while it is open, the visible thread should
update on its own.

Filters should only narrow the view when the user intentionally asked for that.
They should not hide current work by default, explain away missing recent work,
or make stale data look correct.

`Live` should mean the visible app state is current, or is actively catching up
to current Codex state. If the app cannot prove that, it should say the real
state plainly: stale, reconnecting, delayed, failed, partial, or not connected.

No cache, relay shortcut, client projection, pinned-card rule, archived-row
path, SQLite row, simulator state, diagnostic endpoint, test fixture, fallback
path, or other side door should be able to become a second source of truth that
hides current Codex work.

Tests should prove the real path over time: Codex source data, relay state,
Swift state, and the visible iPhone simulator UI. Static snapshots are not
enough for an app whose main promise is that current work keeps updating.

Net: if the user is actively working in Codex right now, Codex Dock should show
that work right now. If it cannot, the app must say so plainly instead of hiding
the gap.

## Related Docs

- [Codex Dock intended live user experience](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01.md)
- [Codex Dock user intention](CODEX_DOCK_USER_INTENTION_2026-06-01.md)
- [Codex Dock live means current user intention](CODEX_DOCK_LIVE_MEANS_CURRENT_USER_INTENTION_2026-06-01.md)
- [Codex Dock live truth intention](CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md)
- [Codex Dock live user experience north star](CODEX_DOCK_LIVE_USER_EXPERIENCE_NORTH_STAR_2026-06-01.md)
- [Codex Dock intended live user experience worklog](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01_WORKLOG.md)
- [Codex Dock live update architecture and testing reference](CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md)
- [Codex Dock protocol and update architecture reference](CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md)
- [Codex Dock relay data contract and lease drift audit](CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md)
- [Codex Dock client card and thread detail complexity audit](CODEX_DOCK_CLIENT_CARD_AND_THREAD_DETAIL_COMPLEXITY_AUDIT_2026-05-31.md)
