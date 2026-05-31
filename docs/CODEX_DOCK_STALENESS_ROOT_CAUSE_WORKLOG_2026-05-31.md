# Codex Dock Staleness Root Cause Worklog - 2026-05-31

## Goal

Root cause why the simulator and phone can stop staying up to date while still looking connected. The concrete symptom under investigation is a Dock list whose latest visible message can show old activity such as `2h ago`.

No implementation fixes in this pass. Testing and evidence capture are allowed.

## Worklog

### 2026-05-31T17:03:20Z - Investigation started

- Current repo has existing Swift changes from the Dock ordering fix:
  - `CodexDock/State/DockCardProjection.swift`
  - `CodexDockTests/DockStoreTestsProjection.swift`
- Existing untracked mockup directories are present and unrelated:
  - `docs/mockups/codex-dock-conversation-time-order-2026-05-31/`
  - `docs/mockups/codex-dock-time-order-2026-05-31/`
- The investigation is now focused on freshness/staleness architecture, not ordering.
- Initial search found repo-owned sync proof tooling in the `Makefile` and freshness language in `README.md`.

### 2026-05-31T17:03-17:05Z - Current simulator and relay evidence captured

Artifacts saved under `/tmp/codex-client/staleness-root-cause-20260531/`.

- `sim-current.png`: simulator visibly shows:
  - global badge: `Online 2/2`
  - summary text includes `Partial`
  - top visible Dock row: `2h ago`
- `sim-log-last-30m.txt` and `sim-log-signal-tail.txt`: app logs repeatedly show stale rows retained:
  - `dock stream rows retained host_id=home.fairy-salmon.ts.net:4510 freshness=stale rows=961`
  - `dock stream rows retained host_id=amir-m5.fairy-salmon.ts.net:4510 freshness=stale rows=188`
  - `dock render input exceeds main publish row budget rows=1149 budget=600`
- `dock-subscribe-combined.json`: direct `dock/subscribe` probes returned:
  - `amir`: `freshness.status=stale`, `complete=true`, `totalRows=188`, `lastError=human-started thread validation failed`, top activity `2026-05-31T14:56:09.000Z`
  - `home`: `freshness.status=stale`, `complete=false`, `totalRows=961`, `lastError=websocket closed: ws://127.0.0.1:4500/`, top activity `2026-05-30T16:28:28.000Z`
- `/statusz` snapshots for both relays report raw app-server health as `up` and relay service `ok=true`, so transport/service health is not enough to prove Dock freshness.

### 2026-05-31T17:04-17:07Z - Immediate stale reasons

- Amir relay is repeatedly failing human-started thread validation during Dock reconciliation.
  - Relay log event: `human_started_thread.session_index_validation_failed`
  - Upstream error example: `thread/read: thread not loaded: 019e0fce-24e5-7471-b971-85b74d72ecf2`
  - Reconcile result: `state.reconcile_incomplete` with `validationFailures=14`
- Home relay recovered during a later periodic reconcile.
  - Relay log event: `state.reconcile_succeeded`
  - Rows: `961`
  - Validation failures: `0`
- This means the repro is not a simple dead relay. At least one relay can be serving a WebSocket connection and cached rows while its Dock freshness is stale or recently recovered.

### 2026-05-31T17:05-17:09Z - Client architecture path identified

- The client intentionally retains rows when a stream update says freshness is stale.
  - `ThreadCardTable.hostStatus(...)` maps `DockStreamFreshnessDTO(status: .stale)` to `.partial(rowCount: message:)`.
  - Existing test `DockStoreStreamTests.test...` asserts stale heartbeat retains rows and reports partial.
- The connectivity layer treats `.partial` as online-like.
  - `HostConnectivityPhase.isOnlineLike` returns true for `.online` and `.partial`.
  - `GlobalConnectivityIndicatorView` displays partial multi-host states as `Online N/N`, not `Partial` or `Stale`.
- Result: the simulator can truthfully show `Online 2/2` while the Dock list is sourced from stale retained rows.

### 2026-05-31T17:09:01Z - Phone config check

- Ran `rtk make device-config-verify-all`.
- iPhone 17 Pro device config verifies hosts:
  - `amir-m5.fairy-salmon.ts.net:4510`
  - `home.fairy-salmon.ts.net:4510`
- iPhone 14 device config verifies hosts:
  - `Amir-M5.local:4510`
  - `192.168.50.74:4510`
- This confirms the phone app path points at the same relay-backed architecture. I did not reinstall or modify the phone app.

### 2026-05-31T17:09Z - Final report saved

- Saved final report:
  - `docs/CODEX_DOCK_STALENESS_ARCHITECTURE_ROOT_CAUSE_REPORT_2026-05-31.md`
- Main finding:
  - Stale Dock freshness is intentionally retained by the relay, converted to `partial` by the Swift Dock store, counted as online-like by connectivity, and displayed as `Online N/N` by the global badge.
- No implementation fix was made.

### 2026-05-31T17:38Z - Missing-current-work clarification

- Rechecked the active Amir thread `019e7e7d-66ca-7280-9aa0-2e272f1752b1`.
- `thread/read` still reports `updatedAt=1780238608` (`2026-05-31T14:43:28Z`).
- `thread/turns/list` reports newer turns, including:
  - `startedAt=1780249079` (`2026-05-31T17:37:59Z`)
  - `startedAt=1780246962` (`2026-05-31T17:02:42Z`)
- Clarification added to the final report:
  - Current turn data exists, but the Dock card source is built from thread-level projection fields, and those fields are not reflecting the latest turn activity.
