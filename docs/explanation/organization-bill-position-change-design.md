---
mode: explanation
summary: "Explains OrganizationBillPositionChange's pending scope, the stance-validation bug it fixed, its two-way status/audit-stamp invariant, why it has no hand-written #approved?, and why rejection fields serialize even when always null today."
status: agent-extracted
related: [docs/explanation/org-position-approval-guard-chain.md]
---
<!-- vale Vale.Spelling = NO -->

# OrganizationBillPositionChange design notes

`OrganizationBillPositionChange` is a member-proposed edit to an existing
published `OrganizationBillPosition`, awaiting admin approval or rejection.

## Why the pending scope filters on two columns together

`.pending(organization)` filters on BOTH `status: :pending` AND
`approved_by_id: nil`. Together the two conditions exclude both approved
and rejected rows. The schema does not enforce that `status` and
`approved_by_id` agree with each other, so dropping either filter is
unsafe — it would rely on an invariant nothing in the database guarantees
(see the two-way validation section below, which is what actually keeps
them in agreement).

Rejected rows are excluded from `.pending`, which means a non-admin
proposer whose change is rejected sees the row simply vanish from their
pending-changes panel, with no notification or history view surfaced yet.
That UX gap is a known, deliberate deferral (notify `updated_by` later),
not a bug.

## Why STANCE_TO_SUPPORT lives on OrganizationBillPosition

`OrganizationBillPosition::STANCE_TO_SUPPORT` is the single source of
truth mapping wire-side stance words (`"support"`/`"oppose"`/`"neutral"`)
to the legacy `support`-column values (`"FOR"`/`"AGAINST"`/`"ABSTAIN"`). It
also maps each legacy value to itself, tolerant of an operator or a
migration that already stores the legacy value directly. It was hoisted
out of two controllers that each carried their own copy of the same
mapping — one edit here now keeps both in sync instead of two hand-typed
copies drifting apart, which is exactly the shape of drift
`OrganizationBillPositionChange#new_support`'s validation (below) depends
on not happening.

## The stance-validation bug: why new_support validates against a shared list

`new_support`'s NOT NULL database column used to accept an empty string,
so a blank `new_support` could be saved on this row and only break later,
when `ApprovePositionChangeService` copied it onto
`OrganizationBillPosition#support`, whose presence validation raised — a
500 handed to the approving admin over someone else's bad input three
steps upstream.

The inclusion list is `OrganizationBillPosition::STANCE_TO_SUPPORT.keys`,
the one place that already names every stance word a caller may send (the
controller's wire words plus the legacy column values), rather than a
second hand-typed list that could drift from it.

## Why status and its *_by_id columns are validated in both directions

A finalized `status` and its audit stamp (`approved_by_id`/`rejected_by_id`/
`rejected_at`) must always travel together, but nothing in the schema
enforces that on its own. The controller's `#destroy` and `#update`
branches write `status` and the `*_by_id` column together atomically today,
but a future code path that flipped `status` without stamping the matching
column (or the reverse) would leave the row in a state where `#finalized?`
(`approved? || rejected?`, which reads the enum) would disagree with any
code that instead checked `approved_by_id.present?` directly.

The model validates the invariant in both directions as cheap
defense-in-depth: presence is required when the matching status is set
(`validates :approved_by_id, presence: true, if: -> { status ==
"approved" }`, and the parallel rules for rejection), and absence is
required when it is NOT (`validates :approved_by_id, absence: true, if: ->
{ status != "approved" }`, and the parallel rules for rejection). Together
the pair of validators guarantees `approved_by_id.present? <=> status ==
"approved"` for any row that ever passes validation.

## Why there is no hand-written #approved? override

An earlier `def approved? = !approved_by_id.nil?` override was removed.
The `enum :status` macro already generates `#approved?` from `status ==
"approved"`, which is the canonical source of truth, and the two-way
validators above guarantee the two definitions agree for any valid row —
so a hand-written override would be a second, redundant definition of the
same fact, exactly the kind of duplicate that can quietly drift. It also
matters for composition: `#finalized?` combines the enum-generated
`#approved?` with the enum-generated `#rejected?`, and a hand-written
`#approved?` reading a different column risks the two no longer meaning
the same thing to a caller reading either.

`#approved?` alone does not mean "is finalized" — a rejected row has
`approved? == false` too — so `#finalized?` exists as the single source of
truth callers asking "is this row still open?" should read, rather than
each caller re-deriving the OR itself.

`organization_bill_position_change_spec.rb`'s `#finalized?` examples check
the helper across all three enum states on purpose: without that coverage,
a future "simplification" to `def finalized? = approved?` would still
compile, still pass the type checker, and silently break the soft-rejected
guard chain (`Organizations::PositionsController#change_must_not_be_finalized!`,
and similar checks) that depends on a rejected row also reading finalized.

## Why rejection fields serialize even though they're always null today

`to_builder` sends `rejected_by_id`, `rejected_at`, and `status`
symmetrically with `approved_by_id`, even though the `pending` scope
(the only scope callers currently use) filters rejected rows out — so
today every serialized row has `status: "pending"` and null rejection
fields. They are included now so a future "history" or "include-all"
surface can tell pending, approved, and rejected rows apart client-side
without re-deriving it from the `*_by_id` columns, matching the optional
fields already declared in
`app/frontend/hooks/users/useUserOrganizationMembership.ts` and mirrored in
`mobile/src/hooks/usePendingChanges.ts`.
