# Vote privacy threshold

A number about how other users voted reaches a reader only when at least ten distinct users stand behind it. [[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy]] holds the minimum and the two questions every serializer asks of it.

## The threat is a small group of users who know each other

With two voters on a bill, each one reads the other's position off the tally. The minimum exists to stop that inference in small groupings.

Two things sit outside the threat by decision. A reader who watches an exact total refresh sees each new vote's direction. District sizes can be worked out from percentages over time or from public records. Neither identifies a voter inside a small group, so neither is defended.

## Bill totals show exact counts at ten voters

A bill's For and Against counts are exact once ten users have voted on it. Below ten the reader gets `comparison_suppressed` and `voters_needed`, the number of further voters that would reveal the total.

The count of voters still needed is safe to send for a bill, because the feed already publishes how many users voted on it.

## Districts are sent as percentages only

A district with ten voters shows its split as two whole-number percentages, with no counts and no voter total. [[app/models/bill_score_district.rb#BillScoreDistrict#for_percent]] rounds the For share and the Against share is the remainder, so the pair sums to 100.

With district counts on the page, a hidden district's exact tally would equal the bill total minus the visible districts. Hiding every district's size removes that subtraction, and it lets each district appear as soon as it reaches ten rather than waiting for its neighbours.

A district under ten has no `voters_needed`, because that number would give its size away. The at-large district is left out as well: it covers every voter, so it repeats the bill total.

## Legislator scores count only bills that reached the minimum

A legislator's locale score counts a bill only when the bill's own total has ten voters, and a district score counts it only when that district's tally for the bill has ten.

Every legislator in a locale is scored over the same users. Were two of them to vote alike on every bill but one, the gap between their agreement percentages would be that bill's For minus Against over a total that published bill tallies give away. Leaving hidden bills out of every score closes that gap. District scores leak the same way where several legislators share one district's users, such as a state senator and the district's delegates.

`tally_group_agreement` in [[app/services/score_recompute_service.rb#ScoreRecomputeService]] applies the rule from the stored `BillScore` and `BillScoreDistrict` rows, so a bill enters a legislator score exactly when its own tally becomes visible. It stores `distinct_voter_count` beside the counters: the number of users with at least one counted bill, which is the figure the minimum is checked against. The counters themselves count user and bill pairs, so one user who voted on twelve bills adds twelve.

A user's own agreement with a legislator is one user's record, so `tally_agreement` keeps counting every bill for it.

## Specs that are not about the minimum

A spec about term windows, score refreshes or page layout has one or two voters, and the minimum would hide everything it asserts.

The shared context in [[spec/support/shared_contexts/voter_minimum_of_one.rb]] lowers the minimum to one for such a spec. Specs that pin the rule itself leave the constant alone and build nine and ten voters.
