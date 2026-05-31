This candidate folds in all three of my corrections (concurrent orchestration, isolated-home actuator for completion-grade lag, 1:1-only fingerprints) on top of the locked agreements. I checked it against the goal's hard constraints one more time and it holds.

## Verdict: yes — sign off

**Goal preserved.** It keeps all four planes' worth of intent: literal rendered Dock/Home + detail, over time, correct/complete/timely, on the real client path. It does not narrow completion to a relay-only pass — the rendered UI is the judged surface.

**Every hard requirement satisfied.**
- Real `iPhone 17` + relay-backed path (`CODEX_DOCK_HOSTS=<relay>:4510`, Makefile/XCTest), no `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`, no `:4500`, no mocks as proof. ✓
- Runs over time, not one-shot; two consecutive stable samples. ✓
- Fails on lag even when sync is eventually correct (first matching UI sample after `t_relay_seen` vs 2,000 ms budget). ✓
- Invariants for missing / stale / wrong-detail / ordering / status / archive / lag are all reachable (checkpoint sweeps for missing-extra-dup-order; row `status/origin` + title fingerprint; detail event-id set + body fingerprint; lag budget). ✓
- Reuses owner paths (`dock-relay-sync-audit.mjs` helpers, Makefile sim flows); no second relay/client truth. ✓
- Design-only; redaction-safe (app-side 1:1 fingerprints keep raw text out of the harness). ✓

**No unnecessary pathways.** The only new surfaces are a sampler test, a sibling judge that imports the canonical audit, a Makefile target, two 1:1 fingerprints, and a dependency on the plan's *existing* Phase-4 scenario owner. The actuator is required (a passive run can pass without an observed change), not gratuitous.

**Reflects my actual agreement.** It is the merged design, not a compromise I'd quietly resist.

## Implementation clarifications (on record; not corrections)

These are things the judge naturally needs and that the candidate leaves implicit — none contradicts it:
- The soak recorder must persist a **per-`dock/update` timestamped timeline** (the small `--stream-event-log` add), so the time-window join has a real `t_relay_seen` series rather than only coarse per-sample snapshots.
- **Archive-boundary** is enforced via the unexpected-row check against the active `dock/subscribe` truth (an archived thread in active Dock = a row absent from relay active truth → `dock_ui_unexpected_row`); full Archive-*view* parity stays owned by the relay/client-route leg.
- **Detail lag** uses the same "first matching UI sample after `t_relay_seen`" rule applied to the detail event-id timeline, not only the Dock plane.
- The full `U-xx`/`detail_ui_*` invariant set (live-gating, request card + resolution, no foreign-thread mutation) is the judge's checklist; the candidate's surface list is representative, not exhaustive.

## Residual risks

1. **Fingerprint normalization drift** — even on title/body, client vs relay whitespace/Unicode handling could false-mismatch. Gate fingerprints behind a bring-up parity test (client fp == relay fp for a known card) before they can fail CI.
2. **Between-sweep coverage** — fast samples only see materialized rows + root count; off-screen anomalies between checkpoints rely on `rows=N` count-equality. Honest windowed boundary; full-set parity remains legs 1–2.
3. **Actuator scope creep** — keep the isolated-home actuator to the thin slice (create thread, add turn, archive/unarchive); reuse the Phase-4 owner, don't fork it.
4. **Clock-window join** — depends on shared Mac wall clock; keep a skew guard that refuses to score if the two recorders' start markers diverge beyond threshold.
5. **Sampling resolution** — ≤ budget/4 interval conservatively over-estimates lag (safe), but a change that appears and vanishes within one interval could be missed; acceptable at ≤500 ms against 2,000 ms.

Signed off.
