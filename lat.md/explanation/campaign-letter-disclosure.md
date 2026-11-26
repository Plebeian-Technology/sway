---
lat:
  mode: explanation
---
# Campaign letter disclosure

The Bill Creator shows each campaign draft's member letters — bundle position, sender, and text — so an operator can read what people wrote before approving a campaign. The text rides a prop of its own, fetched when a disclosure opens.

## Why the letter text was never a redaction question

BillsController is admin-only, and the sibling claimed-affiliation card already renders a raw sender address unredacted, so a sender address and a letter body here were never a new class of exposure.

What moved the text off the campaign drafts prop was its size on a five-second poll, not who could read it. The slicing itself is unchanged wherever it lives: each letter's text comes out of the cleaned artifact's full text by `character_offset` and `characters`, the same idiom `Testimony::SourceKindClassifier#letter_text_for` and `Testimony::CampaignDraftFinder#letter_text` already use.

## Why the letter text is a prop of its own

The letters ride a prop the Bill Creator asks for by name, separate from the campaign drafts they belong to, so a five-second poll of the drafts does not carry them.

Two Bill Creator tabs refresh the campaign drafts every five seconds — the pipeline tab while a run is in flight, the summary tab on a branch that is not tied to a run at all. A draft's letter list is however many people sent the template, so a bill with heavy testimony re-sent most of its testimony corpus on every tick, per open tab. An `InertiaRails.optional` prop is left out of any response that does not name it, and neither poll list names this one.

The phone cannot name a prop, so it asks with a query parameter that only its Positions tab sends ([[mobile-bill-creator#Sections#The campaign drafts section#Serving the letter text to the phone]]).

Addressing a letter list through a dotted path into the drafts array was rejected: Inertia addresses an array element by index, which is the coupling `content_hash` exists to remove. A dedicated route was rejected too — both other optional props here are top-level props fetched by a router reload, and a third mechanism for the same job would earn nothing.

## Why a repeat letter is marked, not hidden

`Testimony::CampaignMarker#finalize_draft` excludes a member `Testimony::DuplicateLetterMarker` flagged `"repeat"` from `sender_count` and `letter_count`, while leaving that member's position in `letter_positions`.

Rendering every position without saying which are repeats would show more letters on a card than the card's own counts admit to, so each shipped letter carries the same `repeat` flag and the campaign card labels a repeat letter as a duplicate rather than leaving the mismatch to speak for itself.

A repeat is a letter whose sender and own words both already appeared on this bill. The case it exists for is a jurisdiction republishing one person's testimony across two hearing bundles for the same bill: counted naively that person speaks twice, and every count built on top inherits the inflation. The exclusion therefore reaches the same way through the coverage report and the domain counts as it does through a campaign draft's own totals, and the drafts carry how many of their members were dropped so a reader can see the difference between the letters shown and the senders counted.

Marking needs the sender addresses, so it runs after the step that reads senders rather than beside it.

## How much testimony reached the model is stated, not implied

A notice on the summary tab says how much of a bill's testimony actually
reached the positions model, against how much exists.

The quantity was previously invisible: an operator saw positions drawn from
testimony with no way to tell whether that meant all of it or a fraction. The
notice names one of six states, in a fixed vocabulary — "reached the model",
"left out" and "removed" mean different things and are never used
interchangeably or rotated for variety, because an operator reading them is
deciding whether to trust the positions.

It renders nothing when there is no testimony at all. A separate notice already
owns that case, and a second empty-state message beside it would be noise.

## Why drafts are matched on lines and on word shingles

Repeated letters are grouped by the text they share, compared one normalized
physical line at a time and never joined across a line break, with sliding
word shingles beside that.

Whole-letter comparison misses whole sending services: a smaller service's
letters carry none of the main template. Matching a template's full opening
sentence misses copies, because extraction can break a character inside that
sentence and some copies wrap the line inside it. Cutting at every line break rather than
bridging it is what stops a wrapped copy missing its own template.

Lines alone still under-merge, because a line break belongs to the source PDF
rather than to the letter: the same sentence wraps at a different column in a
different hearing bundle, so two copies of one template can share no identical
line at all. Word shingles catch that without loosening the line match.

Grouping reads text only. It reads no sender domain and no timestamp: arrival
timing separates nothing, because a campaign's letters spread over days while
a busy ordinary day can carry as many. Domain-based origin marking happens afterwards, on top of
what this finds.

Order matters around it: it runs after character repair and banner removal, so
the banner is gone and the broken ligature fixed before anything is compared.

## Why the disclosure is gated on the count rather than the letters

`CampaignLetterList` decides whether to render, and what its button says, from the draft's `letter_count` aggregate rather than from the length of the letters it was handed.

The letter text sits on a fetch that runs when an operator opens the
disclosure, not on the five-second polled payload. The array is therefore
absent until that fetch returns, so a component reading the array to decide
whether to render would render nothing, and no control would remain to open.

The two numbers do not always agree. A recorded `letter_positions` entry with
no matching letter is dropped rather than raising, so a draft can report more
letters than it can produce. Gating on the count means such a draft opens a
disclosure that resolves to nothing, where previously it showed no disclosure
at all. That is the intended trade: the earlier behaviour made a draft holding
unretrievable letters indistinguishable from one holding none, which is the
same mismatch the repeat-letter marking above exists to keep visible.

## Why the list asks for its own letters

`CampaignLetterList` triggers a partial reload naming the letters prop the first time an operator opens a disclosure, and reads the result out of the page's props rather than holding it itself.

Nothing else on the page needs the letters, and no poll asks for them, so the prop that arrives survives every later tick — a partial reload merges onto the props already there. One card's fetch therefore fills every card on the page, and a card whose letters are already present opens without a request. A locally remembered "requested" flag stops only a second request while the first is in flight, and a failure holds that flag so the list offers a retry rather than re-requesting on each open.

The list has three states it never needed while it was handed its data. A fetch in flight reads as pending. A fetch that failed says so and offers to try again, rather than looking like a campaign with no letters. A fetch that succeeds and returns nothing says that no letter text could be produced — the case the count gate above deliberately admits, where a draft claims more letters than the artifact can slice out.

That third state is settled by the request finishing, not by an empty array arriving. A response can carry bundles while carrying none for this draft's hash, which leaves the card holding nothing rather than an empty list, and the "requested" flag would then block any further attempt. Keyed off the array alone the disclosure would show a pending state that nothing could ever resolve, so the list treats a finished request with no letters of its own the same way it treats an empty one.

The lookup from a card to its bundle goes through the draft's content hash, never through a list position: the hash is what already identifies a draft through a re-run that reorders the array, and the campaign card's own approve and reject paths send nothing else.

## Why replacing an earlier decision is reported as success

Approving a campaign position can overwrite a decision already recorded for
that campaign name, and the notice says so while still reporting success.

The write did succeed, so an error would be a lie; but a plain "Approved" would
hide the overwrite. An operator working several drafts of one campaign is the
person this matters to: before the notice named the replacement, there was
nothing on screen distinguishing a first approval from one that discarded an
earlier draft's decision, and the two look identical afterwards.

Replacing rather than refusing is forced by the shape of the data. A unique
index on the bill and the campaign name means there can be no second row, so
the only options are to refuse the approval or to let it stand and say so.
Refusing would wall the operator on any bill where one campaign fragments
across several drafts — a grouping defect they cannot fix from this screen.

## Why a public body's letter never joins a draft

A campaign draft is a set of people who sent one template, and an agency's report is neither a person nor a template, so a letter the rules read as a public body is kept out of the reuse grouping before it runs.

The grouping matches any eight words in a row, and an agency report of a hundred thousand words shares eight of them with somebody. On one real bill the City Solicitor's letter, holding every agency report in the packet, became the fourth "person" in a campaign of three residents — and the bridge through which one resident joined the other two at all. Excluding the letter before grouping, rather than removing it from a draft afterwards, is what keeps an agency's words from being that bridge. The exclusion reads the deterministic rules alone: a public body is a kind the rules decide without the model, so grouping can ask before the classification step has run.

[[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService#group_by_reuse]] applies the same pre-grouping exclusion via [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService#overlong_letter?]] to any segment exceeding [[app/services/testimony/extracted_text.rb#ExtractedText#MAX_CONSTITUENT_PAGES]]. Partitioning `public_body_letter?` first and evaluating `overlong_letter?` only on the remaining non-public segments avoids running the source-kind rules twice per letter while keeping both classes of non-constituent documents out of [[app/services/testimony/campaign_draft_finder.rb#CampaignDraftFinder]]:

- Agency letters and staff reports of any page count are excluded by the deterministic `:public_body` check.
- Multi-page studies, consultant presentations, and planning appendices that exceed five effective pages without carrying an explicit agency phrase are excluded by the five-page constituent ceiling.
- Effective page counting ignores empty pages and short 1–3 line print-header spillover stubs (including middle-initial periods) that lack sentence punctuation, an email `From:` header, a letter salutation, or stance keywords, so a five-page letter with a trailing clerk print-header stub is still eligible.
- A short constituent letter or email without sentence-ending punctuation that starts with `From:`, a salutation (`Dear`, `Honorable`, `Members of`, `To the Council`), or stance keywords (`Support`, `Oppose`, `Vote`) is never discounted as a print-header stub, so every genuine page contributes to the five-page constituent ceiling.
- When a `From:`-headed constituent cover email is followed by a multi-page report appendix in the same attachment and the remaining unheaded pages exceed five effective pages, [[app/services/testimony/letter_splitter.rb#LetterSplitter#split_overlong_segment]] splits the unheaded appendix into its own overlong segment after five pages (or immediately before an attached study opening matched by [[app/services/testimony/letter_splitter.rb#LetterSplitter#report_appendix_start?]]) so the cover letter remains eligible with its `sender_address` intact while the appendix is excluded.
- When a `From:`-headed segment's remaining unheaded tail is five effective pages or fewer, the splitter leaves the segment intact so capping never creates a short unheaded report fragment that would slip under the five-page constituent ceiling.
- Both excluded slices are tagged with the transient `"excluded_from_drafts"` key and appended after [[app/services/testimony/campaign_draft_finder.rb#CampaignDraftFinder]] runs so [[app/services/testimony/campaign_marker.rb#CampaignMarker]] also skips singleton-domain draft creation for them, before [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService#TRANSIENT_LETTER_KEYS]] strips the transient key from the stored artifact.
- [[app/services/testimony/browsable_letters.rb#BrowsableLetters]] enforces the same `over_constituent_page_limit?` check alongside `source_kind == "person_speaking_for_self"` and strips trailing print-header stub pages so any pre-existing artifact or unsplit study exceeding five effective pages is also kept out of constituent letter counts and [[app/frontend/components/bill/BrowseTestimonyModal.tsx#BrowseTestimonyModal]].

## Why the letters page one at a time

The disclosure shows one letter per page. What an operator is judging is each sender's own additions to the shared template, and a wall of near-identical copies hides the differences that matter.

A campaign on a contested bill runs to hundreds of copies. Listed together they read as one long repeat, and the eye stops on the template rather than on the sentence a particular sender added, which is the only part that tells the operator anything the count did not already say.

## Why the letter list is not a CollapsiblePanel

`CollapsiblePanel` persists its open/closed state to `localStorage` under a `storageKey`, which suits a panel an operator returns to across sessions.

A per-draft key here would leave one permanent `localStorage` row per campaign template per bill, forever, for a disclosure nobody asked to have remembered. `CampaignLetterList` uses a plain `useState<boolean>(false)` instead — the same pattern `nameExpanded` (`BillCreatorCampaignPositionCard`) and `phraseExpanded` (`ClaimedAffiliationEvidence`) already use nearby.

## Testimony coverage states and acknowledgement gate

[[app/frontend/components/admin/creator/llm-summary/LlmSummaryTestimonyCoverageNotice.tsx#LlmSummaryTestimonyCoverageNotice]] and [[app/frontend/components/admin/creator/testimony-report/TestimonyAcknowledgeButton.tsx#TestimonyAcknowledgeButton]] pair each testimony coverage state with fixed copy and gate position approvals until missing testimony is acknowledged.

When the clean-testimony stage has never run or newer hearing testimony has made the cleaned artifact stale, the notice reports raw character counts because the prompt fell back to the raw column. A failed stage reports letter counts from an earlier successful artifact when one exists, or falls back to raw character counts when the first-ever attempt failed with no artifact. On a cleaned artifact, the notice claims all letters reached the model only when both left-out letters and left-out characters are zero, since a letter counts as reached as soon as its first character enters the prompt budget.

When a coverage gap exists, [[app/frontend/components/admin/creator/testimony-report/TestimonyAcknowledgeButton.tsx#TestimonyAcknowledgeButton]] renders the acknowledgement button or switches in place to an acknowledged stamp once recorded, disabling while a run is in flight and echoing the coverage digest so the server can refuse stale submissions.

## How the pipeline testimony report renders coverage, campaigns, and pasted text

[[app/frontend/components/admin/creator/testimony-report/TestimonyReport.tsx#TestimonyReport]] combines [[app/frontend/components/admin/creator/testimony-report/TestimonyRecordBar.tsx#TestimonyRecordBar]], [[app/frontend/components/admin/creator/testimony-report/TestimonyCampaignTable.tsx#TestimonyCampaignTable]], individual letter counts, and [[app/frontend/components/admin/creator/testimony-report/TestimonyPasteNotice.tsx#TestimonyPasteNotice]] on the pipeline stage view.

While a clean-testimony run is in flight or after a failure, [[app/frontend/components/admin/creator/testimony-report/TestimonyReport.tsx#TestimonyReport]] keeps the last run's numbers visible under a stale header rather than hiding them behind a skeleton, omits the individual-letters block when unmeasured while rendering a sentence for a measured zero, and renders nothing when the bill has no testimony. [[app/frontend/components/admin/creator/testimony-report/TestimonyRecordBar.tsx#TestimonyRecordBar]] draws a static three-segment bar hidden from assistive technology above a visible summary sentence rather than using a live progress primitive, floors non-zero segments at one percent by subtracting the bump from the widest raw segment without DOM measurement, and omits the removed-text clause when nothing was removed.

[[app/frontend/components/admin/creator/testimony-report/TestimonyCampaignTable.tsx#TestimonyCampaignTable]] folds into a closed collapsible panel above eight rows, formats every row in its unnamed sender-count form, and reports kept added-word characters separately from the count of senders whose added words hit the bound. [[app/frontend/components/admin/creator/testimony-report/TestimonyPasteNotice.tsx#TestimonyPasteNotice]] states only character counts and budget share for operator-pasted testimony without echoing the pasted text, deriving the character limit from the reported character count and limit share.

## How CampaignMarker marks singleton domain drafts and bounds added words

[[app/services/testimony/campaign_marker.rb#CampaignMarker]] marks lone letters from confirmed sending-service domains as single-letter drafts on origin without merging them, and caps per-draft sender additions at `MAX_CAMPAIGN_ADDED_CHARS`.

Because two advocacy groups can use the same sending service on one bill to argue opposite positions, a confirmed domain never merges letters into a shared draft; multi-letter drafts come exclusively from [[app/services/testimony/campaign_draft_finder.rb#CampaignDraftFinder]]. A letter that joined no text-reuse draft but arrived from a confirmed sending-service domain becomes a singleton draft identified by its domain and position (`build_singleton_draft`), while `dominant_domain` records the plurality domain across a draft's members for the card's origin sub-line. `bounded_added_words` preserves senders' additions in letter-position order and stops at the first addition that would exceed `MAX_CAMPAIGN_ADDED_CHARS`, recording the remaining count in `senders_added_words_left_out` rather than silently trimming or sampling.
