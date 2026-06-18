Raw Goal

I want you to deeply review our stack end to end and I want you to come up with an approach that builds a unified testing framework that has both like sort of smoke tests and full tests and real-time tests where it tests against data over time, not just once, and it tests all of the various cases we actually see in real world scenarios exhaustively and work with Model Consensus Opus 4MX and GPT-55XI to develop the world's most elegant, complete and robust testing frameworks. One of the biggest problems that I have is it's just like we run these isolated limited tests and we're like, oh, it looks good, right? But it's like, yeah, that doesn't work actually when you've got 900 threads and many of them are changing and some of them are stale, et cetera, et cetera. So we've got a shitload of testing stuff. I don't think it's unified. I don't think it's elegant. I don't think it's coherent I need this turned into a pure and architectural coherent framework that is easy to run and follows all the best practices and everything refactored onto it. low value items just simply deleted, right? The instructions on how to use it integrated into our agents.amd. and I want the exhaustive plan put together as a new document in the docs directory. And it's not done until a fresh consult with Composer 25S as like, it's architecturally pure, doesn't preserve shit that was like, is not high value for no reason. and it's like fully specified. Once that's done and it passes a plan audit skill, you can stop for me to review it.

Follow-up Requirement

It should include appropriate documentation in our Agents.md and other places such that like how to use it and how to add to it will always be discovered.

Faithful Goal Brief

Create a repo-grounded architecture plan for a unified Codex Dock testing framework. The plan must cover smoke checks, full checks, and over-time real-time checks against evolving data, including large and stale real-world states. It must inventory and rationalize the existing Swift, Node, contract, simulator, physical-device, and proof surfaces; choose one coherent canonical framework; identify low-value or duplicate testing paths to delete or demote; specify how future tests and scenarios are added; and make usage/addition instructions discoverable in AGENTS.md plus other canonical docs. The plan must be a new document under docs/. After the plan exists, it must receive a fresh Cursor Agent Composer 2.5 Fast consult for architectural purity and must pass the plan-audit skill before stopping for user review.

Hard Constraints

- Work root: /Users/aelaguiz/workspace/codex-client.
- The repo uses AGENTS.md and /Users/aelaguiz/.codex/RTK.md; Makefile is the runnable command source of truth.
- This is planning work. Do not edit files, run formatters, or implement fixes in the child sessions.
- Do not invent a second command surface if Makefile or package scripts already own it.
- Do not preserve low-value or duplicate paths only because they already exist.
- Do not use screenshots, mocks, preview rows, loopback-only raw app-server paths, or one-shot checks as completion-grade proof where real relay-backed or device proof is required.
- Repo claims must cite evidence read from disk.
- The final parent plan must be specific enough for implementation, deletion, and future test additions.
