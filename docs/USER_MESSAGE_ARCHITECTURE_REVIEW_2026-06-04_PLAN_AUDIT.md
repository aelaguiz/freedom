# Plan Audit Log

Plan: `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md`
Audit log: `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-06-04T12:56:49Z
Scope: whole plan, plan-readiness before implementation

## Current Blocking Findings

- [x] PLA-001 - The artifact is a strong diagnosis, but not yet an implementation-grade source of truth.
  - Lens: outcome-north-star, proof-and-phase-exit
  - Evidence: The current doc has a diagnostic verdict and findings, then a broad "Implementation Plan" at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:943`. The phases are task-shaped and can be checked off while the intended world is still false.
  - Required plan repair: Rewrite the plan around explicit done-state truths, owner boundaries, invariants, phase exit gates, and proof requirements.
  - Status: resolved
  - Resolution evidence: Revised plan now has explicit North Star at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:30`, done-state requirements at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:44`, target owner chain at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:216`, and proof matrix at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:628`.

- [x] PLA-002 - Relay command ownership is named but under-specified.
  - Lens: canonical-owner-and-ssot, caller-invariant-state, drift-proof-coupling
  - Evidence: The doc proposes `thread/message/send` at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:867`, but does not define the relay module owner, store API, status contract, idempotency conflict behavior, or how it interacts with existing active detail sessions.
  - Required plan repair: Define the relay message-delivery owner, persistent command schema, command API, idempotency rules, route/retry lifecycle, and exact integration with existing detail streams.
  - Status: resolved
  - Resolution evidence: Revised plan defines `RelayUserMessageCommandEngine` ownership at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:239`, relay API at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:356`, persistent table/API at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:393`, and engine responsibilities at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:432`.

- [x] PLA-003 - Swift pending state is described, but caller and render invariants are not tight enough.
  - Lens: caller-invariant-state, elegance-and-code-judo
  - Evidence: The doc proposes `PendingOutboundMessage` at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:748`, but does not define where it lives relative to `ThreadDetailSnapshot`, how filters/order handle it, or whether `ComposerState.isSending` remains a global blocker.
  - Required plan repair: Name the local owner, render merge rule, ordering rule, filter rule, composer behavior, retry behavior, and which old `isSending` semantics are deleted.
  - Status: resolved
  - Resolution evidence: Revised plan defines `PendingOutboundMessage`, render merge, ordering, filtering, and composer behavior at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:261`.

- [x] PLA-004 - Depth-first implementation sequence defers the highest-risk relay/client seam.
  - Lens: depth-first-risk
  - Evidence: Current phases do DTO plumbing, projection, and Swift overlay before the relay-owned command lifecycle at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:979`.
  - Required plan repair: Make the first implementation slice cross Swift -> relay -> Codex DTO/projection identity, even if the persistent status lifecycle widens in later steps.
  - Status: resolved
  - Resolution evidence: Revised Phase 1 requires the real `RelayUserMessageCommandEngine` and explicitly forbids a temporary relay path at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:499`.

- [x] PLA-005 - Side doors and convergence are incomplete.
  - Lens: deletion-and-side-door, existing-pattern-and-convergence
  - Evidence: The current doc says not to keep Thread Detail subscription ownership equal to message delivery ownership at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:1019`, but does not classify existing `turn/start` and `turn/steer` phone-facing routes as delete, wrap, or reject.
  - Required plan repair: Explicitly close or wrap old phone-facing send side doors so future callers cannot bypass the command owner.
  - Status: resolved
  - Resolution evidence: Revised plan classifies old relay `turn/start` and `turn/steer` behavior at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:456` and lists side doors to close at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:617`.

## Current Non-Blocking Findings

- [x] PLA-006 - The plan should call out that request-card responses remain intentionally different.
  - Lens: existing-pattern-and-convergence
  - Evidence: Current doc compares request cards at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:260`, but the implementation plan does not state that their server-request identity path remains separate.
  - Required plan repair: Add a non-requirement stating the user-message command architecture does not merge request-card responses.
  - Status: resolved
  - Resolution evidence: Revised done-state keeps request cards separate at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:62`, and non-requirements repeat the boundary at `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:78`.

## Current Implementation Findings

Not run. No implementation has been audited against the revised plan yet.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `ThreadDetailStore.sendDraft`, `ClientCommandEngine.sendDraft`, `AppServerThreadDetailSession.turnStart/turnSteer`, `dock-relay.mjs forwardToActiveUpstream`, `dock-relay-thread-detail-projection-adapter.mjs`, generated Codex `TurnStartParams`, `TurnSteerParams`, `ThreadItem` | Current and target user-message delivery boundary | parent | read |
| Caller families | `ComposerView`, `SessionDetailView`, `ThreadDetailScreenStore`, `ThreadDetailRenderProjector`, `ThreadMessageListView` | UI submit, render, and pending row behavior | parent | read |
| Legacy and side-door paths | Relay phone-facing `turn/start`, `turn/steer`; Swift `ThreadDetailSession` methods; relay upstream `JsonRpcWebSocketClient.request` | Must not bypass message command owner | parent | read |
| Adjacent same-contract paths | Request-card response path via `sendResponse`; relay pending server requests | Similar UI action but different identity model | parent | read |
| Comparable patterns | `RelayStateStore`, `RelayStateEngine`, SQLite migrations, state subscriptions | Existing persistent relay-owned state pattern | parent | read |
| Contract/proof surfaces | `ThreadDetailStoreTests`, `ClientCommandEngineTests`, `AppServerClientTests`, `dock-relay-thread-recovery.test.mjs`, `dock-relay-card-contract.test.mjs`, `README.md` | Existing tests/docs encode current behavior and proof gaps | parent | read |

Native subagents: not used. The current tool policy exposes multi-agent tooling only for explicit delegation/parallel-agent requests; this request named audit/implementation skills but did not explicitly request subagents.

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses, if triggered

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Should old phone-facing `turn/start` and `turn/steer` remain callable? | Keep direct passthrough; wrap through command owner; reject and require `thread/message/send`. | Direct passthrough preserves the weak architecture. Rejection may require broad Swift changes. Wrapping keeps compatibility while closing the side door. | Wrap phone-facing `turn/start`/`turn/steer` through the relay command owner when they include `clientUserMessageId`; make Swift use `thread/message/send` for normal sends. | agent, based on repo truth and user request for architecture repair | `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:456` and `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md:617` | resolved |

## Pass History

### Pass 1 - 2026-06-04T12:56:49Z

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md` at reviewed commit `1c316fa`
- Agents/lenses run: parent-only plan-audit lenses
- Code areas read: Swift composer/store/command/session/client/projection/render models; relay detail session/routing/projection/state store/upstream client; generated Codex protocol; relevant tests/docs.
- Findings added: PLA-001 through PLA-006, DEC-001.
- Findings resolved: none.
- Findings carried forward: PLA-001 through PLA-006, DEC-001.
- Verdict: not-ready.
- Next audit focus: confirm revised plan carries owner boundaries, side-door decision, depth-first slices, and proof gates.

### Pass 2 - 2026-06-04T12:56:49Z

- Mode: plan-readiness
- Scope: whole revised plan
- Baseline reviewed: rewritten `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md`
- Agents/lenses run: parent-only plan-audit lenses
- Code areas read: same as Pass 1; no new code coverage required for the plan repair.
- Findings added: none.
- Findings resolved: PLA-001 through PLA-006, DEC-001.
- Findings carried forward: none.
- Verdict: ready.
- Next audit focus: after implementation, run implementation-audit mode against changed code and this plan.
