---
lat:
  mode: explanation
---
# Why Open Legislator API access uses a native client with Legistar fallback

`OpenLegislator::Client` provides a dedicated client for Open Legislator's native REST API (`/api/v1`), supporting composite matter records, Pagy pagination, and resilient Legistar fallback for civic vote updating.

## Architecture and motivation

Granicus Legistar Web API exposes an OData interface requiring multi-step waterfall queries across separate tables, whereas Open Legislator exposes a resource-oriented API designed for civic accountability.

`OpenLegislator::Client` encapsulates HTTP communication, query parameter serialization, JSON parsing, and error wrapping using `Sway::FaradayStack.build`. It enables Sway to ingest legislative actions and passage results directly from native Open Legislator instances while maintaining backward compatibility with legacy Legistar installations.

## Composite matter resolution

The Open Legislator platform resolves legislative items via composite matter records that embed actions, tallies, and document metadata in a single payload rather than waterfall table queries.

In Legistar, finding a matter by file number requires filtering `Matters?$filter=MatterFile eq '...'` to obtain an internal integer `MatterId`, followed by querying `Matters/:id/Histories` to locate action rows. In Open Legislator, `/api/v1/matters?file_number=:file_number` performs an index lookup returning lightweight summaries (`MatterSummaryResource`), followed by resolving the full record via `/api/v1/matters/:slug` (`Api::V1::MatterResource`).

`OpenLegislator::Client#matter_by_file_number` orchestrates this resolution, returning the composite record or `nil` if the matter is not found in the jurisdiction.

## Pagy pagination envelopes

Collection endpoints in Open Legislator standardize responses using Pagy envelopes with page boundaries.

The native client supports bounded single-page retrieval through `matters(page:, limit:, **filters)` and `meetings(page:, limit:, **filters)`. Each response returns a Pagy envelope containing `data` rows alongside `page` metadata (`count`, `page`, `limit`, `last`), allowing callers to inspect pagination state and boundaries.

## Exception hierarchy and error wrapping

Transport, network, and HTTP status codes are wrapped in dedicated exception classes under `OpenLegislator::Client`.

`OpenLegislator::Client::Error` acts as the base class for client errors, including wrapped Faraday connection drops. `OpenLegislator::Client::HttpError` captures non-2xx responses with status, path, and sanitized body snippet. `OpenLegislator::Client::ParseError` captures malformed JSON in 2xx responses, distinguishing upstream data corruption from network issues.

## Honest missing outcome semantics

A core invariant of the civic pipeline is that votes and outcomes are never fabricated.

When `GenericLegislatorVoteUpdateService` queries Open Legislator for final passage data and the matter exists but has no passing action or enacted outcome, the service logs an honest diagnostic notice and leaves `house_vote_date_time_utc` unmodified. It does not invent synthetic votes or assume failure, preserving the authentic historical state of the legislative record.

## Legistar fallback in vote updating

`GenericLegislatorVoteUpdateService` queries Open Legislator first and falls back to Legistar upon connection failure or missing records.

When configured via jurisdiction vote rules or the `source:` parameter, the service queries `OpenLegislator::Client#matter_by_file_number`. If Open Legislator returns an error or reports that the matter is not found, the service logs a warning and falls back to `legistar_client` to attempt legacy resolution. If Open Legislator resolves the matter successfully, its actions determine passage; if the outcome has not occurred, the service records an honest no-op without falling back.
