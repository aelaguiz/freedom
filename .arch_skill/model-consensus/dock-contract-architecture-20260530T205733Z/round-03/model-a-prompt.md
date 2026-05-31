You are Model A, Opus 4.8 max, in the final signoff round of the Codex Dock contract-architecture consensus.

Do not edit files, run tools, spawn subagents, or re-open the repo. Use the prior two rounds and the candidate below only. This round is for final alignment, not fresh discovery.

The user requires the final doc to include an exhaustive affected-location checklist. You already produced a hardened checklist in Round 2; GPT produced a compatible draft but preferred a different canonical name. The final doc will include your hardened checklist.

Candidate final architecture to sign or minimally correct:

1. Canonical schema/product contract name: `DockThreadCard`.
   - This is the relay-owned resolved product object for one Codex thread as seen in Dock and Archive.
   - Swift may keep rendered/presentation names like `DockRowViewModel`; the schema object is not a SwiftUI layout row.
   - `ServerRequestCard` remains a separate Thread Detail object; the final doc will explicitly warn not to confuse it with `DockThreadCard`.
   - Stream envelope names stay stable; the payload inside the envelope becomes cards.

2. Single source of truth:
   - One repo-local versioned schema defines `DockThreadCard` plus the dock stream envelope.
   - The Swift DTO/card struct is generated from that schema and checked in with a regeneration-clean check.
   - The Node relay stays plain `.mjs` but validates every emitted card/envelope against the same schema in `rtk npm run test:relay`.
   - This is not lint-only: real emitted relay objects and real Swift decoding must both conform to the same declared schema.

3. `DockThreadCard` required core fields:
   - `cardID` or `id` derived from `(logicalHostID, threadID)`.
   - `logicalHostID`, `threadID`, `backendSessionID`.
   - `orderKey`: opaque, relay-owned, lexicographically byte-comparable string; Swift must not parse or derive it.
   - `activityAt`: required display timestamp; not the sort authority.
   - `title`, `displaySummary`, final resolved Dock `status`.
   - `sourceKind`/`lane`, `repo` or `workingDirectory`, `branch`, `archiveState`, `freshness`, and `completeness`.

4. Ownership boundary:
   - Relay derives semantic truth: identity, orderKey, activityAt, displaySummary, title, status, source/lane, repo/workspace, branch, host display, archive state, freshness/completeness.
   - Swift consumes canonical fields and presents them: layout, icons, relative time text, colors, navigation, accessibility, and local overlay.
   - Search/filter/group/lens remain client-side for responsiveness, but they may key only on canonical card fields and the one `orderKey` comparator; they must not recompute summary/status/recency.
   - Pin/label/color overlay remains client-owned. Pinned section order remains user-owned drag/order metadata, not `orderKey`.

5. Performance shape preserved:
   - Keep bounded `dock/subscribe`, `dock/update`, `dock/resync`, epoch/seq/baseSeq/window/complete/totalRows, byte caps, incremental diff, catch-up, lazy detail, RenderCoalescer, off-main projection, and no full history mirroring to the phone.
   - Only the row/card payload changes.

6. Scope refinements from your Round 2 sweep:
   - Archive joins the card family.
   - The LLM thread-card labels plan feeds relay-resolved `title`/`displaySummary`; no parallel Swift fallback chain.
   - Wire stream schema version, relay SQLite schema version, and diagnostic snapshot schema version stay distinct and coordinated.
   - DEBUG fixtures/previews are part of the checklist because DTO changes break them.

7. Final doc will use your exhaustive five-bucket checklist:
   - must-touch production code;
   - must-touch tests/fixtures/verifiers;
   - docs/runbooks;
   - optional/upstream ideal;
   - explicitly not-to-touch / preserve-verbatim split-file notes.

Question: Are you ready to sign the final doc as "I cannot imagine a more perfect architecture for this app's goals, constraints, and drift-prevention needs"? If yes, say so plainly and list only any wording corrections that must appear in the doc. If no, give the smallest blocking correction.
