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

Undeclared locales produce no term-start items because only declared jurisdictions have configured term rules in [[app/models/term_window.rb#TermWindow]]. Each term-start timestamp uses midnight UTC on the convening date returned by [[app/services/feed_query.rb#FeedQuery#term_start_on|FeedQuery.term_start_on]].

Items sort by `occurred_at` descending and break ties by `key` descending. The cursor encodes the last returned item's UTC timestamp at nanosecond precision alongside its `key`, so the next page resumes strictly after that boundary without skips or duplicates.
