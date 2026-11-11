---
lat:
  mode: explanation
---

# Why the LLM-summary notice ids each get their own file

`NO_TESTIMONY_NOTICE_ID`, `PIPELINE_BUSY_NOTICE_ID` and `RUN_IN_FLIGHT_NOTICE_ID` (`app/frontend/components/admin/creator/llm-summary/noTestimonyNoticeId.ts`.

`NO_TESTIMONY_NOTICE_ID`, `PIPELINE_BUSY_NOTICE_ID` and `RUN_IN_FLIGHT_NOTICE_ID` (`app/frontend/components/admin/creator/llm-summary/noTestimonyNoticeId.ts`, `pipelineBusyNoticeId.ts`, `runInFlightNoticeId.ts`) are the HTML `id`s of three notices shown on the Bill Creator's LLM summary screen. Each constant sits alone in its own one-line file rather than living beside the component that renders the notice it names.

## An agreement neither component owns

Each id is shared between two components that neither one owns.

Each id is shared between two components that neither one owns: one renders the notice element carrying that `id`, and a disabled Approve or generate/regenerate button somewhere else in the tree points its `aria-describedby` at it. Neither component is a sensible home for the other's dependency — the notice doesn't know which buttons point at it, and a button doesn't know how the notice's markup is built. Typing the same string into both call sites is exactly how such a reference goes stale, and it goes stale quietly: an `aria-describedby` pointing at an id that no longer exists reads out nothing to a screen reader, and nothing raises an error. Putting the string in one file that both sides import makes that drift a compile-time impossibility instead of a silent accessibility bug.

## Why not data-testid

A `data-testid` cannot stand in for this, because `aria-describedby` matches on `id` and nothing else. Each notice carries both attributes, with different values on purpose, so nobody edits one attribute believing it is the other.

## Why a plain constant rather than a per-instance id

Each of these three notices is a statement about something coarser than an individual row, and is drawn at most once per screen:

- `NO_TESTIMONY_NOTICE_ID` is a statement about the BILL, rendered once at
  the top of the org-position list, not once per card.
- `RUN_IN_FLIGHT_NOTICE_ID` is a statement about the ROW, drawn once at the
  top of the panel, above every card it applies to.
- `PIPELINE_BUSY_NOTICE_ID` can only be on screen once because its two
  possible homes, `LlmSummaryStatusShell` and `LlmSummaryEmptyState`, never
  appear together — the empty state shows only when there is no
  provisioning row, which is the one case where the shell renders nothing
  at all.

A per-instance id would solve a problem none of these three notices has, at the cost of every reader having to construct the same string identically.
