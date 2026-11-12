# Encrypting the personal details Sway keeps

Sway holds enough about a person to identify them outright, and it holds it in a SQLite file that travels in every backup. Active Record encryption puts the sensitive columns beyond a reader who has the file but not the key.

The threat this answers is somebody obtaining the database file or one of its
backups, not somebody with a live session. Nothing here defends against an
attacker who already has the running application and its keys.

Rails 8 ships this, so no gem was added. The keys and where they come from are a
separate subject, in [[active-record-encryption-keys]].

## What is encrypted on a user

Three columns on `users` are encrypted without deterministic mode: `full_name`,
`current_sign_in_ip` and `last_sign_in_ip`. A name identifies a person outright,
and an internet address places them.

Non-deterministic mode is the stronger of the two, because the same value
produces different ciphertext every time, so a reader cannot tell which rows
hold the same value. It is available for these three only because nothing
searches by them and none of them carries a unique index. Both were checked
against the schema and against every `where`, `find_by` and `order` in `app/`.

## What is encrypted on an address

`street`, `street2` and `street3` are encrypted without deterministic mode. A home address identifies a person, and the unit number identifies them inside a building as sharply as the street line identifies the building.

None of the three carries a unique index, which is what leaves the stronger mode
available. What had to change first was the searching: an encrypted column
cannot be matched by value in non-deterministic mode, because the same text
encrypts differently every time.

The registration controller and development account paths use the normalized
key ([[address-normalized-key#Finding an address during registration]]). The
primary development seed in [[db/seeds.rb]] was the missed path: it still matched
encrypted street and coordinate columns directly. The seed and the phone
verification provisioner now share [[app/services/development_account_address_service.rb]], so both
reuse the same row. Left as a plaintext lookup, the seed would create a fresh
address row on every run because the stored ciphertext cannot equal the
plaintext being searched for.

## An encrypted column cannot be a lookup key

Encrypting a column in non-deterministic mode silently breaks every query that names it. The stored ciphertext never equals the plaintext being searched for, so the query matches nothing and reports no error.

`SkipPhoneVerificationProvisioner` found its user with
`User.find_or_create_by(phone:, email:, full_name:)`. Once `full_name` was
encrypted the match could not succeed, so a second call tried to create a second
user and failed on the phone and email unique constraints instead. The
development sign-in stopped working on its second use, and the only signal was
that one spec.

The provisioner now finds by `phone` alone, which is the account identity
anyway, and assigns the name rather than matching on it.

The sweep that finds these has to enumerate every query form, not the two or
three that come to mind: `where`, `find_by`, `find_or_create_by`,
`find_or_initialize_by`, `create_or_find_by`, `order`, `pluck`, `group` and
`exists?`. Searching for `where` and `find_by` alone is what let this one
through.

## Why the coordinates are encrypted too, and had to become text

A precise pair of coordinates points at one house exactly as sharply as the street line does, so encrypting the street and leaving the coordinates readable would have been half a job.

The two columns held floats. Ciphertext is text, so both became string columns
in the same migration that encrypted them. The stored value keeps full
precision: the district lookup rounds to four decimal places for the normalized
key, but the geocoding call and `to_cartesian` use the value as given.

`to_cartesian` builds an RGeo point and needs numbers, so it converts with
`to_f` at that boundary rather than relying on the column's type. That is the
one place arithmetic happens; everywhere else the value is passed to an HTTP
query or turned into a string anyway.

`index_addresses_on_latitude_and_longitude` is dropped in the same migration.
Once the values are ciphertext the index can answer nothing, and dropping it
makes every write to the addresses table slightly cheaper. Removing it was safe
only because the lookup had already moved to the normalized key
([[address-normalized-key#Finding an address during registration]]).

## Why the key backfill has to run before the street is encrypted

Registration creates a row when the key finds nothing. A row that still has a
nil key is therefore invisible to the lookup, and the person registering against
it gets a second row for the same building.

The data migration (`db/data/20261111000001_backfill_address_normalized_keys.rb`)
closes that window, so it belongs in the same deploy, before anyone registers
again. Encrypting the street removes the fallback that used to catch this, which
is why the ordering stops being advisory at this point.

## Why the mode is not a free choice

Deterministic mode exists so a column can still be looked up by value or carry a
unique index, and it is weaker for exactly that reason: identical values encrypt
identically, so a reader can group rows without the key.

The mode is therefore decided by what the column has to support, not by
preference. A column with a unique index has no choice. A column nothing queries
takes the stronger mode.

## Why the phone number takes the weaker mode

The phone number is the account. Every sign-in finds a person by it and the database enforces that no two people share one, so it is encrypted in deterministic mode: the same number always produces the same ciphertext.

Ten places call `find_by(phone:)` or `find_or_initialize_by(phone:)`, across the
passkey session and registration controllers, the mobile API, inbound SMS
forwarding and opt-out handling. Non-deterministic mode would break all ten at
once, and the unique index with them.

Deterministic mode is weaker because a reader can tell which rows hold the same
value. On a column the database already declares unique, that reveals nothing a
reader could not already work out. Against the threat this defends — somebody
walking off with the database file or a backup — it holds, because without the
key they cannot encrypt candidate numbers to compare against what they have.

The conversion is the delicate part. The unique rule stays switched on
throughout, while some rows are converted and some are not, so
`support_unencrypted_data` and `extend_queries` are both on: the first lets a
plaintext row still be read, the second makes a lookup and a uniqueness check
match against both forms. With only the first, a person whose row had not been
converted could not sign in, and a duplicate of their number would be accepted.

## Reading rows the backfill has not reached

`config.active_record.encryption.support_unencrypted_data` is on. Without it,
reading a row whose value is still plaintext raises rather than returning the
value.

That matters because the code deploys before the conversion runs, and the
conversion takes time. In between, every row in the table is still plaintext,
and a person signing in during that window would otherwise meet an error rather
than their own name.

It is a transitional setting, not a permanent one. Leaving it on means a row
that never gets converted stays readable in plain words forever, and nothing
reports that. Turning it off is what proves the conversion finished, and that
belongs after the last column has been converted rather than after the first.

## Converting the rows that already exist

Data migrations `20261111000002_encrypt_address_details.rb` and `20261111000003_encrypt_user_personal_details.rb` run at deploy boot via `rails db:migrate:with_data`. Each migration inspects rows and encrypts any plaintext values.

For addresses, `db/data/20261111000002_encrypt_address_details.rb` encrypts `street`, `street2`, `street3`, `latitude`, and `longitude`. It inspects each row and calls `encrypt` only when at least one column holds plaintext, preserving byte-level stability on already-encrypted rows.

For users, `db/data/20261111000003_encrypt_user_personal_details.rb` encrypts `full_name`, `email`, `phone`, `current_sign_in_ip`, and `last_sign_in_ip`. It inspects each row and calls `encrypt` only when at least one column holds plaintext, preserving byte-level stability on already-encrypted rows.

Both migrations use standalone stand-in classes to avoid coupling to application models during migration runs.

Each data migration runs inside one transaction, because data_migrate's migrator is ActiveRecord's migrator and wraps every migration that way on SQLite. The first row that fails rolls back that whole migration and stops the deploy boot, and the SQLite write lock is held for the whole walk over the table.

## Why the shared-addresses admin page reports counts only

`/admin/shared_addresses` (`SharedAddressCountsService`) exists to flag unusual clusters — many registered people at one address — for a person to review, not to let an admin browse where constituents live.

Street, unit and coordinates are encrypted and cannot be grouped or sorted on
([[personal-detail-encryption#An encrypted column cannot be a lookup key]]), so the page has no way to show
address text at all. The constraint and the intent point the same way: a household of a few people is normal, and the number that
matters is how many, not which building. The page therefore reads
`addresses.normalized_key` — not encrypted, and already the identity two
spellings of one building share ([[address-normalized-key]]) — groups
`user_addresses` by it, and counts distinct users. A row whose address has no
key yet (ungeocoded, or written before the backfill) falls back to grouping by
`address_id` alone rather than being merged into every other keyless row.

Each row also carries the bare `address_id` values behind it (more than one
when two rows share a normalized key). An id discloses nothing about where
anyone lives — resolving it to a place still requires the separate boundary of
database access with the encryption key — but without it, a flagged cluster
could not be traced back to a record at all, and the page would be a
histogram rather than a signal a person can act on.

The page must not reject a registration or move a district. It is a signal, and
the follow-up — deciding whether a cluster is a household, an office, or
something to investigate — stays a manual step outside this UI, the same way
the normalized-key backfill stops at a report instead of merging rows
([[address-normalized-key#Why the backfill reports collisions instead of merging]]).

## Finding the seeded development users

The development seed graph identifies the users it owns by listing the
addresses it would have generated, not by matching a pattern against the
column.

Every seeded user's email is `dev-baltimore-user-NNN@dev-baltimore.sway.vote`,
derived from the row's index, so the seeder used
`where("email LIKE ?", "%@dev-baltimore.sway.vote")` to count how many it had
already made. Deterministic encryption answers equality and nothing else — a
`LIKE` compares against ciphertext and matches no row — so that count silently
became zero and every rerun tried to create the whole graph again, which then
collided on the unique index over `user_votes`.

Because the email is a pure function of the index, the set of possible seeded
emails is enumerable. `SeedDevelopmentUserGraph.seeded_users` generates the
first `SEEDED_USER_PROBE_LIMIT` of them and asks for those exact values, which
deterministic encryption does answer. The limit is 999 because the index is
formatted to three digits, so a larger graph would change the shape of the
address rather than extend the range.
