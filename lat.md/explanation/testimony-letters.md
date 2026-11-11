---
lat:
  mode: explanation
---
# Reading the letters inside a testimony bundle

Baltimore publishes hearing testimony as PDF bundles holding many people's letters end to end, so Sway has to split one file into letters, decide who wrote each, and group the ones that are the same campaign.

See [[distributed-testimony-pipeline]] for the end-to-end flowcharts and model routing across `clean-testimony` and `summarize-bill`.

## Fixtures for extracted text are typed by hand

The spacing rule itself belongs to [[testimony-attachment-rules#Every fixed phrase matches through the extracted-text helper]]; what a test can use as evidence for it is a separate question.

The real attachment files carry residents' names, home addresses and personal
email addresses, and this repository has a public remote, so an example is
written from the shapes the extracted text takes rather than copied out of one
of them. The alternative is worse than inconvenient: a fixture that interpolates
the very constant being searched for proves only that the search can find a copy
of itself, which is what several of these examples did before real shapes were
typed in beside them.

A name is subject to the same rule. A two-word name can arrive with the line
break inside it, so a refusal that compares a name literally passes where it
should refuse.

## A broken glyph is recorded rather than repaired

A conversion artifact that cannot be resolved with confidence is marked as an
unresolved break and left in the text.

The question mark is the case that forced the distinction: it became a break
glyph in one corpus, and 60 runs on one bill corroborated 83% of them, every one
resolving to the same two letters. A sentence running straight into the next is
also exactly what a legitimate question mark produces, so rewriting it would
edit somebody's words. Seeing it as a candidate break and leaving it alone keeps
the artifact visible instead of invisible.

## The splitter is biased toward leaving letters joined

A merged pair of letters only undercounts. A wrong split invents a sender and writes their email domain into a shared table under this bill.

So a forward-or-reply marker is the one thing that disqualifies a split, and a
missing blank line above the marker is not: measured, 9 of 28 real markers lack
one and are genuine letters, because extraction loses blank lines. The mail
envelope is not reliably one blank-line-delimited block either, which is why
dropping "the first block" as the envelope connects two unrelated letters
through a shared recipient line. Instead, [[app/services/testimony/extracted_text.rb#ExtractedText]]
strips leading and trailing clerk print-header stub pages across form-feeds and
advances past any leading blank lines, forward/reply divider lines, or folded
page-number and clerk print-header lines before confirming an envelope header
field, while [[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover]]
strips two-line wrapped `On ... wrote:` quote markers when detecting empty
forwarding wrappers, refuses to treat multi-page (`\f`) segments, `MEMORANDUM`
blocks, or constituent testimony prose as disposable forwarding wrappers, and
[[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover#MUNICIPAL_OFFICE_FOOTER_PATTERN]]
excludes formal inside-address blocks beginning with `The Honorable` so council
addressee blocks at the top of constituent letters are preserved.

## Attachment boundaries and the five-page constituent ceiling

[[app/services/testimony/letter_splitter.rb#LetterSplitter]] splits across attachment boundaries and page-top letter cues, while [[app/services/testimony/extracted_text.rb#ExtractedText#MAX_CONSTITUENT_PAGES]] bounds constituent testimony at five pages.

Hearing bundles often concatenate standalone agency PDFs, corridor studies, and scanned written-testimony packets that contain no `From:` email headers at all. Because `mutool draw -F txt` terminates each extracted PDF with `"\f\n"` and [[app/services/fetch_hearings_service.rb#FetchHearingsService#compose_testimony_from_disk]] joins attachment sidecars with `"\n\n"`, every attachment boundary carries the exact sequence matched by [[app/services/testimony/letter_splitter.rb#LetterSplitter#ATTACHMENT_BOUNDARY]]. Splitting on that boundary prevents all pre-email attachments from merging into a single giant `Letter #0`, while [[app/services/testimony/letter_splitter.rb#LetterSplitter#fold_print_header_stubs]] and [[app/services/testimony/letter_splitter.rb#LetterSplitter#collapsible_print_header_stub?]] (backed by [[app/services/testimony/extracted_text.rb#ExtractedText]], bounded by [[app/services/testimony/extracted_text.rb#ExtractedText#TRAILING_PRINT_HEADER_MAX_CHARS]] and [[app/services/testimony/extracted_text.rb#ExtractedText#TRAILING_PRINT_HEADER_MAX_LINES]], ignoring middle-initial periods while exempting `From:` headers, [[app/services/testimony/extracted_text.rb#ExtractedText#BODY_OPENING]] salutations, and stance keywords) fold page-number and clerk print-header stubs forward into an immediately following `From:` segment or at the start of the bundle (or backward into the preceding segment when no `From:` segment follows), and [[app/services/testimony/extracted_text.rb#ExtractedText]] strips folded leading or trailing stub pages during envelope stripping so they never leak into campaign `added_words` or duplicate body hashes.

Formal memoranda (`MEMORANDUM`, `To:`, `From:`, `Date:`) and written-testimony headings also carry a `From:` line that is part of the memo heading rather than an email envelope. [[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover#MEMO_HEADER_LINE_PATTERN]] suppresses a `From:` split when `MEMORANDUM`, a written-testimony title, or at least two memo header fields (`To:`, `Date:`, `Re:`, `Subject:`) precede `From:` within [[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover#MARKER_LOOKBACK_LINES]] lines (or `To:` precedes `From:` and `Date:`/`Re:`/`Subject:` immediately follows `From:`) on a page with no earlier `From:` marker and no `Sent:` line immediately after `From:`, or when a single memo field line appears near the top of that page, keeping the memo's heading attached to its body even below a multi-line agency letterhead without suppressing a subsequent email after a constituent letter that signs off with `Date:`.

When a single attachment or post-email tail spans more than [[app/services/testimony/extracted_text.rb#ExtractedText#MAX_CONSTITUENT_PAGES]] effective non-empty pages on [[app/services/testimony/extracted_text.rb#ExtractedText]], [[app/services/testimony/letter_splitter.rb#LetterSplitter#split_overlong_segment]] walks `\f` page breaks. For non-`From:` packets, it rejects pages opening with an appendix or exhibit divider (`Appendix`, `Exhibit`, `Attachment`, `Table`, `Figure`, `Chart`, `Section`, `Part`, `Chapter`) and starts a new entry whenever a page's first [[app/services/testimony/letter_splitter.rb#LetterSplitter#PAGE_TOP_LOOKAHEAD_LINES]] non-empty lines (with leading `&nbsp;` entities stripped, stopping before any long continuing prose sentence) carry at least two memo header fields or match [[app/services/testimony/letter_splitter.rb#LetterSplitter#PAGE_TOP_LETTER_CUE]] — requiring an uppercase opening letter across greetings, salutations, memoranda, position headers, open letters, and written testimony headings while ignoring spillover closing blocks. For `From:`-headed segments, it keeps cover emails and attached constituent letters together so `sender_address` is never severed. Whenever a constituent letter is open (either a `From:`-headed segment or a constituent letter opened inside a non-`From:` packet), it detaches an unheaded multi-page report appendix when the remaining unheaded pages exceed [[app/services/testimony/extracted_text.rb#ExtractedText#MAX_CONSTITUENT_PAGES]] and either five pages have elapsed or [[app/services/testimony/letter_splitter.rb#LetterSplitter#report_appendix_start?]] (after stripping trailing `\f` and whitespace from the current letter's preceding pages) detects an attachment cue or closing sign-off followed by an all-caps report title or study section opening (`Page 1`, `Section 1`, `Executive Summary`, `Table of Contents`, `Introduction`, `Background`, `Methodology`, or `Appendix`).

Even after splitting, a standalone planning study, slide deck, or multi-page report can remain longer than five pages without carrying an explicit agency phrase. [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService#group_by_reuse]] (via [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService#overlong_letter?]]) and [[app/services/testimony/browsable_letters.rb#BrowsableLetters#for_bill]] therefore exclude any entry exceeding [[app/services/testimony/extracted_text.rb#ExtractedText#MAX_CONSTITUENT_PAGES]], ensuring that overlong reports neither bridge constituent letters inside [[app/services/testimony/campaign_draft_finder.rb#CampaignDraftFinder]] nor surface as individual constituent letters on bill pages.

## What a letter says about who is speaking

The rules capture the bare organization name on its own, separately from the phrase that named it.

The frontend seeds an editable name box from that capture, so shipping the whole
"role of the org" phrase there would have an unedited Approve create an
organization named after somebody's job title. The capture keeps a leading
"the" where the source text has one; stripping it is not this layer's job. The
finalized evidence has to carry the bare name through alongside the phrase, the
role and the sender, or the box has nothing but the sentence to work from.

Every letter also carries a kind drawn from a fixed four-value list, and one
whose kind cannot be decided reads as a person speaking for themselves. That is
the safe fallback: the corpus is mostly campaign template copies signed with a
name and a home address, and defaulting to an organization would publish a
private individual as one.

## The same letter can arrive twice

A hearing bundle is composed by concatenating every attachment with no deduplication, so the same sender's same letter published at two hearings on one bill arrives as two letters.

`Testimony::DuplicateLetterMarker` marks the second and any later occurrence.
The repeat is excluded from the letter and sender counts an operator approves —
by the campaign marker and by the domain panel alike, so the two surfaces cannot
disagree about one bill — while staying in the group's letter positions, so the
draft still shows that it arrived twice. Two copies typically differ only in a
`Sent:` line, and an unrelated letter sharing no phrase with either must not be
pulled into their group.

## How CleanAndGroupService orders and threads the cleaning steps

[[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService]] runs `STEP_ORDER` from character repair through banner removal, splitting, sender reading, reuse grouping, campaign marking, domain counts, classification, and entity extraction.

Character repair must run before [[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover]] because the city IT banner itself contains broken ligatures in raw extraction and matches only after repair; both must finish before splitting and sender extraction so domains are not split across unrepaired characters. Each step shares a uniform `(text, letters, groups)` dispatch signature via `run_step`, and `TRANSIENT_LETTER_KEYS` (`added_words` and `excluded_from_drafts`) are dropped after [[app/services/testimony/campaign_marker.rb#CampaignMarker]] consumes them so the stored `cleaned_testimony` JSON neither duplicates every letter's text nor leaks transient grouping flags.

[[app/services/testimony/stance_classifier.rb#StanceClassifier]] stamps each letter with its position-specific stance (`support`, `oppose`, or `neutral`) and records aggregate stance counts into the artifact's counts. When a letter exceeds [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder#MAX_LETTER_CHARS]], both [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder]] and [[app/services/testimony/stance_classifier.rb#StanceClassifier]] preserve the first [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder#HEAD_LETTER_CHARS]] and last [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder#TAIL_LETTER_CHARS]] characters so closing calls to action (`"Please vote NO or at least abstain from voting."`) are never truncated away. [[app/services/testimony/stance_rules.rb#StanceRules]] provides deterministic lexical stance classification for explicit subject/position headers and unambiguous support or opposition directives (with negation guards and mixed-signal return of `nil`) whenever the LLM returns `neutral`, falls below confidence, or is unavailable, while manual stance overrides (`"stance_override" => true` set via [[app/controllers/bills_controller.rb#BillsController#testimony_letter_stance]]) are preserved across subsequent [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService]] runs by normalized body digest. [[app/services/testimony/organization_entity_extractor.rb#OrganizationEntityExtractor]] runs as step 11 in `STEP_ORDER`, extracting structured organization identities and one-sentence position summaries for non-repeat nameable letters into `extracted_org`. Running entity extraction after source-kind classification and duplicate marking ensures that constituent letters speaking for themselves and repeat copies bypass extraction, preventing unnecessary model invocations.

The clean-testimony stage routes its three model-driven steps through specialized purpose configurations to minimize inference costs while matching task modality. Source-kind and stance classification route through `purpose: :decision`, dispatching closed-set evaluations to specialized classification models (`ScaleDown Classify Latest` via [[app/models/admin_setting.rb#AdminSetting]]). Organization entity extraction routes through `purpose: :extraction`, dispatching schema-constrained entity decoding to specialized extraction models (`ScaleDown Extract Latest` via [[app/models/admin_setting.rb#AdminSetting]]). This purpose routing keeps the clean-testimony map stage aligned with low-cost ScaleDown models, isolating expensive general-purpose chat routes for downstream synthesis.

### Lexical stance rules and head-tail windowing

[[app/services/testimony/stance_rules.rb#StanceRules]] classifies explicit header declarations and unambiguous body calls to action deterministically, while [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder]] windows long letters across their head and tail.

Constituent letters often place their explicit stance in a subject or position header (`Subject: Oppose Bill 25-0169`, `Position: Favorable with Amendments`) or at the very end of a multi-paragraph personal narrative (`"Please vote NO or at least abstain from voting."`). Truncating a long letter strictly at the first [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder#MAX_LETTER_CHARS]] characters discards the closing paragraph where the call to action sits, causing the model to misclassify clear opposition or support as `"neutral"`. Preserving the first [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder#HEAD_LETTER_CHARS]] and final [[app/services/testimony/stance_prompt_builder.rb#StancePromptBuilder#TAIL_LETTER_CHARS]] characters keeps both the opening framing and the concluding directive in the prompt.

Similarly, when the classification model returns `"neutral"`, falls below [[app/services/testimony/stance_classifier.rb#StanceClassifier#MIN_DECISION_CONFIDENCE]], or is unavailable, [[app/services/testimony/stance_classifier.rb#StanceClassifier]] consults [[app/services/testimony/stance_rules.rb#StanceRules]]. `StanceRules.classify` separates explicit stance headers (`Position:`, `Stance:`) from subject headers (`Subject:`, `Re:`, `Bill:`, `Testimony:`) so bill titles containing words like `"Support"` or `"Against"` (`Bill 25-0200 - Peer Support Services`, `Protection Against Discrimination`) never trigger false positives, and combines header verdicts with stripped-body directives while guarding against negations (`do not support`, `cannot support`, `do not oppose`) and returning `nil` whenever header and body signals or opposing body directives conflict.

### Manual stance overrides

[[app/controllers/bills_controller.rb#BillsController#testimony_letter_stance]] records an operator's manual stance override or manual letter removal on a cleaned testimony letter, and [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService]] preserves those overrides across subsequent cleaning runs.

When an operator changes a letter's stance or clicks Remove in [[app/frontend/components/bill/BrowseTestimonyModal.tsx#BrowseTestimonyModal]] (either on `/admin/bill_creator/:id/positions` or while signed in as an admin on a bill page), `PATCH /bills/:id/testimony_letter_stance` validates a non-negative integer `position`, locks the bill's [[app/models/bill_llm_provisioning.rb#BillLlmProvisioning]] row, updates the target letter's `"stance"` (or sets `"excluded" => true` when removing the letter) alongside `"stance_override" => true`, recomputes `stance_support_count`, `stance_oppose_count`, and `stance_neutral_count` in `cleaned_testimony["counts"]` excluding removed letters, and redirects back to the originating page (with `only: ["public_testimony_counts", "public_testimony_letters", "flash"]` on the client so optional modal props remain populated). [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService]] keys `"stance_override" => true` and `"excluded" => true` letters by `[sender_address, digest]` (with a digest-only fallback when `sender_address` is blank or all letters sharing that digest carry the same override) and merges overrides both before [[app/services/testimony/stance_classifier.rb#StanceClassifier]] and again against the reloaded provisioning row right before persisting `cleaned_testimony`, while [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]] skips manually excluded letters in the prompt and credits them as reached so manual removal never triggers a coverage gap.

## Why SenderDomain and SenderReader enforce separate address and domain contracts

[[app/services/testimony/sender_reader.rb#SenderReader]] accepts any dot-containing token after `From:` within a bounded header window, while [[app/services/testimony/sender_domain.rb#SenderDomain]] restricts stored domains to RFC-1035 lowercase hostname characters.

Most extracted letters place the sender address on the lines following `From:`, so `SenderReader` scans up to `WINDOW_LINES` lines and stops early at `NEXT_HEADER_FIELD` (`To:`, `Sent:`, `Subject:`) so recipient headers are never misread as the sender. Keeping `Result#address` even when `SenderDomain.from_address` rejects the domain preserves the sender evidence needed by [[app/services/testimony/source_kind_rules.rb#SourceKindRules]], while preventing malformed or empty domains from reaching `SendingServiceDomain`.

## Selecting browsable constituent letters

[[app/services/testimony/browsable_letters.rb#BrowsableLetters]] extracts non-repeat constituent letters speaking for themselves, stripping mail envelope headers and unwrapping PDF line breaks while excluding internal correspondence, manually removed letters, and campaigns unless marked as individual letters.

When `cleaned_testimony_at` predates `testimony_fetched_at`, `BrowsableLetters` returns an empty list so stale byte offsets cannot slice misaligned raw text. Constituent privacy requires that trailing print-header stub pages, leading forward/reply divider wrappers (including two-line wrapped `On ... wrote:` markers), mail envelope headers (`From:`, `Sent:`, `To:`, `Subject:`), and residual recipient headers are stripped from letter bodies via [[app/services/testimony/extracted_text.rb#ExtractedText]], and that any appearance of the sender email address in the body is stripped out. Standalone unaddressed print-header stubs, internal staff routing notes, administrative government correspondence matching [[app/services/testimony/browsable_letters.rb#BrowsableLetters#GOVERNMENT_SENDER_DOMAIN_PATTERN]], and letters whose body text becomes blank after stripping are skipped; remaining letters have their hard PDF visual line breaks and artificial mid-sentence double-spacing unwrapped into clean paragraphs via [[app/services/testimony/extracted_text.rb#ExtractedText]] (preserving opening salutations, bullet lists, headings, and closing sign-off blocks) and receive sequential 1-based labels (`"Constituent Letter #1"`, `"Constituent Letter #2"`) ordered by ascending testimony position.

Eligibility restricts letters to those where `source_kind` is `person_speaking_for_self`, with manually excluded letters (`excluded` true), repeat copies (`repeat` true or `repeat_of_position` present), and entries exceeding [[app/services/testimony/extracted_text.rb#ExtractedText#MAX_CONSTITUENT_PAGES]] excluded. Letters originating from campaigns (`campaign_origin` true) remain excluded by default, but are included when their campaign draft group identifier is present in [[app/models/bill_llm_provisioning.rb#BillLlmProvisioning#individual_campaign_draft_hash_list]], provided that draft identifier has not been rejected in [[app/models/bill_llm_provisioning.rb#BillLlmProvisioning#rejected_campaign_draft_hash_list]] and does not match an approved campaign on [[app/models/campaign.rb#Campaign]]. Approving a campaign via [[app/services/approve_campaign_position_service.rb#ApproveCampaignPositionService]] clears any prior individual or rejected draft hash via [[app/models/bill_llm_provisioning.rb#BillLlmProvisioning#restore_campaign_draft!]]. To prevent performance degradation on bill pages, queries against campaigns on [[app/models/bill.rb#Bill]] are avoided entirely when no campaign drafts have been marked individual.

### Filtering internal staff routing notes and government correspondence

[[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover]] and [[app/services/testimony/browsable_letters.rb#BrowsableLetters]] prevent municipal staff correspondence from surfacing as public constituent testimony.

When council staff forward constituent emails to the legislative clerk (`Subject: Fw: ...`), they frequently prepend a one-line transit note such as `"Good morning, please add to the bill file."` or `"Please include in the bill folder."` Because `"Good morning"` and `"bill"` match general testimony prose cues in [[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover#TESTIMONY_PROSE_PATTERN]], an unguarded prose check would keep the staff wrapper as its own segment or block `forward_wrapper?` from stripping it. When a segment carries a forward/reply or government-envelope cue, matching short bodies (≤[[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover#MAX_INTERNAL_ROUTING_NOTE_CHARS]] characters, ≤[[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover#MAX_INTERNAL_ROUTING_NOTE_LINES]] lines) against [[app/services/testimony/boilerplate_remover.rb#BoilerplateRemover#INTERNAL_ROUTING_NOTE_PATTERN]] while verifying that no testimony stance or salutation signal is present strips these transit notes cleanly without discarding constituent or organization letters.

Similarly, internal emails sent from municipal, state, or federal government staff addresses (`@baltimorecity.gov`, `@baltimorecouncil.com`, `@baltimorepolice.org`, `@bcps.k12.md.us`, `@maryland.gov`, `@mgaleg.maryland.gov`, `@mdcourts.gov`, `@state.md.us`, `@mail.house.gov`, `@senate.gov`) often lack the formal all-caps agency letterhead required by [[app/services/testimony/source_kind_rules.rb#SourceKindRules]] and fall through to `person_speaking_for_self`. Checking the sender domain against [[app/services/testimony/browsable_letters.rb#BrowsableLetters#GOVERNMENT_SENDER_DOMAIN_PATTERN]] combined with administrative correspondence cues in [[app/services/testimony/browsable_letters.rb#BrowsableLetters#GOVERNMENT_ADMIN_CORRESPONDENCE_PATTERN]] (unless the writer explicitly speaks in a personal resident capacity, such as `"as a resident"` or `"not for my employer"`) excludes internal government correspondence from public constituent browsing while leaving operators a manual Remove control in [[app/frontend/components/bill/BrowseTestimonyModal.tsx#BrowseTestimonyModal]] for any non-testimony correspondence from external domains.

## Browsing constituent testimony in the modal

[[app/frontend/components/bill/BrowseTestimonyModal.tsx#BrowseTestimonyModal]] presents constituent letters filtered by stance with lazy Inertia fetching and client-side pagination.

When the modal opens without preloaded letters (or when `letters` is a stale array whose length no longer matches `counts.total` before the current open cycle's fetch settles), it requests `public_testimony_letters` (wrapped in `InertiaRails.optional` on both [[app/serializers/bill_page_resource.rb#BillPageResource]] and [[app/controllers/bills_controller.rb#BillsController#public_testimony_letters_prop]]) via Inertia partial reload without touching scroll position, settling into an empty state if the reload finishes or errors with no letters. Readers can toggle between stance tabs — All, Support, Oppose, and Neutral — each displaying its respective count badge within a Radix `TabsContent` panel.

Each letter card renders its constituent label alongside a semantic `Badge variant="stamp"` (`success`, `danger`, or `neutral` tone) and full-opacity `text-foreground` body copy on `bg-card` so long constituent letters meet AA contrast across every theme and mode. When `canOverrideStance` and `billId` are provided (on the Bill Creator Positions tab or when an admin views a bill page), each letter card also renders a stance selector and a Remove button that dispatch `PATCH /bills/:id/testimony_letter_stance` to record a persistent manual stance override or exclude the letter from testimony. Paginating at ten letters per page prevents large hearing bundles from degrading browser performance, while switching stance tabs or clamping against updated letter counts keeps pagination within valid bounds. The phone shows the same letters in its own sheet, paged the same size ([[mobile-bill-surface-components-design#BrowseTestimonySheet]]).

The phone does not rebuild the whole bill payload to read the letters. [[mobile/src/hooks/usePublicTestimony.ts#usePublicTestimonyLetters]] requests `GET /bills/:id/public_testimony_letters`, which [[app/controllers/bills/public_testimony_letters_controller.rb#PublicTestimonyLettersController#index]] answers with only the array that [[app/serializers/public_testimony_letter_resource.rb#PublicTestimonyLetterResource]] builds from [[app/services/testimony/browsable_letters.rb#BrowsableLetters]], the same entries the optional prop carries. The controller is open to any reader, so it is not on the admin-gated list. It finds the bill the way [[app/controllers/bills_controller.rb#BillsController#set_bill_for_show]] does, archived bills included and with no locale, active or release filter, so it exposes the letters of exactly the bills the bill page opens. An unknown id is a 404, and the route answers JSON only: a request that asks for HTML gets a 406. The optional prop on [[app/serializers/bill_page_resource.rb#BillPageResource]] and the JSON omission header stay for installed app versions that still read the letters from the bill body.

## Presenting public testimony on bill pages

[[app/frontend/components/bill/PublicTestimonySection.tsx#PublicTestimonySection]] renders constituent testimony counts below organization positions across `BillContent` and the themed bill layouts.

When no public constituent letters exist or counts total zero, the section returns null to preserve zero visual footprint. When constituent letters exist, readers see total letter counts, stance filter pills for support, oppose, and neutral perspectives, and an action button to open [[app/frontend/components/bill/BrowseTestimonyModal.tsx#BrowseTestimonyModal]] with the chosen filter active.

The support, oppose, and neutral filter pills use semantic theme tokens (`border-success bg-success/12 text-success`, `border-destructive bg-destructive/12 text-destructive`, and `border-border-strong bg-surface-2 text-foreground`) rather than raw palette classes or `dark:` media-query variants, ensuring legible contrast when the operating system appearance and Sway's active theme mode differ.

### Signed-out readers receive no public testimony

The bill page and the Bill of the Month page send public testimony counts and letters only when `current_user` is present; a signed-out reader gets `nil` for both.

The gate lives in [[app/serializers/bill_page_resource.rb#BillPageResource]], which both pages and their `/api` JSON twins render through, so the letters never reach page HTML, Inertia partial reloads or bearer-less JSON. The one other route that sends letters, [[app/controllers/bills/public_testimony_letters_controller.rb#PublicTestimonyLettersController#index]], applies the same rule itself and answers a signed-out reader with a `null` body. The key set stays the same for every reader — only the values go `nil` — so the serializer key-set contract does not split by auth state. The website's client needs no gate of its own: [[app/frontend/components/bill/PublicTestimonySection.tsx#PublicTestimonySection]] already renders nothing when counts are absent, and that covers `BillContent` and every themed layout at once.

No sign-in prompt replaces the section; the page shows no trace of it to a signed-out reader. The mobile app does check in the client as well: both bill screens pass `useSession().isAuthenticated` to [[mobile/src/components/PublicTestimonySection.tsx#PublicTestimonySection]] as `isSignedIn`, and the Summaries tab shows constituent letters only when that flag is true and the counts hold at least one letter ([[mobile-bill-surface-components-design#PublicTestimonySection]]).

The admin Bill Creator builds its own `public_testimony_counts` and letters in [[app/controllers/bills_controller.rb#BillsController#public_testimony_letters_prop]]; those routes are admin-only and are not affected.

### Database query pruning on signed-out bill page requests

Omitting testimony letters for signed-out readers allows the server to skip eager-loading hearing provisioning models.

Because signed-out visitors receive `nil` for both public testimony counts and letters, the controller lookups in [[app/controllers/bills_controller.rb#BillsController#set_bill_for_show]] omit `:bill_llm_provisioning` from the eager-load includes. For authenticated readers, the association is loaded when accessed by [[app/services/testimony/browsable_letters.rb#BrowsableLetters]], preserving request performance for anonymous visitors without increasing database overhead.

## Extracting organization entities per letter

[[app/services/testimony/organization_entity_extractor.rb#OrganizationEntityExtractor]] extracts structured organization identities and argument summaries per non-repeat nameable letter using constrained entity decoding.

While `person_speaking_for_org` letters capture regex-based `source_evidence`, `named_organization` and `public_body` letters contain no regex-derived identity fields. Extracting canonical organization names and one-sentence position summaries during the `clean-testimony` stage distributes the synthesis burden, allowing downstream position prompts to receive concise organizational hints rather than parsing entire letters from scratch.

Entity extraction dispatches to the configured extraction route (`purpose: :extraction`, defaulting to `ScaleDown Extract Latest` via [[app/services/llm/open_router_adapter.rb#OpenRouterAdapter#generate_entity_extraction]]). To preserve opening letterhead and closing sign-off while staying within model character bounds, letters exceeding 6,000 characters are windowed to their first 4,500 and final 1,500 characters. Letters classified as `person_speaking_for_self`, marked as repeats (`repeat: true`), or manually removed (`excluded: true`) bypass extraction entirely to prevent wasted model queries and keep removed correspondence out of organizational hints. When extraction encounters model errors or blank responses, the service records an extraction fallback and falls back to regex `source_evidence`, preserving pipeline resilience.

### Decoupling extraction from downstream positions synthesis

Pre-extracting organizations in the clean-testimony map stage prevents token starvation and tail truncation in downstream summary generation.

When a bill receives an extensive hearing bundle containing dozens of organization letters, bundling raw letter bodies into a single position-generation prompt risks exceeding prompt token budgets. By extracting structured `extracted_org` metadata (`org_name` and `summary`) during cleaning, the pipeline equips downstream prompt builders to format concise letter headers. This enables partitioning testimony across chunked map-reduce payloads without dropping late-arriving letters.

The clean-testimony stage records extraction telemetry directly in `cleaned_testimony["counts"]`, tracking letters populated with a non-blank `extracted_org["org_name"]` (`org_entity_extracted_letters`, whether via the extraction model or `source_evidence` fallback) and letters where model extraction fell back (`org_entity_extraction_fallbacks`). Downstream coverage reporting verifies that all nameable testimony letters are accounted for, preventing false coverage gaps while ensuring complete constituent reach.

### Extraction fallback and telemetry accounting

Extraction failure degrades gracefully to regex extraction while recording explicit observability metrics.

When the extraction LLM route is unavailable, rate-limited, or returns unparseable or blank output, `OrganizationEntityExtractor` avoids raising unhandled exceptions that could abort the entire bill ingestion pipeline. Instead, it logs the failure and falls back to regex-derived `source_evidence` extracted from the letter body.

Pipeline accounting recorded in `cleaned_testimony["counts"]` separates output population from model fallback behavior. Letters populated with a non-blank `extracted_org["org_name"]` — whether produced by the extraction model or by `source_evidence` fallback — are counted in `org_entity_extracted_letters`, while every letter where model extraction fell back is counted in `org_entity_extraction_fallbacks`. This granular instrumentation ensures operator visibility into LLM extraction health across automated hearing runs.

### Windowing oversized entity extraction targets

Windowing preserves critical letter framing while respecting token budgets.

Organization testimony frequently arrives as extensive multi-page submissions or comprehensive policy whitepapers. When passing oversized documents into entity extraction, preserving the opening letterhead (identifying the organization and author) and the concluding signature block (identifying affiliations and titles) is paramount. `OrganizationEntityExtractor` therefore applies a 6,000-character window (4,500 characters of head text and 1,500 characters of tail text) separated by an explicit omission marker, ensuring that both essential identity boundaries are available to the extraction model.

### Prompt enrichment and reach accounting in position synthesis

`BillPositionsPromptBuilder` incorporates pre-extracted organizational hints into nameable letter labels while omitting constituent letters and repeats from synthesis prompts.

Attributing organization positions to private citizens speaking for themselves contradicts policy attribution invariants and consumes model context. Excluding `person_speaking_for_self` letters and duplicate repeats from the prompt payload concentrates LLM reasoning on genuine organization submissions.

To ensure downstream coverage auditing reflects true ingestion reach, excluded constituent and repeat letters are credited as reached in `#labeled_reach`. `Testimony::CoverageReport` evaluates this reach against overall testimony volume, verifying that coverage warnings indicate genuine token starvation rather than intentional filtering of non-organizational letters.
