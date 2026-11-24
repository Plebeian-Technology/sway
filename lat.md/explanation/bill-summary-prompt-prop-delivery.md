---
lat:
  mode: explanation
---

# Why summary_prompt_prop is optional and top-level

`summary_prompt_prop` builds the prompt an operator can paste into another agent to summarize a bill.

Building it costs only time — no database write, no model call — so the reason to withhold it by default is its size: it carries the bill's whole diff, and can run to tens of kilobytes.

## Opt-in via InertiaRails.optional

`InertiaRails.optional` withholds the prop from every ordinary page visit.

The Prepare-prompt button asks for it by name, with a partial reload: `router.reload({only: ["summary_prompt", "bill"]})`. Nothing builds the prompt until an operator asks for it.

## Why it lives at the top level, not inside bill

A partial reload merges props one level deep.

If `summary_prompt` lived nested inside the `bill` prop, it would vanish every time the Summary tab's 5-second poll refreshed `bill` — the poll's reload would replace the whole `bill` object, prompt included, even though the poll never asked for the prompt. Keeping it as its own top-level prop means the poll's refresh of `bill` cannot touch it.

## Why JSON callers get it only on request

`#edit`'s JSON half runs every prop through `resolve_inertia_props`, which unwraps `InertiaRails.optional` and keeps whatever value comes out.

That unwrapping is what makes deferred and lazy props work for JSON callers, which cannot name a prop the way an Inertia partial reload does. Left unguarded, it would rebuild the prompt on every JSON request: measured at 25KB of prompt on an 85KB response, and the Summary tab polls every five seconds. [[app/controllers/bills_controller.rb#BillsController#summary_prompt_prop]] therefore builds nothing for a mobile request unless the request carries `summary_prompt=1`, the phone's equivalent of the web's partial reload ([[mobile-bill-creator#Sections#The summary generation section#Preparing the summary prompt]]).
