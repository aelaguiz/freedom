Yes, with one small correction: add the explicit completion gate from the original goal.

Smallest correction:

- After the docs are written, the dated plan must get the required fresh Composer 2.5 Fast consult and pass `plan-audit` before stopping for user review.

Everything else preserves my agreement:

- It documents current commands only.
- It marks umbrella targets as future, not current.
- It avoids `test-realtime`, which is the right call because OpenAI Realtime transcription already uses that word.
- It keeps latency proofs bespoke for now.
- It demotes old sync docs instead of deleting them prematurely.
- It uses `Makefile` as the public command surface.

Residual risk: `docs/TESTING.md` and the dated plan must not duplicate long command explanations. `docs/TESTING.md` should stay current-use, while the dated plan carries future architecture and cleanup decisions.