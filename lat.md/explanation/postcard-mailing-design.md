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

## Open decisions for the owner

Key architectural and product choices requiring owner confirmation, presented with recommended answers based on current system capabilities.

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
