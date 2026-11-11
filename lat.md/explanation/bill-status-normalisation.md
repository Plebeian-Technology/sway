---
lat:
  mode: explanation
---

# Bill status normalisation

A bill's `status` is one of four words, lowercased on the way in. A row already holding something else is left holding it, because emptying the column made every later write to that row fail.

## An unrecognised status is left where it is

`downcase_status` lowercases a value it recognises and does nothing at all to one it does not.

It used to set the column to `nil` instead, as a way of saying "this is not a
status Sway knows". The column is also validated for presence, and the callback
runs `before_validation` on every save, so a row whose stored status was off the
allowlist became unsaveable through every code path — a job, an admin form,
anything — and the error it raised said `Status can't be blank` about a column
nobody in that request had touched. A daily vote sweep writing one date column
was refused by it every morning.

Leaving the value alone keeps a cosmetic data problem cosmetic. The row is still
wrong, and it is still visible as wrong, but being wrong no longer spreads to
every other column on it.

## The allowlist is checked on the way in, not on the way past

The inclusion validation runs only when `status` itself changed, so it judges what a writer is asking for rather than what the row already holds.

Checking on every save would put the write failure straight back, with a better
message but the same effect: a legacy row could not be repaired one column at a
time. Checking on change means a new value off the allowlist is refused and named
in the error, while an existing one is somebody else's problem to correct at
source — its real value has to come from Legistar rather than be guessed, so no
code path invents a replacement.

Presence is still checked unconditionally. An empty status is blank rather than
unrecognised, and a row holding one stays unsaveable until it is given a real
value.

## Database check constraint against blank status

A database check constraint rejects null, empty, and all whitespace-only strings at the SQLite level, preventing unvalidated writes from storing values that Rails treats as blank.

Application-level presence validations on `Bill#status` catch empty strings and nil values during standard model persistence. However, low-level database writes—such as raw SQL statements, data migrations, or `update_column` calls—bypass ActiveRecord callbacks and model validations entirely. When historical Baltimore bills carried empty string statuses, standard model updates on unrelated columns were refused by model callbacks.

The SQLite check constraint `bills_status_not_blank` enforces:
`status IS NOT NULL AND length(trim(status, ' ' || char(9) || char(10) || char(13) || char(160) || char(8203) || char(12288))) > 0`.
SQLite's single-argument `trim` removes only ASCII spaces, allowing tabs, newlines, carriage returns, nonbreaking spaces (U+00A0), zero-width spaces (U+200B), and ideographic spaces (U+3000) to persist. Passing an explicit string of whitespace codepoints via SQLite `char(...)` guarantees that any string ActiveSupport considers `blank?` triggers a constraint violation on direct insertion or update.

The database constraint deliberately omits the four allowed status values (`passed`, `failed`, `committee`, `vetoed`). The domain allowlist belongs to the model inclusion validation in `app/models/bill.rb`, while the database schema guarantees only that stored status values are non-blank.

## Scoped repair for historical Baltimore bills

The historical repair of Baltimore bills 58 and 59 isolates its target selection to the Baltimore jurisdiction, preventing cross-locale mutations on same-numbered rows.

`RepairBills58And59` repairs historical rows where empty status strings prevented automated vote sweep jobs from persisting legislative dates. Stand-in models `MigrationSwayLocale` and `MigrationBill` avoid referencing application model classes, satisfying migration linting rules while querying the database directly.

The migration queries `baltimore_locale_ids = MigrationSwayLocale.where("LOWER(city) = ?", "baltimore").pluck(:id)` and scopes bill lookups strictly to those locale IDs. When Baltimore is absent, the migration returns early with zero mutations. For the intended Baltimore rows (bill 58 / 24-0599 and bill 59 / 24-0592), leading whitespace in `external_id` is stripped and statuses are set to their canonical Legistar mappings (`failed` for Matter 9906 "Failed - End of Term", `passed` for Matter 9895 "Enacted"). Existing authentic source links remain untouched.
