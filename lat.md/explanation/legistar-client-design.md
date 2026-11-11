---
lat:
  mode: explanation
---

# Why Legistar API access goes through one client object

`Legistar::Client` is a standalone Ruby client for the Granicus/Legistar Web API (`https://webapi.legistar.com/v1/<client>`). This explains what problem it solves and how its pieces fit together.

## What it wraps

Legistar's Web API is an OData v3 service — query-string options like `$top` and `$filter`.

`Legistar::Client` gathers URL building, OData encoding, pagination, JSON parsing, and error handling behind one object, so callers think in resources (matters, histories, events, votes) rather than raw HTTP. `FetchBillsService` and `FetchHearingsService` used to build path strings and parse responses by hand; this client replaces that.

Transport is the shared `Sway::FaradayStack.legistar` connection (bounded retries on 429/5xx, a 30s timeout). The client uses leading-slash, host-relative paths so the connection's base `/v1` path is replaced rather than appended to.

## Basic usage

Primary interface patterns and query conventions for retrieving legislative records and attachments from the Legistar API.

```ruby
client = Legistar::Client.new                       # defaults to "baltimore"
client.matters(filter: "MatterTypeName eq 'Ordinance'", top: 5, orderby: "MatterId desc")
client.matter_histories(9928)
```

## Why callers still rescue Faraday::Error

`Legistar::Client#get_raw` (and `#get`) rescue `Faraday::Error` at the method level and re-raise it as `Legistar::Client::Error`, so `Faraday::Error` itself can never actually reach a caller of the client.

Callers throughout `FetchHearingsService` and `FetchBillsService` still list `rescue ..., Faraday::Error` alongside `Legistar::Client::Error` anyway, as defense-in-depth against a future change to the client that stops doing that translation — the rescue costs nothing to keep and the alternative is a silent regression if the translation is ever removed.

## Why a Legistar collection sub-resource answers 200  for an unknown parent

Live-probed against `webapi.legistar.com/v1/baltimore`:

```
Matters/9928                 -> 200      Matters/9928/Histories       -> 200, 12 rows
Matters/99999999             -> 404      Matters/99999999/Histories   -> 200 []
Matters/0|-1/Histories       -> 200 []   Matters/99999999/Attachments -> 200 []
Events/99999999              -> 404      Events/99999999/EventItems   -> 200 []
```

A collection sub-resource (`.../Histories`, `.../Attachments`, `.../EventItems`) answers `200 []` for an unknown parent id, and only the bare parent entity (`Matters/<id>`, `Events/<id>`) 404s. Baltimore's matter-id space is sparse — 10500, 11000 and 11500 all 404 — so a stale or hand-edited `metadata.json` id is an ordinary condition, not a hypothetical one.

This is why `FetchHearingsService` treats a bare-entity 404 as proof a matter or event does not exist (see `#matter_exists?` and `#fetch_hearing_event`'s handling of `Events/<id>`), while an empty sub-resource collection proves nothing on its own — it looks identical whether the parent is real with zero rows, or does not exist at all. A probe that cannot answer either way (a 5xx, a non-JSON body, a transport failure) is treated as neither "exists" nor "does not exist": resolving it to either answer would be the same defect wearing a different exception class, so it raises instead.

## Why an HttpError on a Histories fetch has no fail-soft 404 branch

`FetchHearingsService#call_discover` deliberately has no fail-soft branch for a 404 on `event_ids_for_matter!`'s `Legistar::Client::HttpError`.

A collection endpoint does not 404 for a well-formed integer id — it answers `200` with an empty array (see the probe table above) — and `#coerce_matter_id!` guarantees an Integer. What CAN still 404 there is a malformed route string or an infrastructure fault, and "this bill has no hearings and no testimony" is exactly the wrong conclusion to draw from one. An older version of this code had such a branch; its reasoning came from `Matters/<id>/Events` — a route later proven not to exist, which therefore 404s for EVERY matter, scheduled or not — and was carried onto `Matters/<id>/Histories` without being re-checked. The rescue re-raises as `BillProcessingError`, not `StageError`, so the run continues, the bill is retried next run, and no artifact is written — `Pipeline::ArtifactPresence.present?` stays false rather than making every later auto-include run skip the bill.

## Why event_ids_for_matter's rescue branch stays even though nothing reaches it today

Nothing reaches this rescue in `:discover` mode today (`#call_discover` asks `#event_ids_for_matter!` first, so the cache is already filled by the time `#event_ids_for_matter` runs).

It is kept as a real branch rather than deleted: this method promises that attachment discovery may not fail the bill, and a future caller that gets here first must not get a silent version of that promise.

## Why every response body is scrubbed to valid UTF-8 before anything else sees it

The body is scrubbed a second time inside `HttpError#initialize`, even though `#get_raw` already scrubs it before either branch (success or error) sees the raw bytes.

`body` MUST already be valid UTF-8 by the time it reaches that constructor — mixing in a raw-bytes body holding a byte >= 0x80 raises `Encoding::CompatibilityError` there. That error is an `EncodingError` — neither `Faraday::Error` nor `Legistar::Client::Error` — so it slips past every rescue and kills the whole run over one upstream error page. `HttpError` is a public constructor, and re-scrubbing is cheap (a valid string comes back unchanged), so a future caller need not remember the rule.

`#get_raw` scrubs the body to valid UTF-8 BEFORE the bytes can reach a message or consumer — in `#get_raw`, the one door the bytes come in through — so every Legistar consumer inherits a valid-UTF-8 guarantee. `JSON.parse` does NOT validate encoding — it returns UTF-8-tagged strings holding invalid bytes. Two fields taken verbatim from this JSON reach operations that raise on bad bytes: `MatterAttachmentName` flows into `Testimony::NameRules.classify`'s `#downcase` and `#match?` (`ArgumentError`); `MatterAttachmentFileName` flows into `JSON.pretty_generate` and a `serialize coder: JSON` save. Neither error is a `BillProcessingError`, and neither is caught before `RunLegislationPipelineJob::StageError` — one mis-encoded title would abort `fetch_hearings` for every remaining bill in the run.

The consequence is proven; the trigger is not. The reference cassette shows Legistar encoding en-dashes and quotes correctly, so this is defense at a boundary, not a reproduced upstream bug. It's worth the cost anyway: the failure would take down a whole run, while this subsystem is built to degrade one attachment at a time. That cost is NOT zero — Faraday's `net_http` adapter returns raw-bytes bodies, so `#get_raw`'s scrub copies every response via `dup.force_encoding`. One extra copy of one page body, freed right away — cheap next to parsing it, but not free.

Scrubbing before the parse is structurally safe: JSON syntax is pure ASCII, so only string-literal insides can be touched, and a bad byte run becomes U+FFFD rather than a parse failure. `#parse` repeats the scrub because that is the method whose contract consumers depend on directly.

## Why the already-decoded-body tolerance check lives in get_raw, not parse

A `Faraday::Connection` with `conn.response(:json)` mounted — which the public `connection:` arg openly invites — hands back an already-decoded Array/Hash instead of a String.

This tolerance branch used to live in `#parse`, where it could never fire: `Sway::Utf8.scrub` had already turned the Hash into Ruby inspect syntax, so `JSON.parse` raised on perfectly good JSON. The check has to run BEFORE the scrub, so it lives in `#get_raw` and `#parse` now takes a String only. A decoded body needs no scrub.

## Why only wrappers with real callers are kept

The typed convenience wrappers on `Legistar::Client` are thin shims over `#get` so callers don't repeat resource paths; all accept the same OData keyword options as `#get`. Only wrappers with real callers are kept.

The speculative set (Events/EventItems, reference tables, unused matter/person sub-resources) was removed — call `#get("Matters/#{id}/Sub", ...)` directly when a concrete need arises.

## Why odata_params only prefixes Symbol keys with "$"

Only Symbol keys get the "$" prefix — that is the point.

An earlier version prefixed EVERY key, so a caller passing a String key to opt out (Legistar's `"Attachments"` flag) got silently rewritten. `"$Attachments"` is rejected by Legistar with HTTP 400, proven live against `webapi.legistar.com` while recording `spec/cassettes/legistar_testimony_endpoint_probe.yml`. The cassette holds only the ACCEPTED unprefixed form (`Attachments=1`); the rejected `$Attachments` request was probed by hand and is not in it.

## Why ParseError and HttpError are separate subclasses of Error

[[app/services/legistar/client.rb#ParseError]] and [[app/services/legistar/client.rb#HttpError]] subclass [[app/services/legistar/client.rb#Error]] separately so callers can distinguish malformed 2xx bodies from HTTP status errors.

Callers rescuing [[app/services/legistar/client.rb#ParseError]] handle non-JSON 2xx responses without swallowing transport failures, while callers rescuing [[app/services/legistar/client.rb#HttpError]] can inspect `status` and `path` (such as treating a 404 on a sub-resource distinctly).
