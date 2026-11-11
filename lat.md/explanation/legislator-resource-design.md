---
lat:
  mode: explanation
---

# LegislatorResource design

`LegislatorResource` serializes representative profiles, tenure dates, and contact channels for client applications.

The resource maps database records into client representations, reconciling active and historical terms to ensure consistent presentation across web and mobile clients.

## Why term toggle and history copy coordinates with display_term

`LegislatorResource#display_term` falls back to the most recently completed term when a representative is inactive, aligning tab labels with tenure years.

For actively serving legislators, the primary tab presents `PARITY_COPY.legislators.tabCurrentTerm`. For former representatives, client components dynamically construct the tab label from `term_start_year` and `term_end_year` while displaying [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] `legislators.endedStamp`.

## Why historical terms serialize agreement scores alongside session metadata

Serializing `terms` directly on [[app/serializers/legislator_resource.rb#LegislatorResource]] provides clients with complete term-by-term voting agreement without additional network requests.

Each serialized term entry includes session identifiers, start and end dates, district labels, the `is_executive` chamber flag, and three agreement score dimensions: `district_score`, `locale_score`, and optional `user_score`. All terms serialize district, locale, and user agreement scores on the uniform path regardless of chamber, while `is_executive` indicates whether to display an executive office badge. When official service repairs have adjusted scores, `correction_explanation` includes the audit title, body, and delta for transparent presentation.

## Why contact details are included in serialized payloads

Public profiles expose direct telephone, address, and online communication channels for active engagement.

Reaching an elected representative is fundamental to the platform's civic accountability mission. [[app/serializers/legislator_resource.rb#LegislatorResource]] serializes phone numbers, office addresses, official contact emails, and social handles directly so readers can act immediately without visiting third-party directories.

## Why photo_url preserves its wire key across asset mirroring

`photo_url` transparently serves internally mirrored assets without altering client API contracts.

When Sway stores a local portrait attachment, `MirroredAssetUrl.for` resolves the mirrored URL; otherwise, it falls back to the external source URL. Keeping the `photo_url` key name unchanged preserves client wire stability across web and mobile platforms.

