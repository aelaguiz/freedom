I have everything I need. The decisive findings: the app already exposes machine-readable literal-display values on every Dock row and detail surface, the real relay path is the default (scripted mock is opt-in via one env var), host identity is canonically resolvable, and the existing Node audit already owns relay/client-route truth + lag math I can reuse. Here is my independent round-01 design.

---

# Simulator Displayed-UI Proof Leg — Model A (Opus 4.8 Max) design

## 1. Proposed harness design (concise)

Add a **third observer of the same relay** and prove the *rendered* simulator UI is a faithful, timely projection of the relay/client-route truth the first two legs already establish — without re-deriving that truth.

Three cooperating pieces, orchestrated by one Makefile target:

1. **Literal-display sampler** — a new XCUITest class `CodexDockSimulatorDisplayedUISyncTests` in the existing `CodexDockUITests` target. It launches the app on the real relay-backed path (`launchRelayBackedApp`, `CODEX_DOCK_HOSTS=<relay>:4510`, **no** `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`), then over a bounded duration samples the literal accessibility tree on a fixed interval: the Dock root value, the materialized row set with per-row `automationValue`, and (for selected rows) the opened detail's root/header/message-list/event-card values. Each sample is timestamped with the host wall clock and exported as `XCTAttachment` JSONL. It makes **no** truth judgments.

2. **Relay-truth recorder** — the existing `scripts/dock-relay-sync-audit.mjs` running concurrently in `soak` against the same `ws://127.0.0.1:4510`, producing the already-built fresh-`dock/subscribe` truth + long-lived-stream + detail-probe report, timestamped per sample (plus a small `--stream-event-log` addition for finer-grained relay-seen timestamps).

3. **Join/judge** — a new `scripts/dock-relay-sim-ui-audit.mjs` that **imports** the existing audit's comparators (`compareDockStates`, `evaluateStreamConvergenceLag`, `cardID`, `normalizeForComparison`, report schema) and joins the UI-sample series to the relay-truth series by wall clock + `(logicalHostID, threadID)` key, emitting the same report/invariant/failure-code shape extended with a `renderedUI` plane.

The rendered UI is treated as **just another stream consumer**: the exact `evaluateStreamConvergenceLag` semantics that already fail the Node long-lived stream on slow convergence are reused to fail the *literal screen* on slow convergence. That is the entire lag story — no new lag model.

Completion proof = sampler (real path) + judge (UI plane invariants joined to existing relay truth) + rendered-plane lag budget + multi-sample over-time + two stable samples + reusable report. Everything else (`sim-logs`, `sim-debug-bundle`, `client-observability.json`, screenshots) is **diagnostic support only**, never substituted for the literal-display comparison.

## 2. Evidence read and why it mattered

- `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md` (Phase 6, §Time-Based Sync, §Completion Gate, Dock Client Probe rules) and `..._IMPLEMENTATION_LOG.md` — established that legs 1–2 (Codex→relay, relay→client-route) are *done* at the relay level, that simulator UI is the named third leg, that lag must fail even on eventual match, and that scenario actuators are **not yet built** (so the UI leg must not depend on Phase 4).
- `scripts/dock-relay-sync-audit.mjs` (full) — the existing client-path audit. Critical: it already owns `collectDockClientPathSnapshot` (fresh `dock/subscribe` truth), `DockStreamProbe`, `compareDockStates` (`:763`), `evaluateStreamConvergenceLag` (`:820`) + `applyStreamLagBudget` (`:867`) + `dock_stream_lag_exceeded`, `sanitizeCardForReport`/`normalizeForComparison` redaction, `probeThreadDetail` (turn drain, resume, `detail_*` codes), and an exported surface (`:2027`). This is the "no second source of truth" anchor — the judge must reuse these, and the lag math is directly transferable to the UI plane.
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift:121` — the scripted mock client is selected **only** when `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO` parses; absence ⇒ real `AppServerThreadCardStreamClient`. This is the exact gate that keeps the proof on the real relay path and excludes the forbidden scripted transport.
- `CodexDockUITests/CodexDockAutomationSmokeTests.swift` — proven patterns to reuse: `launchRelayBackedApp` (`:461`), real-path Dock-to-detail (`testDockRowOpensSessionDetailByIdentifierWhenRowsExist` `:433`), `waitForStringValue` polling, `scrollUntilElementExists`, identifier-prefix row discovery, `debugDescription` tree dumps. It also shows the scripted tests assert body text — which is why those scenarios are regression-only, not completion proof.
- Literal-display value sources (the observation surface):
  - `CodexDock/Features/Dock/DockView.swift:786` `dockScreenValue` → `loaded; rows=N; pinned=P; lens=X; search=bool; filters=K; …` on `AutomationID.Dock.root`.
  - `CodexDock/Features/Dock/DockSharedViews.swift:272` `DockRowViewModel.automationValue` → `host=…; thread=…; status=…; origin=…; label=…; Pinned/Not pinned`; row id `AutomationID.swift:243`.
  - `CodexDock/Features/Session/SessionDetailView.swift:125/188` `sessionScreenValue`/header → `host=…; thread=…; live=…; events=N; status=…`.
  - `CodexDock/Features/Session/ThreadMessageListView.swift:113` message list → `events=N; filter=…`; `:181` `Session.messageCard(eventID: event.id)`; `:400` request-card `card=…; kind=…; status=…; needs-input=…`.
  These prove the rendered SwiftUI exposes a stable, structured projection of exactly what is on screen — readable by XCUI without reaching into the store.
- `CodexDock/State/DockHostIdentityResolver.swift` — maps configured `host:port` ↔ relay `logicalHostID` (from `DockStreamHostDTO`/`DockThreadCardDTO`). This is what makes UI-row↔relay-card correlation sound; the audit already keys cards by `logicalHostID` (`dock-relay-sync-audit.mjs:522`).
- `CodexDock/Configuration/HostRegistry.swift:27` + `DockHostConfiguration` `validateAppFacingRelayEndpoint` (`:205`) — `CODEX_DOCK_HOSTS` drives the subscribed relay and the client itself **rejects** raw app-server `:4500`, enforcing the "relay-backed only" hard constraint in-client.
- `Makefile` — `SIM ?= iPhone 17` (`:34`), `app-test` passing `CODEX_DOCK_UI_TEST_HOSTS` (`:214`), `app` injecting `SIMCTL_CHILD_CODEX_DOCK_*` (`:211`), `sim-logs` (`:205`), `sim-debug-bundle` copying `…/CodexDock/Diagnostics` (`:193`). These are the Makefile-owned simulator flows to reuse rather than raw `xcodebuild`/`simctl`.
- `CodexDock/Diagnostics/ClientObservabilityStore.swift:278` + `ObservabilityContract.swift` — app already persists `client-observability.json` route health under the Diagnostics container. Useful triage, but route-health ≠ literal display ⇒ diagnostic support, not proof.

## 3. Existing paths/patterns to adopt

- **Real-path launch:** `launchRelayBackedApp(hosts:)` with no scenario env (`CodexDockAutomationSmokeTests.swift:461`).
- **Literal-display hooks:** `AutomationID.*` + the `accessibilityValue` projections above; treat the Dock root/row/session/message/request values as the observation API.
- **Relay truth + lag + redaction + detail probe:** reuse `dock-relay-sync-audit.mjs` exports verbatim (`compareDockStates`, `evaluateStreamConvergenceLag`, `applyStreamLagBudget`, `cardID`, `normalizeForComparison`, `sanitizeDockSnapshotForReport`, `probeThreadDetail`, report/`failures`/`unsupportedFacts` schema).
- **Host correlation:** `DockHostIdentityResolver` mapping; single-host run makes it trivial and is the recommended default.
- **Ops flows:** `rtk make services`, the `app-test` xcodebuild-in-Makefile pattern, `sim-logs`, `sim-debug-bundle`; `CODEX_DOCK_HOSTS`/`CODEX_DOCK_UI_TEST_HOSTS` env wiring.
- **Owner-path for actuation:** the plan's **Controlled Scenario Runner** (Phase 4) is the owner of deterministic change injection. The UI leg *consumes* it; it does not build its own actuators.

## 4. Exact invariants the harness must enforce (rendered-UI plane, `U-xx`)

Dock/Home:
- **U-01 Reaches loaded:** Dock root value reaches `loaded; …` (not stuck `idle`/`loading`/`configuration-error`) within a startup budget.
- **U-02 Displayed set faithful (windowed):** the materialized displayed row set, keyed by row-id `(host,thread)` → resolved `(logicalHostID, threadID)`, equals the relay fresh-`dock/subscribe` active set **for the rendered window**; every relay "must-exist" probe card (newest, a live one) is reachable by scroll; no displayed row is absent from relay truth.
- **U-03 Per-row fields correct:** displayed `status` == relay card status (after live projection); displayed `origin` == relay `sourceKind`.
- **U-04 Archive boundary:** no archived thread appears as a Dock active row; archived ids appear only in the Archive view plane (cross-checked against relay `archived=true`).
- **U-05 Host isolation:** every displayed row's resolved logical host == the subscribed host; no foreign-host rows.
- **U-06 Count consistency:** Dock root `rows=N` is consistent with the relay windowed total under the active lens/search/filters.
- **U-07 No duplicates:** no repeated row identifier in the rendered tree.
- **U-08 Order:** displayed top-of-list ordered prefix matches relay active all-source order for stable rows (reusing the existing order/movement classification).
- **U-09 Stale/offline honest:** when relay reports a scope stale/offline, the rendered host group/root shows offline/stale (reuse the proven `Offline` label assertion); stale data is never presented as fresh.

Detail (row → screen):
- **U-10 Right thread/host:** opening a displayed row yields detail value `thread=` == row thread id and `host=` == row host (UI-plane T-01/T-02).
- **U-11 Event set + count:** displayed `events=N` and the set of `messageCard(eventID:)` ids match the relay detail probe's drained turn/event id set for the rendered window (structural; no body text).
- **U-12 Live gating:** the live pill shows `.live` only after the relay detail probe shows read+turns+resume succeeded; resume-failed ⇒ stale/error, not live (UI-plane T-08/T-09).
- **U-13 No foreign-thread mutation:** the open detail's `thread=` stays fixed and its event-card ids stay within that thread across samples.
- **U-14 Request cards:** a server request visible after the boundary appears as both a timeline event and a `RequestCard` card; resolution updates the card status label (only asserted when a request occurs).

Lag + over-time (the load-bearing ones):
- **U-15 Dock render lag:** for every relay-truth transition, the rendered Dock display must converge within `--max-ui-lag-ms` (default 2,000); persistent divergence ⇒ `dock_ui_lag_exceeded`. (Direct reuse of `evaluateStreamConvergenceLag` with the UI sample series as the consumer.)
- **U-16 Detail render lag:** a change to the open thread appears in the rendered detail within `--max-ui-lag-ms`.
- **U-17 Two stable samples:** after convergence, ≥2 consecutive UI samples agree with relay truth (mirror `K-03`).
- **U-18 Stale-not-counted:** a relay-stale/incomplete scope is never scored as a fresh UI pass (mirror `K-05`).

New failure codes (additive, mirroring existing taxonomy): `dock_ui_not_loaded`, `dock_ui_missing_row`, `dock_ui_unexpected_row`, `dock_ui_row_field_mismatch`, `dock_ui_order_mismatch`, `dock_ui_archive_boundary`, `dock_ui_host_mismatch`, `dock_ui_duplicate_row`, `dock_ui_stale_reported_fresh`, `dock_ui_lag_exceeded`, `detail_ui_wrong_thread`, `detail_ui_event_set_mismatch`, `detail_ui_stale_live`, `detail_ui_request_card_missing`, `detail_ui_lag_exceeded`, `sim_ui_clock_skew` (guard).

## 5. How the harness observes literal simulator UI state

Through the XCUI accessibility tree only — the `accessibilityValue`/identifier projections are derived from the rendered view models, i.e. literally what SwiftUI drew, not the store:
- Dock plane: read `AutomationID.Dock.root` value (`rows/pinned/lens/search/filters/state`); enumerate materialized rows via identifier prefix `codexdock.dock.row.`, reading each row's `automationValue` (`host/thread/status/origin/label/pin`); scroll (`scrollUntilElementExists`) to prove must-exist/absence of specific ids.
- Detail plane: tap a sampled row, read `codexdock.session.root.<thread>`/`Session.header`/`Session.messageList` values (`host/thread/live/events/status/filter`), enumerate `codexdock.session.message.<eventID>` ids and `RequestCard` card/status values.
- Each sample = `{wallClockISO, monotonicMs, dockRoot, rows:[…], detail?:{…}}` appended as an `XCTAttachment` (and optionally NSLog with a marker for `sim-logs` triage). No prompt/transcript/body text is captured — only structural fields — preserving the redaction rules.

## 6. How the harness correlates UI state with the existing relay/client-route audit report

- The judge consumes the **existing** `dock-relay-sync-audit.mjs` report (the canonical relay/client-route truth) and the UI-sample JSONL. It does not recompute relay truth.
- **Join key:** UI row id `(hostID, threadID)` → `DockHostIdentityResolver` → `(logicalHostID, threadID)` == audit `sanitizeCardForReport` key. Single-host runs make the host mapping identity-trivial; the orchestrator passes the configured↔logical mapping to the judge.
- **Time join:** both producers run on the same Mac wall clock (the simulator shares the host clock), so each UI sample is matched to the relay-truth state in effect at its `wallClockISO`. A `sim_ui_clock_skew` guard compares orchestrator-stamped start markers from both producers and refuses to score if skew exceeds a small threshold.
- **Field comparison** reuses `normalizeForComparison`/`compareDockStates` so the UI-plane diff uses the same normalization/redaction as legs 1–2 — one comparator, one redaction policy, no divergent truth.

## 7. How over-time lag is measured through the rendered client

- The sampler runs for `--sim-duration-ms` at `--sim-sample-ms` (≤ budget/4, e.g. 250–500 ms for a 2,000 ms budget) so resolution is finer than the budget and a true pass is never falsely failed while a true fail is always caught.
- For each relay-truth transition (`t_relay_seen` from the audit / `--stream-event-log`), the judge finds the first UI sample at `t ≥ t_relay_seen` whose literal display reflects it; `lag = t_ui_seen − t_relay_seen`. This is fed through the existing `evaluateStreamConvergenceLag`/`applyStreamLagBudget`, so divergence-that-converges-too-slowly **and** divergence-that-never-converges both fail (`dock_ui_lag_exceeded` / `dock_ui_missing_row`) — eventual match does not rescue a lagging screen.
- Two tiers of change source: **Tier A (now)** passive over-time convergence against concurrent relay activity on the real home — fully implementable today, proves the rendered plane stays converged and timely across many samples; **Tier B (after Phase 4)** the Controlled Scenario Runner mutates an isolated `CODEX_HOME` for deterministic `t_change`, giving precise change-to-screen lag without spending the user's tokens. Tier B strengthens, but Tier A already satisfies "fail on lag, over time."

## 8. Implementation slices and proof commands

- **Slice 1 — Sampler:** `CodexDockSimulatorDisplayedUISyncTests` (real path, bounded over-time sampling, `XCTAttachment` export); new env knobs `CODEX_DOCK_SIM_SYNC_DURATION_MS`/`_SAMPLE_MS`/`_OUT`. *Why new:* no existing test samples literal display over time or exports timestamped samples; existing tests are single-shot or scripted. Lives in the existing UITests target — no new target.
- **Slice 2 — Truth event log:** add `--stream-event-log <path>` to `dock-relay-sync-audit.mjs` (append each applied `dock/update`/fresh-subscribe with `receivedAt`+seq). *Why:* finer relay-seen timestamps for the join; reuses existing notification records, no new truth.
- **Slice 3 — Judge:** `scripts/dock-relay-sim-ui-audit.mjs` importing the audit's comparators; emits `renderedUI` plane + `U-xx` invariants + `dock_ui_*` codes in the existing report schema. *Why new file, not folded in:* distinct inputs (xcresult/sample file) and plane; must reuse, not duplicate, the relay comparators.
- **Slice 4 — Orchestrator:** Makefile `sim-sync-audit` target: `services` → start Node soak recorder (background, `--stream-event-log`) → `xcodebuild test -only-testing:CodexDockUITests/CodexDockSimulatorDisplayedUISyncTests` with sync env on `SIM='iPhone 17'` → extract attachments → run judge. *Why:* keeps raw `xcodebuild`/`simctl` out of the normal workflow per the plan.
- **Slice 5 — Runbook + double-loop:** document in README/runbook; run the loop twice for the same pass (gate item 14).

Proof commands (shape):
```bash
rtk make services
rtk make app-server-status && rtk make dock-relay-status
# one orchestrated over-time rendered-UI proof on iPhone 17, real relay path:
rtk make sim-sync-audit SIM='iPhone 17' \
  CODEX_DOCK_UI_TEST_HOSTS=127.0.0.1:4510 \
  SIM_SYNC_DURATION_MS=180000 SIM_SAMPLE_MS=400 MAX_UI_LAG_MS=2000
# judge artifacts under /tmp/codex-client/sim-ui-audit/*.json|*.md, fail-on-diff
```

## 9. Rejected alternatives and risks

Rejected:
- **Scripted `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO` tests as completion proof** — forbidden mock transport (`CodexDockBootstrapView.swift:121`); regression-only.
- **Screenshot/vision diffing as proof** — not literal-state, brittle, can't assert ids/order/counts; keep screenshots as triage attachments only.
- **App-side "render-committed" diagnostics file as the proof** — one step removed from pixels and needs app code; keep `client-observability.json` as diagnostic support, not proof.
- **A second relay-truth model inside the judge** — violates "no second source of truth"; the judge imports the existing audit's comparators.
- **One-shot UI check** — fails the over-time/lag requirement.
- **Driving real `turn/start` from the test to force changes** — mutating/token-spending, against the observability "no auto-mutate" rule; use Phase 4 isolated-home actuation instead.

Risks:
- **SwiftUI virtualization:** only on-screen rows materialize, so UI set-equality is window-scoped + scroll-probed + count-checked; full-set parity remains owned by legs 1–2. Honest boundary, stated as residual.
- **Sample-interval lag resolution:** bounded by `--sim-sample-ms`; mitigated by ≤ budget/4 and conservative (over-reports, never under-reports, lag).
- **Clock skew** between producers: low risk (shared Mac clock) but guarded by `sim_ui_clock_skew`.
- **Host-identity edge cases** in multi-host runs: mitigated by recommending single-host default and leaning on `DockHostIdentityResolver`.
- **Real-home moving state** during a long run (the same non-atomic gap the impl log already records): the judge classifies movement via the audit's before/after instead of failing client delivery.
- **Determinism without Phase 4:** Tier A is non-deterministic in *what* changes; mitigated by long duration + two-stable-sample requirement, with Tier B as the deterministic upgrade.

## 10. What I need from Model B to converge

1. **Lag observation point:** do you accept interval-sampling + offline join (reusing `evaluateStreamConvergenceLag`) as the rendered-plane lag mechanism, or do you favor in-test `waitForStringValue` precise timing, or an app-emitted render timestamp? I argue for sample+join as the lean spine; converge on one.
2. **UI set-equality scope:** agree that window-scoped + scroll-probed + count-checked is the correct, honest boundary given virtualization (full-set parity owned by legs 1–2)? If you want full-set UI parity, show how without unbounded scrolling.
3. **Change source for completion:** is Tier A (passive over-time on real home) sufficient for the completion gate, with Tier B (Phase 4 isolated-home actuation) as the determinism upgrade — or do you require deterministic actuation before the leg can be called complete?
4. **Judge placement:** sibling `dock-relay-sim-ui-audit.mjs` importing audit exports vs. a `--ui-samples` mode inside `dock-relay-sync-audit.mjs`. I lean sibling-for-cohesion; flag if you see a duplication risk either way.
5. **Detail correctness depth:** agree to assert detail structurally (event-id set, `events=N`, live label, request-card status) and **not** body text, to preserve redaction — or do you see a contract-required field that forces text comparison?
6. **Single-host vs multi-host default:** I propose single-host (`127.0.0.1:4510`) as the canonical proof with multi-host as the host-isolation extension; converge on the default to keep correlation trivial.
