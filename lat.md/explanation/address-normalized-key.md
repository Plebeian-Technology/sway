# The normalized address key

Every address row carries a key built from its rounded coordinates and its unit, so two spellings of one building collapse to one row instead of two.

Registration used to find an existing address by matching every typed field
exactly, so `100 N Holliday St` and `100 N Holliday Street` became separate rows for
one building. Each row then carried its own registered people, and the locale
counts had to compensate with `COUNT(DISTINCT user_id)`.

## Why the key is coordinates rather than street text

Google has already resolved the typed text to a point on the earth, and that
point is the cheaper identity.

Normalizing street text instead would mean owning a table of suffix
abbreviations, ordinal spellings, directionals and punctuation, in every locale
Sway adds, and keeping it current. Two spellings of one building geocode to the
same place, so the point needs no such table.

Coordinates round to four decimal places, about eleven metres. That is close
enough to absorb the small differences between two geocodes of one building, and
far short of the distance to the next building.

The key deliberately excludes street, city, region and postal code. Including
them would reintroduce the text matching the key exists to avoid — a row whose
city is `Baltimore` and one whose city is `baltimore` would disagree again.

## Why the unit is part of the key

Two apartments in one building share a coordinate. Treating them as one address
would merge separate households and hand them each other's district in the case
where a building straddles a boundary.

`street2` and `street3` are folded in position by position rather than sorted, so
a floor recorded in one field and a unit in the other stays distinct from the
reverse. Each is reduced to its bare identifier: `Apt 4`, `#4` and `Unit 4` all
become `4`, which is what makes the same unit written three ways agree.

## Finding an address during registration

Registration looks an address up by its normalized key, and falls back to matching every typed field when the submission has no coordinates and therefore no key.

The fallback is not a courtesy. A submission without coordinates cannot produce
a key, and matching nothing would create a fresh row on every attempt. The old
exact-field match is the honest answer for a submission Sway cannot place.

A row found by key that does not yet carry one has the key written onto it
as it is used. So the table converges without a second pass, and the data
migration (`db/data/20261111000001_backfill_address_normalized_keys.rb`)
only has to cover rows nobody registers against again.

The key is deliberately not part of the create call's matching tuple. It is
computed from the coordinates rather than supplied by the client, so making it a
match condition would be circular.

## Why an unlocated address has no key

`normalized_key_for` returns nil when either coordinate is missing. Geocoding
happens after commit, so a row exists briefly before it has a point, and a key
invented from text during that window would not match the key the same building
gets later.

A nil key is therefore the honest value for a row that cannot yet be compared,
rather than a placeholder that would collide with every other unlocated row.

## Why the backfill reports collisions instead of merging

The data migration (`db/data/20261111000001_backfill_address_normalized_keys.rb`) fills the column on rows written before it existed and lists the keys two or more rows now share, but moves no data.

Merging two address rows means choosing which registered person's district,
legislators and vote history move to the surviving row. That choice can
depend on facts the key does not carry: which row is the one still in use,
whether the two geocodes actually agree on unit, whether a person meant to
move. Filling in a column is not the place to make it. The migration stops at
the report so that decision stays a separate, reviewed step.
