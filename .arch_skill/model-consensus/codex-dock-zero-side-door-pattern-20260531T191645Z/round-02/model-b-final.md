**Verdict**

Not ready. Model A’s additions are required, and I would tighten them rather than soften them. The plan still lets old truth survive through archive mutation, live-only absence, dead provenance, weak freshness semantics, diagnostics, scripts, and fixtures.

**Agreement**

Yes to all five contested additions:

1. **Required:** explicitly remove `dockOrderKey(0, threadID)` and direct `freshness_status = 'stale'` writes from `applyArchiveMutation`.  
   Evidence: [dock-relay-state-store.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:823). This is a second card-order writer.

2. **Required:** live-only row enumeration must be an architecture guarantee.  
   Evidence: `orderedDockRows` only overlays live rows already present in primary/interactive rows; it never adds live-only IDs in [dock-relay-state-views.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:281).

3. **Required:** wire `thread_field_provenance` or delete it.  
   Evidence: the table exists in [dock-relay-state-store.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:159). A dead provenance table is worse than no table because it looks like enforcement.

4. **Required:** bind honest freshness to existing stream/card fields.  
   Evidence: stream `complete`, host `freshness.status`, card `freshness`, and card `completeness` already exist in [dock-thread-card.schema.json](/Users/aelaguiz/workspace/codex-client/contract/dock/dock-thread-card.schema.json:30), [host freshness](/Users/aelaguiz/workspace/codex-client/contract/dock/dock-thread-card.schema.json:157), and [card fields](/Users/aelaguiz/workspace/codex-client/contract/dock/dock-thread-card.schema.json:337). No new DTO is needed.

5. **Required:** add a normative route-scope allow-list across JSON-RPC, HTTP, command, detail, voice, and health planes.  
   Evidence: the current relay exposes mixed planes in one switch in [dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:459), and HTTP state surfaces are separate in [dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:895).

**Remaining Drift Risks**

- The accepted bounded-scan gap still permits a fresh-looking mis-ordered list. The current plan admits this in [Known Residual Gap](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:282).
- `thread/archive` and `thread/unarchive` can bypass canonical projection by mutating stored card order/freshness directly.
- Live-only threads can remain absent from Dock even if they are active.
- `thread_field_provenance` can remain decorative instead of enforcing source proof.
- `/statez`, `/syncz`, `/dbz`, `/explainz/thread/*`, `/selftestz`, and `/bundlez` can become diagnostic proof paths.
- Audit/probe scripts can keep using old oracle routes unless the plan names them directly.
- `thread/read`, `thread/turns/list`, and `thread/resume` can still be abused as Dock proof unless detail scope is explicit.
- Fixtures, previews, and scripted streams can emit fake `fresh` + `complete` cards unless the plan says they are render/reducer fixtures only, never acceptance proof.

**Exact Plan Edits Needed**

- Replace the residual-gap section with an honest-freshness invariant: if canonical activity is not proven for the emitted ordering set, the stream is not `fresh` and not `complete`.
- Change Phase 0 from bounded top-N turn reads to: prove every emitted card’s canonical activity, or emit explicit uncertainty. `thread/list.updatedAt` cannot be treated as an upper bound.
- Remove the Phase 0 instruction to reuse `state-snapshot`, `state-parity`, and `probe` patterns. Those are side-door tools; lift any useful paging helper into the canonical fold path.
- Add a Phase 1 requirement that live-only rows are enumerated into the canonical candidate set, not only overlaid onto existing rows.
- Add a Phase 1.5 for archive/unarchive: command routes are projection inputs only; remove `dockOrderKey(0, threadID)` and direct freshness writes from `applyArchiveMutation`.
- Add a provenance decision: either make `thread_field_provenance` the stored proof source for activity/freshness/completeness, or delete it and use explicit proof columns on `threads`.
- Add field rules: card `completeness=complete` only with proven canonical activity; any unproven emitted card makes stream `complete=false`, host freshness not `fresh`, and affected cards not `fresh`.
- Replace Endpoint Disposition with a default-deny route-scope allow-list. Only `dock/*` and `archive/*` may prove Dock/Archive card truth.
- Expand Phase 4 to include HTTP diagnostics, proof scripts, scripted/previews/fixtures, and detail-only proof rules.
- Update docs so raw `thread/list` is not described as available diagnostics or freshness evidence.

**Ready-To-Implement Criteria**

The plan is ready only when it says, unambiguously:

- No known mis-ranked card may appear in a stream labeled fresh.
- Only `dock/subscribe`, `dock/update`, `dock/resync`, `archive/subscribe`, `archive/update`, and `archive/resync` can prove card truth.
- Commands, detail routes, voice routes, health endpoints, HTTP diagnostics, scripts, fixtures, and previews cannot prove Dock/Archive freshness, ordering, completeness, title, summary, or status.
- Archive/unarchive, live status, session-index IDs, turns, reads, and list rows all enter through one canonical projection.
- There is no dead provenance mechanism and no direct second writer for card order/freshness.
- Tests prove the real card stream path, not an oracle.