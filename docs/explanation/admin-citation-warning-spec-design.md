---
mode: explanation
summary: "Why spec/system/admin_citation_warning_spec.rb clicks Save summary and Approve rather than only checking the warning renders, and its fixture choices for citation keys and testimony."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# spec/system/admin_citation_warning_spec.rb design notes

## The claim under test: informational, not blocking

The unverified-citation warning's whole claim is that it is a warning
rather than an error: it stops nothing. The scenario is two bad section
keys on a bill: both keys named, the plural title right for two, draft cards
with Approve and Reject on screen beside it.

Seeing the buttons is not enough: a disabled button still renders, so
"present" is not "works". Informational-not-
blocking is the whole point of this surface, and only a click can say
whether it holds — so the spec performs both writes the warning sits over:
Save summary, which publishes text to the bill, and Approve, which
publishes an organization's position.

## The two citation keys chosen for the fixture

`bad_citation_keys` returns `["§ 14-402(c)", "§ 99-999"]`. The first is the
shape a model really invents — a real section number with a subsection the
bill does not have — and the second is plainly made up. Both are kept
because the warning message names each one, and a warning that names only
some of the bad keys is worse than useless.

## Why the fixture uses :with_drafts, which brings its own testimony

`:with_drafts` is required rather than decorative: `ApproveOrgPositionService`
refuses a draft on a bill with no testimony, so without it the Approve
click would be refused for a reason that has nothing to do with citations,
and the example would pass while proving the opposite of what it claims.
