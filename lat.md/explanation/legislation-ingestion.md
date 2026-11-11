---
lat:
  mode: explanation
---
# Legislation ingestion

Pipeline bill ingestion fills the Rails-owned records from discovery metadata while preserving jurisdiction boundaries and existing bill associations.

## The write boundary

Each bill upsert and its provisioning changes share a transaction, so a failed write cannot leave half a bill update behind.

The allowed column lists exclude generated LLM summaries and positions, which belong to their own jobs. Database uniqueness identifies a bill by locale and external ID; a competing insert is recovered by loading that same row and applying its attributes. Nested SQLite savepoints do not each force a disk flush under WAL mode with normal synchronization.

## Locale and chamber resolution

An explicit locale selects its own roster. A new Maryland bill's HB/HJ or SB/SJ identifier supplies its chamber from declared jurisdiction rules when the payload omits one.

Payload chamber values and existing bill chambers take precedence. Other missing chambers use the jurisdiction's declared default. An omitted locale retains the legacy Baltimore default. When a locale has no declared jurisdiction rules, chamber resolution degrades gracefully to nil without halting ingestion. The per-service locale cache avoids repeated reads because the public locale name is computed rather than stored as a searchable column.

## Legislative session assignment

Ingestion assigns each bill to a legislative session based on its introduction timestamp and jurisdiction.

An explicit payload identifier overrides automatic resolution. Otherwise, the bill's locale resolves the session covering its introduction date via `sway_locale.legislative_session_for_date`, matching against the data-driven `LegislativeSession` records documented in [[locale-extension#Legislative session schema and validations]]. When no session covers that date, the association remains nil without failing ingestion.

## Required values

Discovery can create a bill before editorial fields exist, so ingestion supplies the values needed to save that draft.

A missing title takes the external ID, a blank summary takes the shared summary placeholder, and a blank category takes the legacy Ordinance default. Blank categories need an explicit check because the database default is an empty string. Status and introduction time retain their existing defaults; public source links have no generic search fallback.

## Declared fallback associations

A bill without an identified legislator uses a declared chamber officeholder to satisfy its required association. That fallback does not establish actual sponsorship or a legislator vote.

An existing bill association is preserved when the payload omits a legislator external ID. A supplied published ID takes precedence, including when correcting an earlier fallback association. Baltimore uses its current Council President term. Maryland uses roster IDs declared separately from the generic Delegate and Senator term titles, because the roster does not encode chamber leadership. The matching current term must also belong to the requested locale. Fallback caching includes both locale and chamber.

The Maryland declarations identify House Speaker Joseline Peña-Melnyk and Senate President Bill Ferguson, verified against the official [House leadership](https://mgaleg.maryland.gov/mgawebsite/Members/Index/house) and [Senate leadership](https://mgaleg.maryland.gov/mgawebsite/Members/Index/senate) pages on September 15, 2026. Their OpenStates person IDs come from the committed Maryland roster. These curated declarations require review when leadership changes; a current legislative term alone does not prove continued leadership. They represent current fallback associations, not historical sponsorship.

Missing or inactive declared officeholders cause an explicit ingestion failure instead of assigning the first available member. Congress has no declared fallback policy and requires an identified legislator; an undeclared chamber likewise cannot borrow another chamber's officeholder.

## Published sponsor metadata

Discovery carries a published sponsor identifier and chamber through shared ingestion without adding jurisdiction-specific fallback people.

Adapters normalize source identities into `legislator_external_id` and source
chambers into `chamber`. `FetchBillsService` preserves both in database payloads
and disk metadata hydration, so retries do not lose attribution. Congress list
responses omit sponsors; discovery reads each bill's detail response for its
published Bioguide ID and origin chamber before ingestion. Missing sponsor or
unrecognized chamber evidence produces an explicit discovery error.

An explicit sponsor ID resolves against all stored legislators in the selected
locale, including former members. Current officeholding is not required to
sponsor historical legislation. Unknown or foreign-locale identities fail
explicitly; they cannot silently become the locale's fallback officeholder.
A valid explicit sponsor replaces an existing association, while a payload
without an identity preserves it. Failed updates retain the prior bill values.
The required bill association remains intact; no placeholder person is created.

Regression coverage includes House and Senate discovery through real ingestion,
PDF persistence, disk hydration, existing fallback corrections, and rejection of
unknown or foreign-locale identities. Shared metadata transport has no provider
name branch, so a future adapter uses the same contract.
