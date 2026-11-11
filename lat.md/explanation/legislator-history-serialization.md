---
lat:
  mode: explanation
---
# Legislator history serialization

Legislator history serializes past representative links grouped by legislative session for civic accountability.

Grouping into sessions occurs in the serializer so web and mobile clients receive identical structures.

## Why database reads are bounded during history serialization

History serialization bounds database reads to a fixed number of queries regardless of past link or score count.

Memoizing the session collection once across the `sessions` and `legislative_sessions` serialization keys prevents evaluating the query graph twice.

[[app/serializers/legislator_history_resource.rb#LegislatorHistoryResource#history_sessions|The memo]] is keyed per user on the resource instance (`@history_sessions_by_user`). Because Alba reuses a single resource instance across collection members, keying by user isolates memoization so collection serialization matches individual serializations without cross-contamination.

Eager loading `{user_legislator_term_scores: {legislator_term: {district: :sway_locale}}}` and `legislator: [:active_term, {district: :sway_locale}, {legislator_terms: [:seat, {district: :sway_locale}, :legislator_district_scores, :legislator_locale_scores]}]` loads all terms, seats, districts, locales, and scores in batched queries.


In-memory term lookup via `terms_by_id` resolves each score row's term directly from the preloaded legislator term collection, eliminating individual SELECT statements per score row. Active term and district resolution links [[current-legislator-term#Which term a payload describes]] for display term semantics without per-record database lookups.

## Why active district ids are loaded once up front

Active district identifiers are retrieved once prior to entry mapping to eliminate per-entry district lookups.

Loading active districts once prevents repeated queries within ended reason calculation across inactive links.

## Why locale filtering uses the legislator sway locale column

Filtering by sway locale targets the legislator column directly rather than joining through district.

Reaching locale through district would inner join through the current term, which excludes former representatives who no longer hold an active term.

## Why portrait attachments and blobs are eager loaded

Representative portrait attachments and blobs are preloaded to prevent N+1 queries during serialization.

ActiveStorage attachments and blob records require eager loading to avoid two database queries per representative.

## Why ended reason requires no per-entry query

The `ended_reason` method on [[app/serializers/legislator_history_resource.rb#LegislatorHistoryResource]] uses the preloaded active district identifier set and the selected term's loaded end date.

District change takes priority when the term district is no longer active for the reader. For a matching district, a known end date on or before today means the term ended; a future end date means the user-legislator link became inactive while the term was still running. [[app/models/term_window.rb#TermWindow]] supplies the fallback date only when the locale declares a calendar. Without either source, the serializer cannot claim the term ended.

## Why session label uses declared jurisdiction rules with year fallback

Session labels derive from declared jurisdiction rules or fall back to calendar year spans.

Jurisdiction rules supply formatting such as Congress ordinal numbering or chamber labels, while locales without rules display start and end years.

## Read-only historical term agreement serialization

Legislator profiles expose past legislative terms with aggregated community scores, user agreements, and repair explanations in a single read-only payload.

Serializing terms directly on [[app/serializers/legislator_resource.rb#LegislatorResource]] keeps historical presentation server-driven and bounded. Preloaded term records, district scores, locale scores, user term scores, and [[app/models/historical_score_explanation.rb#HistoricalScoreExplanation]] records are mapped in memory during page serving, ensuring that page visits never trigger background score recalculations or database writes. The `is_executive` flag identifies terms whose seat chamber is Executive for badge display while serializing district, locale, and personal agreement scores on the same read-only path as legislative terms.

## Why term history preloading eager loads nested score families

The `with_term_history` scope on [[app/models/legislator.rb#Legislator]] eager loads nested score families and attachment blobs in a single query batch.

Serving a legislator profile page with multiple historical terms requires district scores, locale scores, seat chambers, and photo attachments. Preloading `legislator_terms: [:seat, {district: :sway_locale}, :legislator_district_scores, :legislator_locale_scores]` eliminates N+1 queries across terms while keeping score access read-only.

## Why historical score corrections are embedded directly in term payloads

Historical corrections link directly to audit records so readers can trace changes without secondary requests.

Embedding [[app/models/historical_score_explanation.rb#HistoricalScoreExplanation]] in each term entry allows client surfaces to show a verified "Score Corrected" indicator immediately. Tracing to the admin repair preview audit explains why a past score changed without requiring a separate network fetch on demand.

## Why unvoted terms are rendered with distinct coverage indicators

A reader who registered after a term ended cannot have agreement computed against that term's legislation.

Returning `user_score: nil` signals client interfaces to show an explicit "No votes on record" badge rather than zero percent. Making unvoted terms visibly distinct prevents confusing absent registration history with active voting disagreement.
