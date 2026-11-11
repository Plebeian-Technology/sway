---
lat:
  mode: explanation
---
# Organization follows controller

Signed-in readers can follow organizations and change only their own follow rows.

[[app/controllers/organization_follows_controller.rb#OrganizationFollowsController]] serves both browser redirects and mobile JSON through the shared format negotiation. Creation runs through the current user's association, seeds notification settings from that user's defaults, and applies picker choices in the same request. The unique user-and-organization key makes repeat creates idempotent; the race after `find_or_create_by!` is recovered by returning the row another request inserted. Destruction and preference updates look up rows under the signed-in user, so another reader's id is not a write capability.

## Browser follows return to their local origin page

The browser returns to the page that initiated a follow so the list or detail page can finish the settings flow.

[[app/controllers/organization_follows_controller.rb#OrganizationFollowsController#back_or_organization_path]] accepts only a local referer and falls back to the organization detail page, which is also the mobile destination when a bearer request has no referer. Request coverage lives in [[spec/requests/organization_follows_spec.rb]]; browser coverage observes the redirected page and persisted follow state in [[spec/system/organization_follows_spec.rb]].

## The follow preference payload matches the saved controls

The public follow payload carries the saved notification switches and cadence used by each organization card.

The web type's event flags and `notification_cadence` mirror the columns returned for a reader's own follow. [[org-notification-cascade-and-defaults#Org-notification cascade and defaults#Where organization notification copy is shared across pickers and settings]] owns the shared option labels and cadence values; the public endpoint omits these fields for signed-out readers.

## Browser examples wait for the server response

Browser examples wait for a visible response from the page before reading server state, so the database assertion cannot race the request.

The skipped-picker test uses distinct account and follow-column defaults to prove the copy, as described in [[org-notification-cascade-and-defaults#Org-notification cascade and defaults#Why the skipped-picker test separates user defaults from column defaults]].
