---
lat:
  mode: explanation
---

# Why retire_untestified_draft_org_positions_spec.rb is built this way

The rule `RetireUntestifiedDraftOrgPositions` (data migration `20260726000002`) uses to pick rows is the whole point of these examples.

The requirement was that the rows be found "by a provable predicate, not a date guess", so each example pins one step of the proof rather than what a single fixture happens to do.

The proof goes like this. `GenerateBillSummaryJob` asks for organization positions ONLY when `provisioning.testimony_present?` is true. So a row that holds draft positions while BOTH testimony columns are empty cannot have been written by the current code.

## Why "touches nothing" is checked against the write itself

The two obvious things to look at prove nothing here.

`updated_at` never moves, because the migration writes with `update_columns`, and `draft_org_positions` never changes on an empty row, because stamping `[]` gives `[]` back. A check on either would pass even with every guard deleted — and a deleted guard is the one thing these examples exist to catch. Whether an UPDATE was sent at all is the only difference between acting and not acting.

## Why a row WITH testimony is left alone, and why that guard cannot be widened

A row WITH testimony is exactly what the current code produces, so there is no proof it was derived from a diff and it must be left alone. Reaching too far here would throw out legitimate drafts.

Someone once proposed dropping the `supplemental_testimony` half, on the theory that an older row carrying supplemental testimony holds diff-derived drafts. It does not: the older prompt built `draft_org_positions` from the supplemental section and told the model to return `[]` when that section was empty (the migration's header quotes it). Two examples in this spec are what stop a future widening from marking evidenced drafts as retracted.

## The '""' vs '' SQL trap

The SQL half of the rule is checked directly rather than through what the migration ends up doing.

`draft_org_positions` is declared with `serialize ..., coder: JSON`, so every value in a `where` clause runs through that JSON encoder before it reaches SQL. A `"[]"` string written as a marker therefore goes in as the four bytes `'"[]"'` and matches nothing, while an empty array is actually stored as the two bytes `'[]'`. The Ruby-side guards give the right RESULT either way, so nothing above the SQL layer can tell the difference — only the set of rows the query actually selects can.

This is a guard against one specific regression. The first attempt at this fix used a raw SQL fragment with a bound value, and the Rails/WhereNot RuboCop rule rewrote it — inside the pre-commit hook, after staging — back into a hash condition, which restored the `'"[]"'` comparison and the bug with it. The row-set example catches that too, but it only says "wrong rows"; the byte-level example names the exact bytes.

That byte-level check runs against `.draft_bearing_rows`, which is where the SQL lives: `.untestified_draft_rows` is a plain Array of rows, because the testimony question is answered in Ruby by a single predicate. The assertion itself is about the bytes the drafts half of the query emits.

## Why a retracted row keeps its original timestamp

The only other way a row ends up with drafts and no testimony is the `:retract` branch of the companion change, which clears `extracted_testimony` on drafts it has just stamped.

Those must keep their original timestamp: it dates the `fetch-hearings` run that withdrew the evidence, which is what the operator actually wants to know.

## Why the empty-""-string example replaced an earlier, blind one

An earlier version of this example created a `[]` row and claimed it caught the removal of `#up`'s empty-drafts guards.

It could not: the SQL already leaves a `[]` row out, so that row never reaches the loop and the guards are never consulted. Tried for real — both guards deleted (`next if raw.blank?`, `next if drafts.empty?`) — this file's two "issues no write" examples still reported 2 examples, 0 failures.

The row the current example builds is the one the class comment actually describes: a write made in raw SQL leaves a bare `""` in the column, the JSON decoder reads that back as `nil`, and the SQL lets it through (it is not `NULL`, and `''` is not `'[]'`). So it DOES reach the loop, and only the Ruby guard can stop it — which is what gives this example the ability to fail.
