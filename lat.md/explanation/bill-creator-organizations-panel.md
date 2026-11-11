---
lat:
  mode: explanation
---

# BillCreatorOrganizations / BillCreatorOrganization mechanics

Why BillCreatorOrganizations and BillCreatorOrganization keep their own useForm() separate from the main bill form, thread billId/tabKey for the rename redirect, and how row keys and the session cache avoid losing mid-edit state.

## Why BillCreatorOrganizations keeps its own useForm() and posts separately

Keeps its own useForm() and SwayFormContext provider, posting to /organizations separately from the main bill form — same as the V1 version.

V2 swaps react-select for a shadcn-built combobox (text input, filtered options, "Create" row); what goes over the wire to the admin controller is unchanged.

## Why tabKey is threaded through to the rename PATCH

This panel appears on both the Creator and Summary tabs — POST /organizations needs to know which one submitted, to redirect back there.

Comes from page props (route sets `defaults: {tab_key: …}`) and rides along as a POST query param; the controller resolves the path via TAB_KEY_TO_PATH_HELPER. See [[docs/explanation/bill-creator-tab-url-routing.md|bill-creator-tab-url-routing.md]] for how that table is used elsewhere.

`BillCreatorOrganization`'s `billId`/`tabKey` props carry the same information down to the per-organization rename PATCH: which bill and which tab the rename came from, so `OrganizationsController#update` can redirect back to the tab the operator was on.

## Why rowKeys exist instead of keying on organization.value directly

`organization.value` is unique per row in practice — the combobox excludes already-picked options, and inline-created orgs get a fresh negative id each time.

But nothing guarantees uniqueness, and a repeated key would make React silently match two sub-forms to one element.

## Why sessionCacheRef is written at the remove event, not via an effect

Holds a removed organization's draft summary/position, so re-adding it restores the half-finished edit — written at the remove event, not via an effect copying every `selected` change into a ref.

An effect-based version wrote rendered data into the ref and, combined with reused negative ids, let a newly created org resurrect an old removed row via appendOrganization's `cached ?? option`.

## Why the row key dropped its -${index} suffix

`organization.value` is already a stable server id. The `-${index}` suffix that used to follow it changed the key whenever an earlier row was removed.

That rebuilt every sub-form below it, throwing away a rename someone was mid-edit on.

`index` still reaches the sub-form as a prop (it indexes into the form's array) — only the key stopped using it.

## Why BillCreatorOrganization posts the same dotted setData keys as the old form

Reads and writes through SwayFormContext using the same dotted setData keys the old form used, so the body posted to /organizations and /api/admin/organization_bill_positions is unchanged:

- `organizations.${index}.support` ("FOR" | "AGAINST")
- `organizations.${index}.summary` (string)
- `organizations.${index}.icon_signed_id` (the signed id of a direct upload)
- `organizations.${index}.icon_url` (preview URL)

## Why only already-saved organizations (numeric id) can be renamed

Only organizations already saved (numeric id) can be renamed here. One typed in to be created keeps a stand-in value and the combobox name until it's saved.

## Why onSaveRename also writes the label locally

PATCHes the real Organization record; the server redirects back to this tab. The row's label is set here too, since useForm's data doesn't refresh from the page props that redirect brings back.

## Why OrgIconUpload sends nothing to the server itself

A thin wrapper around DirectUploadDialog for the icon slot next to each organization in the Creator's Organizations section.

Works like the older BillCreatorOrganization/DirectUploadModal: shows an upload button, hands back { signedId, previewUrl } on success.

Caller puts those into the nested form fields organizations.${index}.icon_signed_id and organizations.${index}.icon_url.

Passing onRemove adds a button that empties the slot.

Nothing is sent to the server from this file — DirectUploadDialog does the upload POST, and the icon is persisted by the same save step as before, POST /organizations.

## Why onSaveRename's onSuccess checks pageExpired before writing the label

A stale-token refusal also lands here: it redirects to the page it was sent from, a successful visit. Writing the new name in would show a rename that never saved, and carry it into the next save.
