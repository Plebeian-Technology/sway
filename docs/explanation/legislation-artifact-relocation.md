---
mode: explanation
summary: "Why Legislation::ArtifactRelocationService exists to move pre-jurisdiction-segment artifact files rather than delete them, and how it decides each file's owning locale without guessing."
status: agent-extracted
related: [legislation-path-segment-safety, legislation-path-root-resolution]
---
<!-- vale Vale.Spelling = NO -->

# Why Legislation::ArtifactRelocationService moves files instead of deleting them

`Legislation::ArtifactRelocationService` moves artifact files written
before paths gained a jurisdiction segment into the folder the code now
reads.

## Why there is anything to move

A bill's files no longer live under its number alone; they live under the
jurisdiction name too. Two cities can
both number a bill 25-0064. Sharing one folder meant one city's testimony
could be assembled into the other city's summary. The code moved. Files
written earlier did not, so every file already on disk sat where nothing looks for
it. Fetching hearings on its own was impossible for every bill that
already existed — the stage could be picked and could not succeed.

## Why move rather than delete

The classifier's saved answers were re-keyed in the same change and old
rows deleted: that table is a cache, every row re-derivable in seconds,
with no jurisdiction. Neither half of that reasoning holds here.
Re-deriving means downloading every bill again, and the jurisdiction is NOT
a guess — each file names a bill, and the bill names its jurisdiction.

## What it refuses to do

Nothing is deleted and nothing is overwritten. A file whose owner can't be
named, or whose destination is taken, is left where it is and reported by
name with the reason. Guessing a jurisdiction is the one mistake this whole
change exists to prevent, so a file that cannot be placed stays unplaced.
Running it twice does nothing the second time: after a pass there is
nothing left at the old shape to find.

`BILL_KEYED_TREES` deliberately omits `law`: `Legislation::Paths.law` takes
no `sway_locale`, because a law corpus belongs to a jurisdiction's whole
code rather than to one bill, so nothing under it moved.

## How a file's owning locale is found

`#locale_segments` reads every jurisdiction name that already names a
folder off the database rather than off the shape of the name, so a
jurisdiction whose name looked like a bill number could not be swept into
itself. `name` is worked out from city, region, and country rather than
stored, so the rows have to be loaded rather than plucked — there are a
handful of jurisdictions, so that costs nothing. Matching one of these
names means an entry is a destination, not something to move; that is how
a second run knows it has nothing to do.

An attachment file is named after a Legistar attachment id, not a bill, so
its owner is found the other way: the provisioning row that downloaded it
names the bill, which names the jurisdiction. `#locale_for_attachment_id`
compares the id as TEXT because that is how it is stored: every entry in
`testimony_attachments` carries `"attachment_id"` as a string, not
an integer. Comparing it as a number matches
nothing, silently, and every file would be left behind with a reason that
reads like missing data.

`#move` takes the placement (a `[segment, reason]` pair) whole rather than
pulled apart in the parameter list, because the type checker reads a
destructuring parameter as two arguments and rejects the call. A missing
segment always arrives with a reason — `#resolve_single_locale` writes the
two together — but the checker reads the pair as two independent values, so
`#move`'s fallback names the impossible case (`"no jurisdiction could be
named"`) rather than recording a file with an empty reason beside it.

## Why the report keeps moved and left-behind counts apart

`Legislation::ArtifactRelocationReport` keeps MOVED and LEFT apart on
purpose. A count of files moved says nothing about the ones that were not,
and those are the only ones that still need attention. Every left-behind
entry carries the reason in words, because "3 skipped" in a deploy log is a
number nobody can act on — `#left_lines` produces one line per left-behind
file so a deploy log names what still needs looking at rather than only how
much succeeded.
