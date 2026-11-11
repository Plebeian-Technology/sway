# Testimony attachment rules

Attachment classification separates jurisdiction-specific filename conventions from model decisions about extracted document text. Baltimore's clerk practices do not define attachment meaning for Maryland, Congress or an unknown jurisdiction.

## Every fixed phrase matches through the extracted-text helper

Patterns that look for a known phrase in testimony are built through
`Testimony::ExtractedText` rather than written as literals.

These patterns read machine-extracted document text, where the spacing belongs
to the converter rather than to the writer. Measured over the stored attachment
text, a literal match for the city's IT banner found 0 of its 405 real
occurrences while the built pattern found all 405, once character repair also
resolved the variant that breaks on a currency symbol rather than only on the
replacement character; a literal "on behalf of" likewise misses the three real
occurrences that wrap inside the phrase.

The bounds inside those patterns are not relaxed the same way. They exist to
stop a match walking into the next sentence, and on the stored text they cost
nothing — the same count with and without the newline.

## Why the break-glyph screen is a task rather than a note

The evidence behind the list of characters that break a word mid-extraction is
kept as a runnable measurement.

A list written down once is checked once. Running the screen is how a new
glyph is found by measurement, rather than by somebody noticing a mangled word
months later. It emits counts alone: no testimony text is ever printed, written
or logged, because hearing letters carry residents' names, home addresses and
personal email addresses, and this repository is published.

## What a sender's domain is not allowed to decide

A domain says where a letter came from. It never says who is speaking or in
what capacity, so only the letter's own words decide its kind.

A city employee writing from a government mailbox as a resident is still a
resident. Trusting the domain would turn a personal opinion into an official
public-body position, which is the over-attribution the whole guard exists to
prevent.

The phrases that do decide are narrow on purpose, for the same reason the
filename patterns are: a public body's letterhead names the kind of agency by
its generic noun — department, office, commission, board, authority, agency —
and the roster of a particular city's agencies is not this module's business to
know.

The phrase rules alone missed the commonest agency letter there is. Baltimore's
Law Department opens with its letterhead and never says "on behalf of" anything,
so the phrase rules read the City Solicitor as a resident, and the campaign
grouper then took the letter for one resident among several. A line in capitals
holding one of the agency nouns (including `OFFICE` and `BOARD`, while excluding
`BOARD OF DIRECTORS`, `BOARD OF TRUSTEES`, and `BOARD OF GOVERNORS` via
[[app/services/testimony/source_kind_rules.rb#SourceKindRules#LETTERHEAD_NOUN_SOURCE]]),
sitting above the greeting, now reads as a public body as well via
[[app/services/testimony/source_kind_rules.rb#SourceKindRules#LETTERHEAD_LINE_PATTERN]].
The capitals and the line to itself are what separate a letterhead from a
sentence that mentions the agency, while possessive leading whitespace (`[ \t]*+`)
and an explicit `[A-Z0-9]` anchor prevent space-padded lines from backtracking.
The greeting matched by [[app/services/testimony/source_kind_rules.rb#SourceKindRules#SALUTATION_PATTERN]] —
including `Dear`, `To the Honorable`, `To the City Council`, `Honorable`,
`Good morning/afternoon/evening`, `Members of the`, `Hello`, `Chair`,
`I am writing` / `I write`, and closing sign-offs (`Sincerely`, `Respectfully`,
`Regards`, `Cordially`) — is the boundary because a letterhead precedes it while
a city employee's own signature block, carrying the same words, follows the body,
and when no greeting or sign-off is present at all [[app/services/testimony/source_kind_rules.rb#SourceKindRules#LETTERHEAD_WINDOW_CHARS]]
caps the letterhead scan window so a signature block at the bottom of a long
constituent letter cannot be mistaken for a letterhead. A letterhead in title
case is left to the phrase rules and the model: the capitals are the evidence.

Agency position reports, planning studies, and staff reports also use standard institutional phrasings without a greeting or an all-caps letterhead — stating that an agency "is herein reporting on" a bill, that an agency "at its regular meeting of ... considered" a bill, that a staff report was "prepared by the staff of" an agency, board, or office, that an agency "wishes to thank ... study" stakeholders in a corridor study acknowledgement, or opening a line with an all-caps `BILL SYNOPSIS` heading before naming the reporting agency. [[app/services/testimony/source_kind_rules.rb#SourceKindRules#PUBLIC_BODY_PATTERNS]] matches those phrasings against [[app/services/testimony/source_kind_rules.rb#SourceKindRules#AGENCY_NOUN_SOURCE]] and [[app/services/testimony/source_kind_rules.rb#SourceKindRules#REPORT_AGENCY_NOUN_SOURCE]] through [[app/services/testimony/extracted_text.rb#ExtractedText]] so standalone agency report and planning study attachments classify deterministically as `:public_body` without false-positiving on constituent prose that mentions a study or synopsis.

## Filename rule boundaries

NameRules requires an explicit canonical locale name. Only baltimore-maryland-united_states enables the existing pattern lists; all other values return undecided so document contents can determine the answer.

Baltimore's Legistar classification flags are not populated usefully, so fixed filename patterns provide a cheap first pass. Names are scrubbed as UTF-8, lowercased, stripped of recognized extensions and normalized across spaces, underscores, dots and hyphens before matching. Underscores otherwise prevent word-boundary matches.

Narrow reading, enrolled, engrossed and reprint markers reject bill text even when a testimony word also appears. Ordinary-English bill signals such as reader, signed, amendment and numbered ordinance reject only without a testimony signal; together they yield ambiguous_bill_text. Signed letters and passing references to amendments are excluded from those ambiguous signals. Law followed by a number is deliberately absent because Baltimore's Law Department submits agency positions under that name.

Testimony patterns win over procedural patterns. Procedural signals include the observed Voiting Record typo. Remaining names are undecided; the long tail of unfamiliar names belongs to the model rather than an expanding keyword list. The separate ambiguous label also lets primary-PDF ranking place likely testimony below an otherwise undecided document.

The same explicit locale reaches hearing extraction limits and primary-PDF fallback selection. Filename-based larger testimony limits apply only in Baltimore; other jurisdictions retain the ordinary attachment cap. This change adds no filename patterns or bundle classifications.

## Classifier routing and cache

The prefilter resolves its locale once per candidate batch and runs filename rules before consulting saved model verdicts. A missing locale or failed locale lookup leaves names undecided rather than applying Baltimore rules or stopping the bill.

The prefilter performs neither downloads nor model calls. Testimony names are kept, bill-text and procedural names rejected, and other labels enter the cache/model path. Model-pass labels derive from the complete NameRules label set so routing and measurement cannot silently diverge.

Only model verdicts are stored. They remain keyed by locale and attachment ID, with model and prompt version required for reuse. Source endpoint records provenance without distinguishing two views of the same attachment. Filename decisions run afresh and were never cached, so scoping those rules needs no cache deletion or prompt-version bump. Another jurisdiction's same numeric attachment ID cannot reuse Baltimore's verdict.

Content classification sends extracted text as the main evidence and the name as supporting evidence through separate system and user prompts. Batches contain at most 25 attachments. [[app/services/testimony/attachment_classifier.rb#Testimony#AttachmentClassifier|The classifier factory]] captures the independent classification route when it builds the adapter. Calls and cache keys retain that model for the instance, so an intervening settings change cannot pair an existing adapter with another route. Newly built classifiers use the changed setting and can incur fresh model costs because old verdicts no longer match.

Missing adapters, configuration failures, cache errors, malformed model entries and provider failures keep undecided documents. Fallback answers are not cached. Valid model answers apply independently, so one bad entry or failed persistence cannot erase another document's verdict. Provider failures and response-application failures use distinct log events.

## Locale regression coverage

Tests preserve Baltimore's filename corpus while checking that other jurisdictions receive undecided for every rule family. Classifier tests cover same-ID cache isolation, current-locale reuse and lookup failure.

Primary-PDF selection and hearing text-limit tests verify that secondary users of NameRules receive the same explicit locale boundary. Existing classifier tests retain model, prompt-version and failure-path coverage.


## Corpus measurement keeps jurisdiction identity

The classification corpus task measures current Rails hearing artifacts by jurisdiction. Attachment IDs, filenames and bill identifiers are unique only within their jurisdiction, so every measurement key retains that scope.

The task reads the top-level attachments array in hearings/<sway_locale>/<bill>.json, including model-denied candidates. It uses the human name rather than the upstream GUID filename. Malformed JSON and retired bare-event arrays are skipped. Attachment IDs must be integers before they become sidecar paths. Empty corpora stop with an explicit error.

Documents deduplicate by locale and attachment ID. Name tallies count distinct locale/name pairs, while per-bill model counts group by locale and bill identifier. NameRules receives that locale for each decision. AttachmentClassifier::MODEL_PASS_LABELS owns which labels reach the model, so ambiguous bill text cannot disappear from the measured population.

Text comes only from attachments/<sway_locale>/attachment-<id>.txt or the PDF in that same directory. Missing local text never falls back to a matching ID in another jurisdiction. Extraction failures and empty text remain visible as unreadable locale/ID pairs.

PromptLabel.collapse normalizes text before length and first-marker measurements. Marker phrases represent positions, memoranda, legal findings, recommendations, fiscal notes and enacting text. Documents without a marker are reported even when every document lacks one. The p90 offset uses the nearest-rank definition. Changing marker phrases or filename rules changes the measured population or offsets.

Historic corpus numbers came from the retired Python layout and are not evidence about the current Rails artifact tree. Fresh counts require artifacts fetched by the Rails pipeline. The local corpus remains untracked third-party data.

## Source-kind rule ordering and evidence boundaries

[[app/services/testimony/source_kind_rules.rb#SourceKindRules]] evaluates every letter in strict priority order: `:named_organization`, `:public_body`, `:person_speaking_for_org`, and finally `:person_speaking_for_self`.

Checking `:named_organization` before `:public_body` prevents organization names that contain words like "Board" or "Commission" (`"On behalf of the Board of Directors of the Baltimore Housing Coalition"`) from being misclassified as government agencies, while `named_organization?` yields to `public_body?` whenever the letter carries an agency letterhead or public-body phrase and bounds `"on behalf of"` within a single clause (`[^\n.,;]{0,60}`) so agency letters addressing the Mayor and City Council never misclassify as advocacy organizations. Placing `:person_speaking_for_self` last as an unconditional fallback ensures that ambiguous letters default to publishing no personal name rather than attributing an individual as an organization. A sender's email address is used only as the third piece of evidence for `:person_speaking_for_org` and never triggers `:public_body`.

## Source-kind model confirmation and fallback accounting

[[app/services/testimony/source_kind_classifier.rb#SourceKindClassifier]] trusts rule-decided `:public_body` and `:person_speaking_for_self` verdicts outright and sends only `MODEL_PASS_KINDS` (`:named_organization` and `:person_speaking_for_org`) through [[app/services/testimony/source_kind_prompt_builder.rb#SourceKindPromptBuilder]] for model confirmation.

When the model adapter is disabled, unavailable, or returns an error or out-of-batch position, tail letters fall back to `:person_speaking_for_self` and increment `source_kind_model_fallbacks` so an LLM outage is distinguishable from a confident individual classification. When the model confirms `:person_speaking_for_org`, the classifier retains the rule-extracted evidence (`phrase`, `role`, `sender`, `org_name`) rather than allowing the model to invent evidence.
