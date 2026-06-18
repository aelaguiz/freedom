Net: I agree with Opus on the direction, but I would simplify the immediate docs work. The parent should document the current commands truthfully now, and describe umbrella targets, scenario catalog cleanup, and large/stale corpus generation as future plan items.

**Agreements**

- `Makefile` should remain the public command surface. `package.json`, `Package.swift`, and `project.yml` stay as sub-manifests.
- `docs/TESTING.md` is needed because there is no evergreen testing guide today.
- The controlled simulator matrix is the current best over-time proof path.
- The scenario list is drifting and should eventually become one source of truth.
- Screenshots, mocks, preview rows, raw `:4500`, and loopback-only paths must not count as acceptance proof.

**Disagreements**

- Do not document `rtk make test-smoke`, `rtk make test-full`, or `rtk make test-realtime` as current commands. They do not exist.
- Do not delete old dated sync docs now. Demote them by linking to the new canonical guide; fold/delete later if the new guide fully absorbs them.
- Do not fold latency proofs into the controlled matrix yet. Keep `sim-ui-client-rename-proof` and `sim-ui-user-message-latency-proof` bespoke until the matrix can prove the same optimistic UI and ack-latency signal.
- Do not make the large/stale corpus generator sound already designed. It is required by the user’s 900-thread complaint, but it belongs in the future plan, not the current-use guide.

**Simplifications**

- Create both docs, but give them non-overlapping jobs:
  - `docs/TESTING.md`: current “how to run / how to add tests” guide.
  - `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`: dated architecture plan for future umbrella targets, scenario catalog, large/stale corpus, and cleanup.
- Keep `AGENTS.md` short: current commands, proof rules, and a pointer to `docs/TESTING.md`.
- Keep `README.md` shorter: replace the old exhaustive sync pointer with the new testing guide.

**Repo Evidence**

- [Makefile](/Users/aelaguiz/workspace/codex-client/Makefile:136) lists current phony targets; no `test-smoke`, `test-full`, or `test-realtime` exists.
- [README.md](/Users/aelaguiz/workspace/codex-client/README.md:537) already names `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` as live-update proof.
- [AGENTS.md](/Users/aelaguiz/workspace/codex-client/AGENTS.md:89) already has smallest relevant checks by area.
- [AGENTS.md](/Users/aelaguiz/workspace/codex-client/AGENTS.md:277) Docs Map has no testing doc today.
- [Makefile](/Users/aelaguiz/workspace/codex-client/Makefile:111), `dock-relay-controlled-simulator-fixture.mjs`, and `dock-relay-controlled-simulator-matrix.mjs` duplicate scenario knowledge.
- `scripts/codex-dock-isolated-home.mjs` exposes `--thread-count` and `--max-rollout-bytes`, but no stale/changing profile.

**Revised Consensus Proposal**

1. Add `docs/TESTING.md` with current commands only:
   - fast Node: `rtk npm test`
   - targeted Swift: the existing `rtk swift test --filter ...` commands
   - simulator smoke: `rtk make app-test SIM='iPhone 17'`
   - over-time simulator proof: `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
   - physical proof: current `rtk make iphone-17-pro`, `rtk make iphone-14`, and config verify targets
2. Add the dated plan doc for end-state architecture:
   - future umbrella Make targets
   - single scenario catalog
   - large/stale/evolving corpus support
   - proof doctrine
   - latency-proof migration criteria
   - old-doc demotion/fold/delete policy
3. Update `AGENTS.md` and `README.md` to point to `docs/TESTING.md`.
4. Mark old sync docs as historical references, not canonical instructions.

**Sign-Off**

I’m ready to sign off on this revised docs plan. I am not ready to sign off on Opus’s first pass unchanged because it overstates future targets as if they can be current docs and is too aggressive on deleting/folding before the replacement exists.