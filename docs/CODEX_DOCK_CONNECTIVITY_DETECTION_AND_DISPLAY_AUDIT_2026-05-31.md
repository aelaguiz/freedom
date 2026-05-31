# Codex Dock Connectivity Detection And Display Audit - 2026-05-31

## Bottom Line

Connectivity detection is broad, but the display can overstate health. The app collects Dock, Archive, Relay Settings, Thread Detail, route diagnostics, and lifecycle evidence, then rolls it into one status. The problem is that `.partial` is treated as "online-like", so degraded hosts can produce labels like `Online 2/2`.

Plain English: the app often knows something is degraded, but the small top badge can make that feel healthier than it is.

## High-Level Model

Codex Dock has two health layers:

1. Swift app connectivity: local stores report host state into `AppConnectivityStore` or `ConnectivityEventSink`.
2. Node relay health: HTTP endpoints and route observability report process health, route health, app-critical failures, and relay state.

These are related but not identical. `/readyz` proves the relay process can answer. It does not prove Dock card data is fresh.

## Swift App Reporting Paths

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `CodexDock/Features/Dock/DockView.swift` | 250-257 | In the non-runtime path, Dock, Archive, and Hosts stores report directly to `AppConnectivityStore`. | Store state goes straight into the global badge. |
| `CodexDock/State/DockStore.swift` | 495-515 | Dock store either reports directly or emits `ConnectivityRuntimeEvent`s. | Dock stream state is a first-class connectivity input. |
| `CodexDock/State/ArchiveStore.swift` | 279-339 | Archive store uses the same pattern and maps host states to connectivity phases. | Archive can influence global status. |
| `CodexDock/State/HostSettingsStore.swift` | 297-319 | Manual host tests emit connectivity facts. | Settings tests can change app health display. |
| `CodexDock/State/ThreadDetailStore.swift` | 818-850 | Thread detail maps live state to checking, reconnecting, online, stale, or offline. | Opening a thread can update global host health. |
| `CodexDock/Runtime/ConnectivityEventSink.swift` | 13-37 | Runtime events carry source, host id, route, status, phase, and timestamp. | Multiple app areas can feed one health stream. |
| `CodexDock/Connectivity/ConnectivityDataEngine.swift` | 25-43 | Runtime events update host records and last success when phase is online-like. | `.partial` can update success timing because it is online-like. |

## AppConnectivityStore State Rules

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `CodexDock/State/AppConnectivityStore.swift` | 4-15 | Host phases are `unknown`, `checking`, `online`, `partial`, `reconnecting`, `backgrounded`, `resuming`, `stale`, `offline`, `error`, and `configurationError`. | The model has enough vocabulary to represent degraded states. |
| `CodexDock/State/AppConnectivityStore.swift` | 17-26 | `isOnlineLike` returns true for `.online` and `.partial`. | This is the key reason degraded hosts can count as online. |
| `CodexDock/State/AppConnectivityStore.swift` | 76-113 | Overall labels include `Online`, `Partial`, `Stale`, `Offline`, `Error`, and `Config error`. | The model can say partial/stale, but the badge may choose count wording. |
| `CodexDock/State/AppConnectivityStore.swift` | 275-293 | Dock store state is converted into host observations. | Dock stream stale/incomplete states flow into connectivity. |
| `CodexDock/State/AppConnectivityStore.swift` | 296-310 | Archive state is converted using the same host-state model. | Archive and Dock share status vocabulary. |
| `CodexDock/State/AppConnectivityStore.swift` | 313-330 | Manual host test state becomes online/offline/error/checking. | Manual tests can make a host look online even if Dock data is stale. |
| `CodexDock/State/AppConnectivityStore.swift` | 527-540 | Host snapshot prefers lifecycle phase, then route diagnostic phase, then store observations. | Background/resume and route failures can override normal store reports. |
| `CodexDock/State/AppConnectivityStore.swift` | 543-548 | App-critical failed route becomes `.partial("<route> failed")`. | Critical route failure is degraded, not hard offline/error. |
| `CodexDock/State/AppConnectivityStore.swift` | 550-557 | Multiple observations roll up by priority. | One stale/detail event can beat an online Dock event for that host. |
| `CodexDock/State/AppConnectivityStore.swift` | 559-635 | Overall rollup chooses global app status. | The final badge is a rollup, not a direct relay truth. |
| `CodexDock/State/AppConnectivityStore.swift` | 594-618 | `onlineLikeCount` includes partial hosts. | This is where `Online N/N` can include degraded hosts. |
| `CodexDock/State/AppConnectivityStore.swift` | 637-650 | Priority ranks stale above checking/offline/error/partial/online. | Stale should win inside one host if it is reported as stale, but many Dock stale rows are mapped to partial before this point. |

## Dock Store Connectivity Mapping

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `CodexDock/State/ThreadCardTable.swift` | 58-64 | Reconnecting with retained rows becomes `.partial(rowCount, "Reconnecting")`. | Existing rows stay visible and host appears partial. |
| `CodexDock/State/ThreadCardTable.swift` | 67-80 | Offline/error with retained rows becomes partial instead of unavailable. | Data stays visible, but global badge may still count host online-like. |
| `CodexDock/State/ThreadCardTable.swift` | 82-112 | Snapshot freshness and completeness become host status. | Relay freshness drives Dock host state. |
| `CodexDock/State/ThreadCardTable.swift` | 115-168 | Updates preserve latest freshness/complete/window and recompute host status. | Stale heartbeats can keep rows and mark partial. |
| `CodexDock/State/ThreadCardTable.swift` | 321-350 | Incomplete windows and stale freshness map to `.partial`; offline/error map to partial if rows exist. | Retained rows are degraded, not hidden. |
| `CodexDock/State/DockStore.swift` | 517-585 | Dock state emits connectivity events for configuration, loading, offline, error, and loaded host states. | The top badge follows Dock stream host states. |
| `CodexDock/State/DockStore.swift` | 588-605 | `DockHostLoadStatus.partial` becomes `HostConnectivityPhase.partial`. | Partial is later counted as online-like. |

## Thread Detail Connectivity Mapping

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `CodexDock/State/ThreadDetailStore.swift` | 38-55 | Detail live states are `connecting`, `reconnecting`, `live`, `stale`, and `closed`. | Detail has a clearer stale/live model than Dock card rows. |
| `CodexDock/State/ThreadDetailStore.swift` | 476-499 | Backgrounding a loaded live detail marks it stale with message `Backgrounded`. | Background state is explicit. |
| `CodexDock/State/ThreadDetailStore.swift` | 501-523 | Foreground resume rehydrates if connected, waits if reconnecting, or marks stale. | Resume state can temporarily override health. |
| `CodexDock/State/ThreadDetailStore.swift` | 818-850 | Detail publishes checking, reconnecting, online, stale, and offline phases. | Detail stale can correctly become global stale when it wins the rollup. |

## Global Badge Display

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `CodexDock/Features/Dock/DockView.swift` | 400-416 | The Dock header renders `GlobalConnectivityIndicatorView`. | This is the small badge the user sees first. |
| `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | 44-68 | Display label is chosen from overall status. | `.partial` does not always display as `Partial`. |
| `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | 48-51 | `.online` and `.partial` both use `hostCountLabel(prefix:"Online")` for multi-host. | Multi-host partial can display `Online 2/2`. |
| `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | 71-77 | Host count label counts hosts where `phase.isOnlineLike`. | Since `.partial` is online-like, partial hosts are counted as online. |
| `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | 79-101 | Icons distinguish partial/stale/offline/error. | The icon may warn even when text says `Online N/N`. |
| `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | 104-114 | Partial/stale/reconnecting/backgrounded/resuming are orange; online is green. | Color can be more accurate than text. |

Misleading state:

- If both hosts have retained stale rows, the global status can be `.partial`, but the label can say `Online 2/2`.
- That matches the simulator symptom where the header says `Online 2/2` while the Dock summary says `Partial`.

## System Health Display

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `CodexDock/Features/Status/SystemHealthView.swift` | 49-58 | `Run check` calls `store.refreshRelayDiagnostics()`. | User can ask for route diagnostics manually. |
| `CodexDock/Features/Status/SystemHealthView.swift` | 70-81 | Summary card shows `overallStatus.label` and message. | Full sheet is more explicit than the badge. |
| `CodexDock/Features/Status/SystemHealthView.swift` | 84-105 | Category grid shows category health. | Route evidence is grouped by product area. |
| `CodexDock/Features/Status/SystemHealthView.swift` | 109-149 | Host cards use `host.phase.isOnlineLike` for checkmark/green vs warning/orange. | Partial hosts can get green checkmarks. |
| `CodexDock/Features/Status/SystemHealthView.swift` | 225-260 | Host detail lists route evidence and reasons. | The real technical detail exists, but is one tap deeper. |
| `CodexDock/Features/Status/SystemHealthProjector.swift` | 31-59 | Diagnostics route status maps failed/blocked to failed, degraded/partial/stale to degraded. | Route-level stale is handled. |
| `CodexDock/Features/Status/SystemHealthProjector.swift` | 62-86 | Fallback status maps overall partial to degraded, stale to stale, offline/error/config to failed. | System Health has better wording than the top badge. |
| `CodexDock/Features/Status/SystemHealthProjector.swift` | 89-112 | Categories map routes: Dock feed, Thread detail, Archive, Voice, Diagnostics. | Route health is category-based, not card freshness proof. |

## Dock Host Context Rows

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `CodexDock/Features/Dock/DockView.swift` | 927-930 | Contextual host rows include checking, partial, and unavailable hosts. | Dock does surface partial host state below rows. |
| `CodexDock/Features/Dock/DockView.swift` | 958-968 | Non-unavailable partial hosts render using `HostLoadingRow`. | Partial rows look like loading/blue rows, not warning rows. |
| `CodexDock/Features/Dock/DockGroupRows.swift` | 68-92 | `HostLoadingRow` uses blue desktop/checking styling and displays status subtitle. | Degraded partial state can look too calm. |
| `CodexDock/Features/Dock/DockGroupRows.swift` | 95-125 | `HostFailureRow` has orange warning styling and Retry/Relay actions. | Only unavailable hosts get the stronger visual treatment. |

## Relay HTTP Health

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `scripts/dock-relay.mjs` | 848-855 | `/readyz` returns `ok:true`, service name, and auth mode. | Process-only proof. Not data freshness. |
| `scripts/dock-relay.mjs` | 763-767 | `/statusz` checks raw app-server health then returns relay status. | Better than `/readyz`, but callers must read nested fields. |
| `scripts/dock-relay.mjs` | 769-774 | `/metricsz` returns metrics snapshot. | Uses last-known raw health; not a fresh probe by itself. |
| `scripts/dock-relay.mjs` | 783-794 | `/routesz` returns route health evidence. | Best route-level diagnostic source. |
| `scripts/dock-relay-status.mjs` | 205-260 | `/statusz` includes `routes` and `appCriticalFailures`. | Top-level `ok:true` can coexist with nested failures. |
| `scripts/dock-relay-status.mjs` | 263-280 | `/metricsz` includes live status and state counts. | Useful for operators, not directly shown as the top badge. |

## Route Diagnostics

Line audit:

| File | Lines | Behavior | UX implication |
| --- | ---: | --- | --- |
| `scripts/dock-relay-observability-contract.mjs` | 1-9 | Route statuses are `unknown`, `healthy`, `degraded`, `failed`, `stale`, `partial`, and `blocked`. | Route language is richer than the top badge. |
| `scripts/dock-relay-observability-contract.mjs` | 33-79 | Route names include HTTP endpoints, Dock routes, Thread Detail routes, turn routes, and transcription routes. | Diagnostics can be route-specific. |
| `scripts/dock-relay-observability-contract.mjs` | 192-258 | `initialize`, `thread/list`, `thread/read`, `thread/turns/list`, etc. are app-critical as configured. | Critical route failures should matter to UX. |
| `scripts/dock-relay-observability-contract.mjs` | 273-320 | Dock and Archive stream routes are app-critical. | Stream health is tracked separately from data freshness. |
| `scripts/dock-relay-observability-contract.mjs` | 328-370 | Turn and transcription routes are app-critical/passive. | Live work routes can be unhealthy independently of Dock cards. |
| `scripts/dock-relay-observability.mjs` | 219-239 | Route records include schema, route, appCritical, status reasons, counters, and impact. | The evidence model is good. |
| `scripts/dock-relay-observability.mjs` | 291-355 | Active operations start as partial. | In-flight route work is not yet success or failure. |
| `scripts/dock-relay-observability.mjs` | 358-375 | Finished operations update route outcome from request result. | Successful stale payloads can still be route-successful. |
| `scripts/dock-relay-observability.mjs` | 514-516 | `appCriticalFailures` only includes failed routes. | Stale/degraded route evidence may not trigger the strongest UI language. |

## UX Mismatch Inventory

| Mismatch | Root cause | What the user sees |
| --- | --- | --- |
| `Online 2/2` while Dock is partial | `.partial` is `isOnlineLike`, and the badge uses online-like count. | Header sounds healthy even with retained stale rows. |
| Green check for partial host in System Health | Host card icon checks `phase.isOnlineLike`. | A degraded host can look healthy. |
| Blue partial host rows in Dock | Partial-but-available rows render via `HostLoadingRow`. | Degraded state looks like neutral loading. |
| `/readyz` passes while Dock is stale | `/readyz` is process-only. | Operator may think relay is fine when app data is stale. |
| Route health healthy while payload stale | Observability tracks request success, not semantic payload freshness. | System can say route worked even when data is old. |
| Dock partial state counted as success timestamp | `.partial` is online-like. | Last success can advance on degraded evidence. |

## Tests That Encode Current Behavior

- `CodexDockTests/AppConnectivityStoreTests.swift:16` - Dock online rolls up as online.
- `CodexDockTests/AppConnectivityStoreTests.swift:39` - all loading rolls up as checking.
- `CodexDockTests/AppConnectivityStoreTests.swift:51` - loaded plus checking rolls up as partial.
- `CodexDockTests/AppConnectivityStoreTests.swift:78` - partial host rolls up as partial.
- `CodexDockTests/AppConnectivityStoreTests.swift:171` - app-critical route failure overrides process evidence as partial.
- `CodexDockTests/AppConnectivityStoreTests.swift:285` - lifecycle masks old facts until active.
- `CodexDockTests/ConnectivityDataEngineTests.swift:5` - runtime events update connectivity.
- `CodexDockTests/SystemHealthProjectorTests.swift:5` - healthy Dock with passive categories not checked.
- `CodexDockTests/SystemHealthProjectorTests.swift:30` - app-critical failure maps failed.
- `CodexDockTests/SystemHealthProjectorTests.swift:60` - partial route maps degraded.
- `CodexDockTests/DockStoreStreamTests.swift:219` - stale heartbeat retains rows as partial.
- `CodexDockTests/DockStoreStreamTests.swift:333` - windowed snapshot is explicitly partial.
- `CodexDockTests/DockStoreStreamTests.swift:478` - closed stream retains rows as partial/offline.
- `scripts/dock-relay-observability.test.mjs:190` - `/readyz` can pass while Dock state is stale.
- `scripts/dock-relay-observability.test.mjs:238` - stale cached `dock/subscribe` can still leave route health healthy.

## Verdict

This is both a technical and UX mismatch, not just a wording issue.

Technically, the app collects enough evidence to know "degraded but usable" versus "fully healthy." UX-wise, the header badge and some host rows collapse that distinction by treating partial as online-like. That makes the current relay/card staleness bugs feel more confusing because the user sees old work while the app still says some form of "Online."
