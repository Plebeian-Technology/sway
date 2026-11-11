---
mode: explanation
summary: "Why seven ILegislationPipelineRun progress fields are typed optional, and the live crash that happened when they were not."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the run progress fields are optional

`ILegislationPipelineRun`'s `processed`, `total`, `current_bill_external_id`,
`phase`, `eta_seconds`, `errors`, and `queued` fields are typed optional
because the server's own builder (`LegislationPipelineRun#to_builder`) does
not send them. They arrive later over `PipelineRunChannel`, so the first
render after a redirect sees a run object without them.

## The crash this prevents

These fields used to be declared as always present. That was never true of
any actual payload, and it cost a live crash: `PipelineProgress` read them
with destructuring defaults, the lint rule for useless defaults flagged
those defaults as dead code — because the type said the fields could never
be missing — the defaults were deleted, and the Bill Creator pipeline tab
then threw on `errors.length` and rendered its error boundary instead of
any buttons.

Keeping the fields optional forces a reader (and the type checker) to
handle the absent case, so a future cleanup pass can't repeat the same
deletion.
