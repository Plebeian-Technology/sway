# Vote privacy threshold

A number about how other users voted reaches a reader only when at least ten distinct users stand behind it. [[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy]] holds the minimum and the two questions every serializer asks of it.

## The threat is a small group of users who know each other

With two voters on a bill, each one reads the other's position off the tally. The minimum exists to stop that inference in small groupings.

Two things sit outside the threat by decision. A reader who watches an exact total refresh sees each new vote's direction. District sizes can be worked out from percentages over time or from public records. Neither identifies a voter inside a small group, so neither is defended.

## Percentages are rounded to steps and a unanimous split is withheld

A published vote percentage is a multiple of ten under 20 voters and a multiple of five from 20 voters up, and a split where one side holds every vote is withheld like a split under ten voters.

[[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy#unanimous?]] is true when the two counts sum to more than zero and one of them is zero. [[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy#withheld?]] is the minimum test or the unanimous test, and every caller that publishes a two-sided split asks it.

Two figures that each stand on ten voters can differ by one person: a figure before and after one vote, or two overlapping scores. Exact numbers turn that difference into one person's vote, and a rounded step hides most of those differences from 20 voters up. Below 20 it hides fewer, and the operator accepted that. A unanimous split is withheld because knowing that a voter took part then reveals the vote.

[[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy#rounded_percentages]] takes a hash of counts and the number of distinct voters and returns a hash of percentages with the same keys, summing to exactly 100, or nil when every count is zero. It floors each share to a step, gives the leftover steps to the largest remainders with ties going to the key that comes first, and compares integers only, so ties are exact. A key with a non-zero count never rounds to zero: each such key takes one step from the key with the largest value at that moment, so a split that is not unanimous never shows 100 and 0.

Worked examples, as counts, voters and the result:

- For 7, Against 3, 10 voters: 70 and 30.
- For 13, Against 6, 19 voters: 70 and 30.
- For 9, Against 1, 10 voters: 90 and 10.
- For 19, Against 1, 20 voters: 95 and 5.
- For 39, Against 1, 40 voters: 95 and 5, not 100 and 0.
- For 21, Against 19, 40 voters: 55 and 45, the tie going to For.
- Agreed 6, disagreed 3, no legislator vote 1, abstained 0, 10 voters: 60, 30, 10, 0.
- Four keys at 97, 1, 1, 1 with 100 voters: 85, 5, 5, 5.

## Bill totals are sent as rounded percentages

A bill's total reaches a reader as a For and an Against percentage, rounded by [[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy#rounded_percentages]] with the bill's voters as the voter count, once ten users have voted and the split is not unanimous.

[[app/models/bill_score.rb#BillScore#comparison_suppressed?]] asks [[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy#withheld?]], so a bill with nine voters and a bill whose voters all took one side look the same to the reader: `for_percent`, `against_percent` and the counts are nil, and `comparison_suppressed` is true. `voters_needed` stays the number of further voters that would reach ten, so it is zero for a unanimous bill of ten or more. It is safe to send for a bill, because the feed already publishes how many users voted on it.

The counts `for` and `against` still travel beside the percentages, in the same builders and under the same rule, until web and mobile read the percentages only. A later change removes them. [[voter-privacy-threshold#Percentages are rounded to steps and a unanimous split is withheld]] gives the reason for rounding.

## Districts are sent as percentages only

A district with ten voters shows its split as two rounded percentages, with no counts and no voter total. [[app/models/bill_score_district.rb#BillScoreDistrict#for_percent]] and its Against twin round with the district's own voters as the voter count, so the pair sums to 100.

A unanimous district is withheld like one under ten, through [[app/models/bill_score_district.rb#BillScoreDistrict#comparison_suppressed?]].

With district counts on the page, a hidden district's exact tally would equal the bill total minus the visible districts. Hiding each district's size does not remove that subtraction on its own. A ten-voter district rounded to the nearest 10 points still fits one pair of counts only, so its percentages read back as counts. Counts read back that way, taken from an exact bill total, give the tally of the voters outside every shown district. With eleven voters, eight For, and district 4 holding ten at 70% and 30%, only 7 and 3 fit, so the eleventh voter voted For.

[[app/models/bill_score.rb#BillScore#publishable_districts]] closes that gap. It subtracts the voters of every publishable district from the bill's voters and sends the rows only when the remainder is zero or at least the minimum. A remainder of one to nine sends no row for the bill, and each reader sees the placeholder a district under ten gets. A remainder of zero leaks nothing, because nobody stands outside the rows.

The at-large row stays out of the sum. It is never shown, and it counts every voter of its area, so adding it would count each voter twice. The sum also relies on each voter sitting in one numbered district per locale, which holds because a district's name keeps only its number: Maryland's delegate subdistricts 1A and 1B fold into district 1 with its senator. A voter counted in two shown rows would leave the districts holding more voters than the bill, so a negative remainder sends no row.

A district under ten has no `voters_needed`, because that number would give its size away, and its row is not sent at all. A row exists only once someone in that district has voted, so even an empty-looking row would say that someone there did. The at-large district is left out as well: it covers every voter, so it repeats the bill total.

## No endpoint sends a count that could identify a voter

Hiding a number on the page is not the guarantee, because anyone can read the JSON behind it. The guarantee is that the server never sends the number.

Every bill score leaves through one of two doors, and both ask the model. [[app/models/bill_score.rb#BillScore#visible_for]] and its Against twin answer nil below the minimum, and [[app/models/bill_score.rb#BillScore#publishable_districts]] decides which district rows leave at all, asking [[app/models/bill_score_district.rb#BillScoreDistrict#publishable?]] of each row first. [[app/serializers/bill_score_resource.rb#BillScoreResource]] serves the bill page and Bill of the Month to the web and the phone. The two `to_builder` methods serve the bills index, past Bills of the Month and the `bill_scores` and `bill_score_districts` endpoints.

A district row carries its two percentages and never a count. Its `comparison_suppressed` and `at_large` keys stay, always false, because the phone treats a row without the flag as hidden.

The feed's count of how many users voted on a bill stays. It says how many, not how.

Legislator scores follow the same rule. `group_score` in [[app/serializers/user_legislator_term_score_resource.rb#UserLegislatorTermScoreResource]] builds every district, locale and lifetime score that leaves the server, for the legislator page, the legislators list, the legislator history and the `legislator_votes` endpoint. It sends the flag and the four percentages and none of the four counters. The counters stay in the database, where the percentages are computed from them, and in the reader's own score.

## Legislator scores count only bills that reached the minimum

A locale score counts a bill only when the bill's own total has ten voters and is not unanimous. A district score counts it only when that district's split for the bill could itself be published, which also rules out a unanimous district.

Every legislator in a locale is scored over the same users. Were two of them to vote alike on every bill but one, the gap between their agreement percentages would be that bill's For minus Against over a total that published bill tallies give away. Leaving hidden bills out of every score closes that gap. District scores leak the same way where several legislators share one district's users, such as a state senator and the district's delegates.

A district score is a district split under another name. With eleven voters on a bill, ten of them in district 4 at seven For and three Against, the bill page sends no district row ([[voter-privacy-threshold#Districts are sent as percentages only]]). Were that the only bill in the term, district 4's council member would still show 70% agreed over ten voters, which is the hidden 7 and 3, and the exact bill total then gives the eleventh voter's position away.

[[app/models/bill_score.rb#BillScore#countable_district_ids]] therefore names the districts a district score may count a bill for, and it reuses the remainder test that [[app/models/bill_score.rb#BillScore#publishable_districts]] applies. A numbered district counts when its row is publishable. The at-large district is never drawn, so it gets its own test: its tally must reach ten, and the bill's voters outside it must number zero or at least ten. In the Congress locale each state's at-large tally holds only that state's voters, so ten Maryland voters and two from Virginia would otherwise let a Maryland senator's score expose the two.

Both tests read a total that can include users the score never reads. A score reads only the users linked to its own legislator, so a bill that passes either test can still rest on fewer than ten of them. Maryland subdistricts 44A and 44B fold into one district row, yet a 44A resident links only to the 44A delegate. With nine 44B voters and one 44A voter on a bill, the district passes, and the 44A delegate's score on that bill is the one voter's position. A locale total of ten can likewise include eight users who have no representative in the locale. A score therefore also counts a bill only when ten distinct users from its own legislator's users voted on it. The district and locale tests stay, because the first protects the published split and the second protects the published total.

`tally_group_agreement` in [[app/services/score_recompute_service.rb#ScoreRecomputeService]] applies the rule from the stored `BillScore` and `BillScoreDistrict` rows (`bill_ids_with_minimum_voters` leaves out a bill whose total is withheld), then drops each bill with fewer than ten of the legislator's own voters. Because a district's admission hangs on voters outside it, a vote recomputes the district score of every legislator serving a district with a tally on the bill. It recomputes each legislator's active term only ([[score-updater-service-design#Why each score family uses a different scope and a different term]]), so a bill enters an active-term score when its own tally becomes visible, and enters an earlier term's score only at the next full recompute (`sway:scores:recompute_all`). It stores `distinct_voter_count` beside the counters: the number of users with at least one counted bill, which is the figure the minimum is checked against. The counters themselves count user and bill pairs, so one user who voted on twelve bills adds twelve.

A user's own agreement with a legislator is one user's record, so `tally_agreement` keeps counting every bill for it.

## Legislator scores are sent as percentages

A district or locale agreement score carries `comparison_suppressed` and one rounded percentage per counter, and no counter. With fewer than ten distinct voters behind it, or a unanimous split, the flag is true and every percentage is nil.

It also carries `voter_agreement_percent`, the term tile headline, worked out from the counters ([[voter-privacy-threshold#Legislator charts draw percentages or the placeholder]]). A score is unanimous when its agreed and disagreed counters are unanimous ([[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy#unanimous?]]): agreed against disagreed is the split it publishes. A score with neither counted, only pairs without a legislator vote, is not unanimous and stays published.

Percentages replace counts for the reason districts use them: one count can be subtracted from another. `percentages` in [[app/serializers/user_legislator_term_score_resource.rb#UserLegislatorTermScoreResource]] and `voter_agreement_percent` take their figures from [[app/lib/vote_comparison_privacy.rb#VoteComparisonPrivacy#rounded_percentages]], so the four always sum to 100 and the headline is rounded to the same step. The voter count that picks the step is the smallest distinct voter count among the rows behind the score, because the figure stands on its thinnest term. Six agreed, three disagreed and one without a legislator vote among ten voters send 60, 30, 10 and 0, and a headline of 70.

No `voters_needed` is sent. The number of users behind a district score would show how few people in a small district take part, so every hidden legislator score reads the same.

A reader's own agreement with a legislator is their own record, so it keeps its counters and gains none of these fields.

## A lifetime figure needs every summed term at the minimum

The lifetime score adds a legislator's terms together, and it is hidden unless every term in the sum has ten distinct voters.

Distinct voters cannot be added across terms, because the same user may stand behind several. Ten voters in one term and four in another are somewhere between ten and fourteen people, and the four-voter term's share of the sum is the small group the minimum protects.

The unanimous test runs on the summed counters, so a lifetime figure whose terms all agreed, or all disagreed, is hidden like a single-term score.

A term whose row has no distinct voters is left out of both the sum and the check. Such a row is either empty or was written before a full recompute, when its counters still covered bills under the minimum. `group_score` therefore builds the published figure from the same rows the minimum is checked against, so stale counters never reach a percentage, and one empty early term cannot hide a legislator's lifetime figure for good. When every row is of that kind the figure is hidden.

## The placeholder shown in place of a hidden comparison

A reader who meets a hidden number sees a placeholder that says why, so an empty space never reads as a broken page. [[app/frontend/components/bill/VoteComparisonPlaceholder.tsx]] draws it on the web.

With `showInvite` it says that there are not enough votes yet and asks the reader to invite others. A signed-in reader gets a button that copies their own invite link, which the shared `user` prop already carries as `invite_url`. A signed-out visitor gets a sign-up link instead, and a signed-in reader with no invite link gets the message alone.

Without `showInvite` it says only that there are not enough votes yet. Districts and legislator scores take this form. The bill page passes `showInvite` and never a number of voters needed: a bill under ten voters and a unanimous bill must look the same, and only the first has voters still needed.

The strings live in `PARITY_COPY.bill.voteComparisonPlaceholder`, so the mobile app shows the same words.

## The web bill page asks one helper whether to draw a comparison

Seven bill layouts draw the tally, and each asks [[app/frontend/components/bill/sway_utils/billPositions.ts#isVoteComparisonSuppressed]] rather than reading the flag itself.

When it answers yes, the layout draws one placeholder with the invite prompt where its tally stood. The chart panels, the affinity panel and any sentence about the majority draw nothing, so the page says it once. A score with no flag counts as suppressed: a payload the page does not understand is hidden, never shown.

Once the bill passes the minimum the total shows its For and Against percentages again, never counts, and the district charts follow [[bill-vote-charts-design]]. [[app/frontend/components/bill/sway_utils/billPositions.ts#selectVoteTally]] reads the percentages, so "Evenly split" means equal rounded percentages: 11 For and 10 Against shows 50 and 50 and reads as even.

The reader's own vote and the comparison with their legislators stay on the page throughout. Each compares one user with one official, not users with each other.

## Bill lists print one line for a hidden tally

A row in a bill list has room for a line, not a panel, so a hidden tally becomes the placeholder's first sentence alone, with no invite button.

[[app/frontend/components/bill/sway_utils/billPositions.ts#suppressedVoteComparisonLine]] returns the sentence "Not enough votes yet", whatever the row carries. The six themed list layouts and `BillCard` print it where "n for · n against" stood. A row at or above the minimum is unchanged.

## Legislator charts draw percentages or the placeholder

The web draws a district, locale or lifetime agreement score in two places: the charts panel on the legislator card and page, and the tiles and charts on each term card.

Each asks the same helper the bill page asks. A suppressed score draws the no-number placeholder under its title, since a legislator score never carries `voters_needed`. A visible score draws its bars and labels from the percentage fields and reads no counter.

A term tile's headline is agreement among the bills the legislator voted on: `voter_agreement_percent`, the Agreed share of Agreed plus Disagreed. The server works it out from the counters, because the rounded shares of all pairs lose it when most pairs have no legislator vote (3 agreed and 2 disagreed among 500 pairs and ten voters send 10% and 10%, yet the headline is 60%). It is nil when the score is suppressed or when no pair was agreed or disagreed, and the tile then reads `--%`. The line below it gives the shares as sent.

The reader's own chart and tile keep their counts: [[app/frontend/components/legislators/charts/VoterAgreementChart.tsx#VoterAgreementChart]] is untouched.

## The embed widget withholds counts on the server

The partner embed at `/embed/bills/:id` is public and a CDN keeps each response for up to fifteen minutes, so a count hidden only by the card would still be published.

[[app/serializers/embed_bill_resource.rb#EmbedBillResource]] therefore sends `pro_count`, `con_count`, `pro_percent` and `con_percent` as nil whenever the split is withheld (under ten voters or unanimous), with `comparison_suppressed` and `voters_needed`. The percentages follow the same rounding as the bill page. `total_votes` stays, because it says how many voted and not how. The card shows "Not enough votes yet", the invite prompt and a sign-up link that opens outside the frame: nobody is signed in to Sway inside a partner's page, so there is no invite link to copy. A payload with no flag is drawn as suppressed. When the split is published the card draws `pro_percent` and `con_percent` in its text and `aria-label` and never reads a count.

The response's ETag includes [[app/controllers/embed/bills_controller.rb#BillsController#PAYLOAD_VERSION]], so a deploy that changes the payload's shape or privacy rules, and bumps that constant, makes every ETag cached before it stale. A CDN or browser holding the old body revalidates, gets a full response instead of a 304, and drops the old counts. Without the bump the ETag follows only the bill and its score row, and a response cached before the rule would keep revalidating as 304 until someone voted on that bill. A response still inside its freshness window is served without revalidation until it expires, up to fifteen minutes.

The response sends no `Last-Modified`. A date cannot carry the version, so a cache that revalidates with `If-Modified-Since` alone would get a 304 across a version bump; with no date sent, the ETag is the only validator.

## The mobile bill screen hides what the web hides

The phone's Votes tab shows the placeholder in place of the score bar and the district panel while a bill is under ten voters, and a bill card in a list prints the one-line form.

[[mobile/src/utils/districtVotes.ts#isVoteComparisonSuppressed]] answers for the whole screen. It treats a score with no flag as suppressed, because a bill cached before the flag existed still carries exact district counts and the phone would otherwise draw them.

Above the minimum, [[mobile/src/utils/districtVotes.ts#selectDistrictVotes]] keeps only districts that carry percentages and are neither hidden nor at-large. A reader district with no row becomes a suppressed row, which the panel draws as "Not enough votes yet" with no sentence about the majority.

[[mobile/src/components/VoteComparisonPlaceholder.tsx#VoteComparisonPlaceholder]] takes whether the reader is signed in from the `isSignedIn` prop of [[mobile/src/components/BillScreenTabs.tsx#BillScreenTabs]], which each bill screen reads from the session, and the invite link from the bootstrap response's current user. The button copies the link with `expo-clipboard`, as the web button copies it, and prints "Invite link copied to clipboard." under itself once the copy succeeds.

The phone placeholder has no sign-up button. The app mounts the bill screens only for a signed-in reader, and the sign-in screens only for a signed-out one, so a bill screen has no sign-in route to reach. A signed-in reader whose bootstrap is still loading, or failed, has no invite link yet and sees no button, as the web does for a signed-in reader without one.

## The mobile legislator screens draw percentages or the placeholder

The phone draws a district, locale or lifetime agreement score on the legislator detail screen and on each term card, through one chart component that also draws the reader's own score.

[[mobile/src/components/LegislatorChartsPanel.tsx#LegislatorChartsPanel]] takes a `group` flag for the scores that cover many users. With it set, a suppressed score draws "Not enough votes yet" under the title, and a visible one draws its four bars from the percentage fields on a fixed scale of 100. A cached score with no flag counts as suppressed, for the reason the bill screen gives. Without the flag the panel draws the reader's own counters as before.

The term card's district and locale tiles follow [[mobile/src/types/legislator.ts#calculateGroupAgreement]], which gives the same headline the web tile shows.

## Bill tallies are recomputed before the legislator scores that read them

A legislator score decides which bills to count by reading stored bill tallies, so a caller that refreshes both refreshes the bills first.

A vote already does: `ScoreUpdaterService` recomputes the bill and then the scores. A change of address or a late registration moves a user's votes between districts, and `ReconcileUserDistrictsService`, `UserAddressSwitchService` and the registration controller follow the same order. Run the other way round, a district score would count a bill by its old district tally, including one that has just dropped under ten.

## Specs that are not about the minimum

A spec about term windows, score refreshes or page layout has one or two voters, and the minimum would hide everything it asserts.

The shared context in [[spec/support/shared_contexts/voter_minimum_of_one.rb]] lowers the minimum to one for such a spec. The context also stubs `VoteComparisonPrivacy.unanimous?` to false, because such a spec builds one-voter, one-sided bills that the unanimous rule would otherwise withhold. Specs that pin the rule itself leave the constant alone and build nine and ten voters, and mixed splits.
