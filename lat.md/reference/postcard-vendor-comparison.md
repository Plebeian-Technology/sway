---
lat:
  mode: reference
---
# Postcard vendor comparison

Print-and-mail API vendors compared across price, single-piece dispatch, address cleansing, and privacy policies for constituent postcards.

## Vendor comparison overview

Vendors evaluated on 2026-11-13 for on-demand 4x6 physical postcard mailings via First-Class postage without monthly minimum commitments.

| Vendor | 4x6 First-Class cost | Single-piece API | CASS verification | Data retention | Public pricing source |
| --- | --- | --- | --- | --- | --- |
| PostGrid | $0.902 / piece | Yes (`POST /print-mail/v1/postcards`) | Built-in CASS | 30-day asset purge | [postgrid.com/pricing](https://www.postgrid.com/pricing) |
| Lob | $0.905 / piece ($0.645 at $260/mo) | Yes (`POST /v1/postcards`) | Built-in CASS | 90-day asset purge | [lob.com/pricing](https://www.lob.com/pricing) |
| Click2Mail | $0.90 / piece ($0.55 print + $0.35 mail) | Yes (`POST /molpro/postcards`) | Built-in CASS | 30-day order purge | [click2mail.com/pricing](https://click2mail.com/pricing) |

## PostGrid

PostGrid provides on-demand physical postcard printing and delivery through an authenticated JSON REST API.

- **Unit cost**: $0.902 per 4x6 First-Class postcard on the pay-as-you-go Starter tier with no monthly platform fee or minimum volume commitment; checked 2026-11-13 at [postgrid.com/pricing](https://www.postgrid.com/pricing).
- **Single-piece API**: `POST /print-mail/v1/postcards` creates and queues an individual postcard order using HTML templates or raw PDF artwork; test-mode verification confirmed via `POSTGRID_TEST_API_KEY` returning HTTP 200 on 2026-11-14.
- **Environment keys**: Separate test and live API keys (`POSTGRID_TEST_API_KEY` and `POSTGRID_LIVE_API_KEY`); test-mode calls simulate PDF rendering and address validation without billing or printing.
- **Address verification**: Built-in CASS-certified US address validation verifies recipient and sender street addresses against USPS databases before print submission.
- **Data handling**: PostGrid stores recipient addresses, sender addresses, and rendered artwork for fulfillment; rendered print assets purge after 30 days; order metadata remains in account logs; checked 2026-11-13 at [postgrid.com/privacy-policy](https://postgrid.com/privacy-policy).

## Lob

Lob provides print and mail APIs targeting high-volume transactional and marketing mailings.

- **Unit cost**: $0.905 per 4x6 First-Class postcard on the Developer tier with no monthly fee, dropping to $0.645 per postcard with a $260 monthly Growth subscription; checked 2026-11-13 at [lob.com/pricing](https://www.lob.com/pricing).
- **Single-piece API**: `POST /v1/postcards` queues single postcards; checked 2026-11-13 at [lob.com/docs](https://www.lob.com/docs).
- **Address verification**: Built-in CASS address verification included with monthly quota limits, charging $0.01 per lookup above quota limits.
- **Data handling**: Rendered mail assets and address records retain for 90 days by default; constituent records not used for secondary advertising; checked 2026-11-13 at [lob.com/legal/privacy-policy](https://lob.com/legal/privacy-policy).

## Click2Mail

Click2Mail provides cloud-based document printing and postal dispatch through REST and XML interfaces.

- **Unit cost**: Base print cost of $0.55 per 4.25x6 card plus First-Class postcard postage of $0.35, totalling approximately $0.90 per card without monthly subscriptions; checked 2026-11-13 at [click2mail.com/pricing](https://click2mail.com/pricing).
- **Single-piece API**: `POST /molpro/postcards` accepts XML or JSON single-piece postal jobs; checked 2026-11-13 at [click2mail.com/developers](https://click2mail.com/developers).
- **Address verification**: Standard CASS and NCOA address cleansing runs during job submission.
- **Data handling**: Job documents and recipient lists purge from server storage 30 days after dispatch; checked 2026-11-13 at [click2mail.com/privacy-policy](https://click2mail.com/privacy-policy).
