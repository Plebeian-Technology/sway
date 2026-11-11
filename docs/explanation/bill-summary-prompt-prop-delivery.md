---
mode: explanation
summary: "Explains why the bill summary prompt prop is optional, lives at the top level of props, and is withheld from JSON callers."
status: agent-extracted
related: []
---

# Why summary_prompt_prop is optional and top-level

`summary_prompt_prop` builds the prompt an operator can paste into another
agent to summarize a bill. Building it costs only time — no database write,
no model call — so the reason to withhold it by default is its size: it
carries the bill's whole diff, and can run to tens of kilobytes.

## Opt-in via InertiaRails.optional

`InertiaRails.optional` withholds the prop from every ordinary page visit.
The Prepare-prompt button asks for it by name, with a partial reload:
`router.reload({only: ["summary_prompt", "bill"]})`. Nothing builds the
prompt until an operator asks for it.

## Why it lives at the top level, not inside `bill`

A partial reload merges props one level deep. If `summary_prompt` lived
nested inside the `bill` prop, it would vanish every time the Summary tab's
5-second poll refreshed `bill` — the poll's reload would replace the whole
`bill` object, prompt included, even though the poll never asked for the
prompt. Keeping it as its own top-level prop means the poll's refresh of
`bill` cannot touch it.

## Why JSON callers never receive it

`#edit`'s JSON half runs every prop through `resolve_inertia_props`, which
unwraps `InertiaRails.optional` and keeps whatever value comes out — that
unwrapping is what makes deferred and lazy props work for JSON callers,
which have no way to ask for a named prop the way an Inertia partial reload
does. Left unguarded, that same unwrapping would rebuild the ~25KB prompt on
every JSON request, for a caller with no Prepare-prompt button to press.
`summary_prompt_prop` returns `{}` for mobile API requests to avoid that
cost. Left unguarded, that cost is not hypothetical: measured at 25KB of
prompt on an 85KB response, for a caller with no button to press to ask
for it.
