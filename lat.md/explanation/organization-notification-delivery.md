---
lat:
  mode: explanation
---

# Organization notification delivery

[[app/services/notify_organization_followers_service.rb#NotifyOrganizationFollowersService]] sends position updates to organization followers after a committed change.

## The callback hands fan-out to a job

[[app/models/organization_bill_position.rb#OrganizationBillPosition#notify_followers_on_change]] is the single trigger for follower notifications. It queues [[app/jobs/notify_organization_followers_job.rb#NotifyOrganizationFollowersJob]], which rebuilds the service from ids and change labels so Active Record objects do not cross the job boundary.

The callback requires an active position and a changed notifiable field. [[organization-position-removal#Removal deactivates, it does not delete]] explains why deactivation must not notify followers.

## Fan-out batches users and checks the master preference

The service batches eligible users and their preference reads before choosing immediate or digest delivery.

It sends immediate notifications for `every_change` followers and queues daily or weekly followers through [[app/services/digest_org_notification_aggregator.rb#DigestOrgNotificationAggregator#enqueue]]. It calls the aggregator directly, so a missing class raises instead of silently dropping digests. The preference is checked before fan-out so disabled users receive no channel delivery.

## Immediate delivery uses a durable marker

[[app/models/organization_notification_delivery.rb#OrganizationNotificationDelivery]] stores one marker for each position, user, change type, and delivery token. The unique index suppresses retries of the same event while allowing a later position change with a new token to send.

The token comes from the committed position timestamp and is passed through the job unchanged. A missing token remains supported for older queued jobs, which derive it from the current position.

### Bulk upserts use the position callback token

The bulk position endpoint relies on each changed position's commit callback to enqueue one notification job with that change's delivery token.

[[app/controllers/organization_bill_positions_controller.rb#OrganizationBillPositionsController#create]] upserts rows through the model, so the same [[app/models/organization_bill_position.rb#OrganizationBillPosition#notify_followers_on_change]] callback used by individual changes owns delivery. The job receives the committed position timestamp unchanged, allowing the durable marker to suppress a replay without a second explicit fan-out from the controller.

## A failed send removes its marker

The service writes the marker before it queues channel deliveries.

The marker uses the primary database while delivery jobs use Solid Queue's separate database, so one transaction cannot cover both. If fan-out raises, the service deletes its marker so a retry can attempt delivery again.

Daily and weekly entries use the durable queue described in [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]].

## Web push deep-link payload shape

[[app/services/sway_push_notification_service.rb#SwayPushNotificationService]] includes a nested URL payload only when a caller supplies a target path, omitting the key entirely otherwise.

Compacting the top-level payload hash before JSON serialization allows web-push notifications to deep-link to a specific page while preserving the exact historical payload structure for callers that do not pass a URL.

## Notification wording names Sway as the recorder

Every organization notification is titled "Organization update", and every body says what Sway recorded rather than what the organization did.

Most organizations shown on Sway never joined it, so copy such as "{Org} published a new position" would claim the organization acted on Sway. "Sway recorded {Org}'s position on {bill}" stays true whether the position came from testimony, a news article, a Sway admin or the organization's own members, so one wording serves every position origin ([[news-org-position-persistence#Position origin and affiliation]]).

A summary change reads "Sway recorded a change to {Org}'s position summary on {bill}." rather than "Sway updated its summary", because an approved member edit means the organization's members wrote the summary, not Sway. The mobile preference sheets use the same phrase.

The organization's name moved out of the title and into the body, and a text message reads "Organization update: " followed by the body. The daily and weekly digests use the same title and say "Sway recorded new positions from {Org} {period}."
