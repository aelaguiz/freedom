✅ Model B first pass: the architecture should make the relay emit one canonical `DockThreadCard` contract, with a required relay-owned `orderKey`, required `activityAt`, and required `displaySummary`. Swift should render that card and preserve its order, not reinterpret optional upstream/message fields.

I would not sign the “cannot imagine a more perfect architecture” line yet. I need Claude to pressure-test whether Dock search/filter/group projection should also move fully to the relay now, or whether Swift can keep presentation projection as long as it only uses canonical card fields.

**Product Model**
Codex Dock is a phone-native operations dashboard for thousands of real Codex threads across personal hosts. The default question is: “What changed most recently, where is it running, and how do I narrow it by host, branch, repo, status, or search?” That comes from [Codex Dock Goals](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_GOALS_2026-05-29.md:19) and the activity-first UX doc at [CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md:28).

The app must be trustworthy enough that opening, archiving, pinning, filtering, counting, or ignoring a row feels safe. So a row is not just “a thread DTO”; it is a product card with identity, status, workspace, branch, useful summary, freshness, host, and newest ordering.

**Core Architecture**
Create one canonical app-facing product model: `DockThreadCard`.

It should replace Dock Home’s current split between relay `summary`/`updatedAt` and Swift `messageSummary`/`messageUpdatedAt`.

`DockThreadCard` should contain:

- `cardID`: stable `(logicalHostID, threadID)`.
- `logicalHostID`: relay instance identity, not endpoint string.
- `threadID` and `backendSessionID`.
- `orderKey`: required opaque relay-owned sort key.
- `activityAt`: required timestamp for display.
- `displaySummary`: required bounded text, derived from `latestSummary`, `preview`, then title fallback.
- `title`, `repoOrWorkspace`, `branch`, `status`, `sourceKind`, `lane`.
- `freshness` / `completeness` markers where needed.
- optional provenance/debug fields, not separate UI truth.

The key elegance move: `orderKey` is opaque. Swift can compare it, but cannot derive it. That makes newest ordering relay-owned while still allowing efficient incremental local insertion without dense `dock_order` shifts.

**Single Source Of Truth**
The current split is visible in code:

- Relay SQL orders by `dock_order`, `updated_at_ms`, then `thread_id` in [scripts/dock-relay-state-store.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:333).
- Relay normalization populates `summary` and `updatedAt`, but only copies `messageSummary` / `messageUpdatedAt` if upstream provides them in [scripts/dock-relay-state-views.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:262).
- Swift then sorts by missing `messageUpdatedAt` in [DockSessionTable.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockSessionTable.swift:257).
- Swift renders summary/activity from those same missing message fields in [DockRenderProjector.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Dock/DockRenderProjector.swift:60).
- Upstream Codex `Thread` guarantees `preview` and `updatedAt`, not `messageSummary` or `messageUpdatedAt`, in [Thread.ts](/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts:20).

So the new owner should be a generated contract source, not two hand-maintained DTOs. I would add a root-level contract package only because no existing path can generate both Node and Swift. Generated outputs would land back in existing owners: relay state views/subscriptions and `CodexDock/AppServer/**`.

**Performance Model**
Keep the current hard-won shape:

- Relay SQLite remains the compact materialized state source.
- `dock/subscribe` returns bounded windows with `totalRows`, `complete`, and `window`.
- `dock/update` sends row-level card upserts/deletes and catch-up windows.
- Large reorder or oversized delta becomes an explicit windowed snapshot/resync, not a giant payload.
- No row summary work reads turns or blocks subscribe/list.
- Detail still loads only when opened: `thread/read includeTurns:false`, paged `thread/turns/list`, then `thread/resume excludeTurns:true`.
- Swift main actor only publishes prepared render state; render/project work stays off-main per [client responsiveness doc](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_CLIENT_RESPONSIVENESS_ARCHITECTURE_2026-05-30.md:190).

**Migration Shape**
1. Define `DockThreadCard` and `DockViewStream` contract v2.
2. Make relay state views emit required `orderKey`, `activityAt`, and `displaySummary`.
3. Replace Swift Dock Home’s `DockStreamSessionDTO -> SessionSummary -> DockRowViewModel` semantic path with `DockThreadCard -> DockRowViewModel`.
4. Change `DockSessionTable` from dictionary-plus-resort to ordered reducer: `cardsByID` plus `orderedIDs` or `orderKey` index.
5. Retire `messageSummary` / `messageUpdatedAt` as Dock Home UI contract fields.
6. Move Archive and future Activity/Agents toward the same state-view contract family.
7. Replace endpoint-as-host identity with logical relay identity plus ordered endpoint fallbacks.

**Verification**
The proof must exercise the same stream lifecycle as the app:

- A relay fixture with live upstream-like rows: `summary`/`updatedAt` present, `messageSummary`/`messageUpdatedAt` absent.
- A Swift stream test that consumes `dock/subscribe` plus `dock/update` catch-up until `complete: true`.
- A parity harness update so `scripts/dock-relay-state-parity.mjs` does not stop after the first 500-row window.
- Assertions that Swift order equals relay `orderKey` order, not optional field order.
- Assertions that valid rows never show “No message preview” when `displaySummary` is present.
- Existing focused checks: `rtk npm run test:relay`, `rtk swift test --filter DockStoreTests`, `rtk swift test --filter AppServerClientTests`.

**Retire**
- Client sorting by `messageUpdatedAt`.
- Dock Home display fallback based on absent message fields.
- Test helpers that always populate message fields.
- Single-request parity proof for a windowed stream.
- Endpoint string as host identity.
- Any hot-path summary cache outside the relay state engine.

**Rejected**
- One-line fallback from `messageUpdatedAt` to `updatedAt`: fixes today’s symptom but leaves split ownership.
- Populate `messageSummary` in relay and keep old Swift semantics: preserves the bad contract name and makes future drift likely.
- Lint-only contract checks: they detect drift after humans already created it.
- Full raw history or turn mirroring to the phone: violates the performance model.
- Dense `dock_order` as the public rank: inserting one newer row can imply many rank shifts.

**Risks / Open Questions**
The biggest open question is where projection belongs. My lean answer is: relay owns card semantics and order; Swift owns visual rendering and local pin/label overlay. Claude should challenge whether search/filter/group projection also belongs in relay now.

I did not edit files and did not run tests. This was a read-only architecture pass.