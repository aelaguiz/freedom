Model A
- Raw phrase: Opus 4 8 Max
- Resolved: runtime=claude, model=claude-opus-4-8, effort=max
- Role: collaborator

Model B
- Raw phrase: GBD-55XI
- Resolved: runtime=codex, model=gpt-5.5, effort=xhigh
- Role: collaborator

Resolution notes
- `GBD-55XI` is interpreted from repo/user context as GPT/GBT 5.5 xhigh.
- `gpt-5.5` availability was verified through `codex debug models`.
- `claude-opus-4-8` is the exact Opus 4.8 normalization; if the Claude CLI rejects it, the model-consensus run must fail loud instead of substituting.
