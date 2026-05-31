---
title: "Codex Dock - LLM Thread Card Labels - Worklog"
date: 2026-05-30
status: active
owners: [Amir, Codex]
doc_type: worklog
related:
  - docs/CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30.md
  - README.md
  - scripts/dock-relay-thread-summary-cache.mjs
  - scripts/dock-relay-session-table.mjs
  - CodexDock/State/SessionRowProjector.swift
  - CodexDock/Features/Dock/DockSharedViews.swift
---

# Codex Dock LLM Thread Card Labels Worklog

## 2026-05-30 Source Read

Current row text path:

- `README.md` already separates raw Codex history `preview` from relay-owned
  Dock row summaries. The app prefers relay-owned `latestSummary` after the
  relay cache warms.
- `scripts/dock-relay-thread-summary-cache.mjs` currently reads recent turns and
  chooses the latest meaningful user/agent message. It does not synthesize a
  holistic title or current-purpose description.
- `scripts/dock-relay-session-table.mjs` projects rows with:
  - `title`: `name || preview || cwd tail || Thread <id>`
  - `summary`: `latestSummary || preview || title`
  - `messageSummary`: relay-warmed message summary when available
- `CodexDock/State/SessionRowProjector.swift` maps `SessionSummary.displayTitle`
  into `DockRowViewModel.title` and `SessionSummary.shortEventSummary` into
  `DockRowViewModel.summary`.
- `CodexDock/Features/Dock/DockSharedViews.swift` renders the title with two
  lines and the summary/details text with two lines.

Net: the right integration point is the Mac-side relay summary pipeline, not the
iPhone app. The iPhone should receive plain row fields and never receive
`OPENAI_API_KEY`.

## 2026-05-30 Official OpenAI Docs Research

Sources read:

- OpenAI Structured Outputs guide:
  <https://developers.openai.com/api/docs/guides/structured-outputs>
- OpenAI Prompt engineering guide:
  <https://developers.openai.com/api/docs/guides/prompt-engineering>
- OpenAI Reasoning best practices guide:
  <https://developers.openai.com/api/docs/guides/reasoning-best-practices>
- OpenAI Responses API reference:
  <https://developers.openai.com/api/reference/responses/overview>
- OpenAI Prompt caching guide:
  <https://developers.openai.com/api/docs/guides/prompt-caching>
- OpenAI model docs:
  <https://developers.openai.com/api/docs/models/gpt-5.5/>
  <https://developers.openai.com/api/docs/models/gpt-5.4-mini>

Learnings for this feature:

- Use the Responses API, not a phone-side client and not Chat Completions.
  The relay owns the OpenAI key and already owns other OpenAI provider work.
- Use Structured Outputs with `text.format.type = "json_schema"`, `strict:
  true`, and a stable schema. OpenAI says Structured Outputs are preferred over
  old JSON mode when supported because JSON mode only guarantees valid JSON,
  while Structured Outputs also enforce schema adherence.
- Keep the schema stable. OpenAI docs note that structured output schemas can
  be cached and that varying schemas can add latency. The feature should not
  generate dynamic per-request schemas.
- Use `developer` or `instructions` for durable app rules, and pass thread data
  as user input. OpenAI docs describe developer messages as higher priority than
  user messages.
- Keep prompts simple and direct for reasoning-capable models. Do not ask the
  model to expose chain of thought or "think step by step."
- Put static instructions/schema first and variable thread data last so prompt
  caching can help. OpenAI prompt caching depends on exact prefix matches and is
  automatic for prompts at or above 1024 tokens.
- Use `prompt_cache_key` consistently for requests with the same static prefix.
  The proposed key is `codex-dock-thread-card-labels-v1`.
- Pin production to a model snapshot after approval. OpenAI docs recommend
  model snapshots for consistent production behavior and evals for prompt/model
  iteration.
- The account exposed `gpt-5.5`, `gpt-5.4-mini`, and their snapshots, but did
  not expose a `gpt-5.5-mini` model id on 2026-05-30. The closest fast mini
  model available now is `gpt-5.4-mini`; the requested frontier model is
  `gpt-5.5`.

## 2026-05-30 Prompt Iteration 1

Intent: test whether a compact prompt could produce one title/details pair from
multiple thread samples.

Model settings:

```json
{
  "model": "gpt-5.5",
  "reasoning": { "effort": "low" },
  "text": {
    "format": {
      "type": "json_schema",
      "name": "thread_card_label",
      "strict": true
    }
  }
}
```

Schema shape:

```json
{
  "type": "object",
  "required": ["title", "details", "confidence"],
  "additionalProperties": false,
  "properties": {
    "title": { "type": "string", "minLength": 8, "maxLength": 72 },
    "details": { "type": "string", "minLength": 18, "maxLength": 170 },
    "confidence": { "type": "string", "enum": ["high", "medium", "low"] }
  }
}
```

Result:

```json
{
  "model": "gpt-5.5",
  "ok": true,
  "latency_ms": 2980,
  "output": {
    "title": "Thread-card LLM summaries",
    "details": "Designing and testing a prompt for fast OpenAI-generated iPhone dashboard titles and details, with a docs plan before integration.",
    "confidence": "high"
  },
  "usage": {
    "input_tokens": 816,
    "output_tokens": 49,
    "reasoning_tokens": 0,
    "total_tokens": 865
  }
}
```

Comparative mini result:

```json
{
  "model": "gpt-5.4-mini",
  "ok": true,
  "latency_ms": 2870,
  "output": {
    "title": "thread card summaries for codex-client",
    "details": "Multiple active threads: fixing thread detail paging and card stacking, designing LLM-generated thread summaries, and debugging device installs with one blocked by WDA on",
    "confidence": "low"
  },
  "usage": {
    "input_tokens": 816,
    "output_tokens": 267,
    "reasoning_tokens": 207,
    "total_tokens": 1083
  }
}
```

Learning:

- Prompt v1 merged multiple thread samples into one card. That is wrong for a
  batched relay call.
- `details.maxLength = 170` can cut off a sentence. UI line limits should be a
  render concern, not the hard model schema limit.

## 2026-05-30 Prompt Iteration 2

Change:

- Output changed from one card to `cards[]`.
- Prompt explicitly says: "for each input thread, return one independent card
  label. Never merge threads together."

Synthetic test inputs:

- Thread detail full-history pagination and request-card consolidation.
- OpenAI-generated thread card summaries.
- Device install verification with a WebDriverAgent blocker.

`gpt-5.5` result:

```json
{
  "model": "gpt-5.5",
  "ok": true,
  "latency_ms": 3039,
  "cards": [
    {
      "id": "synthetic-1",
      "title": "Thread detail message history",
      "details": "Paging full thread turns newest-first and folding request actions into the shared message card; tests cover paging, ordering, and removal of the separate RequestCardsView",
      "confidence": "high"
    },
    {
      "id": "synthetic-2",
      "title": "OpenAI-generated thread card summaries",
      "details": "Designing and testing a fast LLM prompt for card titles and details, with a docs plan and model fallback before integration",
      "confidence": "high"
    },
    {
      "id": "synthetic-3",
      "title": "Device install and relay host verification",
      "details": "iPhone 17 Pro is installed and verified; iPhone 14 physical verification is blocked because WebDriverAgent is not running",
      "confidence": "high"
    }
  ],
  "usage": {
    "input_tokens": 914,
    "output_tokens": 160,
    "reasoning_tokens": 0,
    "total_tokens": 1074
  }
}
```

`gpt-5.4-mini` result:

```json
{
  "model": "gpt-5.4-mini",
  "ok": true,
  "latency_ms": 1738,
  "cards": [
    {
      "id": "synthetic-1",
      "title": "Full thread detail pagination",
      "details": "Paging thread/turns/list past the 10-message limit, keeping newest-first order, and removing the separate RequestCardsView stack.",
      "confidence": "high"
    },
    {
      "id": "synthetic-2",
      "title": "OpenAI-powered thread card summaries",
      "details": "Designing and testing the prompt for fast LLM-generated titles and details, with a full docs plan before integration.",
      "confidence": "high"
    },
    {
      "id": "synthetic-3",
      "title": "Device install verification",
      "details": "iPhone 17 Pro installed with the correct relay host config; iPhone 14 is blocked because WebDriverAgent is not running on the device.",
      "confidence": "high"
    }
  ],
  "usage": {
    "input_tokens": 914,
    "output_tokens": 175,
    "reasoning_tokens": 18,
    "total_tokens": 1089
  }
}
```

Learning:

- Batch output works once the prompt and schema make per-thread independence
  explicit.
- `gpt-5.4-mini` was faster on this small synthetic batch and good enough to
  keep in the approval comparison if `gpt-5.5-mini` remains unavailable.
- `gpt-5.5` used zero reasoning tokens in this run even with
  `reasoning.effort = "low"`.

## 2026-05-30 Real Relay Thread Test

Method:

- Connected to the running Dock relay at `ws://127.0.0.1:4510`.
- Read `thread/list limit:8`.
- For the first four rows with readable messages, read `thread/turns/list
  limit:12`.
- Built prompt input from metadata plus the last 24 user/agent messages, with
  each message capped at 4000 characters.
- Sent only the structured thread payload to OpenAI.
- Saved generated labels and input sizes here; did not save raw thread message
  text.

Model settings:

```json
{
  "model": "gpt-5.5",
  "reasoning": { "effort": "low" },
  "text": {
    "format": {
      "type": "json_schema",
      "name": "thread_card_labels",
      "strict": true
    }
  }
}
```

Result:

```json
{
  "ok": true,
  "model": "gpt-5.5",
  "reasoning_effort": "low",
  "latency_ms": 5617,
  "input_stats": [
    {
      "id": "019e797a",
      "turns": 1,
      "messages": 1,
      "chars": 310
    },
    {
      "id": "019e7936",
      "turns": 3,
      "messages": 6,
      "chars": 4859
    },
    {
      "id": "019e78d3",
      "turns": 6,
      "messages": 11,
      "chars": 3932
    },
    {
      "id": "019e78a2",
      "turns": 12,
      "messages": 18,
      "chars": 13402
    }
  ],
  "cards": [
    {
      "id": "019e797a-5779-7132-ac8d-fd6e3a5c6c6b",
      "title": "LLM-generated thread card labels",
      "details": "Testing a batch prompt for fast OpenAI card-title/details generation on real relay threads before writing the integration plan doc.",
      "confidence": "high"
    },
    {
      "id": "019e7936-4a83-71f3-b134-165a585f5dae",
      "title": "Scene rendering unification code review",
      "details": "Exhaustive review doc saved beside the epic; verdict is not-approved because chip-budget table content is validated but never lowered into render states.",
      "confidence": "high"
    },
    {
      "id": "019e78d3-06a8-79c2-881e-d1a88b3c4598",
      "title": "Colorado trip booking dossier",
      "details": "United AUS-DEN round trip confirmation H12QTW was found and saved; only flights are booked, so lodging, transport, and activities still need planning.",
      "confidence": "high"
    },
    {
      "id": "019e78a2-0ac0-7b41-acdb-7bbb2a0ea19c",
      "title": "AIMGR Redis credential coordination cutover",
      "details": "Redis-backed credential sharing is implemented, pushed, and working locally; remaining work is rolling the same build and config onto home, agents@amirs-mac-studio, and M",
      "confidence": "high"
    }
  ],
  "usage": {
    "input_tokens": 7365,
    "output_tokens": 318,
    "reasoning_tokens": 14,
    "total_tokens": 7683
  }
}
```

Learning:

- Real labels are directionally strong and much better than first-message
  previews.
- The fourth real-thread `details` value was cut off because
  `details.maxLength = 170`. Final schema should allow a larger string, and the
  app should render two lines with truncation if needed.
- A one-message thread can still get a useful high-confidence label when the
  one message is explicit enough.
- Latency for four real threads on `gpt-5.5` low reasoning was about 5.6s. That
  is acceptable for async warm-cache behavior, not for blocking the first Dock
  list response.

## 2026-05-30 Prompt Iteration 3

Change:

- Kept `cards[]` batch output.
- Raised `details.maxLength` from `170` to `240`.
- Added a sentence-quality rule: `details` must be a complete sentence and must
  not end with a conjunction, comma, semicolon, colon, dangling article, or
  unfinished proper noun.
- Switched the durable prompt message to `developer`, matching current OpenAI
  guidance for application-owned instructions.
- Added `prompt_cache_key = "codex-dock-thread-card-labels-v1"` to the test
  request.
- Added a local validator for card count, ID coverage, duplicate IDs, empty
  fields, and obvious unfinished `details` text.

Method:

- Reused the running Dock relay at `ws://127.0.0.1:4510`.
- Read four real relay threads and up to 12 turns per thread.
- Sent the same sanitized input batch to `gpt-5.4-mini` and `gpt-5.5`.
- Saved generated labels and usage here; did not save raw thread message text.

Input stats:

```json
[
  {
    "id": "019e797a",
    "turns": 1,
    "messages": 2,
    "chars": 438
  },
  {
    "id": "019e7936",
    "turns": 3,
    "messages": 6,
    "chars": 4859
  },
  {
    "id": "019e78d3",
    "turns": 6,
    "messages": 11,
    "chars": 3932
  },
  {
    "id": "019e78a2",
    "turns": 12,
    "messages": 18,
    "chars": 13415
  }
]
```

`gpt-5.4-mini` candidate result:

```json
{
  "model": "gpt-5.4-mini",
  "ok": true,
  "status": 200,
  "latency_ms": 6031,
  "validation_issues": [],
  "cards": [
    {
      "id": "019e797a-5779-7132-ac8d-fd6e3a5c6c6b",
      "title": "LLM-generated thread card summaries",
      "details": "The prompt and plan are being finalized for fast OpenAI-generated thread titles and details, with a final comparison run still pending to align the recommendation with real sample outputs.",
      "confidence": "high"
    },
    {
      "id": "019e7936-4a83-71f3-b134-165a585f5dae",
      "title": "Scene rendering unification review",
      "details": "The exhaustive code review was completed and saved beside the epic files, and the current blocker is an unclosed chip-budget wiring gap in the rendering path.",
      "confidence": "high"
    },
    {
      "id": "019e78d3-06a8-79c2-881e-d1a88b3c4598",
      "title": "Colorado trip booking and lodging",
      "details": "The trip notes were checked, the Denver routing was recovered, and the remaining task is confirming actual bookings and lodging status from the live mail trail.",
      "confidence": "high"
    },
    {
      "id": "019e78a2-0ac0-7b41-acdb-7bbb2a0ea19c",
      "title": "AIM credential coordination cutover",
      "details": "The Redis-based credential coordination rollout is being documented and hardened as a breaking migration, with the remaining work focused on finalizing durable config and import rules across machines.",
      "confidence": "high"
    }
  ],
  "usage": {
    "input_tokens": 7435,
    "cached_tokens": 0,
    "output_tokens": 344,
    "reasoning_tokens": 39,
    "total_tokens": 7779
  }
}
```

`gpt-5.5` candidate result:

```json
{
  "model": "gpt-5.5",
  "ok": true,
  "status": 200,
  "latency_ms": 4473,
  "validation_issues": [],
  "cards": [
    {
      "id": "019e797a-5779-7132-ac8d-fd6e3a5c6c6b",
      "title": "LLM-generated thread card labels",
      "details": "The prompt and planning docs are being finalized, with a final real-data comparison between gpt-5.5 and the recommended mini model before integration approval.",
      "confidence": "high"
    },
    {
      "id": "019e7936-4a83-71f3-b134-165a585f5dae",
      "title": "Scene rendering unification code review",
      "details": "The exhaustive review was saved beside the epic docs and marked not approved because chip-budget content is accepted but not lowered into render states.",
      "confidence": "high"
    },
    {
      "id": "019e78d3-06a8-79c2-881e-d1a88b3c4598",
      "title": "Colorado trip booking dossier",
      "details": "The United flight confirmation was found and recorded, and the dossier now shows that lodging, Amtrak, rental car, and activities are still not booked.",
      "confidence": "high"
    },
    {
      "id": "019e78a2-0ac0-7b41-acdb-7bbb2a0ea19c",
      "title": "AIMGR Redis credential coordination cutover",
      "details": "The Redis-based credential system is committed, pushed, configured, and being rolled out to the home, Mac Studio agents, and M3 Max installs with legacy secrets archived and tests in progress.",
      "confidence": "high"
    }
  ],
  "usage": {
    "input_tokens": 7435,
    "cached_tokens": 0,
    "output_tokens": 318,
    "reasoning_tokens": 10,
    "total_tokens": 7753
  }
}
```

Learning:

- Candidate v3 fixed the observed cutoff problem. Both models produced complete
  `details` strings and passed local validation.
- On this real-thread batch, `gpt-5.5` was faster than `gpt-5.4-mini`
  (`4473ms` versus `6031ms`), even though `gpt-5.4-mini` was faster on the
  synthetic batch. Treat latency as empirical and variable, not as a model-name
  assumption.
- `gpt-5.5` produced slightly sharper, more specific labels on this sample set.
- `gpt-5.4-mini` remains a reasonable fallback if cost/rate limits matter, but
  the approval candidate should compare both instead of locking one from theory.
