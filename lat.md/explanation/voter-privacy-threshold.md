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

## Legislator scores are sent as percentages

A district or locale agreement score carries `comparison_suppressed` and one whole-number percentage per counter. With fewer than ten distinct voters behind it the flag is true and every percentage is nil.

Percentages replace counts for the reason districts use them: one count can be subtracted from another. `percentages` in [[app/serializers/user_legislator_term_score_resource.rb#UserLegislatorTermScoreResource]] floors each share and hands the leftover points to the largest remainders, so the four always sum to 100.

No `voters_needed` is sent. The number of users behind a district score would show how few people in a small district take part, so every hidden legislator score reads the same.

A reader's own agreement with a legislator is their own record, so it keeps its counters and gains none of these fields.

## A lifetime figure needs every summed term at the minimum

The lifetime score adds a legislator's terms together, and it is hidden unless every term in the sum has ten distinct voters.

Distinct voters cannot be added across terms, because the same user may stand behind several. Ten voters in one term and four in another are somewhere between ten and fourteen people, and the four-voter term's share of the sum is the small group the minimum protects.

A term with no counted votes adds nothing to the sum and so reveals nothing. `comparison_suppressed?` leaves such a term out of the check, which keeps one empty early term from hiding a legislator's lifetime figure for good.

## The placeholder shown in place of a hidden comparison

A reader who meets a hidden number sees a placeholder that says why, so an empty space never reads as a broken page. [[app/frontend/components/bill/VoteComparisonPlaceholder.tsx]] draws it on the web.

Given the number of voters still needed, it says how many more users must vote and asks the reader to invite others. A signed-in reader gets a button that copies their own invite link, which the shared `user` prop already carries as `invite_url`. A signed-out visitor gets a sign-up link instead, and a signed-in reader with no invite link gets the message alone.

Without that number it says only that there are not enough votes yet. Districts and legislator scores take this form, because their voter counts are never sent.

The strings live in `PARITY_COPY.bill.voteComparisonPlaceholder`, so the mobile app shows the same words.

## The web bill page asks one helper whether to draw a comparison

Seven bill layouts draw the tally, and each asks [[app/frontend/components/bill/sway_utils/billPositions.ts#isVoteComparisonSuppressed]] rather than reading the flag itself.

When it answers yes, the layout draws one placeholder with the bill's `voters_needed` where its tally stood. The chart panels, the affinity panel and any sentence about the majority draw nothing, so the page says it once. A score with no flag counts as suppressed: a payload the page does not understand is hidden, never shown.

Once the bill passes the minimum the total shows exact counts again, and the district charts follow [[bill-vote-charts-design]].

The reader's own vote and the comparison with their legislators stay on the page throughout. Each compares one user with one official, not users with each other.

## Bill lists print one line for a hidden tally

A row in a bill list has room for a line, not a panel, so a hidden tally becomes the placeholder's first sentence alone, with no invite button.

[[app/frontend/components/bill/sway_utils/billPositions.ts#suppressedVoteComparisonLine]] picks the sentence: the count of voters still needed when the row carries one, and "Not enough votes yet" otherwise. The six themed list layouts and `BillCard` print it where "n for · n against" stood. A row at or above the minimum is unchanged.

## Specs that are not about the minimum

A spec about term windows, score refreshes or page layout has one or two voters, and the minimum would hide everything it asserts.

The shared context in [[spec/support/shared_contexts/voter_minimum_of_one.rb]] lowers the minimum to one for such a spec. Specs that pin the rule itself leave the constant alone and build nine and ten voters.
