Net: I would not build a new test framework beside the repo. I’d make `Makefile` the single public test surface, with three clear tiers that wrap the existing Swift, Node, simulator, and device proof paths.

**Proposed Architecture**

Use these canonical tiers:

- `rtk make test-smoke`: fast local proof. Wrap `rtk npm test` plus focused `rtk swift test` filters for `AppServerClientTests`, `DockStoreTests`, and `ThreadDetailStoreTests`.
- `rtk make test-full`: smoke plus `rtk make app-test SIM='iPhone 17'` and the strict controlled simulator matrix.
- `rtk make test-realtime`: define this plainly as “live over-time projection proof,” not only OpenAI Realtime transcription. It should run the relay soak path and strict simulator over-time UI proof with `MAX_UI_LAG_MS=2000`.

Keep `package.json`, `Package.swift`, and `project.yml` as sub-manifests. Do not add a separate runner script as the top-level interface.

**Evidence Read**

- [Makefile](/Users/aelaguiz/workspace/codex-client/Makefile:136): already owns service, app, simulator, proof, and device targets.
- [package.json](/Users/aelaguiz/workspace/codex-client/package.json:9): Node test surface already composes contract, relay, and host-service tests.
- [Package.swift](/Users/aelaguiz/workspace/codex-client/Package.swift:19): SwiftPM owns `CodexDockTests`.
- [project.yml](/Users/aelaguiz/workspace/codex-client/project.yml:75): XcodeGen owns app/unit/UI test wiring.
- [README.md](/Users/aelaguiz/workspace/codex-client/README.md:39): physical phone proof cannot be replaced by mocks, loopback, or simulator-only evidence.
- [CodexDock/Projection/StreamReconciler.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Projection/StreamReconciler.swift:76) and [ProjectionReducer.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Projection/ProjectionReducer.swift:147): existing canonical Swift runtime owners.
- [scripts/dock-relay-controlled-simulator-fixture.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-controlled-simulator-fixture.mjs:32) and [dock-relay-controlled-simulator-matrix.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-controlled-simulator-matrix.mjs:12): existing scenario registry and matrix verifier.
- [scripts/proof-report-contracts.mjs](/Users/aelaguiz/workspace/codex-client/scripts/proof-report-contracts.mjs:173): proof reports already reject weak evidence like raw `:4500` and route side doors.

**Adopt These Patterns**

- Contract truth: `contract/projection/**`, `contract/proof/**`, `scripts/check-projection-contract.mjs`, `scripts/check-proof-report-contracts.mjs`.
- Swift unit owners: `ProjectionReducerTests`, `ProjectionRuntimeTests`, `AppServerClientTests`, `DockStoreTests`, `ThreadDetailStoreTests`.
- Simulator proof owner: `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`.
- Scenario owner: controlled simulator fixture plus matrix verifier.
- Public commands: `Makefile` only.

**Demote Or Stop Using As Acceptance Proof**

- `sim-ui-dump`: diagnostic only.
- `/readyz`, `/statusz`, `/routesz`, logs, debug bundles: diagnostics only.
- `app-server*` Make aliases: compatibility names, not canonical docs surface.
- `thread/detail/read`: not client-display proof.
- `projection/witness/read`: proof-only witness, never app UI route.
- Screenshots, preview rows, mocks, scripted transports, loopback-only WebSockets, raw `ws://127.0.0.1:4500`: never completion proof.

**Adding New Tests**

Pick the smallest owner first:

- Protocol/DTO: `AppServerClientTests` or contract schemas.
- Projection law: `ProjectionReducerTests`.
- Reconnect/catch-up/runtime: `ProjectionRuntimeTests`.
- Dock behavior: `DockStoreTests` or `DockStoreTestsProjection`.
- Thread Detail behavior: `ThreadDetailStoreTests` or lifecycle tests.
- Real over-time UI scenario: add to `dock-relay-controlled-simulator-fixture.mjs`, add matrix requirements in `dock-relay-controlled-simulator-matrix.mjs`, then expose through the Makefile matrix list.

**Docs**

`AGENTS.md` needs a short “Unified Testing” section with the three commands and what counts as proof. `README.md` should point to one new docs file under `docs/`, and old exhaustive sync docs should become historical references, not the canonical entrypoint.

**Risks / Open Questions**

- The scenario list is duplicated between `Makefile` and matrix scripts. Make one source canonical or generate the other.
- `test-realtime` is ambiguous because the repo also has OpenAI Realtime transcription. Docs must define it as live over-time proof.
- Physical phone behavior still needs real device proof or exact blocker text.

What I need from the other model: whether it proposes any new runner or scenario language. If it does, I would push back unless it proves why `Makefile` plus the existing matrix/proof-contract system is not enough.