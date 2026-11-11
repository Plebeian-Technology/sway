---
lat:
  mode: explanation
---

# BillCreatorSummaryAudio mechanics

Why BillCreatorSummaryAudio stores an upload's signed id under the same audio_bucket_path field a pasted external link uses, and why its label reads from the shared AUDIO_FIELD_LABELS const.

## Why this is a rebuild, and why audio_bucket_path holds either an upload or a link

Rebuilt version of the older app/frontend/components/admin/creator/BillCreatorSummaryAudio.

An upload is stored as its signed file id under `audio_bucket_path`, the same field name the old form used; pasting a link to externally hosted audio still works too.

Playback reuses the existing BillSummaryAudio component instead of duplicating it.

## Why onUploaded writes the signed id straight into audio_bucket_path

The upload helper gives a signed id for the stored file instead of `fileUpload.bucket_file_path`; the server accepts either since `audio_bucket_path` is plain text on IApiBill.

## Why the label reads from AUDIO_FIELD_LABELS instead of being typed inline

Read from the shared const rather than typed here, so fieldDisplayName's copy of this label can't drift from a rename. See [[docs/explanation/bill-creator-field-display-labels.md|bill-creator-field-display-labels.md]].
