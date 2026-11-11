---
mode: explanation
summary: "Test-setup rationale for BillCreatorLlmSummary.test.tsx: fixture override handling, provisioning fixture typing, and why certain fixture fields and assertions are shaped the way they are."
status: agent-extracted
related: []
---

# BillCreatorLlmSummary test notes

## fixtureOverride reads an explicit null correctly

Read one field out of a fixture's overrides, letting an explicit null mean
null.

`??` cannot distinguish an explicit null override from a missing key — the
fallback would swallow it, silently handing every null override the
default instead.

Centralized here so a newly added field can't reintroduce the `??` bug by
accident.

The cast states what Object.hasOwn has just proved and the optional
property type cannot: the key is there, so the value is the caller's rather
than a missing one.

(`app/frontend/components/admin/creator/__tests__/fixtureOverride.ts`)

## Provisioning fixtures are typed, unlike the whole TBill

PROVISIONING is typed, unlike the whole TBill (fifteen unused fields). usePage is a
bare vi.fn(), so an untyped fixture let five required provisioning fields go missing
silently.

Every override goes through fixtureOverride, reading via Object.hasOwn not `??` — `??`
can't express an explicit null, so `llm_summary: null` silently became a default.

## paste_owns_summary_run is set independently of llm_provider

Separately settable from llm_provider, on purpose: the two disagree on a row pasted
into and then regenerated, and a fixture moving them together hid a bug that read the wrong column.

(`app/frontend/components/admin/creator/__tests__/BillCreatorLlmSummary.test.tsx`)

## The refused-Generate test relies on the onError toast, not a flash

generate_summary refuses with a redirect carrying `inertia: {errors: {generation:}}` and no flash —
nothing on this screen reads it, so a refused Generate showed the operator nothing.

`llm_summary: null` is load-bearing: Retry lives on the generate branch, and a
failed row that still holds a summary is drawn by the completed view instead.

Retry and Generate are the two buttons through handleGenerate. The regenerate confirm step posts
to /regenerate_summary instead, which writes the audit entry.

## The no-provisioning empty-state CTA also posts to /regenerate_summary

The button shown on a bill that has no summary record at all.

This screen used to offer no way to make a summary — Regenerate needs an existing
stale record. Generate here POSTs to /regenerate_summary, and the job creates the
record itself.

## Clear supplemental testimony must keep scroll and report a failed PATCH

This was the only write in app/frontend sent with no options at all;
every one of the other 26 passes at least `preserveScroll`. That had two
consequences.

Every Inertia reload should keep scroll position — Clear sits below a 16-row text box, so a redirect
that lost scroll dumped the operator at the top of the page.

Clearing sets `has_testimony`, which greys out Approve on every draft card. When the
PATCH fails, the page never reloads, the box still shows deleted text, and nothing
says otherwise. (C1-i6-IN-03 / EXT-02)

## The editable-summary test must drive the real parent, not a child fixture

This box was filled from llm_summary but saved to bills.summary — different columns,
and the public page reads bills.summary. ANY save replaced a hand-written summary with
the model's draft.

Driven through the REAL parent, not the child — the defect was in the wiring, and every
child-level fixture handed the editor one string, hiding it.

## Taking the model's draft must stay an explicit act, and the test proves click order

Taking the draft has to stay possible — it is the whole point of
generating one — but as a deliberate act with the difference on screen
first, rather than as the silent default.

Copying is not publishing — this example used to click copy then Save and assert loosely, which
wouldn't catch copy also saving. Click order is load-bearing.

## Draft position card indices are checked against the full server-side list

Old `rejected: true` entries are dropped before drawing cards, but each card's position number is checked
against the FULL server-side list, so a stale entry would approve the wrong draft.

## The positions-failure notice must reach the completed branch too

generation_error explains a positions-call failure, but that only reached LlmSummaryGenerateBranch, which
a finished summary never shows — leaving an empty area unexplained.

## A positions-call failure does not make a good summary look ungenerated

Draft positions are kept on a positions-call failure, so "were not generated" was false over cards that
are still good — a skipped-but-has-a-summary bill breaks the same assumption.

## Clear-testimony confirmation is skipped when the bill has no drafts

This bill has no drafts, so clearing blocks nothing and the warning
would just be noise.

## The no-testimony notice fixture must type has_testimony, not leave it undefined

The typed fixture matters: before it, has_testimony read as undefined on every bill built here, so the
notice's `=== false` gate never matched here.

## An expired-page Generate failure needs its own banner, since there is no onSuccess

Generate carried onError and onFinish but no onSuccess, so an expired page cleared the busy flag with
only a generic banner as the sign nothing had started.
