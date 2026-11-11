---
lat:
  mode: explanation
---

# Unlinked bill presentation

A bill with no verified official source URL displays an unavailable notice rather than a button that opens a generic portal or search engine. The database holds null rather than a placeholder string.

## Sourced addresses must point to specific legislation

External source links exist to let readers verify legislation directly against primary government records. A link that drops a reader onto a search form or homepage fails that purpose.

When Sway ingests legislation from city or state bodies, each bill record ideally links to the canonical detail page hosted by the government's legislative management system. For Baltimore City legislation on Legistar, individual matters are identified by a [[legistar-detail-url-resolution#The disconnect between API identifiers and public URLs|public record ID and GUID]] rather than the matter number alone.

Prior to resolving direct matter links, earlier pipeline steps occasionally populated the bill's link column with the generic Legistar search address (`https://baltimore.legistar.com/LegislationSearch.aspx`). Because that URL does not open the specific bill, readers were forced to re-enter search queries manually. Sway treats such generic landing pages as absent source links rather than authentic references.

## The absent shape eliminates sentinel leakage

Storing null for unlinked bills avoids sentinel values that leak into serialized API payloads or collide with database uniqueness constraints.

Previous proposals considered placeholder strings such as empty strings, sentinel URLs, or synthetic tokens. Those tokens require every downstream client, serializer, and report generator to implement token-aware parsing, risking presentation of synthetic values to end users.

In contrast, database-level null represents genuine absence. The `Bill` model enforces presence on title and status, but allows link to be absent. Any whitespace-only strings are normalized to nil before validation. Furthermore, the uniqueness validation on link allows multiple nil records without triggering uniqueness violations in SQLite or application logic.

## Cross-platform parity in unlinked presentation

The primary web source button, summary notice, and mobile reader share unavailable-source copy. When an official source address is missing, an unavailable notice replaces the external link across all reader surfaces.

The web reader in [[app/frontend/components/bill/BillContent.tsx#BillContent]], the summary notice in [[app/frontend/components/bill/AiUnreviewedNotice.tsx#AiUnreviewedNotice]], and the mobile reader in [[mobile/src/components/HearingTestimonySection.tsx#HearingTestimonySection]] all consume the shared copy string declared in [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] under `PARITY_COPY.bill.officialSourceUnavailable`.

When `hasValidSourceLink` returns false, source buttons and anchors are suppressed, and the shared notice appears. In the summary notice bar, `AiUnreviewedNotice` checks `hasValidSourceLink(billLink)`, ensuring generic Legistar search addresses and portal roots never appear as active links across any themed layout. At the same time, the report action in `AiUnreviewedNotice` remains active whenever a bill ID is present. Source absence also affects [[bill-summary-reporting#Reader reporting of inaccurate summaries|summary reporting]] and [[outbound-email#The preview is built from the object the mailer renders|legislator email rendering]].

## Separation of URL safety from link validity

Checking whether a link points to specific legislation is kept separate from checking whether a link's destination host is safe to open.

The mobile application maintains an allowlist of trusted domain names to guard against open-redirect or malicious navigation attacks. That security boundary determines whether a destination domain is permitted.

In contrast, link validity determines whether a URL actually points to a specific bill rather than a generic search catalog. Combining validity checks with host security checks would overload the security policy with domain-specific presentation logic. By evaluating [[mobile/src/components/HearingTestimonySection.tsx#hasValidSourceLink]] independently of [[mobile/src/components/HearingTestimonySection.tsx#ALLOWED_HOSTS]], the system keeps security policies simple and legislative validity explicit. The phone composes the two predicates in [[mobile/src/components/HearingTestimonySection.tsx#canOpenSourceLink]], which gates the Votes tab's source button and the summary's source link alike; when it fails the reader sees the unavailable sentence in place of a button that would do nothing.

Link validity uses standard WHATWG URL parsing within a guarded evaluation to inspect lowercased hostnames and normalized pathnames. This ensures query parameters (such as Legistar's `?Mode=Advanced`) and protocol variations do not bypass rejection of generic search endpoints or portal roots across Baltimore City, Maryland, and US Congress. When `genericPortalUrls` from [[app/models/sway_locale.rb#SwayLocale]] configuration are supplied to [[mobile/src/components/HearingTestimonySection.tsx#hasValidSourceLink]], portal roots are matched against those configured URLs rather than hardcoded hostnames, and malformed `genericPortalUrls` entries are ignored so a single bad entry cannot break validation. Furthermore, to eliminate `data-testid` collisions when the action card and summary notice render simultaneously on unlinked bill pages, [[app/frontend/components/bill/AiUnreviewedNotice.tsx#AiUnreviewedNotice]] identifies its notice using `summary-no-source-link` while [[app/frontend/components/bill/BillContent.tsx#BillContent]] retains `no-source-link`.
