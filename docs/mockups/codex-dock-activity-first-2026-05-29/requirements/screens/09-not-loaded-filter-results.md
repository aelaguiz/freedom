# Screen Requirements: 09 Not Loaded Filter Results

Source: `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md` sections 12 and 15.

## Purpose

The not-loaded result state explains that rows exist but Dock does not currently have loaded thread detail for them. It must avoid implying rate limits or broken access.

## Requirements

- `S09-001` Filtering to not-loaded rows MUST show a visible `Not loaded` state or section label.
- `S09-002` The screen MUST explain that these sessions exist in the list.
- `S09-003` The screen MUST explain that Dock does not have loaded thread detail for them.
- `S09-004` The screen MUST keep matching not-loaded rows visible unless another explicit filter hides them.
- `S09-005` The screen MUST show active filters and search state.
- `S09-006` The screen MUST provide a way to clear the not-loaded filter.
- `S09-007` The screen MUST preserve host, branch, repo, and last-known activity metadata when available.
- `S09-008` The screen MUST keep host identity visible for multi-host lists.
- `S09-009` The screen MUST keep the selected lens visible.

## Row Behavior

- `S09-020` Not-loaded rows MUST use the `Not loaded` status chip.
- `S09-021` Not-loaded rows MAY use skeleton text only for unknown content.
- `S09-022` Not-loaded rows MUST show known title or thread id fallback when title is unavailable.
- `S09-023` Not-loaded rows MUST show known host metadata.
- `S09-024` Not-loaded rows MUST show known branch metadata when available.
- `S09-025` Not-loaded rows MUST remain navigable if thread detail can be fetched after tap.

## Copy And Tone

- `S09-030` Explanation copy SHOULD be equivalent to `These sessions exist in the list, but Dock does not have loaded thread detail for them.`
- `S09-031` Copy MUST be neutral.
- `S09-032` Copy MUST NOT imply rate limiting.
- `S09-033` Copy MUST NOT imply user action is required unless a concrete action is known.

## Prohibited Content

- `S09-040` The screen MUST NOT show `Limited`.
- `S09-041` The screen MUST NOT use `Rate limited` unless explicit rate-limit evidence exists.
- `S09-042` The screen MUST NOT use `Needs me`.
- `S09-043` The screen MUST NOT show not-loaded rows as errors.
- `S09-044` The screen MUST NOT hide host or branch metadata that is already known.
- `S09-045` The screen MUST NOT use raw endpoint strings as primary host names.

## Acceptance Evidence

- Applying a `Not loaded` status filter shows explanatory copy and not-loaded rows.
- Accessibility output contains `Not loaded` and the explanatory copy.
- Accessibility output does not contain `Limited` or unsupported rate-limit language.
