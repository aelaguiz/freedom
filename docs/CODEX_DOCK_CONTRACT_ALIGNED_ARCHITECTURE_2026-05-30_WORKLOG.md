# Codex Dock Contract-Aligned Architecture Worklog

Plan: `docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md`

## 2026-05-30

- Started `$arch-step auto-implement` after the stage gate reported `READY next=implement-loop`.
- Confirmed implementation target is a hard cut to `DockThreadCard` and `ThreadCardStreamUpdate`, with no runtime compatibility bridge from `SessionSummary` rows.
- Began Phase 1 by adding the implementation worklog and preparing the contract/schema/generator spine.

## 2026-05-31

### Touched Contract Surface

- Added the schema source of truth at `contract/dock/dock-thread-card.schema.json`, plus generated/fixture checks under `contract/dock/fixtures/`, `scripts/generate-dock-thread-card-contract.mjs`, and `scripts/check-dock-thread-card-contract.mjs`.
- Replaced the Swift stream DTO path by deleting `CodexDock/AppServer/DockStreamDTO.swift` and generating `CodexDock/AppServer/DockThreadCardDTO.swift`.
- Renamed the Swift stream client path from `AppServerDockStreamClient` to `AppServerThreadCardStreamClient`, including Dock and Archive stream views.
- Replaced the old `DockSessionTable` storage path with `ThreadCardTable`, keyed by card id and sorted by relay-owned `orderKey`.
- Replaced production row projection from `SessionSummaryMapper` / `SessionRowProjector` with `ThreadCardRowProjector`.
- Updated Dock rendering (`DockRenderModels`, `DockRenderProjector`, `DockDataEngine`, `DockStore`, previews, scripted streams) to consume cards directly.
- Updated Archive and Archive Cleanup data engines/stores to subscribe to card streams instead of rebuilding rows from `thread/list`.
- Replaced Host Settings test-connection behavior with a card-stream snapshot tester instead of a raw session loader.
- Updated relay state views/store/engine/subscriptions so Dock and Archive emit `cards`, `upsertCards`, and `deleteCardIDs`; old `sessions`, `upsertSessions`, and `deleteSessionIDs` are rejected by the contract check.
- Updated relay diagnostics and observability to treat Dock rows as thread cards and to validate the `dock/subscribe` stream as a windowed card snapshot.
- Updated docs that were still describing physical proof as real `SessionSummary` rows.
- Split production identity/origin models out of `CodexDock/Models/SessionSummary.swift` into `CodexDock/Models/ThreadIdentityModels.swift`; the remaining fixture-only row seed is named `ThreadCardFixtureSummary`.
- Added `ThreadCardStreamSnapshotCollector` so Archive and Archive Cleanup collect stream catch-up windows before building one-shot snapshots.
- Added Archive route names to Swift observability and System Health so `archive/subscribe`, `archive/update`, and `archive/resync` are tracked alongside archive/unarchive commands.

### Refactored Or Deleted Legacy Paths

- Deleted `CodexDock/Models/SessionSummaryMapper.swift`.
- Deleted `CodexDock/State/SessionRowProjector.swift`.
- Deleted `CodexDockTests/ThreadListMappingTests.swift`.
- Renamed `AppServerDockClient` to `AppServerThreadCommandClient` so archive commands are not described as a Dock session loader.
- Renamed `DockSessionProjection` to `DockCardProjection`, `ArchiveSessionProjector` to `ArchiveThreadCardProjector`, and test helpers from `dockStreamSession` / `sessions:` to `threadCardFixture` / `cards:`.
- Renamed test fixtures from "Dock session loader" and `SessionSummary` wording to `ThreadCardFixture` wording.
- Renamed the remaining test-only `messageActivityDate` fixture field to `cardActivityDate`.
- Wired `npm test` through `npm run contract:check` so relay tests cannot pass with stale generated contract output.
- Updated Archive section ordering to prefer the relay-owned row `orderKey` before falling back to activity date/title.
- Extracted shared Archive/Archive Cleanup host card-stream loading into `ThreadCardHostSnapshotLoader`.
- Tightened Swift window validation so card stream `window.rowCount` must match the number of cards in that window.

### Contract Checklist

- [x] `DockThreadCard` is the single production list row object for Dock and Archive.
- [x] `ThreadCardStreamUpdate` is the single stream envelope for Dock and Archive.
- [x] `dock/subscribe`, `dock/update`, and `dock/resync` use `view: dock`.
- [x] `archive/subscribe`, `archive/update`, and `archive/resync` use `view: archive`.
- [x] Relay payloads use `cards`, `upsertCards`, and `deleteCardIDs`.
- [x] Relay payloads do not emit `messageSummary`, `messageUpdatedAt`, `upsertSessions`, or `deleteSessionIDs`.
- [x] Swift decodes generated `DockThreadCardDTO` and rejects the legacy stream DTO path.
- [x] Swift presentation uses relay-owned `title`, `displaySummary`, `activityAt`, and `orderKey`; it does not infer card summary or order from message history.
- [x] Archive restore/archive commands remain commands; list state moves through card-stream deltas.
- [x] Archive and Archive Cleanup wait for card catch-up windows before creating one-shot snapshots.
- [x] Host connection tests prove the card stream path, not raw `thread/list` loading.
- [x] Physical-phone proof wording now names real `DockThreadCard` rows.

### Verification

- `rtk npm run contract:generate` passed.
- `rtk npm run contract:check` passed.
- `rtk npm run test:relay` passed after diagnostic updates.
- `rtk swift test --filter AppServerClientTests` passed.
- `rtk swift test --filter DockStoreTests` passed.
- `rtk swift test --filter ThreadDetailStoreTests` passed.
- `rtk swift test --filter ArchiveCleanupStoreTests` passed.
- `rtk swift test --filter ArchiveDataEngineTests` passed.
- `rtk swift test --filter DockScreenStoreTests` passed.
- `rtk swift test --filter DiagnosticsLoggingTests` passed.
- `rtk swift test --filter SystemHealthProjectorTests` passed.
- `rtk swift test --filter DockStoreTestsProjection` passed.
- `rtk swift test` passed.
- `rtk make services`, `rtk make app-server-status`, `rtk make dock-relay-status`, and `rtk make relay-doctor` passed for the local relay.
- `rtk make relay-probe` passed for `ws://amir-m5.fairy-salmon.ts.net:4510`.
- `rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510` passed readiness/status checks for both hosts.
- `scripts/dock-relay-state-parity.mjs` reported `0` errors and exact Dock card parity for the current `500`-row stream window: no missing active cards, no extra cards, no duplicate card ids, and no order mismatches. The broader parity report still records non-card warnings for Codex storage/history disagreements and non-atomic goal rows.
- `rtk make relay-thread-fidelity` reported `0` errors. It still reports warnings for raw `thread/read` metadata differences that are outside the Dock card contract.
