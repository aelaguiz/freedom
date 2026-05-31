---
title: "Codex Dock - LLM Thread Card Labels - Architecture Plan"
date: 2026-05-30
status: proposed
fallback_policy: no_app_integration_until_approved
owners: [Amir, Codex]
reviewers: [Amir]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30_WORKLOG.md
  - README.md
  - Makefile
  - scripts/dock-relay-thread-summary-cache.mjs
  - scripts/dock-relay-session-table.mjs
  - scripts/dock-relay-thread-data.mjs
  - CodexDock/AppServer/ThreadListDTO.swift
  - CodexDock/AppServer/DockStreamDTO.swift
  - CodexDock/Models/SessionSummary.swift
  - CodexDock/Models/SessionSummaryMapper.swift
  - CodexDock/State/SessionRowProjector.swift
  - CodexDock/Features/Dock/DockSharedViews.swift
---

# TL;DR

Outcome: replace first-message-ish thread card text with Mac-side
OpenAI-generated labels. Each Dock row gets a human title that says what the
thread is actually about and details that say what the thread is actually doing
now.

Current problem: the Dock can still force the user to remember the first thing
they asked for. The relay summary cache currently chooses the latest meaningful
message from recent turns; that is useful activity text, but it is not a
holistic label.

Approach: add an async relay-owned LLM label cache. The first Dock response must
stay fast and use existing text. The relay warms labels in the background from
bounded user/agent messages, stores them by thread/version/input signature, and
pushes row updates when a better title/details pair is ready.

No app integration is included in this plan. This document prepares the prompt,
schema, cache contract, rollout plan, and approval samples so implementation can
start after Amir approves the visible output shape.

# Decision Summary

- API surface: OpenAI Responses API from the Dock relay only.
- Output mode: Structured Outputs with strict JSON Schema.
- Prompt owner: relay-side prompt module, versioned as
  `thread-card-labels-v1`.
- Secret boundary: `OPENAI_API_KEY` stays Mac-side. The iPhone never receives
  OpenAI provider config or raw API keys.
- Default model policy:
  - Requested target if/when available: `gpt-5.5-mini` with low reasoning.
  - Available quality-first target on 2026-05-30: `gpt-5.5` with
    `reasoning.effort = "low"`.
  - Available latency-first mini target on 2026-05-30: `gpt-5.4-mini` with
    `reasoning.effort = "low"`.
- Call timing: never block `thread/list`, `dock/subscribe`, or app launch on an
  OpenAI call.
- Data scope: use bounded user/agent messages plus row metadata. Do not send
  tool output, reasoning summaries, raw JSON-RPC payloads, base64 audio,
  transcript text unrelated to the thread, bearer tokens, or `.env` content.
- Approval gate: Amir reviews generated samples before the prompt/model/schema
  are locked for implementation.

# User-Visible Contract

Each loaded Dock row should eventually show:

- `title`: a stable, human-readable phrase for what the thread is about.
- `details`: a concise sentence for what the thread is currently doing, blocked
  by, reviewing, or has completed.

Good examples from testing:

```json
{
  "title": "OpenAI-powered thread card summaries",
  "details": "Designing and testing the prompt for fast LLM-generated titles and details, with a full docs plan before integration."
}
```

```json
{
  "title": "Device install verification",
  "details": "iPhone 17 Pro installed with the correct relay host config; iPhone 14 is blocked because WebDriverAgent is not running on the device."
}
```

```json
{
  "title": "Colorado trip booking dossier",
  "details": "United AUS-DEN round trip confirmation H12QTW was found and saved; only flights are booked, so lodging, transport, and activities still need planning."
}
```

Bad or not-yet-approved example from testing:

```json
{
  "title": "AIMGR Redis credential coordination cutover",
  "details": "Redis-backed credential sharing is implemented, pushed, and working locally; remaining work is rolling the same build and config onto home, agents@amirs-mac-studio, and M"
}
```

Reason it is not acceptable: `details` was cut off by the schema length limit.
The final schema should allow a complete sentence, and Swift should own visual
truncation.

# Non-Goals

- Do not integrate this into the app yet.
- Do not make the iPhone call OpenAI.
- Do not block Dock loading on LLM labels.
- Do not replace Thread Detail content loading.
- Do not generate or persist labels from tool output, reasoning/thinking, raw
  command output, or private prompt text in diagnostics.
- Do not create a second source of truth for thread identity inside Swift.
  Swift should render the relay fields it receives.
- Do not add user-visible confidence labels unless Amir explicitly wants them.

# Current Architecture

The current flow is:

```text
Codex app-server thread/list or live owner
-> relay aggregateThreadList
-> ThreadSummaryCache.decorateRows
-> ThreadSummaryCache.warmRows
-> latest meaningful user/agent message from recent turns
-> latestSummary/messageSummary
-> DockStreamSessionDTO.summary/messageSummary
-> SessionSummary.shortEventSummary
-> DockRowViewModel.summary
-> DockRowView Text(row.summary)
```

This is already the right ownership boundary. The relay can read turns, keep
secrets, cache derived labels, and push row deltas. The app should only need DTO
field support when labels are added.

# Proposed Runtime Architecture

Add a new relay cache next to, or replacing, the current
`ThreadSummaryCache` behavior:

```text
thread/list or dock snapshot rows
-> decorate with last approved cached LLM label when available
-> enqueue stale/missing labels without blocking
-> read bounded turns from owning upstream
-> build sanitized thread-label input
-> batch up to N threads per OpenAI Responses call
-> validate strict schema + local string quality rules
-> remember labels by thread/version/input_signature/prompt_version/model
-> push dock/update row deltas when visible fields improve
```

The existing "latest meaningful message" summary can remain as immediate
fallback while the LLM label warms. After rollout confidence is high, the LLM
label should become the preferred `title` and `details` source for Dock rows.

# Prompt Contract

Use a developer message or `instructions` field:

```text
You generate compact thread-card labels for an iPhone dashboard.

Job: for each input thread, return one independent card label. Never merge
threads together.

Each visible card has two strings:
- title: what this one thread is actually about now, holistically. It should be
  stable across small updates.
- details: what this one thread is actually doing now, holistically. It should
  name the active work, blocker, review, or outcome.

How to read a thread:
- Use the whole available conversation, not just the first user request and not
  just the latest message.
- Prefer the user's real objective and the current implementation state over
  procedural chatter.
- Treat currentTitle/currentDetails as weak hints; replace them when
  conversation evidence is better.
- If the thread is blocked, say the concrete blocker in details.
- If the thread is done, say the completed outcome in details.
- If the thread is still being worked, say the current work in details.

Style:
- Specific enough to distinguish similar threads in the same repo.
- Human-readable and elegant; no prefixes like "Task:" or "Status:".
- No meta phrases like "The user asked" or "This thread is about".
- Use exact file, feature, repo, or subsystem names only when they are central.
- Never mention hidden reasoning, token usage, tool calls, prompt mechanics, or
  internal chain of thought.
- details must be a complete sentence. It must not end with a conjunction,
  comma, semicolon, colon, dangling article, or unfinished proper noun.

Return exactly one card per input thread id.
```

Input shape:

```json
{
  "threads": [
    {
      "id": "thread-id",
      "currentTitle": "existing row title",
      "currentDetails": "existing row summary/latestSummary",
      "repo": "repo-or-workspace-name",
      "branch": "branch-name",
      "status": "active|idle|systemError|notLoaded|unknown",
      "messages": [
        {
          "role": "user|agent",
          "text": "bounded message text"
        }
      ]
    }
  ]
}
```

Output schema:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["cards"],
  "properties": {
    "cards": {
      "type": "array",
      "minItems": 1,
      "maxItems": 8,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "title", "details", "confidence"],
        "properties": {
          "id": { "type": "string" },
          "title": { "type": "string", "minLength": 8, "maxLength": 72 },
          "details": { "type": "string", "minLength": 18, "maxLength": 240 },
          "confidence": { "type": "string", "enum": ["high", "medium", "low"] }
        }
      }
    }
  }
}
```

Local validator after model return:

- response parses as JSON;
- `cards.length` equals input thread count;
- every input `id` appears exactly once;
- no unknown IDs appear;
- `title` and `details` trim to non-empty strings;
- `details` passes complete-sentence checks;
- `title` does not start with `Task:`, `Status:`, `Thread:`, or
  `This thread`;
- visible strings do not contain raw bearer-token patterns, OpenAI key
  patterns, base64-looking audio blobs, or obvious JSON payload dumps.

# Model And Latency Plan

Observed test results:

| Model | Input | Latency | Quality note |
| --- | --- | ---: | --- |
| `gpt-5.5`, low reasoning | 3 synthetic threads, 914 input tokens | 3039ms | Strong labels, zero reasoning tokens |
| `gpt-5.4-mini`, low reasoning | 3 synthetic threads, 914 input tokens | 1738ms | Strong labels, faster |
| `gpt-5.5`, low reasoning | 4 real relay threads, 7365 input tokens | 5617ms | Strong labels; one cut off by too-tight schema |
| `gpt-5.4-mini`, low reasoning | 4 real relay threads, 7435 input tokens | 6031ms | Complete labels after schema fix |
| `gpt-5.5`, low reasoning | 4 real relay threads, 7435 input tokens | 4473ms | Complete labels and sharper specificity after schema fix |

Recommended default before approval:

- Compare `gpt-5.5` low reasoning and `gpt-5.4-mini` low reasoning during
  approval instead of assuming the mini model is always faster.
- Use `gpt-5.5` low reasoning as the current approval candidate because the
  account exposes it, it matches the requested `5.5` family, and the latest real
  run was both faster and slightly sharper than `gpt-5.4-mini`.
- Keep `gpt-5.4-mini` low reasoning as the available mini fallback.
- If `gpt-5.5-mini` becomes available, test it against the same sample set
  before replacing `gpt-5.4-mini`.
- Pin the final approved model to a snapshot, for example
  `gpt-5.4-mini-2026-03-17` or `gpt-5.5-2026-04-23`.

# Caching And Call Discipline

Cost is less important than latency, but spammy calls still create stale labels,
rate-limit risk, and needless Dock churn.

Cache key:

```text
thread_id + row_version + prompt_version + model_snapshot + input_signature
```

`input_signature` should hash sanitized metadata plus selected user/agent
message fingerprints, not raw message text in logs.

Call triggers:

- missing label for loaded row;
- row version changed and selected message signature changed;
- user/agent message activity changed;
- manual debug/approval tool request.

No call triggers:

- pure tool output changed;
- reasoning/thinking event changed;
- status heartbeat changed without message change;
- row already has a fresh label for the same input signature;
- OpenAI key is missing;
- relay is in a degraded state where label warmups would compete with critical
  app traffic.

Batching:

- batch up to 4 visible/high-priority rows at a time during initial rollout;
- raise to 8 only after latency and quality are acceptable;
- max concurrent OpenAI label calls: 1 initially, 2 after proof;
- queue newest visible rows before archive/offscreen rows;
- never retry in a tight loop. Retry once after transient provider failure, then
  keep the existing label/fallback until the next row version.

Prompt caching:

- Keep the developer prompt and JSON schema stable and at the start of each
  request.
- Put variable thread data last.
- Use `prompt_cache_key = "codex-dock-thread-card-labels-v1"`.
- Log only usage counters, latency, model, prompt version, and hashed thread
  IDs. Do not log raw prompt input or generated private text outside explicit
  local approval artifacts.

# Data Selection

Use only user/agent message text:

- include first user message if available;
- include most recent 20 to 24 user/agent messages;
- cap each message text to a bounded size, initially 4000 characters;
- include row metadata: existing title, existing details, repo/workspace,
  branch, normalized status, last message timestamp;
- optionally include the current persistent goal summary if app-server exposes
  a compact goal endpoint and it does not leak secrets.

Exclude:

- reasoning/thinking items;
- tool output and command output;
- raw JSON-RPC payloads;
- request-card internals beyond a safe status hint;
- transcript text unless it has already become a user message;
- audio bytes/base64;
- bearer tokens, OpenAI keys, `.env`, service env, raw headers, and cookies.

# DTO And Swift Surface Plan

Relay row fields should eventually separate legacy text from LLM labels:

```json
{
  "title": "fallback/current title",
  "summary": "fallback/current summary",
  "messageSummary": "latest true-message fallback",
  "llmTitle": "holistic generated title",
  "llmDetails": "holistic generated details",
  "llmLabel": {
    "version": "thread-card-labels-v1",
    "model": "gpt-5.4-mini-2026-03-17",
    "confidence": "high",
    "generatedAt": 1770000000
  }
}
```

Swift should map:

- `displayTitle = llmTitle ?? title`
- `shortEventSummary = llmDetails ?? messageSummary ?? summary`

The first implementation can avoid visible UI redesign. The existing
`DockRowView` already has two title lines and two summary/details lines. If the
approved labels feel dense, UI tuning should happen as a separate visual pass.

# Rollout Plan

## Phase 1: Approval Harness Only

- Add a relay-local script or test helper that builds sanitized label inputs
  for selected thread IDs.
- Call OpenAI with the proposed prompt/schema.
- Save outputs to a local approval artifact under `/tmp/codex-client/...` or an
  explicit docs worklog when Amir asks to preserve samples.
- No runtime Dock behavior changes.

Acceptance:

- Amir can review at least 10 real thread labels.
- Worklog includes good and bad samples.
- Prompt/schema are adjusted until labels are approved.
- Approval comparison includes both `gpt-5.5` and `gpt-5.4-mini` unless a true
  `gpt-5.5-mini` model becomes available first.

## Phase 2: Relay Cache Behind Disabled Flag

- Add `scripts/dock-relay-thread-label-cache.mjs`.
- Add env flag `CODEX_DOCK_LLM_THREAD_LABELS_ENABLED=0` by default.
- Add relay-owned OpenAI config:
  - `CODEX_DOCK_OPENAI_THREAD_LABEL_MODEL`
  - `CODEX_DOCK_OPENAI_THREAD_LABEL_REASONING_EFFORT`
  - `CODEX_DOCK_OPENAI_THREAD_LABEL_PROMPT_VERSION`
  - `CODEX_DOCK_OPENAI_THREAD_LABEL_MAX_BATCH`
- Reuse `OPENAI_API_KEY` from Mac-side service env.
- Add tests with fake OpenAI client for batching, cache keys, validation, and
  no-log secret guarantees.

Acceptance:

- `rtk npm run test:relay` passes.
- Missing key disables warmups without degrading Dock rows.
- Runtime logs contain no raw prompt text or generated private details.

## Phase 3: Relay Row Fields Behind Enabled Flag

- Add optional `llmTitle`, `llmDetails`, and label metadata to relay row DTOs.
- Decorate rows from cache without blocking.
- Push `dock/update` when a cached label becomes available.
- Keep old title/summary fields as fallback.

Acceptance:

- Existing Swift app keeps working if it ignores new fields.
- Relay test proves first snapshot can return before OpenAI finishes.
- Relay test proves a later delta carries the warmed label fields.

## Phase 4: Swift Mapping

- Add optional DTO fields to `ThreadDTO` and `DockStreamSessionDTO`.
- Map `llmTitle` and `llmDetails` into `SessionSummary`.
- Project Dock rows with LLM title/details first, fallback text second.
- Add focused Swift mapping/projection tests.

Acceptance:

- `rtk swift test --filter AppServerClientTests` passes for DTO mapping.
- `rtk swift test --filter DockStoreTests` passes for row projection.
- `rtk make app-test SIM='iPhone 17'` passes if UI behavior changes are
  visible enough to need generated-project proof.

## Phase 5: Enable For Local Relay

- Enable on `Amir-M5` only.
- Run `rtk make services`.
- Verify `rtk make dock-relay-status`.
- Inspect real Dock rows on simulator.
- Capture app screenshot or UI output for approval.

Acceptance:

- Dock initially loads with fallback text.
- Labels appear after warmup without row reordering.
- Offline/provider failure leaves existing/fallback row text intact.
- No OpenAI key or raw prompt text appears in app config, host env, logs, or
  diagnostics.

# Verification Matrix

| Requirement | Proof |
| --- | --- |
| No app integration yet | This plan/worklog only; no source DTO/cache edits in this goal |
| Official OpenAI best practices captured | Worklog source list and findings |
| JSON Schema structured output chosen | Prompt contract and schema in this plan |
| Samples preserved for approval | Worklog Prompt Iterations 1-3 and Real Relay Thread Test |
| Mac-side secret boundary preserved | Architecture keeps OpenAI calls in relay |
| No LLM call spam | Cache key, trigger, no-trigger, batching, concurrency rules |
| Latency respected | Async warmup; no blocking snapshot/list path |
| Human-readable labels | Prompt style rules and approval samples |

# Open Questions For Approval

- After reviewing the saved samples, does Amir prefer the `gpt-5.5` approval
  candidate or the `gpt-5.4-mini` fallback style?
- Is the approved visible field name "details", or should code call it
  `llmDetails` while the UI keeps rendering it as the row summary text?
- How aggressive should warmup be for archive/offscreen rows: visible rows only
  at first, or newest 50 loaded rows in the background?

# Current Recommendation

Use `gpt-5.5-2026-04-23` with `reasoning.effort = "low"` as the current
approval candidate, and keep `gpt-5.4-mini-2026-03-17` with
`reasoning.effort = "low"` as the mini fallback. The account did not expose a
`gpt-5.5-mini` model on 2026-05-30, so there is no exact "5.5 mini" model to
lock today. If a `gpt-5.5-mini` model appears, rerun the saved approval samples
before changing the default.

Keep the first runtime cut narrow: relay cache, strict schema, optional DTO
fields, Swift fallback mapping, and no UI redesign. The feature succeeds when
the Dock can open instantly with fallback text and then quietly improve each
row into an at-a-glance label that makes the thread understandable without
remembering the opening prompt.
