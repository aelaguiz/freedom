I have enough evidence. Let me synthesize. I verified the existing status space (5-case `DockRowStatusKind`: running/idle/notLoaded/error/unknown; Codex `ThreadStatusDTO`: notLoaded/idle/systemError/active(activeFlags:[…])/unknown) and confirmed the relay's `LiveStatusCache` is already a `setInterval` background poller — so the plan's 7-status enum is a clean superset and the "always-on aggregator" generalization is grounded.

---

## Review: `CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md`

### Blocking findings

**none.**

Every load-bearing claim I checked is accurate, and the core architecture is feasible on existing rails. Specifically verified true: all section-3.2 file/line citations (`aggregateThreadList`@457, `LiveStatusCache`@43, `DockStore.reload`@569 / `loadAllHostsPublishingPartial`@665 / `makeSnapshot`@746 / `deduplicated`@876, `loadSessions`@83, `ThreadListDTO.notLoaded`@257, `SessionSummaryMapper`@334, `SessionRowProjector`@58, `HostSettingsStore`@152, `AutomationID.notLoadedExplanation`@109, `DockFilterSurfaceView`@103/@181, `DockSharedViews`@258); `npm run test:relay` exists and runs the cited test files; every `rtk make` target exists (`app`, `app-test`, `sim-logs`, `iphone-17-pro`, `services`, `*-status`, `*-logs`); all five `swift test --filter` targets exist as files and the package is genuinely macOS-buildable (UIKit/AppKit imports are `#if os(...)`-guarded, `.macOS(.v14)` declared, `FoundationNetworking` guards present), so the Phase 3–4 proof gates are real; `dock/*` is net-new; server→client push already exists on both ends; `.codex-dock/` is gitignored; the destructive-partial-snapshot root cause is real (DockStore.swift:665–764 unions only current-refresh outcomes, still-checking hosts contribute host-state only). No duplicate-runtime-path, no fallback, no data-loss instruction. The plan is safe to audit.

### Non-blocking findings

1. **(Highest priority — pin this in audit) Per-stream sequencing/scoping is described in singular terms that conflict with the per-host-stream design.** §0.5 says deltas apply when "`baseSeq` equals **the client's current `seq`**" (singular), §5.3 names a single `DockSessionTable`, and Phase 3 says it "atomically replaces on snapshot" — but §1.4/§5.2/§5.4 specify "**one DockStreamClient per configured relay host**" + "trivial client union," and each per-host relay owns its own `epoch`/`seq`. A literal single-table/single-seq reading would let one host's snapshot/resync clear another host's union rows and cause perpetual cross-stream gap→resync — the exact row-clearing the plan exists to prevent. The per-host-stream architecture makes the safe implementation the natural one (seq is server-assigned per connection), so this is unlikely to actually ship wrong, but the plan should state explicitly: `(epoch, seq, baseSeq)` are tracked **per stream**, and a snapshot/resync replaces only the rows for the host(s) in that snapshot, never the global union.

2. **Heartbeat `seq` vs delta `baseSeq` chain is underspecified.** §5.3 gives heartbeat `{epoch, seq, asOf, freshness}` (no `baseSeq`) and delta `{epoch, baseSeq, seq, …}`. The plan never says whether a heartbeat's `seq` advances the delta chain — i.e., what `baseSeq` the next delta references after a heartbeat. If heartbeats advance `seq` but the client treats them as row-neutral, the next delta can spuriously fail the gap check. Self-healing via resync, but worth nailing for an audit.

3. **Delta vs heartbeat are discriminated by presence/absence of `baseSeq` rather than an explicit tag.** Both ride `dock/update`. An explicit `type`/`kind` field would match the plan's "fail loud" ethos and avoid a fragile structural discriminator; consider adding one.

4. **Codex active-flag array → singular wire status needs a precedence rule.** The existing input is `ThreadStatusDTO.active(activeFlags: [ThreadActiveFlagDTO])` (an array), while the wire enum is one status per row. The §5.4 mapping table lists `running` / `needsInput` / `needsApproval` separately but doesn't state precedence when a row carries multiple active flags (e.g., needsApproval > needsInput > running). The adapter spec should define it.

5. **`dormant` visibility wording is internally inconsistent.** The §5.4 mapping-table reason for `notLoaded → dormant` says "this is **not** a user-facing product state," yet the §5.5 mockup shows a visible "Dormant history row" / "Dormant" label. The contract (notLoaded off the wire; canonical enum) is intact either way, but clarify whether `dormant` renders as a visible badge or a neutral/no-badge state — this is the same product question Option E raised in the root-cause doc.

6. **Trivial:** §3.2 cites `dock-relay-phase5.test.mjs:304` for "`notLoaded` survives list output"; the actual assertion is `:306` inside the same test block starting at `:192`. Not misleading — fix only if convenient.

### Evidence read

- `docs/CODEX_DOCK_HOME_REFRESH_NOT_LOADED_ROOT_CAUSE_2026-05-29.md` — source root cause; confirmed destructive-partial-snapshot + upstream `notLoaded` framing the plan builds on, and the `:4510` relay / `:4500` app-server topology.
- `package.json` — confirmed `test:relay` exists and runs the cited relay test files (DoD depends on it).
- `Makefile` — confirmed every `rtk make` target the DoD/runbook cites exists; confirmed `app-test` is `xcodebuild test` on the iOS sim (the real E2E runner).
- `Package.swift` + `project.yml` — established the two build systems; `.macOS(.v14)`/`.iOS("26.0")` SwiftPM package vs iOS-only XcodeGen app; validated `swift test` as a real proof path.
- `CodexDock/**` import/guard sweep — confirmed UIKit/AppKit are `#if os`-guarded (so macOS `swift test` compiles), which de-risked the Phase 3–4 proof gates.
- `scripts/dock-relay.mjs:700–795` — confirmed relay can push server→client JSON-RPC notifications (`sendNotification`/`sendJson`) and currently ignores downstream notifications; grounds `dock/update` push feasibility.
- `CodexDock/AppServer/AppServerClient.swift` (grep) — confirmed client exposes incoming `notifications: AsyncStream<JSONRPCNotification>`; grounds transport reuse.
- `scripts/dock-relay-thread-data.mjs:457`, `scripts/dock-relay-live-status-cache.mjs:43–132`, `scripts/dock-relay-phase5.test.mjs:188–310` — confirmed the relay anchors, that `LiveStatusCache` is an always-on `setInterval` poller, and that the `notLoaded`-survives + `dockRelaySource`-stripped contracts are real protected tests to replace.
- `CodexDock/State/DockStore.swift:4–9, 665–764`, `CodexDock/Models/SessionSummaryMapper.swift:328–345`, `CodexDock/AppServer/ThreadListDTO.swift:255–275` — confirmed current status enum/mapping space and that the plan's 7-status enum is a non-lossy superset (splits `active(activeFlags:)`, maps `notLoaded→dormant`, `systemError→error`).
- `.gitignore`, all Swift line citations, `CodexDockTests/` listing — confirmed `.codex-dock/` convention and that the five cited test targets exist.

### Final judgment

**acceptable for plan-audit? yes.** No blockers; the plan is well-grounded and the cutover/no-fallback posture is clean. Recommend the audit/implementation pin down non-blocking item #1 (per-stream `epoch/seq` scoping and per-host snapshot replacement) early, since it touches the core "never clear rows" non-negotiable, and resolve the smaller protocol-precision items (#2–#4) in the relay Phase 1 contract.
