---
mode: explanation
summary: "Why no phrase can be compared literally against machine-extracted document text, and what Testimony::ExtractedText relaxes and deliberately does not relax."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Matching phrases in machine-extracted text

`Testimony::ExtractedText` is the one place that turns a phrase written with
ordinary spacing into a pattern that finds the same phrase in machine-extracted
document text.

## Why a literal comparison fails

Spacing in extracted text is an artifact of the converter, not of what anyone
wrote. Measured over the ten stored attachment files: every line
ends with one to three trailing spaces, the same sentence wraps in different
places from one document to the next, and single spaces come back doubled.

So no phrase in this module's callers may be compared literally. A literal
"on behalf of" misses the three real occurrences broken across a line, and a
literal city IT banner missed all 405 of its occurrences.

## What is relaxed, and what is not

Words are escaped and joined by "any run of whitespace". Nothing else is
relaxed. A caller that needs a bound on what may sit BETWEEN two phrases still
writes that bound itself — `Testimony::SourceKindRules` embeds
`phrase_source` between its own bounds for exactly that reason.

This is a deliberate floor rather than a convenience. Relaxing more here would
make every caller's pattern quietly looser than the caller intended, and the
callers are the ones deciding what counts as a match.

## The two header-line helpers

`header_line_pattern` matches the phrase wherever a line opens with it. It is
the one definition behind "a letter's header begins with `From:`", which
`Testimony::LetterSplitter`, `Testimony::SenderReader` and
`Testimony::CampaignDraftFinder` each used to spell out separately.

`header_line?` is narrower: it is true only when the text's OWN opening is the
header line, not a later line inside it. That is what `CampaignDraftFinder`'s
envelope-block guard needs, and the distinction is easy to lose — a text whose
second line starts with `From:` matches the pattern and must still be refused
by the offset check. A test that exercises `header_line?` with a mid-line
`From:` proves nothing, because the pattern's own `^` anchor already rejects
that case and the offset check never runs.

## Telling a real letter's header from a forwarded one

`LetterSplitter` decides whether a column-zero `From:` starts a new letter or
sits inside a forwarded message pasted into the previous letter's body. Both
shapes are textually identical at the splitter's grain: Outlook and Exchange
write a forwarded header at column zero, with no indentation, and (unlike a
`>`-prefixed quoted reply) it is itself preceded by a blank line — so "require
a blank line before `From:`" cannot separate the two. A real letter's header
and a forwarded one look the same from where the splitter stands; the only
distinguishing signal is what sits in the few lines just above, which is where
a mail client leaves its own forward-or-reply marker
(`-----Original Message-----`, `Begin forwarded message:`, `On ... wrote:`, or
a bare Outlook-style underscore rule).

**A missing blank line disqualifies nothing**. The blank-line
requirement was added alongside the marker rule anyway, as a second guard, and
measured afterwards it was doing nearly all of the rejecting: across three real
Baltimore bills, 9 of 28 column-zero `From:` markers were rejected for want of
a blank line and **not one** for a forward marker. On 25-0058 that was 5 of 6,
taking a seven-letter bill down to two — and with it the bill's only campaign
draft, four letters that vanished into their neighbours. A bill can look
campaign-free purely because its letters were merged. Extraction loses blank
lines; the marker is the signal, and it stands alone.

A bare **dash** rule is deliberately excluded from that marker set. This
codebase's own synthetic testimony bundles (`campaign_bundle.txt`,
`no_campaign_bundle.txt`) use a 40-dash line as an ordinary divider between
unrelated letters, in exactly the position — blank line, rule, blank line,
`From:` — a forwarded header's rule would also sit. Treating a dash rule as a
forward marker would collapse every letter in those bundles into one. Only an
underscore rule counts, because that is the character Outlook actually writes;
dashes stay a no-op for this check.

**The bias is deliberate and asymmetric.** When the splitter cannot tell
whether a `From:` starts a real letter, it does not split.

Merging is not free. Two letters wrongly merged undercount the testimony, and
the second writer's words are read as part of the first writer's letter, so
they are attributed to a person who did not write them.

Where the marker rule genuinely cannot tell, a merge is still the better
error. A wrong split invents a sender who never wrote in, and that invented
sender's domain is what `Testimony::DomainCountsWriter` writes into the
sending-service domain table shared across every bill — a fabricated fact that
outlives the run that created it, on a table no later run re-derives. A merge
is wrong inside one bill's artifact and is recomputed the next time the stage
runs; a fabricated domain row is neither.

That asymmetry justifies erring toward merging **when the two shapes are
genuinely indistinguishable**. It does not justify adding guards that merge on
a signal which does not distinguish them at all — that trades a bounded,
recomputed error for a large one, and the blank-line guard above is exactly
how that goes wrong. A ten-bill average (19 of 1,790, about 1%) made it look
cheap; the per-bill rate was 32%, and 83% on one bill.

## Stripping the mail envelope by field, not by block

`CampaignDraftFinder#paragraphs_for` and `DuplicateLetterMarker#body_paragraphs` both
need a letter's body with its mail envelope removed — comparing two copies of
the same letter must never fail merely because they carry different `Sent:`
timestamps, and comparing two unrelated letters must never succeed merely
because they share the same `To: City Council <...>` recipient line. Both call
`ExtractedText.strip_envelope`, which drops lines from the start of the text by
what they are (a member of a fixed allowlist of real mail header field names:
`From`, `Sent`, `Date`, `To`, `Cc`, `Bcc`, `Subject`, `Reply-To`, `Importance`,
`Attachments`) rather than assuming the envelope is exactly one
blank-line-delimited block.

The allowlist matters as much as the line-by-line approach. The generic shape
"a short word followed by a colon" also matches the city IT banner's
`CAUTION:` and `Reminder:` lines; a consumer that crossed a blank line on that
generic shape would eat two banner lines as if they were envelope fields.
Using real field names is what keeps `strip_envelope` from reading past the
envelope into the letter's own text.

`strip_envelope` crosses one blank run inside the envelope only when the next
non-blank line is itself a recognized field — this is what correctly drops a
`To:` line separated from `Sent:` by a stray blank line, closing the shape
where the old block-based drop left `To: City Council <...>` (identical across
every letter in a bill) as the surviving first "paragraph," linking every
letter in the bill into one reuse draft. It also stops consuming the instant
the next non-blank line is not a recognized field — which is what keeps a
letter's own opening line (`Dear Council Members,` immediately after
`Subject:`, with no blank line between them) from being thrown away before
anything is ever compared.
