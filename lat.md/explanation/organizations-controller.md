---
lat:
  mode: explanation
---
# Organizations controller

The admin JSON controller keeps organization identity and position writes within their locale and returns explicit response shapes for readers and editors.

## A missing organization returns a real 404

The `show` action answers missing ids with JSON `not_found` and HTTP 404 for its browser-facing and mobile callers.

Returning HTTP 200 with `{success: false}` would look successful to clients that inspect only status.

[[app/controllers/organizations_controller.rb#OrganizationsController#show]] handles `/organizations/:id` and `/api/organizations/:id`; the public HTML page is served by the separate `Public::OrganizationsController`.

## Create errors retain their row and field shape

The create response stores validation messages under the plural `organizations` key, with one hash per submitted row and one entry per failed field.

The Bill Creator reads that nested shape to display errors beside the corresponding input. `ActiveModel::Errors#objects` yields error objects, so the controller reads each object's `attribute` and `message` instead of destructuring it as a pair. [[app/controllers/organizations_controller.rb#OrganizationsController#create]] builds and fills the response shape.

## A failed batch rolls back every row write

Organization and position writes share one transaction; if any row fails, successful writes earlier in the batch roll back with the error response.

This keeps the stored batch aligned with the response that reports which rows failed. An icon uploaded during a batch that later rolls back can leave an unused file for storage cleanup. [[app/controllers/organizations_controller.rb#OrganizationsController#create]] applies that transaction boundary.

## Icon addresses keep their source meaning

An uploaded icon has no outside source address, and a Sway Active Storage URL must not be stored as an organization's source `icon_url`.

The provenance check matches the URL path rather than host so local development addresses are rejected too; blank values carry no source. Organization readers prefer an attached mirrored copy and otherwise use the retained source address, as described by [[sway-google-cloud-storage#A mirrored photo keeps its source address]]. [[app/controllers/organizations_controller.rb#OrganizationsController#our_own_asset_url?]] performs the source-address check.

## Rename changes the shared locale record

The update action permits only `name`, because an organization is shared across every bill in its locale; `bill_id` is used only to return to the originating Creator surface.

The locale-wide effect and its authorization rationale are owned by [[organization-position-removal#Renaming an organization changes it everywhere in its locale]]. The active-tab URL contract is owned by [[bill-creator-shell#Why tab URLs retain legacy compatibility]]. [[app/controllers/organizations_controller.rb#OrganizationsController#organization_update_params]] limits the writable fields.

## Organization lookup stays within the bill's locale

When [[app/controllers/organizations_controller.rb#OrganizationsController#create]] resolves a submitted row in [[app/controllers/organizations_controller.rb#OrganizationsController#find_or_initialize_organization_from_param]], it scopes ID lookups to `@bill.sway_locale_id` and matches inline-created names case-insensitively after collapsing whitespace.

Scoping ID lookups to `@bill.sway_locale_id` prevents cross-locale organization IDs from attaching a foreign organization to a bill, while normalizing whitespace and matching `LOWER(name)` keeps inline creation in the organizations panel consistent with [[app/services/link_campaign_organization_service.rb#LinkCampaignOrganizationService]] so creating the same organization on both surfaces never produces duplicate rows in the locale.
