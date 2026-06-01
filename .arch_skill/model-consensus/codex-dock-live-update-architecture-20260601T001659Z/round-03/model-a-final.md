I read the full candidate doc (816 lines) myself, and the parallel fact-checker independently verified every repo-dependent claim in it against the actual codebase. Both come back clean.

The doc faithfully encodes our converged consensus: the 3 principles (P1 one-owner-per-fact, P2 liveness-must-be-re-proven, P3 over-time convergence), the 9 rules (my 7 with Corrections A/B/C promoted to first-class Rules 7/8/9 — a cleaner editorial choice), close-downstream with `detail/resync` correctly marked sanctioned-future, heartbeat-made-real, `itemsView:"full"` scoped to the detail path only, the six test tiers with static fixtures explicitly demoted, the five drift gates (including the new proof-result schema gate GPT-5.5 flagged), the ongoing cadence, the side-door list (including "a skipped over-time proof is itself a side door"), rejected alternatives, and a no-implementation plan outline. The fact-checker confirms it contains **no drift of its own**: every path/flag/target/command resolves, the two booby-traps (`--exhaustive`, deleted `dock-relay-state-parity.mjs`) appear only as things the doc-command gate must *catch*, and every "gap/should/future" item is correctly distinguished from what already exists.

## Signoff: **YES**

## Blocking corrections
**None.** No hard requirement dropped, no unmarked new pathway invented, no fabricated anchor/command/flag, and it reflects my actual agreement with GPT-5.5.

## Non-blocking corrections (optional polish)
- **Make the "trend across runs" idea explicit.** The doc captures *retained* + *scheduled* reports, but the over-time regression signal I proposed (trend `maxObservedUiLagMs`/failure counts across retained runs to catch slow drift) is only implied. One line in "Ongoing Cadence" or "Proof Acceptance Rules" would close it.
- **Tier D representative command** (line 510) uses `--client-path-only` (now a compatibility no-op) and omits `--duration-ms`/`--sample-interval-ms`; since it's labeled a "representative command family," a pointer to the RUNBOOK for exact invocations would tighten it. Harmless as-is (the flag is accepted, not throwing).
- **Physical-device UUIDs** (lines 555–556) are a specific example; noting they're illustrative (the runbook lists two devices) avoids a future reader treating one UUID as canonical.

None of these affect architecture, requirements, or correctness.

## Residual risks (all correctly out-of-scope for the doc; flag for implementation)
1. **Heartbeat false-positives on healthy-but-quiet streams.** The doc guards the dangerous direction ("heartbeat must never mark failed data fresh") and bounds cadence/timeout, but the inverse — an idle-but-healthy stream misread as stale, causing reconnect thrash — is the real tuning hazard. Correctly an implementation parameter, but it's the top residual.
2. **Close-downstream UX cost.** On long active threads, closing the detail socket on every transient relay upstream blip forces a full re-drain (all turn pages × `itemsView:"full"` bodies). Acknowledged, with `detail/resync` as the sanctioned escape hatch gated on evidence — so it has a defined resolution path.
3. **Enforcement depends on a capable runner.** The "mandatory simulator-matrix for update-path changes" and scheduled soak require Xcode/simulator + a live host service. Without a provisioned Mac runner, the gate degrades to `blocked` and the proof stays opt-in in practice. This is the single biggest *practical* threat to the goal of "actually ongoing" — an ops/provisioning dependency, not a doc defect.
4. **`itemsView:"full"` payload/compat.** Pinning full item bodies on every detail page must be verified against the app-server's acceptance on that route and against the lag budget for large threads. Listed as a gap-to-close; verify at implementation.
5. **The new gates can themselves rot** if added but not wired into a mandatory run — looping back to risk 3. The doc sequences this correctly (CI-safe gates first), but it depends on follow-through.

## Evidence read
- The full candidate doc `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md` (all 816 lines).
- A parallel independent fact-check of the doc against the repo: all file paths, the absence of `file:line` anchors, every make target/npm script/sync-audit flag, the `--exhaustive`/parity-script booby-traps, the `TurnItemsView` flag values, `ThreadTurnsListParams` lacking `itemsView`, relay not injecting `itemsView`, `stateGeneration` emitted-but-client-unused, relay never emitting `kind:"heartbeat"`, `ensureRoute`, the `-32601` dispatch fallback, `rehydrateAfterReconnect`, the `Dictionary(uniqueKeysWithValues:)` crash vector, and the archive-mutation reconcile path — all verified PASS.
- Carried-forward verified evidence from rounds 01–02 (six `file:line` code audits + GPT-5.5's three repo corrections), none contradicted by the doc.

The parent's candidate is a valid, drift-free encoding of the consensus. It can stand as the canonical `CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`.