---
lat:
  mode: tutorial
---
# Trace a vote through the system

This walkthrough follows one user's vote from the tap that casts it to the number that appears on a legislator's page. By the end you will have seen every layer of Sway once and will know which file to open for each of them.

Reading [[system-shape#One process, two languages]] first is worth five minutes; everything below assumes the Inertia model it describes.

## What you will end up with

An understanding of the whole request-to-score path: which controller receives a vote, which job carries the work off the request cycle, which service rebuilds the aggregates, and how the browser learns the numbers changed.

## Steps

Each step opens one file. Reading them in order follows the vote forward through the system.

1. **Start at the page.** Open `app/frontend/pages/Bill.tsx`. The bill, the current user's vote and the score props all arrived from a controller — there is no fetch call to find. Then open `app/frontend/components/bill/hooks/useCastUserVote.ts`, which owns the submit: it is Inertia's `useForm`, not an API client.

2. **Find the controller.** Open `app/controllers/user_votes_controller.rb` and read `create`. It writes a `UserVote` and answers with `redirect_or_json` — a redirect for the browser, a `{redirect, flash}` envelope for mobile. Notice that it computes nothing: the next render supplies fresh props.

3. **Read the model's commit hook.** Open `app/models/user_vote.rb`. Two things are worth pausing on. The `support` validation allows only `FOR` and `AGAINST` — a user cannot abstain, though a legislator can. And `after_create_commit :update_scores` enqueues `OnUserVoteUpdateScoresJob` rather than doing work inline.

4. **Follow the job to its service.** Open `app/jobs/on_user_vote_update_scores_job.rb`, then `app/services/score_updater_service.rb`. The service opens one transaction and calls `ScoreRecomputeService` four times: once for the bill, once per the user's own legislators, once for each of those legislators' districts, and once across the locale.

5. **Read the rebuild.** Open `app/services/score_recompute_service.rb`. Each call rebuilds its aggregate from the underlying votes rather than incrementing a counter. Find `classify` — it is the single place that decides whether a user and a legislator agreed, and it returns four outcomes, not two. [[scores-and-agreement#Abstention is not disagreement]] explains why.

6. **Notice the term binding.** Still in the recompute service, see that every legislator-facing score hangs off a `LegislatorTerm` resolved by `LegislatorTerm.covering(bill_anchor_date, ...)`. The bill's own date decides the term, not today's date, which is what makes a re-run years later reproduce the same answer.

7. **Watch the push go out.** Back in `ScoreUpdaterService`, after the transaction commits, `broadcast_score_refresh` publishes to `scores_<user_id>` on `ScoreChannel`. The broadcast is wrapped in a rescue: a failed push logs and moves on rather than failing the job that already wrote correct data.

8. **Close the loop in the browser.** Open [[app/frontend/hooks/useScoreSubscription.ts#useScoreSubscription]]. It answers `refresh_scores` with `router.reload({ only: onlyProps })` — a partial reload of just the score props from the same controller action you read in step 2. The socket is not the only path; user-facing pages also poll every 15 seconds so a dropped connection cannot strand a stale tally on screen.

9. **See where the number lands.** The rebuilt `UserLegislatorTermScore` is what a legislator page renders as voter agreement. Open `app/frontend/pages/Legislator.tsx` and confirm it, too, receives its numbers as props.

## Where to go next

[[domain-entities#Scores]] is the map of the five score families and the question each one answers. [[legislation-pipeline#The stage graph]] covers the other direction — how the bill you just voted on came to exist.
