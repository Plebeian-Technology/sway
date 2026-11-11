# Official service evidence

An official service fact enters civic records only when a configured trusted source supports the person, office, dates, and locale in that exact interval.

## Capability is explicit

An optional service profile declares whether exact official facts can be read.

The generic roster adapter reads `roster_rules.official_service`. An absent or malformed profile returns an unsupported result without making a request. Current locale configuration declares no profile, so presidential service remains unavailable until a verified source and exact field mapping are configured.

The profile pins the official URL, publisher, jurisdiction, identity source, fixed office identity, record path, and field paths. The reader requests that URL directly and checks the response URL before retaining evidence. A mirror roster request cannot be attributed to an official source by changing labels after retrieval.

## A retained fact proves one interval

One immutable evidence record retains the original response and its SHA-256 digest.

Each normalized fact records the source-specific identity, office identity, title, district, chamber, and exact service bounds in that response. Repeated reads reuse the retained evidence only when the payload, profile attribution, locale, normalized facts, and boundary semantics agree. [[app/models/official_evidence.rb#OfficialEvidence]] supplies the retained record.

Service dates require valid ISO calendar dates and use a half-open interval: the start is inclusive and the end is exclusive. A published vacancy remains an evidence-backed vacancy fact, with no person identity or invented term dates. A failed request remains a coverage gap and does not imply a vacancy.

## Civic writes use the existing term path

Supported present facts enter civic records through the existing term writer.

[[app/services/official_evidence/seed_service.rb#SeedService]] requires a source-qualified person identity, exact locale district, explicit title and chamber, and the same persisted evidence locale. It writes the person, identifier, seat, and term atomically through the existing term writer. Conflicting overlapping facts for one office are refused together, and the service never creates votes.

An existing person is matched by its typed LegislatorIdentifier identity. A raw external ID from another source cannot claim that person. Existing term data is preserved when it conflicts with the official fact, and the result reports the conflict rather than treating it as a successful write. [[app/models/legislator_identifier.rb#LegislatorIdentifier]] owns typed identity matching.

The prepared official service entry is term evidence, not a roster history. It never treats omitted executive history as proof that a previous term ended. An exact current fact is current only when `start_date <= today < end_date`.
