---
lat:
  mode: explanation
---
# Toasts

Sway raises every pop-up toast through one shared [[app/frontend/sway_utils/index.ts#notify]] helper, over one [[app/frontend/App.tsx#App]]-mounted Toaster, which is why a corner or a cap decided once holds everywhere.

## Flash toast dedupe

[[app/frontend/sway_utils/flashToasts.ts#registerFlashToasts]] shows Rails flash messages as toasts after every Inertia visit, and holds the identity of the last flash toasted, so a stale prop left behind by a partial reload does not toast twice.

`flash` is an ordinary shared prop, and a partial reload only fetches the
props it asked for, so an old flash message can still be sitting on
`page.props`.

Two flashes are distinguished by the request that set each one, not by the
words in it. `ApplicationController` merges `request.request_id` into the shared
prop as `id`, so a partial reload replays the id the page was rendered with,
while two consecutive actions carry different ids however alike their wording.

Keying that identity on the message text instead cost the second of two
identical confirmations: adding two categories one after the other, or saving
the same settings field twice, produced the same sentence each time and only
the first one appeared. The inline banners that used to say it as well were
removed, leaving the toast as the only confirmation there is. A
flash that carries no id falls back to its text.

### Why per-page flash banners were removed in favor of the global Toaster

Flash messages are shown once by the global Toaster that drops duplicates, so a page drawing its own banner for the same flash said the same thing twice.

`LlmSettings.tsx` used to draw its own banner as well, saying the same thing
twice, so it was removed. Inline validation errors under each Select stay —
they belong to one field rather than to the flash.

### A refusal that arrives in the errors hash needs its own reader

A controller that refuses a write with `inertia: {errors: {...}}` sets no
flash, so the global Toaster has nothing to show and the screen reports
nothing at all.

The visible result is a click that looks like a slow request: a dialog stays
open, a form sits there, and the operator waits for something that already
finished. `notifyServerRefusal` reads the named channel out of the errors hash
in an `onError` callback and raises the toast the flash would have carried.

The channel names are a fixed union rather than free strings, so a name that
does not exist is a compile error instead of a silently undefined lookup, and
every new refusal channel is covered the same way as the others.

## Toast position is owned by the mounted Toaster

Every toast's on-screen corner comes from the single `position` prop on the Toaster in `App.tsx`; no other layer sets one, so changing that prop moves every toast at once.

Two call sites used to defeat it. [[app/frontend/sway_utils/index.ts#notify]]
defaulted `position` to `"bottom-center"` on every call that did not name one,
so the Toaster's own default was never reached. Separately,
[[app/frontend/sway_utils/flashToasts.ts#registerFlashToasts]] hard-coded
`position: "top-center"` on the flash toasts it raised, which
`react-hot-toast` treats as a per-toast override that beats whatever the
mounted Toaster says. A single change to the Toaster's `position` prop could
not have moved flash toasts while that stayed in place.

A third call site survived that sweep and was found by review afterwards:
[[app/frontend/components/offline/SWUpdateToast.tsx#SWUpdateToast]] raises the
service-worker update prompt through `react-hot-toast` directly rather than
through `notify`, so grepping the helper's call sites did not reach it. It
pinned `bottom-center` on a toast that `AuthLayout` renders on every signed-in
page, which put the update prompt in a different corner from every other toast
the same session could raise. Only its `duration: Infinity` is a genuine
per-toast property — the prompt carries a Reload button and must wait to be
answered rather than fading.

## The five-toast cap reuses the de-dup identifier

`react-hot-toast` has no visible-count limit of its own, so [[app/frontend/sway_utils/index.ts#notify]] hand-rolls one: a module-level list of the ids it has issued, capped at five, evicting the oldest with `toast.dismiss` once a sixth arrives.

The list only ever grows by a genuinely new id and only ever shrinks by
eviction, so its length bounds the visible count even though nothing removes
an entry when its toast expires on its own timer — a toast that already faded
out is a no-op `dismiss` later, not a phantom slot.

The same stable id [[app/frontend/sway_utils/index.ts#notify]] already builds
for de-duplication (`` `${level}-${title}-${message}` `` for a string title)
decides whether a call is new. A call whose id is already tracked is a
`react-hot-toast` upsert, not a new toast, so it neither grows the list nor
triggers an eviction check — reusing an identifier can refresh a toast's
content without ever pushing a neighbor out.
