Net: Model B’s first pass is: keep the draft’s intent, but make the permanent architecture stricter and smaller. One `DockScreenStore`-owned presentation pipeline should decide what SwiftUI sees, publish only bounded UI state, and move full-row proof data to a test-only snapshot file.

**Proposed Architecture**
- Add a small `DockPresentationPipeline` owned next to `DockScreenStore`, not a broad new subsystem.
- Input: full `DockSnapshot` from `DockStore`, current `DockProjectionOptions`, local UI state.
- Internal work: use existing `DockRenderProjector` off-main, then compute a `DockScreenFingerprint`.
- Output to SwiftUI: `DockScreenFrame`, not full proof data. It contains scalar header/filter/host state plus a bounded `DockRowWindow`.
- Publish rule: if the new fingerprint matches the current frame, do not assign new `.loaded` state.
- Proof rule: `DockAutomationSnapshotStore` writes full row proof only in UI-test mode, keyed by render revision. The Dock root accessibility value stays compact: `loaded; rows=1247; shown=300; revision=26; automationRevision=26`.

**Evidence Read**
- Worklog final cause: repeated full-row accessibility payload is the direct offender, `469,211` chars taking `20-22 ms`, with hitches up to `103 ms`: [worklog](/Users/aelaguiz/workspace/codex-client/docs/IPHONE_17_PRO_DOCK_LAG_PROFILE_WORKLOG_2026-06-04.md:1083).
- Draft plan is directionally right but overbroad around `DockScreenModel`, `DockRenderDataset`, and `DockAutomationSnapshot`: [draft](/Users/aelaguiz/workspace/codex-client/docs/DOCK_LIGHTNING_FAST_ARCHITECTURE_FIX_PLAN_2026-06-04.md:77).
- Current full publish path: `DockStore.publishSnapshot` always calls `screenStore.publish`: [DockStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockStore.swift:515).
- `DockScreenStore` always turns a published snapshot into `.loaded(renderSnapshot)`: [DockScreenStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Dock/DockScreenStore.swift:57).
- `DockView.dockScreenValue` builds `rowValues=` from all automation rows in the view body path: [DockView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockView.swift:1078).
- Displayed UI proof currently treats root `rowValues=` as the single Dock row oracle: [DisplayedUICaptureSupport.swift](/Users/aelaguiz/workspace/codex-client/CodexDockUITests/DisplayedUICaptureSupport.swift:454).
- Relay already has window/page/heartbeat contracts, so do not invent a second feed: [dock-relay-state-engine.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-engine.mjs:559), [dock-relay-constants.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-constants.mjs:32).
- Proof processor already fails on row identity, duplicates, order, count, status, origin, and lag: [dock-relay-simulator-ui-sync-proof.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-simulator-ui-sync-proof.mjs:1213).

**Owner Path**
Adopt the existing Dock screen boundary: `DockStore` remains the data/action owner, `DockScreenStore` becomes the single presentation publish owner, and `DockView` stops deriving all-row truth.

**Delete Or Replace**
- Delete root `rowValues=` construction from `DockView.dockScreenValue`.
- Delete `dockAutomationRows` and `automationEncoded` if they only serve root bulk proof.
- Replace `DisplayedUICaptureSupport.dockRowsFromRootValue(...)` with one snapshot-reader path. No fallback parser.
- Replace README claims that Dock order comes from root `rowValues=`.
- Replace `DockScreenState.loaded(DockRenderSnapshot)` as directly observed full render state with bounded `DockScreenFrame`.
- Replace `DockView.syncSelectedDetail` full-row scan with a row lookup from the presentation/data owner.

**Proof Gates**
- Unit: heartbeat/no-row-change produces zero new `DockScreenFrame` publishes.
- Unit: title/status/order/pin/label/host-status display changes do publish.
- Unit: root accessibility value length stays bounded under 10k rows.
- Unit: automation snapshot matches accepted render revision and full projected order.
- UI proof: `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` still uses `--fail-on-diff`, but reads rows from the new test-only snapshot.
- Perf proof: with 1,200+ rows, no all-row accessibility rebuilds, no heartbeat-driven UI revisions, and scroll work stays bounded by the row window.

**Rejected Alternatives**
- Only throttle relay heartbeats: misses upserts and leaves the huge root string.
- Only remove `rowValues=`: fixes the main offender but leaves future full-state churn easy to reintroduce.
- Hidden paged accessibility proof: still keeps bulk proof inside accessibility.
- Local diagnostic endpoint: too much surface area for a UI proof channel.
- Keeping both old root `rowValues=` and new snapshot proof: duplicate oracle, guaranteed drift.

**Risks / Open Questions**
- Pick the exact `DockRowWindow` size and UX for “show more” or infinite paging.
- Decide whether the first implementation may temporarily keep full row arrays after removing `rowValues=`, or whether the permanent doc requires windowing immediately. My vote: permanent plan requires bounded UI state.
- Physical iPhone proof is intentionally not part of this pass.

**Need From Model A**
- Agree or challenge `DockScreenStore` as the central owner.
- Decide whether bounded `DockRowWindow` is mandatory for the permanent plan.
- Confirm app-container JSON is the proof route, not hidden accessibility chunks.
- Check whether any existing UI tests need a special migration path beyond `DisplayedUICaptureSupport`.