---
lat:
  mode: explanation
---

# DirectUploadDialog object URL cleanup

Object URLs from createObjectURL are revoked when superseded by another upload in the same dialog session, while ownership of the final preview URL transfers to onUploaded on dialog close.

(`app/frontend/components/admin/creator/__tests__/DirectUploadDialog.test.tsx`)

## Why DirectUploadDialog wraps DirectUpload instead of being duplicated

Wraps Rails ActiveStorage's DirectUpload helper — uploads straight from the browser to storage.

Behaves like the older FileUploadModal/DirectUploadModal (POSTs to /rails/active_storage/direct_uploads, hands back {signedId, previewUrl}) but draws itself inside the newer Dialog.

Used by BillCreatorSummaryAudio and the organization icon uploader; any later uploader should reuse this too.

## Why previewUrlRef mirrors previewUrl state

Mirrored in a ref so a superseded upload in the same dialog session can be revoked without adding previewUrl to callback deps, while reset() clears the ref on close so the parent keeps the final preview.

## Why the previous preview is released before the new one is created

A second upload during the same dialog visit revokes the previous blob URL before creating a replacement, while callers that do not render previewUrl revoke it in onUploaded.
