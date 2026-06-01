# Codex Dock Live Truth Intention

Date: 2026-06-01

## Intention

Your intended experience is simple: when you look at Codex Dock, it should show
the real current Codex work, in the same order and state that Codex itself would
make you expect.

Newest current work should be at the top. Opening a thread should show what is
actually happening in that thread now. If new work happens while the thread is
open, the visible thread should update without making you back out, reopen,
toggle filters, restart services, or guess whether the view is stale.

No filter, cache, relay shortcut, client projection, pinned-card rule, SQLite
row, simulator state, test fixture, or fallback path should be able to hide
current work or make old work look current.

If the app cannot prove that the visible state is current, it should say that
plainly: stale, reconnecting, delayed, failed, or not connected. It should not
show old rows under a `Live` label.

Net: Codex Dock is supposed to be a trustworthy live window into Codex. If the
user is actively working in Codex right now, the app should show that reality
right now, and any gap should be explicit.

## Cross-Links

- [Codex Dock user intention](CODEX_DOCK_USER_INTENTION_2026-06-01.md)
- [Codex Dock trustworthy live window intention](CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md)
- [Codex Dock live means current user intention](CODEX_DOCK_LIVE_MEANS_CURRENT_USER_INTENTION_2026-06-01.md)
- [Codex Dock intended live user experience](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01.md)
- [Codex Dock intended live user experience worklog](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01_WORKLOG.md)
- [Codex Dock live update architecture and testing reference](CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md)
- [Codex Dock live update architecture and testing worklog](CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md)
- [Codex Dock live filter simulator audit worklog](CODEX_DOCK_LIVE_FILTER_SIM_AUDIT_WORKLOG_2026-06-01.md)
- [Codex Dock protocol and update architecture reference](CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md)
- [Codex Dock relay data contract and lease drift audit](CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md)
- [Codex Dock client card and thread detail complexity audit](CODEX_DOCK_CLIENT_CARD_AND_THREAD_DETAIL_COMPLEXITY_AUDIT_2026-05-31.md)
- [Codex Dock thread types and states reference](CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md)
