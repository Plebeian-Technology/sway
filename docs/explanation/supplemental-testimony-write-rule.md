---
mode: explanation
summary: "Explains SupplementalTestimonyWrite's clear/blank/present rule for turning an operator's testimony paste into attributes, and why blank never clears."
status: agent-extracted
related: [docs/explanation/evidence-retraction.md, docs/reference/evidence-retraction-writers.md]
---
# The supplemental-testimony write rule

<!-- vale Vale.Spelling = NO -->

`SupplementalTestimonyWrite.attrs` is the one rule for turning a
supplemental-testimony request into attributes to write. An earlier fix
established the rule and `GenerateBillSummaryService` owned it. A later change
added a second caller, `UpdateSupplementalTestimonyService` (behind the
Clear affordance) — and a rule with this much history behind it is exactly
the kind that must not be copied. The phase's signature defect is a control
applied at one call site when two exist, so `SupplementalTestimonyWrite`
exists to make that impossible: both callers go through the same class.

For how a write also marks existing drafts as evidence-retracted, see
[Marking a draft's evidence as retracted](evidence-retraction.md) and the
[writer catalog](../reference/evidence-retraction-writers.md), which cover
`SupplementalTestimonyWrite`'s two retraction paths in detail.

## Why the request specs cover all three routes to `attrs(clear: true)`

`SupplementalTestimonyWrite.attrs(clear: true)` is a single piece of code,
but three different requests reach it. `spec/requests/bills_spec.rb`
gives each its own example, because the recurring
defect in this area is a check added at one call site when several exist.
Covering all three is what makes "every route is behind the check" a fact
rather than a claim.

## The rule, and why each branch is what it is

- **`clear` → `nil`**, and retract the drafts standing on it. Destroying
  stored text requires an explicit act, and it destroys the evidence behind
  every draft drawn from it.
- **blank → `{}`** (leave untouched). A blank value never destroys a stored
  one.
- **present → write it**, and retract the drafts it was standing on when the
  write replaces stored testimony rather than adding to it.

## Why blank never clears

The client seeds its textarea once at mount while `usePoll` refreshes the
bill prop every 5 seconds without remounting, so a tab opened while the
column was `NULL` holds `""` for as long as it stays open. Under an earlier
contract (`""` meant clear), that stale tab destroyed a paste another
operator had made in the meantime.

No compare-and-swap is available: the client does not send the value it
last saw, so "the operator deleted the text" and "this tab never had the
text" are the same request over the wire. The write cannot tell them apart,
so it treats a blank value as the second case — the safe one — and only the
explicit `clear` flag can destroy stored text.

## Why `provisioning:` is required, not defaulted

`SupplementalTestimonyWrite.attrs` takes `provisioning:` as a required
keyword rather than a default. The retraction decision cannot be made
without the row's stored value, and a third caller quietly omitting the
argument is precisely the shape this class exists to make impossible — see
above, one caller already skipped the shared rule once.

## `to_s.presence` and the Steep narrowing trap

`written = value.to_s.presence` is the blank-detection line, deliberately
spelled this way rather than `return {} if value.blank?`. `to_s.presence`
collapses exactly what `value.blank?` would reject — `nil`, `""`, and any
whitespace-only paste — down to `nil`, and returns the paste itself
(`String#to_s` and `#presence` both return `self` on a present value)
otherwise, so the value written is the operator's, byte for byte.

The nil-check spelling matters because Steep narrows a local on
`return ... if x.nil?` but does NOT narrow one on a `blank?` guard. The
`blank?` spelling left `value` typed as `(String | nil)` at the
`#evidence_retraction_attrs` call, which takes a `String` because it calls
`#include?` on it — reaching that call with `nil` would be a
`NoMethodError`, and the guard was the only thing preventing it. Switching
to a `nil`-returning local (`written`) and a `return {} if written.nil?`
guard gives Steep what it needs to narrow.
