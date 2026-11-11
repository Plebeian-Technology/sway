---
lat:
  mode: explanation
---

# Legislation artifact backup

The pipeline's downloaded and rendered files sit on one disk on one machine, unlike the database, which is replicated continuously. A dedicated cloud bucket holds a second copy of that tree.

The bucket's name is not written down in this repository. It arrives through
deploy config the same way the database bucket's name does, because the tracked
tree is public and a bucket name describes a deployment's cloud account.

## Why the lifecycle rules match only noncurrent versions

`deploy/gcs/legislation-lifecycle.json` removes superseded object versions and never live ones. The `isLive: false` condition carried by every rule is what enforces that.

The bucket keeps versions, and in a versioned bucket a `Delete` action against a
live object does not remove it — it archives it as a noncurrent version. A rule
without that condition would therefore turn each current backup into a
noncurrent one scheduled for its own deletion, and the bucket would empty itself
on a delay rather than fail in a way anyone would notice.

The retention clock is `daysSinceNoncurrentTime` rather than `age` for a related
reason. `age` counts from the moment an object was created, so a file written
two years ago and superseded yesterday reads as 730 days old while holding the
only prior copy of something that has just changed. Counting from the moment a
version was superseded measures the interval the retention window is about.

A second rule bounds versions by count as well as by age. Conditions within one
rule combine with AND and separate rules with OR, so a version is removed once
it has been superseded for ninety days, or once five newer versions exist. The
count rule is the bound on a defect that rewrites one file repeatedly.

## Why the application's credentials cannot delete

The service account the application authenticates as holds object create and object view on this bucket, and deliberately not object admin.

The backup path only ever adds files, so deletion is an ability it never needs,
and withholding it means a defective sweep or a mistaken prefix cannot destroy
the copy the bucket exists to hold. Retention still happens, because lifecycle
rules are carried out by the storage service itself rather than by the caller,
and are unaffected by what the application's own credentials permit.

## Why the bucket name is resolved on use rather than on load

`Legislation::ArtifactBucket` asks deploy config for the bucket name when an upload or a listing needs it, rather than in a constant evaluated while the class body loads.

The database backup service resolves its bucket into a class-level constant, and
that shape is wrong here. Deploy config raises when a value is absent, so a
constant turns absence into a load-time failure: a console session, a rake task
or a background job that merely names the class stops before it does anything,
and on a developer machine the legislation bucket is normally not configured at
all. Resolving on use moves the failure to the moment something genuinely tries
to reach the bucket, which is the point at which the missing value actually
matters.

Production loses nothing by the change. `config/initializers/deploy_values.rb`
requires the name while the application starts, so a deployment without it still
stops immediately rather than hours later. The literal
`SwayDeployConfig.fetch("SWAY_GCS_BUCKET_LEGISLATION")` stays spelled out in the
source because the deploy-values gate finds names by reading that exact call out
of the tracked files.

The constructor also accepts a bucket name, which is how a test drives the
adapter without any deploy configuration present and without naming a real
bucket in a public repository.

## Why the walk asks the paths helper for each root

`Legislation::ArtifactBackupService::ROOTS` names each artifact root by the `Legislation::Paths` method that answers where it is, rather than by a path rebuilt from the base root.

Seven roots are separately overridable, and each one falls back to a directory
under the base only while its own override is empty. A walk that rebuilt
`bills/text` from the base would look somewhere the pipeline never wrote as soon
as that root was pointed elsewhere, and an override may name any absolute path
on the machine, including one outside the base entirely.

What follows is quiet rather than loud. A root nothing was written to holds no
files, so the walk finds none, copies none, and finishes without an error —
which from the outside is indistinguishable from a tree that was already fully
copied.

Bucket keys stay keyed by the logical root rather than by the path on disk for
the related reason. A remainder taken against the base would be a string of
`..` segments for a root that lives elsewhere, while the same remainder taken
against the root the file was found under is always clean, and a restore into an
empty directory reproduces the default layout from it.

## Why the bucket is listed once and a failed listing stops the run

One paginated listing per run is held in memory and compared against the walk locally, and a listing that raises ends the run rather than standing in for an empty bucket.

The tree holds thousands of files. Asking the bucket about each of
them separately would be thousands of round trips over a small machine's
uplink on every run, where one listing is a few pages of names, sizes and
timestamps held for the length of the run.

`DatabaseBackupService` rescues its own listing to an empty array, and that is
right there: its listing feeds pruning, so an empty answer means nothing is old
enough to remove and the run simply skips retention. Here an empty answer means
the opposite — that the bucket holds none of those twelve thousand files — so
the run would copy the entire tree again, and again on every later failure.
Stopping leaves the existing copy alone and turns the outage into a status the
run reports rather than a bill it silently runs up.

## Why the walk ignores the atomic-write temporary files

`Legislation::AtomicWrite` leaves a dot-prefixed sibling named after its destination for the duration of a write, and the walk recognises those by their name and passes over them.

A file in the tree is either an artifact or one of these, and nothing about the
file itself separates a write happening at this moment from one abandoned by a
process that died. Its name is the only signal available, so the name is what
the walk goes by.

The cost of taking one is permanent rather than passing. The application never
deletes from this bucket, so a stale temporary file copied once is kept until
the lifecycle rules expire it, and a restore would put a fragment of a
half-written file back on disk beside the real one.

They are counted rather than dropped in silence, because a growing number of
them is the visible symptom of writes that keep dying.

## Why a file whose size matches is copied again when the local one is newer

A local file is copied when the bucket holds no object for it, when the two sizes differ, or when its content differs from the stored object's.

Size alone was the first test, and it rests on artifacts being written once.
That is nearly true and not quite: a pipeline re-run rewrites a bill's text or
its diffs, and a rewrite landing on the same byte count would leave the stored
object exactly as it was the day it was first copied, with nothing anywhere
recording that the two had diverged. The second copy is defeated in the one case
that is hardest to notice.

The modification time was the next test, because the listing already returned
`created_at` and a version created before the local file was last written cannot
hold what the local file holds now. It cannot tell a changed file from a
rewritten one, and it trusts two things that need not hold: that the local clock
agrees with the bucket's, and that nothing set the time back. `cp -p`, an
archive extraction and a restore all do, and a file changed behind a restored
time reads as untouched.

[[legislation-artifact-backup#Why a rewrite with identical bytes is not copied again]]
replaces that test with the stored object's MD5. The modification time is now
read only for an object whose listing carries no MD5, which GCS omits for a
composite object. For those the old reading stands: the file is copied when it
was modified after the stored version was created, and an object whose creation
time is absent counts as older, because reading a missing value as a reason to
copy errs toward the outcome that can still be undone.

The bucket keeps versions and its lifecycle rules bound them at five newer
versions or ninety days superseded, so a file whose bytes really changed costs a
bounded number of stored copies, while an edit that is never noticed is not
recoverable at all.

## Why a rewrite with identical bytes is not copied again

A file at the same size as its stored object is copied only when its MD5 differs from the one the bucket listing already carries, whatever either timestamp says.

Every copy is a billed write, and a Nearline bucket's writes cost twice a
Standard bucket's. A pipeline re-run rewrites a bill's text, diffs or
prompt dumps with the bytes it wrote the day before, which moved the
modification time and nothing else, so each run paid to store a version that
held what the previous version already held.

The listing carries each object's MD5 at no extra request, so the comparison
adds no call to the bucket. The price is local: every file whose size already
matches is read and hashed on every run, because a timestamp cannot stand in for
the content. That is disk reading across the whole tree and nothing sent over
the uplink, and it is cheaper than a bucket write.

Matches are counted in `skipped_identical_count`, separate from the
`skipped_present_count` of files kept by the timestamp rule, so a run's log shows
how many files were proven the same by content.

## Why a file that vanishes mid-walk does not stop the run

Each entry the walk finds is examined inside its own rescue, so a file that disappears between the glob and the stat is counted and passed over rather than ending the pass.

A glob answers with the names that existed when it ran, and every question asked
afterwards — whether the entry is a symlink, its real path, its size, its
modification time — reaches the disk again. Any of them raises `Errno::ENOENT`
once the file is gone. Without the rescue a single vanished file would abort a
walk of roughly twelve thousand, and the pass would upload nothing.

The window is small, because artifacts are written through
[[legislation-pipeline]]'s atomic rename and so never disappear mid-write, and
temporary files are excluded by name before anything that can raise. It is not
empty: a relocation or a cleanup running beside the backup can remove a file the
glob has already named. On an unattended daily schedule that would be a loud
failure for a cause that does not matter, since the next pass copies the file if
it still exists.

The count is reported rather than swallowed. A pass that skips a handful of
vanished files is ordinary; one that skips thousands means something else is
removing the tree while the backup reads it.

## Why a run checks what it found against a floor taken from the database

A pass that walks the wrong directory finds nothing, uploads nothing and finishes without complaint, which from outside is indistinguishable from a tree already fully copied. A floor separates the two.

The floor is the number of bills whose extracted text is stored, and it is
compared against the count found under the `bills/text` root alone rather than
against the grand total. `RunLegislationPipelineJob` sets that column and writes
the matching file in the same method, so every row counted implies one file. A
count of all bills would not: a seeded bill that never ran the pipeline has no
artifact, and the floor would be unreachable for ever. Nothing else in the schema
records what the tree holds.

Comparing one root against a floor derived from that root is what makes the check
honest. It catches a wrong `LEGISLATION_ROOT` and a wrong
`legislation_bills_text_root` alike, and it covers finding nothing at all, since
zero falls below any positive floor. It says nothing about whether the files it
found are intact, which is a question only a restore answers.

A floor of zero asserts nothing and an empty walk passes. A database with no
extracted text genuinely implies no artifacts, and a check that failed there
would fail on every fresh machine.

The loudness has a cost worth stating. An operator who deletes regenerable
`bills/text` files turns every run red until they are regenerated. That is the
intended behaviour rather than a fault to soften: the whole point is that a run
which cannot see the tree refuses to report success.

## Why the restore destination has no default

A restore writes files, and the one directory it must never write into is the live tree the bucket exists to protect. The destination is therefore a required keyword with no default, and the service never guesses it.

Three separate refusals stand between an operator and an overwritten tree. The
first is the missing default: omitting the destination is an `ArgumentError`
raised by Ruby itself, so no code path exists that could quietly resolve to the
live tree. The second is a containment check against
`Legislation::Paths.root` and all seven overridable roots, which raises
`LiveTreeRefused` naming the path it refused. The third is a per-object check,
described in the next section.

The containment check runs in both directions on purpose. A destination inside a
root would overwrite part of the tree; a destination that holds a root would
overwrite the whole of it once a bucket key happened to match. Comparing only one
way would catch half the cases. The seven roots are consulted individually rather
than being assumed to sit under the base root, because each can be pointed
anywhere on disk, and a restore aimed at a relocated root would then look
harmless.

The keyword `allow_live_tree` is the escape, and it is deliberately awkward to
reach: the rake task does not offer it, so writing over the live tree takes a
console session and a caller who spells the intention out. The ordinary recovery
path is a restore into an empty directory followed by a separate, deliberate
move, which is described in [[restore-the-legislation-artifacts]].

## Why every object name is checked again before it is written

The destination is checked once, when the service is built. What lands under it
depends on names that arrived from the bucket, so each one is checked again in
the moment before its download.

A local path is built by removing the prefix from the object name and joining the
remainder to the destination. A remainder that is absolute, or that holds a `..`
segment, resolves somewhere the destination check never approved, so both are
refused, as is a name that does not carry the expected prefix at all. Nothing in
the current backup path can produce such a name; the check exists because the
names are data from a remote service, and the cost of trusting them is measured
against a tree that has no second copy.

Refused names are counted in the report rather than swallowed, and the rest of the
listing is still written. One malformed name is a curiosity; thousands would mean
the prefix or the bucket is not what the caller believed.

## Why a restore fetches one object at a time

The adapter's `download` takes a single object name and a single local path,
rather than leaning on the shared storage module's whole-directory helper.

`download_directory` rebuilds each local path from the entire object name,
including the prefix. A restore through it would land the tree under
`<destination>/legislation/<environment>/…` instead of reproducing the layout the
pipeline reads, and the result would not serve as a `LEGISLATION_ROOT` without
being moved again. Fetching one object at a time also keeps a single failure
local: it is recorded and the listing continues, exactly as a failed upload does
on the way out.

## Why the destination is resolved through its symlinks

A restore destination is followed through any symlink before it is compared against the live tree, because expanding a path resolves `..` and `~` but leaves a link pointing wherever it points.

The refusal exists to stop a restore writing over the only copy of the tree it is
meant to protect. A destination given as a link into that tree expands to its own
harmless-looking name, matches none of the live roots, and passes — after which
every downloaded object lands on the original.

Resolution walks up to the nearest ancestor that exists and takes its real path,
because a destination is usually a directory that has not been created yet and a
path that does not exist has no real path of its own.

## Why the sweep runs daily rather than as often as the database backup

The artifact sweep is scheduled once a day, where the database backup runs every six hours.

The two cost different amounts to attempt. A database backup copies one file; a
sweep lists a whole bucket prefix and walks thousands of paths before
it can decide that nothing has changed, so the cadence is set by what an
unproductive run costs rather than by how fresh the copy needs to be.

## Why the scheduled backup carries a cron monitor

`BackupLegislationArtifactsJob` checks in against a Sentry cron monitor and raises on any pass that did not finish clean, so a backup that has stopped working is a standing red state rather than a silence.

The two ways this job fails quietly are exactly the ones an error event cannot
express. A listing that keeps failing, and a walk that keeps falling below its
floor, are conditions rather than moments: each run reports the same thing, and
grouped error events read as one fault that may already have stopped. A job that
stops being scheduled at all emits nothing to group. The reasoning is
[[scheduled-job-monitoring]]'s, and this job is the third to follow it.

The margin is an hour on a daily schedule, which is wider than the run needs.
A pass that finds nothing to copy takes seconds, but the first pass after a
locale is seeded uploads gigabytes over a slow uplink, and a margin tight
enough to suit the ordinary case would page on the useful one.

The job raises rather than returning quietly when a pass ends `:listing_failed`
or `:floor_not_met`, and also when a pass ends `:ok` while individual uploads
failed. A pass that copied most of the tree and lost some of it is not a success,
and the count that matters is on the report rather than in the exception.

## Why a run's cost tracks its file count rather than its size

Uploads happen one object at a time, so wall-clock time follows the number of files far more closely than the total bytes, and the two estimates diverge sharply on a tree of many small files.

Byte throughput alone predicts a first run much shorter than the object count
does, because the mean file is small and each object carries a fixed request
overhead on top of its own transfer.

The difference decides whether a first backup is an afternoon or a day, so a
size-based estimate is the wrong instrument for planning one. It also locates
where a speed-up would have to come from: the transfer is nowhere near
saturating the link, so overlapping requests is the lever, and compressing the
payload is not.

A later run is cheap regardless. The walk compares each file against the single
listing taken at the start and uploads only what is missing or newer, so the
count that matters after the first pass is the number of files that changed.

## An incomplete backup needs its object failures identified

The planned incomplete-backup diagnosis recovers the failed object names and bounded exception reasons before choosing a repair. Aggregate upload counts establish that the backup is incomplete, not why it failed.

ArtifactBackupService records each failure in `report.failed` and local
`legislation_artifact_backup.upload_failed` logs. `BackupLegislationArtifactsJob`
includes bounded failed-object details (up to five entries plus an overflow count)
in the logged error and raised `BackupIncomplete` exception message, distinguishing
transport, filesystem or bucket-policy failures directly from Sentry.

## Why the monitor is told how long a run may take

The monitor config names a `max_runtime`, unlike the two shorter jobs that carry monitors, because a first backup can legitimately run for hours and an unset ceiling leaves the collector to pick one.

`MonitorConfig#to_h` compacts a nil `max_runtime` out of the payload, so leaving
it unset does not mean "no limit"; it means whatever limit the collector applies
by default. `ReplicationLagCheckJob` and `RefreshLegislatorsCacheJob` finish in
seconds, so the question never arose for either, and this job inherited their
shape rather than choosing it.

The distinction matters here because a first pass uploads the whole tree while
every later pass uploads only what changed, and the two differ by orders of
magnitude. A first run over a tree this size takes hours, for the reasons in
the section above, so a default ceiling of tens of
minutes would mark a healthy first backup as timed out — and a monitor whose
first report is a false alarm teaches the reader to discount the second.

Eight hours clears that projection with room for a larger tree, and still
resolves long before the next daily run.
The figure bounds a run that is working rather than predicting how long one
takes. A backup that has genuinely stopped is still caught from both sides: the
check-in margin reports a run that never starts, and the job raises on any pass
that ends other than clean.
