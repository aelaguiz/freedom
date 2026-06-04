# Plan Implementation Log

Plan: `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md`
Audit log: `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04_PLAN_AUDIT.md`
Active scope: whole plan through simulator proof, review, commit, push, and relay deploy
Last updated: 2026-06-04T14:05:11Z
Current checkpoint: implementation complete, strict review fixes applied, full tests and simulator proof passed; commit/push and relay deploy still pending

## Resume Snapshot

- Current state: The approved architecture is implemented and strict-review fixes are applied. Client sends are non-blocking, the relay owns user-message delivery through `thread/message/send`, user-message identity crosses Swift, relay, projection, and UI, and final simulator proof passed.
- Next useful move: Commit/push, then refresh relays on Mac and `home`.
- Do not redo unless stale: Plan-readiness audit coverage in `USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04_PLAN_AUDIT.md`.
- Known blockers: none.
- Native subagents used or useful next: not used; current tool policy does not allow subagents without explicit delegation request.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Phase 1 identity seam | `Phase 1 - Identity Crosses The Whole Seam` | implemented | `TurnDTO`, `AppServerClient`, `ThreadDetailDTO`, `ThreadEvent`, `dock-relay-thread-detail-projection-adapter.mjs`, `dock-relay-outbound-user-message-store.mjs` | Swift and relay focused tests passed | thermo review complete |
| Phase 2 pending UI | `Phase 2 - Client Pending Row And Non-Blocking Send` | implemented | `ThreadDetailStore`, `OutboundUserMessage`, `ThreadDetailRenderProjector`, `ThreadMessageListView` | Swift tests and simulator proof passed | thermo review complete |
| Phase 3 relay owner hardening | `Phase 3 - Relay Delivery Ownership And Side-Door Closure` | implemented | `dock-relay-user-message-command.mjs`, `dock-relay.mjs`, `dock-relay-outbound-user-message-store.mjs` | `rtk npm run test:relay` passed | thermo review complete |
| Phase 4 simulator proof | `Phase 4 - Simulator Proof` | passed | `CodexDockUserMessageLatencyUITests`, `dock-relay-user-message-latency-fixture.mjs`, `Makefile` | `/tmp/codex-client/sim-ui-user-message-20260604T140445Z/user-message-latency.json` | thermo review complete |
| Phase 5 review/deploy | `Phase 5 - Review, Commit, Deploy` | in progress | review/deploy surfaces | final local tests passed | commit, push, relay refresh pending |

## Code Read Ledger

| Area | Files/symbols read | Why relevant | Fresh until | Notes |
| --- | --- | --- | --- | --- |
| Swift submit path | `ComposerView`, `SessionDetailView`, `ThreadDetailStore.sendDraft`, `ClientCommandEngine.sendDraft` | User submit caller and state owner | stale when these files change | Current send is blocking and projection-only. |
| Swift DTO/client | `TurnDTO`, `AppServerClient`, `AppServerMethods`, `AppServerThreadDetailSession` | Wire contracts and session commands | stale when DTO/client changes | Needs new `thread/message/send`. |
| Swift projection/render | `ThreadDetailDTO`, `ThreadEvent`, `ThreadDetailRenderProjector`, `ThreadDetailScreenStore` | Pending/canonical merge target | stale when projection/render changes | No `clientID` today. |
| Relay route/session | `dock-relay.mjs`, `dock-relay-thread-data.mjs`, `dock-relay-json-rpc-client.mjs` | Phone route and upstream delivery | stale when relay route changes | Sends currently require active upstream. |
| Relay state store | `dock-relay-state-store.mjs`, `dock-relay-state-engine.mjs` | Durable command storage pattern | stale when store changes | Reuse existing SQLite. |
| Projection adapter/ledger | `dock-relay-thread-detail-projection-adapter.mjs`, `dock-relay-thread-detail-ledger.mjs` | Canonical `clientId` projection | stale when projection changes | Must carry `clientID`. |
| Tests | `ThreadDetailStoreTests`, `AppServerClientTests`, `ClientCommandEngineTests`, relay tests | Proof targets and old expectations | stale when tests change | Existing tests encode no pending row. |

## Proof Freshness Ledger

| Proof | Scope covered | Result/context | Fresh until | Rerun trigger |
| --- | --- | --- | --- | --- |
| `rtk swift test --filter ThreadDetailStoreTests` | thread-detail send state, pending rows, canonical prune, voice final send | passed, 64 tests | Swift thread detail code changes | any `ThreadDetailStore` / pending projection change |
| `rtk swift test --filter ClientCommandEngineTests` | command engine wrapper for `thread/message/send` | passed, 3 tests after deleting the old raw-turn send wrapper | command engine changes | any `ClientCommandEngine` send change |
| `rtk swift test --filter AppServerClientTests` | JSON-RPC DTO/client encoding, including `thread/message/send` | passed, 54 tests, 5 skipped | app-server DTO/client changes | any DTO/client method change |
| `rtk swift test --filter ThreadDetailRenderProjectorTests` | pending row merge and canonical replacement | passed, 4 tests | projector changes | any thread-detail projection change |
| `rtk swift test` | full Swift package | passed, 369 tests, 5 skipped | Swift source/test changes | before commit after any Swift source change |
| `rtk npm run test:relay` | full relay test suite | passed, 195 tests | relay source/test changes | before commit after any relay change |
| `rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'` | real simulator UI send path against delayed upstream relay fixture | passed at `/tmp/codex-client/sim-ui-user-message-20260604T140445Z/user-message-latency.json`: composer clear 445 ms, pending row 539 ms, canonical row 2791 ms with 2500 ms artificial upstream ack delay and 700 ms UI budget | UI/relay send behavior changes | before final proof if user-message send path changes |

## Continuous Review Ledger

| Finding | Source | Status | Repair anchor | Notes |
| --- | --- | --- | --- | --- |
| Plan-readiness gaps PLA-001 through PLA-006 | `USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04_PLAN_AUDIT.md` pass 1 | fixed before implementation | architecture doc sections on identity, relay ownership, pending rows, side-door closure, proof, deployment | pass 2 approved the plan |
| UI proof initially passed xcodebuild but fixture was blocked because UI result was not written | `rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'`, run `/tmp/codex-client/sim-ui-user-message-20260604T134837Z/` | fixed | `Makefile` target now also writes `/tmp/codex-client/codex-dock-user-message-proof-ready.json` | rerun passed |
| Stale active-turn steering could fail instead of falling back to `turn/start` | relay user-message command self-review while implementing | fixed | `dock-relay-user-message-command.mjs` tracks attempted method and falls back from any stale `turn/steer` attempt | covered by relay command test |
| Main relay state store was becoming a command-table dumping ground | thermo-nuclear review | fixed | extracted `dock-relay-outbound-user-message-store.mjs`; `dock-relay-state-store.mjs` keeps only schema/prune hooks | keeps the command outbox boundary explicit |
| Swift send delivery depended on a weak store task | thermo-nuclear review | fixed | delivery task now captures session, command actor, thread ID, body, and client ID strongly enough to submit; screen updates are optional | reduces chance of losing a tap before it reaches relay |
| Old `ClientCommandEngine.sendDraft` raw-turn wrapper remained as a client-side side door | thermo-nuclear review | fixed | deleted the wrapper and its test; normal command path exposes `sendUserMessage` | raw DTO/client tests remain for protocol coverage |
| Relay idempotency could double-submit duplicate in-flight commands while first row was `acceptedByRelay` | thermo-nuclear review | fixed | existing rows now return stored command state; only inserted rows own upstream submission | covered by in-flight duplicate relay test |
| Relay input hash depended on incidental object key order | thermo-nuclear review | fixed | `stableInputJSON` sorts JSON keys before hashing | covered by duplicate request test with reordered input keys |
| Swift UI flipped pending row to `acceptedByRelay` before the relay answered | thermo-nuclear review | fixed | removed pre-send accepted state; pending stays pending until relay response | avoids false status |
| UI proof ISO timestamps were captured after all waits rather than at each observation | thermo-nuclear review | fixed | `UserMessageLatencyUIObservation` captures ISO timestamp and millisecond value together | final report timestamps match measured events |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| Relay `turn/start` / `turn/steer` | normal phone sends use command owner; no-ID direct sends rejected | no-ID direct sends rejected with `missing_client_user_message_id`; ID-bearing direct sends are wrapped through command owner | done | `scripts/dock-relay.mjs` |
| Swift normal send | uses `thread/message/send` | `ThreadDetailStore.sendDraft()` calls `ClientCommandEngine.sendUserMessage(...)` in a background task | done | `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/Commands/ClientCommandEngine.swift` |
| Projection userMessage `clientId` | projected as `clientID` | relay projection carries `clientId` to `payload.clientID`; Swift DTO reads `clientID` | done | `scripts/dock-relay-thread-detail-projection-adapter.mjs`, `CodexDock/AppServer/ThreadDetailDTO.swift` |

## Decision Carry-Through

| Decision | Owner | Plan carry-through | Code carry-through | Status |
| --- | --- | --- | --- | --- |
| Normal phone sends use `thread/message/send`; old turn routes are wrapped/rejected. | agent | `Old Route Convergence`, `Side Doors To Close` | `ThreadDetailStore`, `ClientCommandEngine`, `dock-relay-user-message-command.mjs`, `dock-relay.mjs` | implemented |
| A client-generated message ID is the cross-layer reconciliation key. | agent | `Identity Contract` | `ClientUserMessageID`, `clientUserMessageId`, projection `clientID`, outbound command table | implemented |
| The client clears the composer and renders pending immediately; server echo replaces pending later. | agent | `Client State Machine` | `PendingOutboundMessage`, projector merge, UI delivery badge | implemented |

## Pass Notes

### 2026-06-04T12:56:49Z - Implementation Start

- Intent: Start Phase 1 from the approved plan.
- Changed: implementation log only.
- Read: plan, audit log, relevant code surfaces listed above.
- Proof: none yet.
- Review: plan-readiness approved.
- Next: implement identity seam.

### 2026-06-04T13:52:08Z - Implementation And Proof Checkpoint

- Implemented: Swift `thread/message/send` method, non-blocking `ThreadDetailStore.sendDraft()`, pending outbound message model, canonical `clientID` reconciliation, relay command owner, durable outbound command rows, direct-route side-door rejection, and controlled simulator proof target.
- Important user-visible behavior: tapping send clears the composer immediately, inserts a pending row immediately, and lets the relay/server echo replace that row when Codex confirms the message.
- Proof: full Swift package passed, full relay suite passed, and the controlled iPhone 17 simulator proof passed with 443 ms composer clear and 538 ms pending row under a 700 ms budget while upstream ack was delayed by 2500 ms.
- Review: thermo-nuclear code quality review still pending.
- Next: strict review, fix findings, rerun final proof if code changes, then commit/push and refresh relays.

### 2026-06-04T14:05:11Z - Strict Review Complete

- Review: thermo-nuclear code quality review completed. Findings were structural, not cosmetic: command storage boundary, weak client delivery task, raw-turn side door, in-flight duplicate idempotency, input hash canonicalization, premature accepted state, and UI proof timestamp precision.
- Fixed: extracted outbound command storage, deleted the raw client send wrapper, made duplicate command rows return without resubmitting, canonicalized input hashing, kept pending UI pending until relay response, and repaired proof timestamp capture.
- Proof: `rtk swift test` passed 369 tests with 5 skipped; `rtk npm run test:relay` passed 195 tests; `rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'` passed at `/tmp/codex-client/sim-ui-user-message-20260604T140445Z/user-message-latency.json`.
- Final simulator timings: composer clear 445 ms, pending row 539 ms, canonical row 2791 ms with 2500 ms artificial upstream ack delay and 700 ms UI budget.
- Remaining: commit, push, refresh relays on Mac and `home`.
