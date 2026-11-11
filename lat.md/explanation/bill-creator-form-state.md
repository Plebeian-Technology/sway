---
lat:
  mode: explanation
---
# Bill Creator detail form state

The Creator tab's Details form keeps editable bill fields in one Inertia form, reconciles the published summary without erasing local edits, and stores recoverable drafts.

## The details form owns its Inertia state

[[app/frontend/components/admin/creator/BillCreatorBillForm.tsx#BillCreatorBillForm]] owns one form instance and provides it to the Details fields through [[app/frontend/components/admin/creator/context/SwayFormContext.ts|SwayFormContext]]. Those fields read and write the same Inertia form data.

## The summary field reads current form data

The summary editor and preview follow the summary held by the Details form, including programmatic updates.

[[app/frontend/components/admin/creator/fields/SummaryField.tsx#SummaryField]] reads the current summary from the form context and writes edits through its field setter. It keeps no mirrored summary value. [[app/frontend/components/admin/creator/hooks/useBillFormSubmit.ts#useBillFormSubmit]] takes summary from current Inertia form data, while the other request fields retain submitted DOM/`FormData` serialization. Programmatic summary updates therefore remain part of a save even when a disabled textarea is absent from browser `FormData`.

### A browser save carries a programmatic summary update

The system example updates the mounted Details form through its Inertia context without a textarea change, then verifies the server response and persisted bill summary. [[spec/system/admin_bill_creator_form_state_spec.rb]] exercises the mounted form rather than changing only the DOM value.

## Published summary and draft provenance are separate

Page props identify the published text; restored draft data does not establish its own provenance.

[[app/frontend/components/admin/creator/hooks/useNewBillInitialValues.ts#useNewBillInitialValues]] can initialize the form from a restored draft, so that initial text cannot establish which public summary the draft was written against. [[app/frontend/components/admin/creator/BillCreatorBillForm.tsx#BillCreatorBillForm]] reads the published value from page props and tracks it separately. If an operator's draft survives a newer published value, its provenance remains the older value; when the form is untouched or already matches the newly published text, the provenance advances with the server.

## A refreshed summary replaces only untouched text

The server replaces the summary only while the form still holds the prior published text.

The form compares its current summary with the previous published summary before accepting a newer server value. A match means the form has no local edit to protect; a mismatch preserves the operator's draft while the saved baseline moves forward. This reconciliation runs during render so the field does not briefly show the stale value while an effect catches up.

## Autosaved drafts read current form data

The storage callback reads the current form data when a field stores the draft. The summary text and its provenance stamp therefore describe the same form state, including when another field triggers the save after a summary refresh.

## The dirty flag starts clean for a new bill form

Each new bill form starts with a clean navigation-warning flag.

The shell keys the form by bill id, which gives each bill a separate form instance. Clearing the parent's dirty flag at mount prevents the prior bill's unsaved state from warning about the newly mounted form; a successful save clears the flag and the temporary draft together.

## Dropdown drafts are stored after selection

The form stores a dropdown value after selection, not when its trigger blurs.

The select trigger blurs when its Radix listbox opens, before a new option has been chosen. The form stores a dropdown field from its selection callback rather than from blur, so it saves the selected value instead of the value the operator was about to replace.

## Browser saves exercise the controlled form and server response

The browser examples use real form controls and wait for the controller's response before checking saved bills.

The system spec replaces controlled text with real keystrokes after selecting the input contents, so React's change handler receives the edit. The date input is set through [[spec/support/narrow_viewport_helpers.rb#NarrowViewportHelpers#paste_into]] and checked for its ISO day and native validity; this avoids depending on segmented date typing for the tested browser. The edit example submits through native `requestSubmit`; the new-bill example chooses the sponsor, chamber, and status through the rendered controls. The incomplete-form example waits for the client validation toast before checking that no bill was created. Successful examples wait for the server's flash before reloading the saved record; [[capybara-wait-semantics#Waiting on the side effect instead]] explains why the progress-bar helper alone cannot gate a database read. [[spec/system/admin_bill_creator_spec.rb]] covers these browser paths alongside the Details form's [[app/frontend/components/admin/creator/BillCreatorBillForm.tsx#BillCreatorBillForm]] and [[app/frontend/components/admin/creator/hooks/useBillFormSubmit.ts#useBillFormSubmit]].
