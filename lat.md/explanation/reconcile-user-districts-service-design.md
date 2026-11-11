---
lat:
  mode: explanation
---

# Why ReconcileUserDistrictsService is built the way it is

`ReconcileUserDistrictsService` brings one user's district and legislator links back in line with reality, without ever leaving them worse off than before.

It asks the same question signing up asks — "given this address, who represents you?" — by calling `SwayRegistrationService#district_legislators`. There is no second copy of that logic. It then compares the answer with what is already stored and changes only the differences. It does NOT wipe everything and rebuild; `lib/tasks/assign_new_user_legislators.rake` is the cautionary example of that approach. Comparing is what lets an outage half-way through leave the user's existing links alone instead of leaving them with none.

## Why the comparison happens at two levels

Either level can change on its own, and only one of them touches the `user_districts` table:

- **WHICH LEGISLATORS** (updates `user_legislators`). One district can
  have several legislators — Maryland gives each district three Delegates
  and a Senator — and the person holding a seat can change while the
  district stays exactly the same, for instance when a term ends and a
  successor is added. Comparing legislator ids catches that even when the
  set of districts has not moved at all.
- **WHICH DISTRICTS** (updates `user_districts`). The rougher question of
  whether the user's geographic district changed, regardless of who holds
  the seat.

When either set changes, `#apply_diff` recomputes affected `UserLegislatorScore`, `LegislatorDistrictScore`, and `BillScore` rows through `ScoreRecomputeService` before broadcasting a score refresh so aggregate and personal agreement scores immediately reflect the reconciled assignments.

## Why a vacant seat needs no special case

The fresh answer only ever contains legislators who are currently serving, because `district_legislators` already filters to those with a current term.

So an empty seat with no successor yet simply does not appear. Comparing against that automatically switches off the old link and creates nothing new, with no special "is this seat vacant" check needed anywhere.

## Why call does not catch its own lookup failure

`#call` looks up the answer first, writes second.

If the lookup blows up — the OpenStates or Census service is down, the address will not geocode — the error escapes before a single row has been touched, because nothing before the comparison step writes to `user_legislators` or `user_districts`.

This method deliberately does not catch anything. The caller, `ReconcileUserDistrictsJob`, is responsible for keeping one bad user from stopping the rest: it catches, logs, reports to Sentry, and moves on to the next user. Keeping that in one place means a failure is not logged twice.

## Modeling a vacant seat in specs

`spec/system/legislator_reassignment_spec.rb` models a sitting representative resigning with nobody replacing them yet by deleting their only `legislator_term`, so they stop counting as serving.

`spec/system/legislator_reassignment_spec.rb` models a sitting representative resigning with nobody replacing them yet by deleting their only `legislator_term`, so they stop counting as serving — the same setup `spec/services/reconcile_user_districts_service_spec.rb` uses for an empty seat.

Its Legislators-page assertion checks for the "Representatives" heading before checking that the departed legislator's name is absent. Checking only that something is missing says nothing about a page nobody confirmed loaded — "the departed rep is not listed" is just as true of an error page, a redirect, or a list that never loaded at all, and `wait_until_loaded` only checks that a progress bar is gone, which is another absence. Checking for the heading first is what makes the following absence assertion a real claim about the Legislators page.
