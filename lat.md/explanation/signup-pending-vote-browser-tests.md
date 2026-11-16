---
lat:
  mode: explanation
  require-code-mention: true
---

# Signup pending-vote browser tests

Browser tests prove that a provisional vote cast by an unauthenticated reader is reconciled and persisted upon registration completion.

The onboarding journey allows an unauthenticated visitor to cast a provisional vote on a featured bill. The vote is held in an encrypted session cookie while the visitor completes phone verification, passkey enrollment, and address matching. When registration completes, the pending vote is materialized into a verified user vote and the user is redirected to the bill page.

## Provisional vote reconciliation

A provisional vote cast before signup persists through registration and is recorded as a verified user vote upon completion.

When an unauthenticated reader votes on the bill of the month, the browser saves the choice in a provisional cookie (`sway_pending_vote`). As the user completes SMS verification, passkey registration, and address selection, the cookie is preserved across redirects. After final registration submission, [[app/services/pending_vote_reconciliation_service.rb#PendingVoteReconciliationService]] creates the verified `UserVote`, deletes the provisional cookie, and lands the user on the bill page with the recorded vote visible.
