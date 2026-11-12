---
lat:
  mode: explanation
---
# Home feed

The home feed collects a user's relevant legislative activity across all of their Sway locales into one reverse-chronological list.

## What items a user sees and how paging works

[[app/services/feed_query.rb#FeedQuery]] builds a user's feed items in Ruby, sorts them newest first, and slices pages in memory using an opaque cursor.

Every user receives a `user_joined` item dated at account creation, a `representatives_found` item dated at the earliest active `user_legislator` assignment when active representatives exist, and one `legislative_term_began` item per declared locale.

Each declared locale also contributes `bill_of_the_month_released` items for bills whose `scheduled_release_date_utc` falls between that locale's term start and today in UTC, carrying the bill, its locale, and the user's vote when present. Bills without a release date, scheduled for a future UTC date, or released before the current term are excluded.

Confirmed votes by the user's active legislators produce `legislator_voted` items on any bill in a declared locale, including archived bills from earlier sessions in the current term loaded via `Bill.unscope(where: :archived_at)`. Inferred votes (`inferred: true`) are excluded until pipeline confirmation sets `inferred` to `false`. Each vote's timestamp uses the legislator's chamber vote date on the bill (`senate_vote_date_time_utc` for senators, `house_vote_date_time_utc` otherwise), falling back to the other chamber's date and then `legislator_vote.created_at`, and drops votes earlier than the locale's term start.

Active positions by organizations the user follows produce `organization_position_taken` items on bills in declared locales, dated by `activated_at` rather than `created_at` so draft positions approved later appear when published. Inactive positions, unfollowed organizations, and positions activated before the locale's term start are excluded.

Undeclared locales produce no term-start items because only declared jurisdictions have configured term rules in [[app/models/term_window.rb#TermWindow]]. Each term-start timestamp uses midnight UTC on the convening date returned by [[app/services/feed_query.rb#FeedQuery#term_start_on|FeedQuery.term_start_on]].

Items sort by `occurred_at` descending and break ties by `key` descending. The cursor encodes the last returned item's UTC timestamp at nanosecond precision alongside its `key`, so the next page resumes strictly after that boundary without skips or duplicates.

## Searching the feed

[[app/services/feed_query.rb#FeedQuery]] filters built items in memory before cursor paging when `query` is non-blank after stripping whitespace.

Matching ignores letter case across the bill's `title` and `external_id`, the `full_name` of the item's `legislator` or `legislators`, the locale's `human_name`, and the organization's `name`. Because `user_joined` carries none of those fields, it never matches a non-blank search, and cursor paging advances only through matching items.
