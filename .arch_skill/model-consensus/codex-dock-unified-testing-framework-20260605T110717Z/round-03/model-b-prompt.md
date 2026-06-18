Candidate Consensus

The parent will write documentation now, not implement new test infrastructure now.

Immediate docs changes:
- Add `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md` as the dated architecture plan.
- Add `docs/TESTING.md` as a short evergreen current-use guide that lists only commands that exist today and links to the dated plan for future framework targets. It must not present `test-smoke`, `test-full`, or `test-overtime` as current commands.
- Update `AGENTS.md` with a concise "Testing And Proof" section that lists current commands, proof doctrine, and links to `docs/TESTING.md` plus the dated plan.
- Update `README.md` so the old "Exhaustive Sync Harness" pointer routes through `docs/TESTING.md` and identifies the older sync docs as historical/narrow references.

Plan content:
- Makefile remains the single public command surface. No new runner.
- Proposed future umbrella targets are `test-smoke`, `test-full`, and `test-overtime` or equivalent, explicitly marked proposed/not-yet-existing until implemented.
- Avoid `test-realtime` for the over-time tier because OpenAI Realtime transcription already exists.
- A single scenario source of truth is required so the fixture, matrix, and Makefile do not duplicate scenario lists; the orphaned `file-change-review` must either become matrix-gated or be removed.
- A large/stale/changing corpus capability is required for the 900-thread complaint; the lean recommended owner is `scripts/codex-dock-isolated-home.mjs` with a synthesize/scale profile path.
- Current latency proof targets stay bespoke until the controlled matrix can prove equivalent optimistic UI and upstream-ack timing.
- No old dated sync docs are deleted now; they are demoted by links and the plan carries the later fold/delete ledger.

Question
Does this candidate preserve the user's goal, satisfy every hard requirement, avoid teaching nonexistent commands, and reflect your actual agreement? If no, name the smallest correction needed. If yes, sign off and name any residual risk.

Do not edit files. Do not invoke skills that spawn subagents.
