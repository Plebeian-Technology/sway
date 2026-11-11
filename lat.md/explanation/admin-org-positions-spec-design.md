---
lat:
  mode: explanation
---

# spec/system/admin_org_positions_spec.rb design notes

Design notes for spec/system/admin_org_positions_spec.rb: the conditional bill fixture, why some examples were split or renamed, the click_testid fix history, and the exact-count assertions that catch dedup regressions.

## Only materializing the bill fixture when an example uses it

The file's `after` hook cleans up summary files for `bill`.

Running that cleanup unconditionally would force every example to CREATE a bill — plus its district, legislator, and locale — purely to delete files that could not exist, including examples that never touched `bill`. The `@bill_materialized` flag, set inside the `let(:bill)` block itself, lets the cleanup ask whether the record was ever built instead of building one just to find out.

## Why an example about rendering existing drafts was renamed

"Renders a card per draft org position carried on the provisioning row" was previously named "after generation completes," which promised something about `GenerateBillSummaryJob` that it never tested.

"Renders a card per draft org position carried on the provisioning row" was previously named "after generation completes," which promised something about `GenerateBillSummaryJob` that it never tested — it renders a row the fixture wrote directly, so it still passed when the job's `draft_org_positions:` write was replaced with a plain `nil`. Rendering drafts that already exist is worth pinning on its own; producing them belongs to the job's own spec (`generate_bill_summary_job_spec.rb`, "persists the positions payload").

## Two examples for the no-testimony warning: empty list vs. stranded drafts

"Warns and disables Approve when drafts outlive the testimony they came from" exists because an empty `draft_org_positions` list is the harmless case, pinned by the example above it.

The no-testimony notice used to live inside that empty-list branch only, so the dangerous state — drafts left standing on a bill whose testimony was cleared out from under them — rendered ordinary cards with a working Approve button and no warning at all. This example pins the state the empty-list example could not see.

The retracted-evidence example that follows depends on `:with_testimony` being present: without it, the bill-level no-testimony gate fires and the example would prove nothing the stranded-drafts example above does not already prove.

## Exact counts, not be >= 1, catch org-dedup regressions

`expect(Organization.where(sway_locale: sway_locale).count).to eq(1)` (plus asserting the name) replaced a `be >= 1` check.

`be >= 1` passed whether the approval reused one organization, created one, or created three near-duplicates, so it pinned nothing about the near-match deduplication in `ApproveOrgPositionService#find_or_create_org`. An exact count plus the name is what actually catches a mistake there.

## The click_testid fix and where a shadcn Select renders its options

"Approving an edited org position" could not be written until the system-spec `click_testid` helper was fixed: a scripted JavaScript click skipped React's wrapper around the event AND Selenium's waiting.

`click_testid` now scrolls the element into view and clicks it for real, falling back to a scripted click only when something genuinely covers the element.

The shadcn Select built on Radix renders its OPTIONS at the bottom of the page body rather than inside the card, so only the `[role='option']` search runs outside the `within(card)` block — the TRIGGER is in the card and is clicked the same way every other control in this file is, through `click_testid`. This example used to script the trigger's click directly, which is the exact technique that had to be fixed: it skips React's event wrapper and Capybara's waiting.

`click_testid`'s real click runs React's whole event chain, including the `nprogress` bar that tracks Inertia requests still in flight, so it works properly with `wait_until_loaded` (see `lat.md/explanation/capybara-wait-semantics.md`). `click_testid` falls back to a scripted click only for elements something genuinely covers — a modal dialog button sitting under the dialog's own backdrop at the test window size, a react-select trigger hidden behind a sticky header. That fallback works for handlers that only change the UI, but it does NOT hook into Capybara's waiting, so the caller MUST wait on something it can see afterward — a DOM change, a prop update — and not on `nprogress` via `wait_until_loaded`, which races when the request finishes before the progress bar ever appears. If a target genuinely cannot be reached by a real click at all, call `page.execute_script("arguments[0].click()", element.native)` directly at the call site with a comment explaining why, rather than changing `click_testid` itself.

## What the audit log entry does and does not carry

The edited-approval audit log entry does not carry the stance or summary.

The edited-approval audit log entry does not carry the stance or summary — the `OrganizationBillPosition` row is the authority on those — but the entry must exist with `decision: "approved"`, so an edited approval can be told apart from a plain one in the log.
