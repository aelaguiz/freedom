Net: I converge with Model A. Use existing `DockScreenStore` as the owner, keep full row arrays for the first repair, use existing `Equatable`, and move row proof off the Dock root into one dedicated test-only accessibility payload.

**Agreements**
✅ `DockScreenStore` is the owner. It already owns `state`, `publish(snapshot:)`, options changes, and `enqueueProjection`; a new `DockPresentationPipeline` would be a second owner without evidence. See [DockScreenStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Dock/DockScreenStore.swift:12).

✅ Keep full row arrays for now. The measured bad path is the root accessibility payload: `1,247` rows produced `469,211` chars and cost `20-22 ms`; projection was ~`8 ms`, data snapshot ~`9 ms`, main publish ~`1 ms`. See [worklog](/Users/aelaguiz/workspace/codex-client/docs/IPHONE_17_PRO_DOCK_LAG_PROFILE_WORKLOG_2026-06-04.md:1083).

✅ Use existing `Equatable` first. `DockSnapshot`, `DockRowViewModel`, `DockRenderSnapshot`, and projection types are already equatable, so display fingerprints are extra machinery until equality itself proves hot.

**Disagreements**
⚠️ I would not use an app-container JSON snapshot as the first proof route. It is cleaner in theory, but it adds new plumbing and risks creating a second proof oracle. The repo already has strict JSONL proof samples fed by XCUITest.

⚠️ I would tighten Model A’s “hidden element” wording: the proof element must be visually nonintrusive and test-only, but not `.accessibilityHidden(true)`, because XCUITest may not see it.

**Simplifications**
- No new `DockPresentationPipeline`.
- No immediate `DockRowWindow`.
- No display fingerprints yet.
- No app-container JSON proof path yet.
- One proof oracle only: the dedicated Dock row payload element.

**Repo Evidence**
- `DockStore.publishSnapshot()` currently writes `.loaded` and calls `screenStore.publish(...)` unconditionally, so no-op syncs still invalidate UI. See [DockStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockStore.swift:529).
- `DockScreenStore.enqueueProjection` bumps revision before any equality gate. See [DockScreenStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Dock/DockScreenStore.swift:169).
- `DockView` attaches the huge row payload to the root accessibility value. See [DockView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockView.swift:634) and [DockView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockView.swift:1087).
- The current UI proof intentionally parses `rowValues=` from one source and fails loud when missing. See [DisplayedUICaptureSupport.swift](/Users/aelaguiz/workspace/codex-client/CodexDockUITests/DisplayedUICaptureSupport.swift:636).

**Revised Proposal**
1. Add the equality gate inside `DockScreenStore` before revision bump/projection, comparing displayed input plus `DockProjectionOptions`.
2. Guard `DockStore.state = .loaded(...)` so unchanged display snapshots do not invalidate the root view.
3. Remove all-row `rowValues=` from `DockView.dockScreenValue`; keep root accessibility bounded to scalar state only.
4. Move encoded row proof into one test-only `AutomationID.Dock.renderedRows` payload sourced from the same rendered projection rows.
5. Update `DisplayedUICaptureSupport` to read only that payload. Do not fall back to visible row scraping.
6. If that payload exceeds XCUITest size limits, chunk the same single oracle by revision; do not add JSON as a second oracle.

**Delete Or Replace**
- Delete root `rowValues=` assembly from [DockView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockView.swift:1097).
- Move/replace `dockAutomationRows` and `automationEncoded` out of production `DockView`.
- Replace `dockRowsFromRootValue(_:)` in [DisplayedUICaptureSupport.swift](/Users/aelaguiz/workspace/codex-client/CodexDockUITests/DisplayedUICaptureSupport.swift:636).
- Update README text that says root `rowValues=` is the Dock proof oracle.

**Sign-Off**
✅ Ready to sign off with Model A’s architecture plus the dedicated proof-element rule above. I did not edit files, implement anything, run tests, or run physical phone checks.