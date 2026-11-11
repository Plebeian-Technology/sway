---
mode: explanation
summary: "Explains why bill external IDs are validated at every point they enter the system, to stop path-traversal values reaching the filesystem."
status: agent-extracted
related: []
---
# Bill external ID validation

<!-- vale Vale.Spelling = NO -->

Why `FetchBillsService` validates a bill's `external_id` at every point
where untrusted text could become one, instead of trusting it once.

## Why this value needs checking at all

A bill's `external_id` ends up used as a filesystem path segment in many
places: `Bill#external_id`, `PipelineRunBill#bill_external_id`, and inside
`FileUtils.mkdir_p(artifact_root.join(...))` in `FetchBillsService#persist`
— 13 different places in total. If that value ever contains path pieces
like `../`, it can write outside the bill's own artifact folder.
`Legislation::Paths.external_id_segment` is the shared guard that rejects
that shape, and it is applied at each point where the value enters the
system, not just once.

## Entry point 1: Legistar's `MatterFile` field

`FetchBillsService#build_metadata` builds a candidate `external_id` from
Legistar's `MatterFile` field. `MatterFile` is free text typed by someone at
the city, so it is checked before it becomes an `external_id`:

- A value padded with spaces would pass a simple "not blank" check, but
  would then fail
  `BaltimoreLegislatorVoteUpdateService::MATTER_FILE_PATTERN` on every vote
  sweep from then on — skipped silently, forever.
- Trimming the spaces is not enough on its own either: trimming strips
  neither `/` nor `..`, so a hostile or mistyped value could still become a
  `Bill#external_id` and, from there, part of a file path in those 13
  places.

`Legislation::Paths.external_id_segment` rejects the bad shape right here,
at the point where the data comes in from Legistar. `return nil` is how
`#build_metadata` already skips other unusable rows (it skips
`SKIP_MATTER_TYPES` and a blank `MatterFile` the same way), so one bad
matter is dropped instead of stopping discovery for every bill.

`MatterFile` can arrive as any JSON scalar or array, not only a string.
`Legislation::Paths` deliberately accepts only a `String` or `nil` — that
module must not have to know about Legistar's wire types. The `.to_s` call
before validation turns anything that is not already a `String` into text,
which the pattern then rejects, and that is the correct outcome.

## Entry point 2: operator-edited `metadata.json`

`FetchBillsService#read_disk_metadatas` rebuilds database rows from
`metadata.json` files already on disk. An operator can edit those files
directly, so the `external_id` read back out of one cannot be trusted
either: an attacker, or a typo, could put path pieces like `../` into it.

That value flows to the same places listed above — `Bill#external_id`,
`PipelineRunBill#bill_external_id`, and `FileUtils.mkdir_p` in `#persist` —
so `#read_disk_metadatas` runs it through the same
`Legislation::Paths.external_id_segment` safe-segment check used everywhere
else, rather than trusting a file just because it is already on disk.

A row that fails the check is dropped, with a warning logged. That matches
what `#read_disk_metadatas` already does for a blank `external_id`, a
`matter_id` that is not an `Integer`, or JSON it cannot parse: one bad file
must not stop the rebuild for every other bill.

## The model's own format validation is the same guard, not a separate one

`Bill::EXTERNAL_ID_PATTERN` reuses `Legislation::Paths::EXTERNAL_ID_PATTERN`
rather than a second hand-copied regex that could drift from it. Only
presence and uniqueness were checked on the `Bill` record itself until this
was added. `Legislation::Paths` already cleans the value at the point a
path is built from it; the model-level validation is the same guard placed
earlier, on the record, so a hostile value can never be SAVED in the first
place and picked up later by some reader that forgets to clean it.

## The bill factory's external_id fixture

`spec/factories/bills.rb`'s `:bill` factory generates `external_id` as
`"bill-#{n}-#{Faker::Color.color_name.parameterize}"`. `external_id` is
checked against `Bill::EXTERNAL_ID_PATTERN` (the same format guard
described above), so the fixture has to keep producing values that pass
it. All 72 of Faker's English `color_name` values happen to fit that
pattern today, so the sequence was already safe — but "happens to fit" is
not a promise, and a single Faker release adding a two-word colour name
would break hundreds of unrelated examples at once. `.parameterize` forces
the value into `[a-z0-9-]` either way, so the fixture does not depend on
Faker's word list staying single-word forever.

## Why the format spec updates a saved bill instead of using build(:bill)

`build(:bill)` is always invalid in this project: the factory's
`initialize_with` passes a legislator that has not been saved, and `Bill`
requires `legislator_id`. So `expect(build(:bill, external_id: x)).not_to
be_valid` would pass whatever `x` is, telling the test nothing. The
`external_id` format spec instead changes `external_id` on a bill that HAS
been saved, so the only thing under test is that one attribute — and it
also exercises the `if: :external_id_changed?` condition on a real row.

`scheduled_release_date_utc` is left unset in that fixture because the
example makes several bills in one locale, and a locale may hold only one
bill per release date. Nothing in the example is about scheduling; an
unscheduled bill is a real state and keeps each row distinct.

## Why a stored external_id is stripped rather than rejected

Whitespace around `external_id` is cleaned up, not rejected. Legistar's
`MatterFile` field is already stripped where it enters the app, for this
same reason (see "Entry point 1" above), and
`Legislation::Paths.external_id_segment` strips it again when a path is
built. Stripping it at the model layer too means the stored value, the
path segment, and the Legistar query can never disagree about which bill
is meant.

## Related

See also
[Filtering malformed API response rows](legistar-response-row-filtering.md)
for the companion defense against malformed rows earlier in the same
pipeline (a `nil` row rather than a bad `external_id`).
