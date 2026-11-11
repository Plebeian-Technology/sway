---
mode: explanation
summary: "Explains why the Summary tab's testimony attachment lists only show documents that need an answer from a person, never a full inventory."
status: agent-extracted
related: [admin-mirror-display-vs-identity.md]
---

<!-- vale Vale.Spelling = NO -->

# Why the testimony attachment screen only lists problems

The Summary tab does not list every hearing document behind a bill. It
lists the ones that need an answer from a person: text that never arrived,
text that was cut short, text carried over from an earlier run, or a
document the classifier judged is not testimony. A document that was read
whole needs nothing, so nothing is drawn for it.

That design choice means a list that only ever renders problems is a list
whose empty state nothing else can check. `LlmSummaryTestimonyAttachmentWarning`
and its sibling components draw nothing at all when every row is clean, so
a suite that only exercises the problem rows would pass on a screen that
reports healthy documents as problems just as easily as on a correct one.
Proving the "all clear" case — that a bill with only cleanly read
attachments renders none of the four lists — needs an example of its own,
separate from the ones that stock each list with a problem row.

## The fixture keeps the testimony-mirror rule intact

`spec/system/admin_testimony_attachments_spec.rb`'s fixtures keep the
mirror rule `BillLlmProvisioning` states: the attachment list describes the
stored testimony, so the row whose extraction succeeded is the row whose
text is in `extracted_testimony`. A fixture pairing a "succeeded"
extraction status with no testimony text describes a state the pipeline
can never actually reach.

## Why the absence assertion is scoped to the Summary tab

Inertia writes the whole prop payload into the document, so a file name
that is not drawn anywhere is still in the page's text — an unscoped
`have_no_text` can never pass for it, and would read as the component
being wrong when it is not. The example asserting that a cleanly-read
document is reported nowhere therefore scopes that check to
`[data-testid='summary-and-positions-tab']`, the container everything the
tab draws sits under.

## Testing that the attachment list arrives with no reload

"Nothing needs a browser refresh" was part of the original expectation for
this screen and was never pinned anywhere until
`spec/system/admin_testimony_attachments_spec.rb`'s "lists the documents a
hearing fetch brought in, with no reload" example. The write it waits for
is the one `FetchHearingsService` actually makes: the testimony text and
the attachment mirror that describes it, saved together.

The example leaves the pipeline run RUNNING throughout, which is what puts
the five-second poll timer on this tab —
`SummaryGenerationPoller` mounts while a pipeline run is going (see
[summary-tab-pipeline-running-poll-fallback.md](summary-tab-pipeline-running-poll-fallback.md)).
Take that reason away and the example fails, because a finished summary
with no run in progress is neither generating nor missing, and nothing
else asks the server again.
