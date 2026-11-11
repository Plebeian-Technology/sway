# Bill Creator organization form

The Bill Creator organization panel keeps unsaved position edits separate from the bill form and carries its active tab through organization writes.

## A separate form submits organization edits

The panel owns independent form state for organization position edits and submits through the organization endpoint.

[[app/frontend/components/admin/creator/BillCreatorOrganizations.tsx#BillCreatorOrganizations]] submits the nested list to [[app/controllers/organizations_controller.rb#OrganizationsController#create]]. The panel is separate from the Details form because organization positions have their own save endpoint and validation response.

The panel passes the persisted bill id and active tab to each [[app/frontend/components/admin/creator/BillCreatorOrganization.tsx#BillCreatorOrganization]] row, and synchronizes its form `isDirty` state with the parent `setCreatorDirty` guard (clearing it on unmount) so bill or tab switches warn before discarding unsaved organization edits. The page prop remains `tab_key`; writes use the `bill_creator_tab` namespace, with legacy `tab_key` accepted only when the canonical key is absent. [[query-parameter-namespaces#Backward compatibility and dual-reading]] owns the precedence rule.

## New rows and stable row keys

Inline-created rows use temporary negative values, and rendered keys must remain stable when another row is removed.

Those values must not be reused after removal because a session cache keyed by value could restore a removed row in place of the newly created one. [[app/frontend/sway_utils/uniqueStableKeys.ts#uniqueStableKeys]] disambiguates rendered rows, while the React key omits the row index so deleting an earlier organization does not remount later subforms.

The selected form stores the current organization option before either remove control changes the selected list.

[[app/frontend/components/admin/creator/BillCreatorOrganizations.tsx#BillCreatorOrganizations]] routes both [[app/frontend/components/admin/creator/BillCreatorOrganization.tsx#BillCreatorOrganization]] and the selected chip through the same removal callback, clearing `position_id` on the cached option (and omitting `position_id` on unselected `availableOptions`) so re-adding an organization restores its unsaved support and summary edits without re-sending a server `DELETE` for an already-deactivated position if removed a second time. Saved positions still follow [[organization-position-removal#Taking an organization's position off a bill#The button only reaches the server for a position that exists]].

## The cache outlives the organization-set form

Each mounted bill view keeps removed drafts while the server refreshes the saved organization set.

[[app/frontend/components/admin/creator/context/BillCreatorOrganizationDraftCache.tsx#BillCreatorOrganizationDraftCache]] owns the in-memory option cache above the keyed form in both [[app/frontend/components/admin/creator/BillCreatorAccordions.tsx#BillCreatorAccordions]] and [[app/frontend/components/admin/creator/BillCreatorPositions.tsx#BillCreatorPositions]]. The inner [[app/frontend/components/admin/creator/BillCreatorOrganizations.tsx#BillCreatorOrganizations]] still remounts when [[app/frontend/components/admin/creator/organizations/organizationsFormKey.ts#organizationsFormKey]] changes, so refreshed saved rows reseed the form while removed drafts remain available for re-add. The owner is keyed by bill id, so drafts do not carry to another bill.

## Rename updates the saved organization and current form

Only a persisted organization can be renamed from the panel, and its successful response updates the form's displayed label.

The PATCH includes the bill id and active tab so the server can return to the right Creator surface; after a successful response without a flash alert the component updates the row label in its own form state. A stale page token or a server-rejected rename (`flash[:alert]`) leaves the label and rename input unchanged, as described by [[identity-and-access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]. The rename's locale-wide effect belongs to [[organization-position-removal#Taking an organization's position off a bill#Renaming an organization changes it everywhere in its locale]].

## Browser removal tests restore unsaved values

Real browser coverage verifies that both removal controls preserve current support and summary values across the server request and re-add.

The card and chip examples each edit both fields before removing the organization, wait for the server's removal notice, assert a single position DELETE, then re-add the same organization and check that both edits return. Their separate cases expose a row-removal path that bypasses the shared cache.

[[spec/system/admin_bill_creator_form_state_spec.rb]] exercises those controls with the actual parent panel and row form.

## The component tests keep the picker real

The component tests keep the organization picker and chips real while observing form updates across renders.

They stand in for Inertia's form hook with a `React.useState`-backed implementation. The stand-in does not replace the interaction that creates, removes, and re-adds rows.

The temporary-id test checks that a removal cannot free an id for the next inline-created organization, and the sibling-row test checks that removing one row preserves an in-progress rename in another. [[app/frontend/components/admin/creator/__tests__/BillCreatorOrganizations.test.tsx]] pins those transitions.

[[app/frontend/components/admin/creator/__tests__/BillCreatorOrganizationsRemovalIntegration.test.tsx]] keeps the parent, picker, and position subform mounted together. Its stateful form stand-in verifies the card and chip paths restore current unsaved values after a keyed server refresh and that the cache resets when the bill changes.
