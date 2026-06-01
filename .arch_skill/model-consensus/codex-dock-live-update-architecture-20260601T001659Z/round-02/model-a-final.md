All three of GPT‑5.5's material corrections are verified against the repo — none requires dropping a hard requirement or inventing an unevidenced pathway, and each tightens the position. We have clean convergence. Evidence:

- **`--turn-items-view` exists, but `itemsView` never actually ships on the detail path.** The flag is real (`dock-relay-sync-audit.mjs:91`, parsed at `:261‑267`, default `turnItemsView:"notLoaded"` at `:188`, threaded at `:4390`). But production Swift `ThreadTurnsListParams` has **no `itemsView` field** (`ThreadDetailDTO.swift:18‑23` — only threadId/cursor/limit/sortDirection), and the relay's `listThreadTurns` **forwards params as‑is without injecting it** (`dock-relay-thread-data.mjs:964‑971`). The help text even claims `"Exhaustive defaults to full"` — but `--exhaustive` throws and the real default is `notLoaded`. So the harness *can* request `full` yet by default proves only pagination, and production sends nothing. GPT‑5.5 is right; this is a concrete capability hole, and it strengthens my Decision‑2 rule.
- **Harness not "in full."** Conceded — capability holes (above) + enforcement holes (opt‑in/default‑off/unscheduled/ungated, which I already documented). "Exists and is proven on real local services, but incomplete and unenforced" is the accurate framing.
- **No proof‑result schema file.** Verified: the only `.schema.json` in the repo is `contract/dock/dock-thread-card.schema.json`. The harness JSON carries an inline `schemaVersion:1`/`kind` but nothing validates report shape. So the proof‑result schema gate is genuine new work, not wiring.

---

# Round‑02 — Opus 4.8 final: convergence

## Do I agree with GPT‑5.5?

**Yes — full agreement, no architectural disagreement remaining.** I accept all three of its material corrections (verified above), and it accepted my three principles, the three first‑class corrections (A/B/C), heartbeat‑made‑real, and the `itemsView:"full"` scoping. We are converged on the same small architecture and the same testing methodology.

## Final revised proposal (the converged small architecture)

**Three generating principles** (the elegant compression): **P1** one owner per fact, no second oracle; **P2** liveness must be positively and continuously re‑proven — a connected socket is never proof, and any change of a relay‑owned stream/session identity (downstream reconnect, dropped subscription, **or relay upstream re‑resume**) must force a rebuild the client can observe; **P3** proof = over‑time convergence of real app‑server → relay → client → rendered UI, enforced on a cadence, or it does not count.

**Seven architecture rules** (GPT‑5.5's), rule 7 = **detail upstream recovery closes the downstream phone socket** (reuses Swift's already‑tested rehydrate path, zero new protocol; a `generation`+`threadId`‑stamped `detail/resync` notification is the *only sanctioned future* alternative, documented as rejected‑for‑now, not a side door).

**Three first‑class corrections** (both models agree, all verified): **(A)** live‑scope probe failure must fail closed → `freshness:"stale"` (today `failedEndpoints` is counted then discarded; the stale‑marking path has no caller); **(B)** snapshot generation guard — relay stamps monotonic generation, client rejects older snapshots (today `stateGeneration` is on the wire but unused, so an older snapshot can move the UI backward); **(C)** Archive mutations must explicitly `reconcileArchive` and freshness must be per‑scope (today archive mutation only `reconcileDock`s, and host freshness is global so Dock/Archive stale each other).

**Heartbeat made real** as the P2 liveness signal: relay emits periodic `kind:"heartbeat"` `dock/update` carrying `{epoch, seq, freshness, lastSyncAt}` with no row change; client uses it to detect a connected‑but‑stuck/unsubscribed stream and to surface stale UI; heartbeat must **never** mark failed data fresh. Exact cadence/timeout is a bounded implementation parameter (cadence ≈ reconcile interval ≥ 30 s; client stale‑timeout a small multiple of cadence) — not an architectural decision and not a blocker.

**`itemsView:"full"` scoped to Thread Detail history only**, kept off relay card‑order proof calls. Folding in GPT‑5.5's correction: the value must actually flow on the detail path (Swift `ThreadTurnsListParams.itemsView` or relay injection on the `thread/turns/list` detail route) — today neither side sends it — and the detail‑completeness invariant must assert `itemsView:"full"` on the real outbound params **and** that full item kinds (command/tool/file‑change) render. The `--turn-items-view` audit flag must default to `full` for the detail proof (or the harness does not actually prove completeness).

**Testing = six existing tiers made mandatory, not a new framework:** (A) contract/drift gates, (B) Swift unit (demoted to merge‑proof only), (C) relay `node --test`, (D) real‑relay client‑path soak with lag budget + scenario matrix, (E) displayed‑UI‑over‑time matrix (`sim-ui-controlled-matrix-proof`, 2 passes, `MAX_UI_LAG_MS=2000`), (F) physical phone. **The new work is enforcement:** aggregate CI‑safe gate on every change; path‑based **mandatory** simulator proof for update‑path changes (flips the default‑off `XCTSkip` gate to required); scheduled soak/matrix (over‑time as a trend, not a one‑shot); retained JSON reports with trended `maxObservedUiLagMs`/failures.

**Five drift gates** (union of both models, all cheap/CI‑safe): (1) route registry/dispatch parity (relay `switch` == `ROUTE_CONFIGS` == Swift `AppServerMethods` allow‑list; today `ensureRoute` silently absorbs unregistered routes); (2) schemaVersion/DTO parity (JSON‑schema const 2 == Swift `streamSchemaVersion` == relay emitted literal; generated‑DTO staleness already covered by `contract:check`); (3) executable doc‑command gate (lint RUNBOOK/TEST_PLAN command blocks against the real arg parser + `make -n` — would have caught `--exhaustive`, the deleted `dock-relay-state-parity.mjs`, and the `--client-path-only` no‑op); (4) **proof‑result schema gate (new file)** — author a `contract/.../sync-proof-report.schema.json` and validate every harness report against it; (5) heartbeat‑contract gate (relay emits heartbeat iff schema/Swift/README claim it) — meaningful once heartbeat ships. Plus the existing `contract:check`.

**Deliverable:** `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md` — claims the currently‑unclaimed canonical title; leads with the 3 principles; states the 7 rules + corrections A/B/C; protocol owner map + forbidden side doors; update/session lifecycle (close‑downstream + sanctioned future `detail/resync`); edge/exception → invariant → failure‑code matrix; six tiers **by reference** to RUNBOOK/TEST_PLAN + the enforcement changes; proof acceptance rules (pass/fail/blocked/outside‑contract + lag budget); drift‑maintenance rules + the five gates; rejected alternatives; implementation‑plan outline (no code). Supersedes the architecture/strategy summary of `PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE` (links it as the deep edge/bug appendix), converges with RUNBOOK + TEST_PLAN (and triggers fixing their `--exhaustive`/parity drift), aligns with `DATA_CONTRACT_SINGLE_SOURCE`, updates README's heartbeat claim.

## Explicit requirement coverage

- **Do not implement** ✓ (doc only; this round produced no code).
- **Unified/elegant/end‑to‑end/close side doors** ✓ (one canonical path; 3 principles + 7 rules; explicit side‑door list incl. the default‑off proof gate, `ensureRoute` registration gap, observability `relayState` name drift).
- **Prove real update over time incl. client behavior + server state changes** ✓ (Tiers D/E/F: real‑relay soak over a duration, displayed‑UI sampled over time, controlled server‑state transitions, physical phone).
- **Not static‑snapshot/fixture/one‑shot only** ✓ (Tier B demoted to merge‑proof; canonical proof is over‑time convergence; opt‑in proof flipped to mandatory/scheduled).
- **Edge/exception cases, drift‑prevention, ongoing proof** ✓ (edge→invariant→failure‑code matrix; five drift gates; cadence + retention + trend).
- **Desired doc sections** (architecture, SSOT + side doors, edge/exception, ongoing convergence proof, UX freshness proof, tiers+commands, drift gates+maintenance, rejected alternatives, implementation‑plan outline) ✓ all present.

## Remaining disagreement

**None architectural.** The only open item is the exact heartbeat cadence/timeout values — GPT‑5.5 and I both classify this as a bounded implementation parameter, not an architecture decision; the rule ("prove liveness without ever marking failed data fresh"; cadence ≈ reconcile interval) is fixed. It is not a hidden decision and does not block the doc.

## Evidence for repo‑dependent claims

This round's verifications (above): `--turn-items-view` flag present + default `notLoaded` (`dock-relay-sync-audit.mjs:91,188,261‑267,380‑381,4390`); production detail sends no `itemsView` (`ThreadDetailDTO.swift:18‑23`); relay forwards turns params without injection (`dock-relay-thread-data.mjs:964‑971`); no proof‑result schema file (only `contract/dock/dock-thread-card.schema.json` exists). Round‑01 evidence (six parallel `file:line` audits) stands and was not contradicted by GPT‑5.5; it confirmed the corrections A/B/C, the two reconnect bugs, heartbeat‑not‑emitted, and the existing six‑tier harness.

## Can the parent write the doc now?

**Yes.** Both models converge on the same small architecture (3 principles + 7 rules + corrections A/B/C), the same testing methodology (six existing tiers + enforcement + five drift gates), and the same deliverable shape. All hard requirements are covered, every repo‑dependent claim is verified from files, no hard requirement was dropped, and the single open item (heartbeat cadence/timeout) is an explicitly bounded implementation parameter, not a hidden unresolved decision. The parent can author `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md` from this consensus now.