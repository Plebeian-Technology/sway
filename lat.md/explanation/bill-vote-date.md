---
lat:
  mode: explanation
---

# The shared bill vote date

[[app/models/bill.rb#Bill#vote_date_time_utc]] gives callers one date for the bill's roll-call activity without making each caller choose between chamber columns.

When both chamber dates exist, the method returns the earlier date. When only one exists, it returns that date; when neither exists, it returns `nil`. Services that need a shared anchor, including [[app/services/term_year_from_votes.rb#TermYearFromVotes]], use this method instead of repeating the comparison.
