# Goal Brief

## Raw Goal

I want you to work with a model consensus GBT55X-Hi and Opus for a Max to build
the most elegant robust architecture that's aligned with how how codex actually
works, regardless of how our code works today, I have zero-salt cost fallacy. I
don't care how it works today. I want the absolute most robust possible as a
new document. And then once they're aligned on that dock, not the
implementation. You're going to use ArcStep AutoPlan to step through and plan
out the implementation of the most elegant possible architecture, regardless of
how hard it is. I don't care about cost. I want most elegant possible and robust
possible and I want it to be fucking like I want it logging everything so that
it's easy to debug I want it to just be fan-fucking-tastic, blog-worthy. And
then once you think you've got that plan ready, and it's saved out, the ARC step
auto plan is complete, then run that through the plan audit skill. and then
once all of that is all the way done, I want you to use the ArcStep Auto
Implement Path. And once that's fully implemented, I want you to do a fresh
consult with Composer 2.5 fast and have it audit our code against the plan and
see if we missed anything. And once that's good, we need to do a plan audit,
implementation check, and then a thorough nuclear code review.

## Resolved Participants

- `gpt55xhi`: Codex runtime, model `gpt-5.5`, effort `xhigh`.
- `opus-max`: Claude runtime, model alias `opus`, effort `max`.

## User-Named Inputs And Current Evidence

- Work root: `/Users/aelaguiz/workspace/codex-client`.
- Supporting Codex source root: `/Users/aelaguiz/workspace/codex`.
- Current root-cause audit:
  `docs/CODEX_DOCK_CODEX_APP_SERVER_END_TO_END_AUDIT.md`.
- Current root-cause worklog:
  `docs/CODEX_DOCK_THREAD_SORT_ROOT_CAUSE_2026-05-29_WORKLOG.md`.
- Repo command source of truth: `Makefile`.
- Generated Xcode source of truth: `project.yml`.
- Product/runbook orientation: `README.md`.
- Repo instructions: `AGENTS.md`.

## Hard Constraints

- Do not optimize for preserving current Dock code shape.
- Do optimize for Codex's real app-server/session/lifecycle model.
- Physical phones must connect to the relay on `:4510`, not raw app-server
  `:4500`.
- Raw app-server bearer tokens and `OPENAI_API_KEY` stay Mac-side.
- iPhone 17 Pro uses Tailscale endpoints:
  `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`.
- iPhone 14 uses non-Tailscale endpoints:
  `Amir-M5.local:4510` and `192.168.50.74:4510`.
- Builds, installs, services, and verification must be Makefile-owned.
- Architecture must include explicit observability and debuggability design.
- Do not quote secrets, bearer tokens, raw prompt text, raw transcript text,
  raw audio, base64 audio, or full JSON-RPC payloads.
- This phase is read-only architecture consultation. Do not edit implementation
  files.

## Desired Output

Return a deeply reasoned architecture proposal that can be synthesized into a
canonical architecture document and then used as the input to ArcStep AutoPlan.
Name exact repo files and Codex files used as evidence. Include the smallest
set of hard architectural decisions that make the system robust, observable,
and aligned with Codex.
