---
mode: explanation
summary: "Why DirectUploadDialog must revoke its preview blob: object URLs on replacement and on dialog close/reset."
status: agent-extracted
related: []
---

# DirectUploadDialog object URL cleanup

Object URLs from createObjectURL must be revoked — once when replaced by a new upload, and again
on dialog close/reset — or the previewed blob leaks until page reload.

(`app/frontend/components/admin/creator/__tests__/DirectUploadDialog.test.tsx`)

## Why DirectUploadDialog wraps DirectUpload instead of being duplicated

Wraps Rails ActiveStorage's DirectUpload helper — uploads straight from
the browser to storage.

Behaves like the older FileUploadModal/DirectUploadModal (POSTs to
/rails/active_storage/direct_uploads, hands back {signedId, previewUrl})
but draws itself inside the newer Dialog.

Used by BillCreatorSummaryAudio and the organization icon uploader; any
later uploader should reuse this too.

## Why previewUrlRef mirrors previewUrl state

Mirrored in a ref so it can be released (next upload, reset) without
adding previewUrl to every callback's deps. A blob URL stays in memory
until revoked or the page reloads.

## Why the previous preview is released before the new one is created

Release the previous preview before making a new one, since one visit to
this dialog can upload several files.
