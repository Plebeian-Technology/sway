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

## Open decisions for the owner

Key architectural and product choices requiring owner confirmation, presented with recommended answers based on current system capabilities.

### Entry surfaces for postcard sending

Should postcard mailing initiate from the Bill of the Month screen, the legislator detail screen, or both?

Recommendation: Both. Bill of the Month delivers high civic engagement immediately after voting on priority legislation, while the legislator screen enables constituent advocacy across all historic votes.

### Message length limits

Should voter message length have a strict character limit on 4x6 postcard stock?

Recommendation: Yes. Capping voter messages at 300 characters guarantees readable typography alongside required postal routing barcodes and return address blocks.

### Postcard tracking visibility

Should voters see step-by-step postal delivery updates in their activity history?

Recommendation: Yes. PostGrid webhooks provide order events (created, printed, processed for delivery) that offer clear confirmation that their message reached the representative's office.
