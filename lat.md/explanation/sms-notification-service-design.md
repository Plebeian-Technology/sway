---
lat:
  mode: explanation
---

# SMS notification service design

Outbound notification services identify verified recipients through active legislator assignments and ensure carrier-mandated opt-out instructions accompany SMS deliveries.

## Why recipient selection resolves through active legislator links

[[app/services/sms_notification_service.rb#SmsNotificationService#send_bill_of_the_month_notification]] queries active [[app/models/user_legislator.rb#UserLegislator]] links rather than the user districts table to identify recipients.

Registration via [[app/services/sway_registration_service.rb#SwayRegistrationService]] assigns users to their representatives by creating [[app/models/user_legislator.rb#UserLegislator]] records. The legacy `user_districts` table is only populated in development seed environments and contains no production member assignments; querying `user_districts` in production matches zero recipients.

The locale query reads `sway_locale_id` directly from [[app/models/legislator.rb#Legislator]] rather than traversing district terms. Filtering through districts requires each legislator to maintain an active district term, inadvertently dropping constituents whose representatives are between recorded terms.

## Why the opt-out suffix is appended once in SmsDeliveryJob

Carrier compliance rules under A2P 10DLC require every outbound SMS message to include opt-out instructions, which [[app/jobs/sms_delivery_job.rb#SmsDeliveryJob]] appends once centrally.

Multiple services enqueue outbound text messages: [[app/services/sms_notification_service.rb#SmsNotificationService#send_bill_of_the_month_notification]], [[app/services/sms_notification_service.rb#SmsNotificationService#send_voting_reminder]], [[app/services/notify_organization_followers_service.rb#NotifyOrganizationFollowersService#dispatch_immediate]], and [[app/services/digest_org_notification_aggregator.rb#DigestOrgNotificationAggregator#dispatch_period]]. Appending the compliance suffix inside [[app/jobs/sms_delivery_job.rb#SmsDeliveryJob#perform]] guarantees that every outbound message carries mandatory opt-out instructions regardless of caller implementation.

The job helper no-ops when the message body already ends with the suffix, preventing duplicated notices when a caller or retry includes the disclaimer.

## Where the displayed Sway number comes from

The notifications page shows the number Sway texts from, formatted by [[app/services/sway/twilio_client.rb#TwilioClient#display_from_phone]] from `TWILIO_FROM_PHONE`. With no usable number the page leaves the number and the contact download out.

The number people see and the number messages arrive from are one fact, so they are read from one place. A separate setting with its own default used to hold the displayed number, which put a real installation's phone number in the code and could drift from the one Twilio actually sends from.

`TWILIO_FROM_PHONE` is a production credential that comes from the vault, so outside production the page usually shows no number. A value that is not a ten-digit North American number shows nothing rather than a half-formatted string, because a contact card saved with a wrong number would send replies nowhere.
