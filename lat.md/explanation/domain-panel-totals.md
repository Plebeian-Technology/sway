---
lat:
  mode: explanation
---

# Where the domain panel's totals come from

A `SendingServiceDomain` row holds no running totals. Its four counts are summed from `sending_service_domain_bills` on every read, so re-running the cleaning stage replaces a bill's contribution rather than adding to one.

A domain with no contribution rows reads as zero, never as absent — summing an
empty relation gives 0, not nil.

## Why the panel computes the totals in one query

`panel_ranked` computes all four sums as `summed_*` aliases in a single grouped
query, rather than letting each row sum its own.

That is not only about the query count. It is the panel's selection rule: the
domain string is lifted straight out of a `From:` line in a PDF any member of
the public can submit, and the format admits leading digits and hyphens, so
ordering by domain and then applying the cap could push the real sending service
past the limit where no screen ever reaches it. Ranking by machine-sent count
*before* the limit is what makes the cap and the display agree.

## Why the aliases are spelled in one place

`PANEL_TOTALS` holds the four aggregate expressions, `summed_alias` builds the
name each one is selected as, and both the query and the row readers go through
that one method.

The alias is the whole contract between the two halves. `panel_ranked` writes
`AS summed_sender_count` in SQL and `summed_or_query(:sender_count)` reads it
back by rebuilding the same name in Ruby, so a rename on one side is silent on
the other: the reader finds no such attribute, falls through to summing per row,
and the panel keeps returning correct numbers at the cost the aliases existed to
avoid. Nothing fails, which is why it would not be noticed.

## Why the readers read the attribute rather than call the alias

`summed_or_query` asks `has_attribute?` and reads with `self[alias_name]`.
Calling the alias as a method instead — `public_send(:summed_sender_count)` —
returns the same number for 360 times the allocations.

An alias from an ad-hoc `SELECT` is not a declared attribute method. Every call
falls through `method_missing` and rebuilds the lookup, and nothing about that
is visible at the call site: the code reads like a plain attribute read and
costs a metaprogramming round trip. Measured over 30 panel rows, four reads
each: 43,595 object allocations through `public_send` against 121 through the
attribute reader, for identical values. That one difference was 184,631
allocations and 61ms inside `SendingServiceDomainResource`, which was 60% of
every admin Bill Creator tab.

`has_attribute?` rather than `respond_to?` for the guard because it asks the
question actually being asked — does this loaded record carry this column. The
two agree on both load paths: true for a row loaded through `panel_ranked`,
false for one loaded any other way, which is what sends the plain load back to
summing in SQL. That fallback sums in SQL per call rather than loading every row
into Ruby, because unlike `Organization` at Baltimore's scale this table grows
with every bill.

## Why domain labels are set only by an operator

[[app/services/set_sending_service_domain_label_service.rb#SetSendingServiceDomainLabelService]] records explicit operator confirmation or dismissal of a domain rather than applying an automatic volume threshold.

Every ordinary consumer mailbox provider has many senders across multiple bills, so message volume alone cannot distinguish a coordinated advocacy platform from a general email host. Only the confirmed and dismissed statuses are writable through the service because the proposed status belongs exclusively to automated candidate detection, and confirming an already-confirmed domain is a no-op so the original confirming administrator and timestamp remain intact.

## Why the domain panel bounds, filters, and validates untrusted domains

[[app/models/sending_service_domain.rb#SendingServiceDomain]] validates domain shape against [[app/services/testimony/sender_domain.rb#SenderDomain]], caps panel queries at `MAX_PANEL_ROWS`, and hides unlabelled zero-bill rows.

Every row in `sending_service_domains` is derived from a line of a hearing PDF that any member of the public can submit, and every panel row is shipped on Bill Creator renders. Reusing `Testimony::SenderDomain::MAX_CHARS` and `Testimony::SenderDomain::FORMAT` on the model enforces the same contract where the domain is stored as where it is extracted, while `MAX_PANEL_ROWS` bounds how many rows a single document with many `From:` lines can surface. The `for_panel` scope keeps domains that still have `SendingServiceDomainBill` rows or carry a `proposed` or `confirmed` label, filtering out unlabelled residue while keeping labelled rows reachable so an operator can still revoke a label. `machine_sent_share` returns `nil` rather than `0.0` when `letter_count` is zero because a share across zero letters is undefined.

## Why DomainCountsWriter re-validates domains and deletes unlabelled orphans

[[app/services/testimony/domain_counts_writer.rb#DomainCountsWriter]] re-checks every letter's `sender_domain` against [[app/services/testimony/sender_domain.rb#SenderDomain|SenderDomain.valid?]] and deletes unlabelled `SendingServiceDomain` rows that have no remaining bill associations.

Re-validating domains on write protects stage re-runs against older stored artifacts that were extracted before empty or malformed domains were filtered out by `SenderReader`. Running `collect_unlabelled_orphans` inside the same transaction removes unlabelled domains whose last bill reference was just replaced, while preserving any domain carrying an operator's `proposed` or `confirmed` decision.
