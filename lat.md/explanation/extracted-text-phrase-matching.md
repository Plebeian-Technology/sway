---
lat:
  mode: explanation
---

# Matching phrases in machine-extracted text

`Testimony::ExtractedText` is the one place that turns a phrase written with ordinary spacing into a pattern that finds the same phrase in machine-extracted document text.

## Why a literal comparison fails

Spacing in extracted text is an artifact of the converter, not of what anyone wrote.

Measured over the ten stored attachment files: every line ends with one to three trailing spaces, the same sentence wraps in different places from one document to the next, and single spaces come back doubled.

So no phrase in this module's callers may be compared literally. A literal "on behalf of" misses the three real occurrences broken across a line, and a literal city IT banner missed all 405 of its occurrences.

## What is relaxed, and what is not

Words are escaped and joined by "any run of whitespace".

Nothing else is relaxed. A caller that needs a bound on what may sit BETWEEN two phrases still writes that bound itself — `Testimony::SourceKindRules` embeds `phrase_source` between its own bounds for exactly that reason.

This is a deliberate floor rather than a convenience. Relaxing more here would make every caller's pattern quietly looser than the caller intended, and the callers are the ones deciding what counts as a match.

## The two header-line helpers

`header_line_pattern` matches the phrase wherever a line opens with it.

It is the one definition behind "a letter's header begins with `From:`", which `Testimony::LetterSplitter`, `Testimony::SenderReader` and `Testimony::CampaignDraftFinder` each used to spell out separately.

`header_line?` is narrower: it is true only when the text's OWN opening is the header line, not a later line inside it. That is what `CampaignDraftFinder`'s envelope-block guard needs, and the distinction is easy to lose — a text whose second line starts with `From:` matches the pattern and must still be refused by the offset check. A test that exercises `header_line?` with a mid-line `From:` proves nothing, because the pattern's own `^` anchor already rejects that case and the offset check never runs.

## Telling a real letter's header from a forwarded one

`LetterSplitter` decides whether a column-zero `From:` starts a new letter or sits inside a forwarded message pasted into the previous letter's body.

Both shapes are textually identical at the splitter's grain: Outlook and Exchange write a forwarded header at column zero, with no indentation, and (unlike a `>`-prefixed quoted reply) it is itself preceded by a blank line — so "require a blank line before `From:`" cannot separate the two. A real letter's header and a forwarded one look the same from where the splitter stands; the only distinguishing signal is what sits in the few lines just above, which is where a mail client leaves its own forward-or-reply marker (`-----Original Message-----`, `Begin forwarded message:`, `On ... wrote:`, or a bare Outlook-style underscore rule).

**A missing blank line disqualifies nothing**. The blank-line requirement was added alongside the marker rule anyway, as a second guard, and measured afterwards it was doing nearly all of the rejecting: across three real Baltimore bills, 9 of 28 column-zero `From:` markers were rejected for want of a blank line and **not one** for a forward marker. On 25-0058 that was 5 of 6, taking a seven-letter bill down to two — and with it the bill's only campaign draft, four letters that vanished into their neighbours. A bill can look campaign-free purely because its letters were merged. Extraction loses blank lines; the marker is the signal, and it stands alone.

A bare **dash** rule is deliberately excluded from that marker set. This codebase's own local-only testimony bundles (`campaign_bundle.txt`, `no_campaign_bundle.txt`, see [[lat.md/explanation/testimony-fixtures]]) use a 40-dash line as an ordinary divider between unrelated letters, in exactly the position — blank line, rule, blank line, `From:` — a forwarded header's rule would also sit. Treating a dash rule as a forward marker would collapse every letter in those bundles into one. Only an underscore rule counts, because that is the character Outlook actually writes; dashes stay a no-op for this check.

**The bias is deliberate and asymmetric.** When the splitter cannot tell whether a `From:` starts a real letter, it does not split.

Merging is not free. Two letters wrongly merged undercount the testimony, and the second writer's words are read as part of the first writer's letter, so they are attributed to a person who did not write them.

Where the marker rule genuinely cannot tell, a merge is still the better error. A wrong split invents a sender who never wrote in, and that invented sender's domain is what `Testimony::DomainCountsWriter` writes into the sending-service domain table shared across every bill — a fabricated fact that outlives the run that created it, on a table no later run re-derives. A merge is wrong inside one bill's artifact and is recomputed the next time the stage runs; a fabricated domain row is neither.

That asymmetry justifies erring toward merging **when the two shapes are genuinely indistinguishable**. It does not justify adding guards that merge on a signal which does not distinguish them at all — that trades a bounded, recomputed error for a large one, and the blank-line guard above is exactly how that goes wrong. A ten-bill average (19 of 1,790, about 1%) made it look cheap; the per-bill rate was 32%, and 83% on one bill.

## Stripping the mail envelope by field, not by block

`CampaignDraftFinder#paragraphs_for` and `DuplicateLetterMarker#body_paragraphs` both need a letter's body with its mail envelope removed.

`CampaignDraftFinder#paragraphs_for` and `DuplicateLetterMarker#body_paragraphs` both need a letter's body with its mail envelope removed — comparing two copies of the same letter must never fail merely because they carry different `Sent:` timestamps, and comparing two unrelated letters must never succeed merely because they share the same `To: City Council <...>` recipient line. Both call `ExtractedText.strip_envelope`, which drops lines from the start of the text by what they are (a member of a fixed allowlist of real mail header field names: `From`, `Sent`, `Date`, `To`, `Cc`, `Bcc`, `Subject`, `Reply-To`, `Importance`, `Attachments`) rather than assuming the envelope is exactly one blank-line-delimited block.

The allowlist matters as much as the line-by-line approach. The generic shape "a short word followed by a colon" also matches the city IT banner's `CAUTION:` and `Reminder:` lines; a consumer that crossed a blank line on that generic shape would eat two banner lines as if they were envelope fields. Using real field names is what keeps `strip_envelope` from reading past the envelope into the letter's own text.

`strip_envelope` crosses one blank run inside the envelope only when the next non-blank line is itself a recognized field — this is what correctly drops a `To:` line separated from `Sent:` by a stray blank line, closing the shape where the old block-based drop left `To: City Council <...>` (identical across every letter in a bill) as the surviving first "paragraph," linking every letter in the bill into one reuse draft. It also stops consuming the instant the next non-blank line is not a recognized field — which is what keeps a letter's own opening line (`Dear Council Members,` immediately after `Subject:`, with no blank line between them) from being thrown away before anything is ever compared.

## Handling multiline envelope headers and forwarded wrappers

Extracted PDF text strips RFC 822 indentation from wrapped mail headers and precedes forwarded testimony with transit envelopes.

In PDF extracts from municipal testimony, `To:` and `Cc:` recipient lists commonly span a dozen lines containing every council member and the mayor. Because document extraction drops leading whitespace, these continuation lines start at column zero. [[app/services/testimony/extracted_text.rb#Testimony#ExtractedText|Testimony::ExtractedText]] recognizes continuation lines holding email addresses, council role tags, and trailing list separators without matching ordinary prose sentences that happen to contain commas or mention the council.

[[app/services/testimony/extracted_text.rb#Testimony#ExtractedText|Testimony::ExtractedText]] also strips multiline `To:`, `Cc:`, and `Bcc:` blocks inside envelopes while ignoring mid-body prose lines that open with `To:`. When [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder|BillPositionsPromptBuilder]] strips recipient headers from a letter that fits inside the prompt budget, it credits the letter's full stored length toward reached characters so [[app/services/testimony/coverage_report.rb#Testimony#CoverageReport|Testimony::CoverageReport]] never mistakes removed header characters for truncated testimony.

When council offices or staff members forward constituent testimony to legislative mailboxes, a forwarding envelope sits above the constituent's email, often accompanied by an office signature block, a brief transit note, or an Outlook divider line.

Because footers vary across council members and staff, [[app/services/testimony/boilerplate_remover.rb#Testimony#BoilerplateRemover|Testimony::BoilerplateRemover]] strips municipal office signatures, meeting request links, device footers, confidentiality notices, and forwarding wrapper segments ahead of the underlying constituent `From:` header, including short internal staff routing notes (`"Good morning, please add to the bill file"`, `"Please include in the bill file"`, `"See attached"`) via `INTERNAL_ROUTING_NOTE_PATTERN`. [[app/services/testimony/letter_splitter.rb#Testimony#LetterSplitter|Testimony::LetterSplitter]] pairs each segment's start and end offsets before filtering out forwarding wrappers so a mid-bundle wrapper is never appended to the preceding constituent letter, while preserving short constituent letters that carry `Fw:` in their subject line.

## Unwrapping PDF visual line breaks in browsable letter bodies

[[app/services/testimony/extracted_text.rb#Testimony#ExtractedText|Testimony::ExtractedText]] unwraps hard PDF visual line breaks and mid-sentence double-spacing into continuous paragraphs via `unwrap_body_paragraphs` while preserving salutations, lists, headings, and sign-offs.

When municipal clerks print constituent emails to US Letter PDFs and `TestimonyTextExtractor` extracts the text with `mutool draw -F txt`, every visual line on the PDF page ends with a literal `\n` (and page boundaries emit `\f`). If the constituent's original email or web-form submission was wrapped at 115–125 characters per line before printing to a ~104-character PDF page, each original line breaks into a long ~104-character line followed by a short 10–25 character overflow line (`"is going"`, `"5 houses on BOTH sides"`). Some PDFs also insert a blank line (`\n\n`) between every visual line mid-sentence or split a sentence across a `\f` page break and page number. Rendering those raw newlines inside a narrower modal card with `whitespace-pre-wrap` produces jagged, double-wrapped sentences.

`unwrap_body_paragraphs` normalizes zero-width characters and line separators, drops empty or clerk print-header stub pages across `\f` boundaries along with standalone edge page numbers, collapses artificial single blank lines where the preceding line ends mid-sentence without terminal punctuation, and joins consecutive prose lines within each paragraph with a single space. Intentional line breaks are preserved whenever a line is an opening salutation (including short first-line greetings such as `"Mayor Scott- and Coucilman"`), a bulleted or numbered list item, a metadata or all-caps heading, or a closing sign-off (`"Sincerely,"`, `"Respectfully,"`, `"Thank you,"`) and the signature lines beneath it.

To prevent wrapped mid-sentence prose from masquerading as structural breaks:
- Opening salutations (`OPENING_SALUTATION_LINE_PATTERN`) without trailing colons or commas are recognized only on the very first line of the letter body, so mid-paragraph wrapped lines beginning with `"Mayor"`, `"Councilmember"`, or `"Chair"` still unwrap into the surrounding sentence.
- Closing sign-off transitions (`CLOSING_SIGNOFF_LINE_PATTERN` and `closing_signoff_transition?`) require the sign-off phrase to anchor the full line and follow terminal sentence punctuation or a short line (`<= 60` characters), preventing wrapped lines starting with `"best interest..."` or `"thank you for holding this evening hearing..."` from splitting the paragraph or locking subsequent lines into a sign-off block.
- Metadata headings (`METADATA_HEADER_LINE_PATTERN` and `metadata_or_heading_line?`) reject lines starting with lowercase letters, lines longer than 90 characters, and lines ending with sentence punctuation so mid-sentence phrases like `"testimony on this bill..."` unwrap normally.
