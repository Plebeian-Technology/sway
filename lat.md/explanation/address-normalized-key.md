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

Registration looks an address up by its normalized key. A submission without two valid coordinates has no key, so it always gets a new row of its own.

There is no fallback that matches every typed field. Two unlocated submissions
cannot be shown to be one place, and sharing a row would hand each user the
other's later geocode and district. A fresh row per attempt is the cost of
never merging strangers.

The address is accepted as a fact, so nothing in it refuses the user. A missing
or null text field is stored as an empty string, and a body with no address at
all still stores a blank row
([[app/controllers/sway_registration_controller.rb#SwayRegistrationController#submitted_text]]).
A coordinate that is not a finite number inside its bounds counts as absent,
and both are stored as nil when either is absent
([[address-normalization#Defensive coordinate parsing and validation bounds]]).
Reading the text `abc` as `0.0` would otherwise give every such submission the
same key and one shared row.

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

The after-commit lookup runs outside the write transaction because the SQLite
write lock is held for the whole of an immediate transaction, and a slow HTTP
call must not hold it. When the lookup finds a point it saves the coordinates
and the key from those coordinates in one update, because the row is now
comparable and a nil key would hide it from the next registration of the same
building. The registration controller creates the address outside any
transaction, so the callback finishes before `create!` returns and resolution
sees the located row.

A geocoder failure (an over-limit or denied reply, a timeout, a socket error)
is logged and reported to Sentry instead of raised, because the row is already
committed and an error raised from an after-commit callback would turn a saved
address into a failed request. A failure or an empty result leaves the row
unlocated. Resolution then makes no district lookup and no OpenStates request
for it, rather than testing the point 0,0, and the address resolves by its
state: the locale-wide officers and, through
[[representative-resolution#Congress fallback]], the state's Senators.

## Why the backfill reports collisions instead of merging

The data migration (`db/data/20261111000001_backfill_address_normalized_keys.rb`) fills the column on rows written before it existed and lists, by address id, the rows that now share a key, but moves no data.

Merging two address rows means choosing which registered person's district,
legislators and vote history move to the surviving row. That choice can
depend on facts the key does not carry: which row is the one still in use,
whether the two geocodes actually agree on unit, whether a person meant to
move. Filling in a column is not the place to make it. The migration stops at
the report so that decision stays a separate, reviewed step.
