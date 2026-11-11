---
mode: explanation
summary: "Explains why FetchBillsService prefers a Legistar Reader attachment over the most-recently-modified PDF, and the fallback ranking used when no Reader attachment exists."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Picking the primary PDF attachment for a bill

`FetchBillsService#select_primary_attachment` picks the PDF attachment that
actually holds the bill text, out of every PDF Legistar has on file for a
matter.

## Why "most recently modified" was the wrong rule

The old rule — take the attachment with the newest
`MatterAttachmentLastModifiedUtc` — reliably picked the WRONG document.
Supporting files (public testimony bundles, hearing packets, voting
records, agency reports) get uploaded and revised for months AFTER the bill
text is final, so the most recently changed attachment is almost never the
bill. For bill 25-0064 it chose a 12.4 MB "Public Testimony" bundle whose
text (about 352k tokens) was far more than the summarizer could read at
once.

## The Reader-attachment rule

Baltimore Legistar names the official bill text `"<bill>~Nth Reader"` (1st
Reader = the bill as introduced, 3rd Reader = the final, passed version).
`READER_NAME_PATTERN`'s capture group picks out the reading number.

`#select_primary_attachment` prefers a "Reader" attachment (Baltimore's word
for the official bill text), highest reading number first, which is the
bill in its most advanced form; ties break on latest modified. When there
is no Reader attachment at all — a just-introduced matter, a resolution, an
appointment — it falls back to `#best_non_testimony_pdf`.

## Why `#pdf_attachment?` asks the cleaned name, not the raw one

Legistar file names arrive with stray spaces and, rarely, a stray zero
byte, both of which sit AFTER the `.pdf` extension. Asking the raw string,
a real bill PDF called `"25-0064.pdf "` reads as not a PDF, gets dropped,
and the bill ends the run with no text at all — silently, because dropping
every PDF just looks like a matter that has none.
`Legislation::Paths.upstream_file_name` strips those characters and takes
the last path segment, which is the same name the download step later
writes to disk. `FetchHearingsService#pdf_attachment?` asks the same
question the same way; the two services disagreed about which files were
PDFs for a while, before that side was cleaned first and this one caught up.

## The fallback ranking when there is no Reader attachment

`#best_non_testimony_pdf` used to just take the newest-modified file — the
same rule the Reader-attachment section above calls out as wrong — and on a
matter with no Reader attachment, the newest PDF is usually testimony, so
the public summary ended up being written from a community letter.

`FALLBACK_CLASSIFICATION_PREFERENCE` ranks, best first:

- **`:bill_text`** — `Testimony::NameRules` recognised this as bill text. It
  can happen with no "Reader" match: `"cc25-0064(1)~1st (LUT)"` carries the
  reprint marker but never says the word "Reader".
- **`:undecided`** — unknown. Agency reports land here, and on an
  appointment or a resolution one of them may be the only real document.
- **`:procedural`** — hearing packets, voting records. Not bill text, but at
  least about this measure.
- **`:ambiguous_bill_text`** — a loose bill-text word ("reader", "signed",
  "amendment") on a name that ALSO looks like testimony. Ranked here on
  purpose, neither with `:bill_text` nor with `:undecided`: these names used
  to count as `:bill_text` and so won the TOP spot, which is how, on a
  matter with no Reader, "Baltimore Readers Alliance Testimony" became the
  bill's main document and the public summary was written from it. Plain
  `:undecided` would still have beaten a hearing packet. So: below anything
  that plausibly concerns the measure, above a document that says nothing
  but "testimony", because it does at least carry a bill-text word.
- **`:testimony`** — advocacy. Last resort, and the thing this ordering
  fixes.

`#best_non_testimony_pdf` takes the best kind of document available, and
within that group the one changed most recently — so when every candidate
for a matter falls in the same group, it behaves exactly like the old rule
and nothing gets worse.

It uses `Testimony::NameRules.classify` (the first two stages of
`Testimony::AttachmentClassifier`: no network, same answer every time)
rather than the full classifier, whose third stage calls a language model.
This runs inside the loop over every matter, so a model call per attachment
would cost a lot and would add a new way for a path that must keep working
without the LLM to fail. The full classifier is split into three steps for
that reason.

The final `pdfs.max_by { newest modified }` line is neither dead code nor a
formality: it is what happens if `NameRules` ever returns a label
`FALLBACK_CLASSIFICATION_PREFERENCE` does not mention. It is written as a
catch-all rather than a `fetch` on a `find` result, so adding a fifth label
falls back to the old behavior instead of raising in the middle of bill
discovery.
