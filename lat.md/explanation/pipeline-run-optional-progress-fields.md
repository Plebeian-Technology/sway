---
lat:
  mode: explanation
---

# Why the run progress fields are optional

`ILegislationPipelineRun`'s `processed`.

`ILegislationPipelineRun`'s `processed`, `total`, `current_bill_external_id`, `phase`, `eta_seconds`, `errors`, and `queued` fields are typed optional because the server's own builder (`LegislationPipelineRun#to_builder`) does not send them. They arrive later over `PipelineRunChannel`, so the first render after a redirect sees a run object without them.

## The crash this prevents

These fields used to be declared as always present.

That was never true of any actual payload, and it cost a live crash: `PipelineProgress` read them with destructuring defaults, the lint rule for useless defaults flagged those defaults as dead code — because the type said the fields could never be missing — the defaults were deleted, and the Bill Creator pipeline tab then threw on `errors.length` and rendered its error boundary instead of any buttons.

Keeping the fields optional forces a reader (and the type checker) to handle the absent case, so a future cleanup pass can't repeat the same deletion.

## Why cancelled_at is absent and download_missing_assets is nullable

`ILegislationPipelineRun` has no `cancelled_at` property because no such database column exists and the serializer never emits one.

`download_missing_assets` (formerly `refresh`) is non-null in the database with a `true` default, but is typed as `boolean | null` on the frontend because partial page payloads can omit the field.
