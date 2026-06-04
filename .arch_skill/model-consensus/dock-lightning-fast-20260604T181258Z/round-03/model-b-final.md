VERDICT: sign-off
BLOCKING: none
NON-BLOCKING: JSON is acceptable as the single row oracle because the proof pipeline already consumes JSON/JSONL files; keep the live root revision check as the UI anchor and never add a hidden bulk accessibility fallback.
DOC CHANGES REQUIRED: none
SUMMARY FOR PARENT: v1 captures the converged plan: gate inside `DockScreenStore.enqueueProjection`, equality-guard `DockStore.state`, delete root `rowValues=`, use one test-only app-container JSON snapshot keyed by accepted render revision, keep full row arrays for the first repair, use exact `Equatable` first, and replace `syncSelectedDetail` linear scan with indexed lookup.