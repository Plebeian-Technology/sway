---
lat:
  mode: explanation
---
# Low-friction voting

Low-friction voting captures constituent intent immediately upon article arrival while strictly preserving verified-only score invariants and passkey authentication.

Related architectural concepts include [[identity-and-access]], [[embeddable-bill-widget]], and [[partner-article-engagement]].

## Web and mobile preview destinations

The web Preview Sway control stays inside the application; the mobile control opens the public website through its existing external URL.

The web candidates are the in-app `/bill_of_the_month` route and `https://sway.vote/bill_of_the_month`. [[app/frontend/components/auth/PasskeyPanel.tsx#PasskeyPanel]] uses an Inertia link to the monthly route declared by [[app/frontend/sway_constants/routes.ts#ROUTES]]. [[mobile/src/screens/AuthScreen.tsx#AuthScreen]] continues to open the external address from [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]].

Keeping the web entry in-app preserves the public bill and provisional-vote journey described in [[low-friction-voting#Provisional vote capture and cookie lifecycle]]. That preview belongs to the same guest-interaction scope. The mobile entry follows its separate signed-out navigation boundary, documented in [[identity-and-access#The sign-in challenge says which ceremony to run#Mobile authentication screen]].

## Provisional vote capture and cookie lifecycle

Provisional voting captures a reader's intent in an encrypted HTTP-only cookie before authentication, avoiding database bloat and maintaining the never-fabricate-domain-data invariant.

When an unauthenticated reader arrives at a bill page from a partner newsroom article and selects a vote option, the selection is transmitted to `ProvisionalVotesController#create`. Rather than persisting an unverified row into `user_votes` or mutating public `BillScore` tallies, the server validates the bill and support stance before issuing an encrypted cookie (`cookies.encrypted[:sway_pending_vote]`). The cookie payload contains the target `bill_id`, the validated `support` stance (`FOR` or `AGAINST`), a cryptographic nonce, and an expiration timestamp set to 24 hours. This structure ensures zero database pollution from abandoned sessions while providing tamper resistance through Rails message encryption.

Because provisional vote submissions use browser `fetch` directly rather than an Inertia visit, successful provisional vote responses invoke `router.flushAll?.()`. This invalidates prefetched bill and featured-bill pages in the client cache, preventing subsequent link visits from serving stale `pending_vote: null` props.

## Reconciliation on registration and sign-in

Post-authentication reconciliation converts pending provisional votes into verified constituent votes and routes returning voters back to their chosen bill.

When a visitor completes passkey enrollment and address geocoding in `SwayRegistrationController#create`, or signs into an existing account via `Users::Webauthn::SessionsController#callback`, `PendingVoteReconciliationService` checks for the presence of the provisional cookie. If found, the service decrypts the vote payload and validates that the referenced bill is active and the support value conforms to `LegislatorVote::Support::FOR_AGAINST`. It then creates the verified `UserVote` record, triggers `ArticleEngagementTrackerService.track_vote` to record the partner attribution, logs the `first_vote_cast` funnel event, and redirects the constituent directly to `bill_path(bill)`.

## Cast-vote finality and replay protection

Reconciliation enforces strict replay protection and respects cast-vote finality when an authenticated user has previously voted on the target bill.

To prevent duplicate submission or replay hazards, `PendingVoteReconciliationService` deletes the provisional cookie immediately upon reading it from the request. When an authenticating user already holds a recorded vote on the target bill, the service enforces Sway's immutable cast-vote finality policy: if the provisional stance matches the existing vote, the system treats the operation as an idempotent success without incrementing engagement counters; if the provisional stance conflicts with the existing vote, the recorded vote remains unchanged and the conflicting provisional stance is rejected with `UserVotesController::VOTE_ALREADY_RECORDED_MESSAGE`.

## Secret ballot preservation and attribution

Provisional vote conversion increments anonymous partner engagement metrics without creating any relational link between the constituent and the newsroom source.

Ballot secrecy is maintained across the entire provisional lifecycle. The provisional cookie carries only the bill identifier and support choice, completely separated from the partner referral cookie (`cookies.permanent[:sway_attribution_key]`). When `PendingVoteReconciliationService` materializes the verified vote, it creates a standard `UserVote` row containing only `user_id`, `bill_id`, and `support`, leaving no relational tie or foreign key to partner articles. Partner metrics are incremented exclusively through atomic counter caches on `ArticleBill`.
