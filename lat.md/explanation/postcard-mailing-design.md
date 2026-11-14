---
lat:
  mode: explanation
---
# Postcard mailing design

Architecture and operational design for allowing voters to mail physical First-Class postcards to their elected representatives directly through Sway.

## Voter flow

Voters compose and mail physical postcards to their representatives through web and mobile interfaces linked to their voting history.

### Starting points

Voters initiate postcard delivery from two primary surfaces across web and mobile platforms.

On the legislator profile page (`app/frontend/pages/Legislator.tsx` on web and `mobile/src/screens/LegislatorDetailScreen.tsx` on mobile), voters find a "Mail Postcard" action alongside the existing email and phone links. This entry point connects constituent messages directly to a specific elected official, prompting the voter to select a bill they recently voted on.

On the Bill of the Month page (`app/frontend/pages/BillOfTheMonth.tsx` on web and `mobile/src/screens/BillOfTheMonthScreen.tsx` on mobile), the post-vote confirmation view presents a postcard option immediately after the voter casts their vote. This entry point anchors the postcard directly to the featured bill and automatically addresses the card to the voter's district representative.

### Composition and message layout

Voters review a digital preview of the printed postcard before confirming delivery.

The front side of the 4x6 postcard features a standardized civic template displaying the bill number, formal title, and the voter's stance (For, Against, or Abstain). The reverse side allocates space for the recipient's mailing address, postal barcode clearance, return address, and a constituent message box capped at 300 characters. Restricting custom text to 300 characters ensures legible font sizes and reliable printing on standard postcard stock.

### Delivery confirmation and tracking

Upon submission, the application queues the mailing and updates the user interface with dispatch status.

The web and mobile applications display a confirmation dialog showing the estimated arrival window. The record persists in the voter's activity feed with an initial status of queued. As the print vendor processes the order, background webhooks update the card state to printed and mailed.

### Comparison with email outreach

Postcard delivery shares structural similarities with the email flow while introducing tangible physical delivery.

The email path in `app/frontend/components/bill/EmailLegislatorsModal.tsx` and `app/controllers/user_legislator_emails_controller.rb` generates an immediate electronic message delivered via outbound SMTP. Email outreach requires only the representative's official inbox address. Postcards require validated physical mailing addresses, incur physical printing and postage costs, and require several business days for postal transport.

## Legislator mailing address sources

Postal delivery requires physical office addresses for elected representatives across all supported locales.

The `legislators` table in `db/schema.rb` lines 757 to 775 stores `email`, `phone`, `fax`, `link`, and `photo_url`, but lacks physical address columns. A previous migration (`db/migrate/20250126181143_remove_address_from_legislator.rb`) removed the historical `address_id` foreign key. While `app/services/legislators_cache/base_refresh.rb` line 194 references postal code aliases (`postal_code`, `postalCode`, `zip`, `zip_code`, `zipCode`), the application discards these fields during roster refreshes without writing them to disk. Furthermore, `lat.md/reference/legislator-seed-photo-address-rules.md` governs HTTP URLs for portrait images rather than physical postal destinations.

### Baltimore City address availability

Baltimore City municipal seeds provide complete physical street addresses for all city council members and the mayor.

In `db/seeds/data/united_states/maryland/baltimore/legislators.json`, each entry includes `street`, `street2`, `city`, `regionCode`, and `zip` (for example, "100 Holliday Street, Room 250, Baltimore, MD 21202"). These curated records offer immediate postal delivery targets without requiring third-party data enrichment.

### State of Maryland address availability

State legislative rosters currently lack physical street addresses in the seed payload and upstream sync services.

The Maryland roster in `db/seeds/data/united_states/maryland/maryland/legislators.json` originates from OpenStates. The parser in `app/services/legislation/adapters/generic_roster_adapter.rb` lines 381 to 421 extracts names, party affiliation, district, and photos, but receives no postal address attributes from the OpenStates payload. Sourcing postal delivery addresses for Maryland General Assembly delegates and senators requires augmenting the roster sync pipeline with the official Annapolis legislative office directory (typically House and Senate office buildings on Bladen Street in Annapolis, MD 21401).

### US Congress address availability

Federal congressional seeds provide member metadata and phone numbers, but exclude postal office locations.

In `db/seeds/data/united_states/congress/congress/legislators.json`, records parsed by `app/services/legislation/adapters/generic_roster_adapter.rb` lines 278 to 330 contain Bioguide IDs, party, and state, but omit Washington, D.C. office addresses. Sourcing congressional postal addresses requires ingesting Capitol Hill office directories (Cannon, Longworth, and Rayburn buildings for House members; Russell, Dirksen, and Hart buildings for Senators) from the official Clerk directories or the public `@unitedstates/congress-legislators` dataset.

### Storage requirements

Supporting physical mailings requires extending the database schema to store postal address attributes.

Adding columns directly to the `legislators` table (`street_address`, `street_address2`, `city`, `state_code`, and `postal_code`) mirrors the existing storage pattern used for `phone` and `email`. This approach avoids join overhead when loading representative profiles for postcard preview cards.

## Vendor recommendation

PostGrid serves as the primary print-and-mail vendor for physical postcard fulfillment across all jurisdictions.

### Why PostGrid fits Sway

PostGrid matches Sway's on-demand delivery architecture without requiring upfront capital or monthly subscriptions.

As documented in [[postcard-vendor-comparison]], PostGrid provides a pay-as-you-go model with no monthly base fees. Postcards mail at a single-unit cost of $0.902 for 4x6 First-Class delivery. The REST API (`POST /print-mail/v1/postcards`) supports dispatching individual postcards as voters complete their actions, avoiding batch queuing delays.

Address verification represents another decisive factor. Because state and congressional legislative addresses originate from diverse public sources, automated postal standardization protects against delivery failures. PostGrid includes CASS-certified US address verification within its base API without the per-lookup overage fees charged by competing platforms. Furthermore, the application repository already configures `POSTGRID_TEST_API_KEY` and `POSTGRID_LIVE_API_KEY`, accelerating implementation and testing.

### Conditions for switching vendors

Sway would evaluate alternative print providers if monthly sending volume expands significantly or API reliability falters.

If constituent postcard volume exceeds 1,500 pieces per month, Lob's Growth subscription ($260 monthly fee with $0.645 per postcard) yields lower total unit costs despite the monthly platform commitment. Similarly, if PostGrid encounters API availability problems, Click2Mail provides an unmetered on-demand fallback using standard REST endpoints.

## Funding and payment models

Delivering physical mail incurs tangible marginal costs requiring a clear payment mechanism.

At PostGrid's unit price of $0.902 per 4x6 card (detailed in [[postcard-vendor-comparison]]), each delivered postcard consumes real capital. Three distinct funding models present practical trade-offs between user friction, operational complexity, and budgetary predictability.

### Option 1: Platform-funded civic allocation

Sway absorbs the cost of postcard printing and postage as core civic infrastructure.

Under this model, the platform funds postcards directly from its operating budget, subject to per-user rate limits. Voters encounter zero checkout friction, maximizing civic participation and representative outreach on priority legislation such as the Bill of the Month. The primary trade-off involves financial exposure: an unexpected surge in voter engagement directly increases monthly vendor invoices.

### Option 2: Voter-funded micropayments

Voters pay for their own postcards directly through a credit card or mobile wallet payment flow.

This approach requires integrating a payment gateway such as Stripe (`app/controllers/` currently contains no payment handling). Charging voters $1.25 to $1.50 per card covers PostGrid's $0.902 unit cost plus credit card interchange fees (2.9% + $0.30). While this model eliminates platform financial liability, checkout friction significantly reduces the proportion of voters who complete the mailing action.

### Option 3: Organization-sponsored campaigns

Community organizations sponsor postcard budgets for specific legislation aligned with their civic mission.

Organizations already exist as first-class domain models in Sway (`app/models/organization.rb`). Under this approach, an advocacy group allocates a prepaid credit balance (for example, $500 for approximately 550 postcards) to an active bill. Voters in designated districts can then dispatch sponsored postcards at zero personal cost until the organization's campaign budget depletes.

### Payment recommendation

A hybrid model starting with platform-funded priority postcards offers the highest civic impact.

For the initial implementation, Sway funds postcards directly for the featured Bill of the Month, bounded by strict rate limits of one card per voter per representative. This design delivers immediate constituent utility without the development overhead of integrating Stripe. Once constituent demand is verified, Sway can introduce organization-sponsored campaign budgets to support broader bill catalogs.

## Sending limits and abuse prevention

Strict rate limits protect legislative offices from spam and insulate the platform against unbounded mailing expenditures.

Because postcards incur immediate marginal costs ($0.902 per piece under the recommended funding model), volume controls are more critical for physical mail than electronic messaging. Sway adapts proven constraints from its existing email outreach infrastructure to govern postcard dispatch.

### Comparison with existing email constraints

The email pipeline establishes baseline consent, rate-limiting, and constituent identity verification patterns.

In `app/controllers/user_legislator_emails_controller.rb`, sending requires authenticated users with verified names (`current_user.full_name`) and verified email addresses (`current_user.email_sendable?`). A controller-level sliding window enforces a limit of 10 submissions per hour per user. At the database layer, `app/models/user_legislator_email.rb` enforces a unique index on `[user_legislator_id, bill_id]`, guaranteeing that a voter contacts a specific representative exactly once per bill. The voter provides explicit consent through `app/frontend/components/bill/EmailLegislatorsModal.tsx` before delivery.

### Recommended postcard sending limits

Postcard delivery requires layered per-bill, per-hour, and platform-wide budget ceilings.

First, the system enforces a strict one-card limit per voter per representative per bill. Mirroring `user_legislator_emails`, a unique database constraint on `[user_legislator_id, bill_id]` within the proposed `user_legislator_postcards` table prevents duplicate physical mailings.

Second, a controller-level rate limit restricts postcard dispatches to 10 per hour per user, preventing automated script execution.

Third, platform-funded postcards require constituent address verification: only voters with geocoded residential addresses confirmed within the representative's electoral district can mail cards.

Fourth, a monthly platform safety cap (for example, $500 or approximately 554 postcards) pauses platform-funded mailings when reached, alerting administrators and prompting voters to use email instead.

## Return address and constituent verification

The return address on a postcard establishes constituent credibility and provides a reply path for legislative offices.

Legislative staff prioritize communications from documented district constituents while filtering out nationwide advocacy campaigns. In physical mail, the return address serves as the primary proof of local residence.

### Comparison with email reply routing

The physical mail return address combines delivery routing and sender identity into a single printed block.

In the email pipeline (`app/mailers/user_legislator_email_mailer.rb`), outbound messages set `from` to `"outreach@sway.vote"`, carbon-copy the voter (`cc: user.email`), and set `reply_to` to `@user_legislator_email.user.email`. Because sway.vote email addresses are catch-alls, the platform handles sender authentication while routing replies directly to the constituent. In physical mail, no secondary reply routing exists: the single printed return address dictates where USPS delivers return-to-sender cards and where legislative staff mail formal written replies.

### Return address options

Three return address strategies balance constituent authenticity against personal privacy.

Under the first option, the postcard prints the voter's full name and residential street address (`user.address`). Legislative staff verify the voter against voter registration files, giving the card maximal advocacy weight. The voter also receives physical response letters directly in their home mailbox. The trade-off is postal visibility: postal workers and household members can view the address printed openly on the card.

Under the second option, the card prints a centralized Sway mailing address (such as a Baltimore post office box). This option conceals the voter's street address, but legislative staff often discard mail without a local constituent address as out-of-district lobbying. Furthermore, legislative replies would accumulate at Sway rather than reaching the constituent.

Under the third option, the card omits a return address entirely. Omitting the return address risks USPS delivery rejections for automated First-Class processing and guarantees that legislative caseworkers disregard the message.

### Return address recommendation

Printing the constituent's residential address with explicit user consent offers the strongest legislative impact.

The application presents the voter's street address in the pre-send preview modal, asking for explicit confirmation before queueing the print job. For voters who decline to print a full street address, the system provides a fallback format displaying their name, city, and ZIP code alongside Sway's return address. This compromise preserves partial constituent recognition while honoring personal privacy preferences.

## Privacy impact and external data flows

Mailing a physical postcard transmits constituent personal data outside Sway's self-hosted infrastructure to an external print vendor.

Unlike digital votes, which Sway aggregates anonymously, physical postal delivery requires transmitting constituent identity attributes to PostGrid for USPS printing and delivery.

### Personal data transmitted to the print vendor

Postcard dispatch requires transmitting five personal data fields across the vendor API boundary.

When a voter confirms postcard delivery, the application transmits the following payload to PostGrid's `POST /print-mail/v1/postcards` endpoint:

- **Voter full name**: `current_user.full_name`, printed in the return address block.
- **Voter residential address**: `current_user.address` (street, unit, city, state, postal code), printed as the return address for constituent verification.
- **Recipient legislator name and office address**: Extracted from the target representative's profile.
- **Voter stance and bill details**: The official bill number, title, and the voter's recorded vote stance.
- **Constituent custom message**: Custom personal message text up to 300 characters composed by the voter.

### Vendor retention and data handling

PostGrid stores rendered postcard assets temporarily before automated deletion.

As detailed in [[postcard-vendor-comparison]], PostGrid's data processing policy purges rendered PDF artwork, recipient address labels, and message text after 30 days. Order metadata, including delivery status timestamps and carrier tracking identifiers, persists in PostGrid transaction logs. PostGrid does not sell constituent data or repurpose mailing lists for third-party marketing.

### Privacy policy modifications

Introducing physical postcard mailing requires updating the public privacy policy at `about.sway.vote/html/privacy.html`.

Two specific sections on the public privacy page require updated wording before enabling live postcard delivery:

In "Which other services does Sway use?", the current text reads:

> "A few services help run Sway. Twilio sends the text message that verifies your phone number. Firebase delivers push notifications. Sentry receives error reports so we can fix bugs, and we configure it to leave out personal data. Google Cloud Storage holds our backups."

The proposed revision names PostGrid explicitly:

> "A few services help run Sway. Twilio sends the text message that verifies your phone number. Firebase delivers push notifications. Sentry receives error reports so we can fix bugs, and we configure it to leave out personal data. Google Cloud Storage holds our backups. PostGrid prints and mails physical postcards when you choose to send one to your representatives, retaining print assets for 30 days to complete delivery."

In "When does Sway share information?", the current text reads:

> "We show vote totals in the app that cannot be linked to you. We disclose information when the law requires it, such as in response to a valid court order."

The proposed revision clarifies constituent-initiated disclosure:

> "We show vote totals in the app that cannot be linked to you. When you choose to mail a physical postcard to an elected representative, we transmit your name, mailing address, and message to our print vendor and the representative's office. We disclose information when the law requires it, such as in response to a valid court order."

## Open decisions for the owner

Key architectural and product choices requiring owner confirmation, presented with recommended answers based on current system capabilities.

### Privacy policy disclosure timing

When should the public privacy policy be updated to name PostGrid?

Recommendation: Update `about.sway.vote/html/privacy.html` and the in-app `app/frontend/pages/public/Privacy.tsx` simultaneously with the deployment of the postcard feature flag, before opening physical delivery to voters.

### Return address format

What return address should be printed on constituent postcards?

Recommendation: Print the constituent's full name and verified residential street address by default with explicit UI confirmation, offering a city-and-ZIP privacy fallback for voters who prefer not to display their street address.

### Postcard rate limits and idempotency

What rate limits should govern constituent postcard mailings?

Recommendation: Enforce one card per voter per representative per bill using a database uniqueness constraint on `[user_legislator_id, bill_id]`, coupled with a 10 cards per hour per user burst limit.

### Platform budget safety cap

Should platform-funded postcards have a monthly spend ceiling?

Recommendation: Yes. Implement an automated monthly spending cap of $500 for platform-funded postcards, after which the interface falls back to email outreach until the next billing cycle.

### Postcard funding model

Who pays for physical postcard printing and postage?

Recommendation: Platform-funded for the initial rollout. Sway covers the $0.902 unit cost for Bill of the Month postcards under strict per-voter rate limits, deferring payment gateway integration until user demand warrants it.

### Organization sponsorship integration

Should organizations be permitted to sponsor postcard campaigns for specific bills?

Recommendation: Yes, as a phase two enhancement. Organizations defined in `app/models/organization.rb` can purchase campaign postcard balances, allowing district constituents to send sponsored cards without personal expense.

### Primary print-and-mail vendor (Decided)

Which vendor handles physical postcard printing and USPS delivery?

Status: Decided. PostGrid is the chosen vendor. The owner holds an existing account, and environment secrets (`POSTGRID_TEST_API_KEY` and `POSTGRID_LIVE_API_KEY`) are already provisioned.

### Entry surfaces for postcard sending

Should postcard mailing initiate from the Bill of the Month screen, the legislator detail screen, or both?

Recommendation: Both. Bill of the Month delivers high civic engagement immediately after voting on priority legislation, while the legislator screen enables constituent advocacy across all historic votes.

### Message length limits

Should voter message length have a strict character limit on 4x6 postcard stock?

Recommendation: Yes. Capping voter messages at 300 characters guarantees readable typography alongside required postal routing barcodes and return address blocks.

### Postcard tracking visibility

Should voters see step-by-step postal delivery updates in their activity history?

Recommendation: Yes. PostGrid webhooks provide order events (created, printed, processed for delivery) that offer clear confirmation that their message reached the representative's office.

### Legislator address storage structure

Should representative postal addresses live directly on the legislators table or in a separate table?

Recommendation: Place nullable address columns directly on the `legislators` table (`street_address`, `street_address2`, `city`, `state_code`, `postal_code`), mirroring `email` and `phone`.

### Sourcing missing state and federal addresses

How should missing postal addresses for Maryland state legislators and US Congress members be populated?

Recommendation: Ingest official Annapolis office addresses from the Maryland General Assembly directory, and ingest Washington, D.C. office building suites for Congress members using the public `@unitedstates/congress-legislators` dataset.

### Handling legislators without verified mailing addresses

How should the application handle representatives whose postal addresses remain unverified?

Recommendation: Disable the postcard option and display a clear explanation indicating that postal verification is in progress, while keeping phone and email actions enabled.
