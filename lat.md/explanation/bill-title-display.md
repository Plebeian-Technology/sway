---
lat:
  mode: explanation
---
# How a bill's title is shown

A stored bill title is not what a reader is shown. Baltimore's titles carry a legal enacting clause after the subject, so every surface prints the subject and treats the rest as a qualifier.

The clause beginning "FOR the purpose of" appears on most bills, which means it
distinguishes almost nothing. The raw titles average hundreds of characters and
the longest runs to thousands.

## Why the qualifier is kept rather than discarded

The part after the subject is still the bill's own wording, so a layout that
has room sets it in a lighter weight beside the subject rather than dropping
it.

That keeps the heading scannable by subject while leaving the full text
readable, and the list and the detail page use matching treatments so a reader
moving between them sees the same title in the same shape.

## Where only the subject is shown

Some places cannot take a qualifier at all: an option label, a dialog heading,
and a chart label read aloud to somebody using a screen reader.

Those take a single line of plain text with no markup. It has to produce the
same words the list heading renders, or a picker and a list end up disagreeing
about a bill's name. The screen-reader case is what makes the length matter
rather than merely look untidy — a label thousands of characters long is read out in full.

Native mobile app screens follow the same rule across their surfaces: the bill
header at the top of detail and Bill of the Month views, bill list cards,
voting confirmation sheets, and organization position pickers render only the
headline. Full bill titles are too lengthy for phone screens and crowd out
status, counts, and actions.

The one exception is the Bill tab of the detail and Bill of the Month views,
which also carries the full stored title in an "As introduced" block when the
title holds more than its headline, a deck after a dash or the enacting clause
([[mobile-bill-surface-components-design#BillAsIntroduced]]).
The block sits below the summary rather than in any header, so the headline
stays the title everywhere a reader scans.

## Which outbound messages carry the shortened title

Every message Sway sends about a bill carries the subject alone: the Bill of
the Month announcement, the voting reminder, and an organization's change of
position, each on every channel it goes out over.

That is a text message and a web push and a native push for the announcement,
a text message for the reminder, and all three again for a position change.
The shortening produces the same words the list heading renders, so a reader
who follows a notification into the app sees the title they were sent.

A text message is the channel that forces the question. It is billed and
capped by the carrier per 160-character segment, and a title that averages
hundreds of characters spends that budget several times over before the sentence
around it is counted. A carrier rejects the whole message once the
concatenated body passes its ceiling — 1,600 characters where the body is
plain ASCII, 700 where a single character outside the GSM-7 set forces the
two-byte encoding. The en dash that separates subject from qualifier on many
titles is one such character, so the tighter ceiling is the usual one.

Push has neither limit, and an earlier version of the position fan-out kept
the stored title there for that reason. Sending one wording on one channel and
another on the next is the worse trade: a reader who has both sees the same
event described two ways, and the subject is the part they recognise.

The daily and weekly digests name organizations rather than bills, so no bill
title reaches them and there is nothing to shorten.

### Why the earlier segment measurement did not describe real traffic

The wording of these messages was once tuned against the seed corpus, where
titles run 35 to 54 characters, and that measurement is what
`docs/explanation/sms-notification-service-design.md` still records.

Seeded titles are short because they are written by hand. Imported ones are
not, and the gap between a title of tens of characters and one of hundreds is the whole budget several
times over, so a calculation showing a comfortable single segment described no
message that was ever sent to a subscriber. Such a message can be rejected by
the carrier for content size.

Shortening the title moves the variable part of the body from hundreds of
characters to tens, which is what makes a measurement against real titles
meaningful at all.
