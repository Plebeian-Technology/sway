---
lat:
  mode: explanation
---
# Panels that remember whether they were open

[[app/frontend/components/CollapsiblePanel.tsx#CollapsiblePanel]] is the fold-away panel the Pipeline, LLM and Bill Schedule surfaces use. It remembers per browser whether the operator left it open, so a panel someone folded away stays folded on their next visit.

## No effect watches the stored value

The stored value is read once, by `useState`'s initializer as the panel first appears, and written straight through from the change handler.

An effect would be watching for something that does not happen. Nothing else in the application writes these keys, and a panel's open state is not shared between tabs or devices — so there is no second writer whose change would need picking up, and the read has exactly one moment where it matters.

## Storage that is not there falls back to the default

Every read and write is wrapped, and a browser that refuses storage gets the panel's own `defaultOpen` rather than an exception.

Reading `window.localStorage` is not merely a call that can return nothing: in a browser told to block all site data, touching the property throws. That throw would happen inside a `useState` initializer, during render, with no boundary nearer than the page-level one — so a private-browsing window or a hardened privacy setting would take down the whole Bill Creator page rather than costing one panel its memory. This is the same defence [[app/frontend/sway_utils/report_once.ts#reportOnce]] already applies to the same API for the same reason.

A stored value that is neither `"1"` nor `"0"` falls back to `defaultOpen` too. Only this component writes these keys, so anything else there is a leftover from a version that wrote them differently, and honouring the panel's declared default is a better answer than reading every unrecognised string as closed.
