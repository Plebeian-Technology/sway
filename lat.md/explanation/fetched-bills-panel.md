---
lat:
  mode: explanation
---

# What has actually been fetched to disk

`BillCreator::FetchedBillsPanelSerializer` fills the admin Bill Creator's fetched-bills list. It reports what is sitting on disk across every bill in a locale, whether or not any pipeline run recorded it.

Before this panel existed, seeing what had been fetched meant logging into the
server or opening a Rails console.

## Why it reads the disk rather than the database

It lists every bill with files under
`legislation/bills/raw/<sway_locale>/<external_id>/`, the tree
`FetchBillsService` writes into.

A folder with no matching `Bill` row still gets a row, with `bill_id` left nil.
Showing those stranded downloads is the whole point of the panel — a database
listing could not, because the database is exactly what they are missing from.
Reading one segment too shallow listed the locale folders themselves and no
bills at all, silently, which is why the spec builds its fixture
paths through `Legislation::Paths` — the same builder `FetchBillsService` writes
through — rather than spelling the layout out a second time where it could drift.

## Why it is scoped to one locale

Only the asked-for locale's own subtree is read, never the whole raw root.

Every row is stamped with the locale it was asked for, so sweeping all of them
would report one city's stranded downloads as another city's. An unusable locale
name comes back as "nothing on disk" rather than raising, because this feeds an
admin panel and one bad row must not take the page down.

## Why the walk is done with Dir and File rather than Pathname

The folder is read once per bill with `Dir.children`, and modification times are
taken with `File.mtime` against plain path strings.

The panel's cost grows with every bill ever fetched and is never reclaimed,
because nothing prunes the tree. `Pathname` turns each of those entries into an
object, and the original walk asked for the same folder three times over — a
glob for the PDFs, a second read for everything else, and a `directory?` plus
read for the attachments. With a couple of hundred bill folders that came to
tens of thousands of object allocations, a large share of the admin page's time. One read answers all three questions, because the PDF names
and the presence of `metadata.json` are both already in the list of entries.

`fetched_at` still means the newest modification time of any file under the
folder, and is still read file by file. Taking the folder's own modification
time instead would be far cheaper and quietly wrong: a directory's timestamp
moves when entries are added or removed, not when one is rewritten in place.

## Why the row carries no attachment count

The row says whether a bill's PDF and its metadata are on disk, and nothing about attachments, because a bill's folder never holds any.

`FetchBillsService#persist` writes exactly two things into `legislation/bills/raw/<sway_locale>/<external_id>/`: the primary PDF and `metadata.json`. Hearing attachments live under a different root entirely, `Legislation::Paths.attachment_dir`, keyed by the sway locale and the Legistar attachment id — the filename carries no `external_id` at all, which is why `ArtifactRelocationService` says an attachment file is named after an attachment id and not a bill.

The panel nevertheless counted files in an `attachments/` subfolder of the bill's own directory and reported the result, so every row in production read zero and always had. The only thing in the repository that ever created that subfolder was the spec's own fixture, which invented a layout production never produces and then asserted against it.

Counting from the database was rejected: attachments reach a bill only through the classification rows indexed on sway locale and attachment id, which is a join per row on a panel that already walks every folder on disk. Renaming the key to count the sway locale's attachment files was rejected too, because the same number would then repeat on every row of the table and say nothing about the bill each row names.
