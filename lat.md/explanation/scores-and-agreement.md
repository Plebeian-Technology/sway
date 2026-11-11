---
lat:
  mode: explanation
---
# Scores and agreement

Sway's product claim is that a user's voting record can be compared with their legislators'. Everything on this page exists to make that comparison defensible: five score families, one classification rule, and a rebuild-from-source discipline.

The comparison is the reason the platform exists, so a score that drifts from
the underlying votes is not a cosmetic bug — it is the product being wrong.

## The five score families

A single vote can move five different aggregates, and they answer five
different questions.

`BillScore` holds the for/against tally for one bill across a whole locale.
`BillScoreDistrict` breaks that tally down by district, which is what lets a
reader see how their own neighbourhood voted. `LegislatorDistrictScore` and
`LegislatorLocaleScore` record how well one legislator's term matched the
people they represent — the first among their own constituents, the second
across the entire jurisdiction. `UserLegislatorTermScore` is the personal one:
how often this user and this legislator agreed, within one term.

They are deliberately not derived from one another. A locale score is not the
sum of its district scores, because the district breakdown only counts users
who have an active legislator assignment, while the locale figure counts every
voter in the jurisdiction. Summing would quietly drop the unassigned.

## Bill score builders receive one district snapshot

The bills index preloads each score's district rows and supplies one reader-district list to every personalized score builder.

[[app/models/bill_score.rb#BillScore#to_builder]] exposes every district tally, while [[app/models/bill_score.rb#BillScore#to_builder_with_user]] selects the tallies matching the reader's districts. Computing that district list once outside the bill loop avoids repeating the address-to-district lookup for every row and keeps each bill's personalized score on the same request snapshot.

## Scores are recomputed, never incremented

`ScoreRecomputeService` rebuilds each affected aggregate from the underlying
votes rather than adding one to a counter.

Incrementing is faster and wrong in several ordinary situations: a retried job
would double-count, a corrected legislator vote would leave every derived tally
stale, and a district reassignment would strand a user's contribution in the
wrong bucket.

The rebuild also has to handle subtraction. When nobody in a district has voted
on a bill any more, its `BillScoreDistrict` row is zeroed rather than left
holding a total that is no longer true — an absent row and a zero row mean
different things to the frontend.

## The one-time repair walks every term, not only the current one

The task that rebuilds every derived score row from the source votes walks all
of a person's terms and all of a reader's links, live or ended.

It used to walk only serving legislators and each person's running term, on the
argument that a score for a term already over cannot change. That was fair
while nothing read a past term, and it stopped being fair when the history tab
shipped, because that tab reads exactly those rows. Under the old rule a
sitting member whose invented current term was retired was repaired — the real
term they keep becomes the running one — while anybody who had left was never
repaired at all: their district and locale scores, and each reader's agreement
history with them, stayed missing although their votes were recorded the whole
time and the numbers were always derivable. A reader's link is walked whether
or not it is still live, for the same reason.

The task deletes nothing and can be run again. It exists because recomputing
totals from scratch needs a one-time repair behind it: production totals had
drifted for years, with vote tallies dropping increments and a legislator-vote
update overwriting all but one bill.

## An at-large official has no district tally worth drawing

A mayor, a council president and the like carry a district number of zero or
none, and their screens draw the reader's own chart and the locale chart
without a district one.

They stand for the whole jurisdiction, so their district totals are the locale
totals. Drawing both would put the same numbers on the page twice under two
different labels, which reads as a coincidence rather than as the identity it
is.

## Executive offices and reader agreement

A whole-jurisdiction assignment adds that district to the reader's existing district set, while executive offices participate in reader agreement through bill signing and veto actions.

The selected policy keeps the reader's district set derived from active representative links through [[app/models/user.rb#User#districts]]. A link to a supported locale-wide office can therefore add that office's whole-jurisdiction district alongside the reader's ordinary districts. [[app/models/bill_score.rb#BillScore#to_builder_with_user]] may include the corresponding [[app/models/bill_score_district.rb#BillScoreDistrict]] tally on a bill page; this does not replace the reader's other district tallies. No narrower score-specific district derivation is needed. [[representative-resolution#Locale-wide district]] applies this policy using supported distinct seats and an exactly configured whole-jurisdiction district.

Executive officeholders who sign or veto legislation (the Mayor in Baltimore, the Governor in Maryland, and the President in US Congress) participate in a legislative capacity where signing or vetoing a bill is recorded as a [[app/models/legislator_vote.rb#LegislatorVote]] and scored per term by [[app/services/score_recompute_service.rb#ScoreRecomputeService]]. Non-legislative statewide offices (Lieutenant Governor and Attorney General) remain excluded from representative resolution.

[[app/controllers/legislators_controller.rb#LegislatorsController#user_legislator_score_pair]] serializes `user_legislator_score` and `lifetime_score` for executive offices on the standard legislative path rather than suppressing them. The detail page has no separate district chart for a locale-wide office because its district tally duplicates the locale total.

The office's work, rather than the word in its title, determines whether roll-call agreement exists. A Council President is a legislative office: it can have agreement only when the supported source publishes that officeholder's legislative votes. Its district is still whole-jurisdiction, so its detail shows no separate district chart duplicating the locale chart.

Exact official service evidence remains necessary for published service intervals and historical dates. A configured seat-keyed current roster can establish only the mapped current office identity; its locale calendar supplies the term window, as described in [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Configured office metadata for current seat-keyed rosters]]. Other statewide or at-large offices are not inferred from that configuration. Expected locale-wide coverage includes the Governor in Maryland (the Attorney General and Lieutenant Governor are excluded, per [[representative-resolution#Representative resolution by seat#Maryland seat identity conventions#Executive offices without a configured chamber]]); the Mayor and Council President in Baltimore; and the President in the US Congress locale. Congress US0 is nationwide. Congress MD0 represents Maryland's U.S. Senate seats; other states' zero-numbered U.S. Senate districts also belong to Congress and are excluded for Maryland readers. Maryland's executive MD0 is a separate locale record. Sharing a whole-jurisdiction district does not merge office identities or establish that each office has the same vote or agreement behavior.

## Abstention is not disagreement

One method decides whether a user and a legislator agreed, and it recognises
four outcomes rather than two: `agreed`, `disagreed`, `legislator_abstained`,
and `no_legislator_vote`.

The distinction matters because collapsing either of the last two into
`disagreed` would punish a legislator for a bill they never got to vote on, or
for a deliberate abstention. Both would make the headline agreement figure
easy to attack. `ScoreRecomputeService.classify` is the single place that
ruling is made, so it cannot diverge between the district, locale and personal
score paths.

## Every score is bound to a term

Agreement is scoped to a `LegislatorTerm`, not to a `Legislator`. A legislator
who serves three terms accumulates three separate records, and a user's
personal score against them is likewise per-term.

Without that binding, a legislator's record from a previous term would follow
them into the current one, and a user who moved into the district last year
would be scored against votes cast before they arrived. `LegislatorTerm.covering`
resolves which term a bill falls into, using the bill's anchor date rather than
the current date, so re-running a recomputation years later produces the same
answer.

[[app/models/legislator.rb#Legislator#current_district_score]] reads the active
term's district score. It returns nil when no term is current or no score row
exists. The helper remains available to the model regression in
[[spec/models/legislator_spec.rb]] even without a production caller, so the
person-level read cannot substitute a departed term's score.

Legislators with no current term — such as a former representative whose
service has ended — are skipped rather than scored against an empty term.

## Sway is a separate quantity

"Sway" is the gamification currency: invites redeemed plus bills voted on
plus bills shared (once opened by another reader), computed by
[[app/services/influence_service.rb#InfluenceService|InfluenceService]]. It
measures participation and has nothing to do with agreement.

The vocabulary is enforced precisely because the two are easy to conflate.
"Voter agreement" is the metric comparing a user to a legislator; "sway" is the
user's own clout. `docs/terminology.md` records that "sway score" is retired as
a name for the agreement metric, and [[naming-decisions#One term per concept]]
explains why that register of decisions exists at all.

The chart captions carry that vocabulary on both surfaces.
[[app/frontend/components/legislators/charts/LegislatorChartsPanel.tsx#LegislatorChartsPanel]]
and the Expo app's legislator detail screen title the three charts
`Your agreement with <name>`, `District N agreement with <name>` and
`<jurisdiction> agreement with <name>`. In the web panel's lifetime mode only
the first appends the qualifier, as `Your agreement with <name> · lifetime`;
the district title becomes `All districts · lifetime agreement with <name>`,
which drops the district number, and the jurisdiction title carries
`· lifetime` after the locale name. Neither surface names the metric a score.
