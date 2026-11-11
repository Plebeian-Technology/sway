---
mode: explanation
summary: "Explains why failureTiming.ts returns null instead of an empty string for a missing or unreadable timestamp."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why failureTiming.ts returns null, not an empty string

The roadmap locks one rule for a missing pipeline-failure
timestamp: it renders as nothing, separator included — never an em dash,
never the word "unknown", never a 1970 date. The nearest existing example
in the codebase, `PipelineTerminalAlerts.tsx`'s cancelled-run alert, renders
a raw stored timestamp with an em dash fallback for the missing case. That
example is the one this module exists to not repeat.

`failureTiming`, `exactTime` and `failureAge` each return `string | null`
rather than `string`. A caller reading `null` can drop the whole clause
`{value && <span>{value}</span>}` in JSX. An empty string would still
render — an empty `<span>`, or a lone separator — so `null` is what makes
"renders as nothing" the caller's default behavior rather than something
each call site has to remember to check for.
