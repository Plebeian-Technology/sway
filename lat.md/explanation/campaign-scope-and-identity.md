---
lat:
  mode: explanation
---

# About campaign scope and identity

A campaign, in Sway, is advocacy by an organization's members about one specific bill. Members write letters about that bill as part of that campaign. An organization spans many bills; a campaign does not.

That definition corrects the shape the code had, which came from an inference rather than a decision.

## Where the wrong scope came from

The plan that introduced campaigns described them as a first-class record "mirroring Organization, with a per-bill position row alongside it".

The implementation mirrored `Organization` faithfully — and `Organization` is locale-scoped with its bills reached through a position join table. Bill-spanning came along with the mirror.

This is worth dwelling on, because it is not a coding slip and there is no careless commit to point at. The settled list for campaigns is specific about a lot of things: a campaign looks like an organization on screen, is never followable, may tie to an organization, may stay unnamed, a sender's words stay with the campaign, approval reuses the draft-position flow, a guessed sponsor shows its evidence. Scope is not on that list. So the implementation drew an inference where the record was silent, and the inference was reasonable. Mirroring a good design is how the wrong thing got built.

The lesson generalises: when a plan says "mirror X", the properties of X that nobody discussed come across too, and the ones that do not fit are the ones nobody will notice.

## What follows from scoping to a bill

Once a campaign belongs to one bill, three things stop making sense.

**The join table.** `campaign_bill_positions` existed because a campaign could have a different stance on each of several bills. With one bill per campaign the join holds nothing the campaign does not already imply, so the stance, the summary and the counts an operator approved became the campaign's own attributes and two tables became one.

**The old uniqueness rule.** Names were unique per locale, so one campaign named X existed for a whole jurisdiction and was reused on every bill in it. Under the corrected model that is not merely redundant, it is actively wrong: two different bills' campaigns of the same name collide, and the second approval silently reuses the first row — rewriting a stance an operator approved on a different bill entirely. Uniqueness is now per bill.

**The card's match step.** The campaign draft card used to show existing named campaigns from elsewhere in the locale, so an operator could say "this is that campaign again". A fresh bill now has no campaigns to match against, so the step could never show anything. It was removed rather than rescoped, because matching across bills is the *organization's* job: the organization is the one thing here that legitimately spans bills, and it already does. The surface that records which organization is behind a campaign is a separate, second approval step — the one you reach for when more than one organization is a plausible match. That step does not exist yet; the column and the association do.

## How one campaign is told from another

Within a bill, a campaign is matched by its whole name, ignoring case, taking the lowest id when two rows differ only in case.

An operator retyping a name is not naming a different campaign, but an operator typing a different name is.

It did not always work that way. Matching once used a Jaro-Winkler similarity score with a 0.9 bar. Two campaign names that opened the same way and then argued opposite sides scored 0.9405 — over the bar. The second approval reused the first campaign, found its existing position on that bill, and rewrote FOR to AGAINST. Nothing in the interface said so.

The judgement behind removing it: fuzziness belongs where a person can see it and overrule it, not in a silent server-side merge. A suggestion an operator accepts or ignores is a good use of a similarity score. Choosing which stored row to overwrite is not.

An unnamed campaign is never matched at all, and every approval of one creates a fresh record. "324 people sent this letter" is a whole record without a name, and matching unnamed rows to each other would fold every anonymous campaign on a bill into one.

## Why one campaign means one draft, within a bill

A campaign draft is a cluster of letters that reuse the same text.

It is tempting to think a campaign might own several such clusters on one bill — the same template appearing at two different hearings, say — which would make a single "which draft did this come from" reference the wrong shape.

It does not, because of where the grouping runs. Letters are grouped over the bill's whole composed testimony, after every hearing bundle has been concatenated, not per bundle. A template that appears at two hearings is therefore one cluster containing letters from both, not two clusters. The observation that one group id appeared in two of bill 25-0064's bundles was made by grouping each bundle separately; it does not describe what the stage actually produces. (That same bill has a separate, real problem: roughly a third of its letters are published in both bundles and counted twice.)

## Recording which draft a campaign came from

Two *different* campaign drafts on the *same* bill, approved under the same name, resolve to the same row.

Scoping to the bill shrank that collision from locale-wide to one bill; it did not close it. What made it a defect rather than a limitation was that the second approval was indistinguishable from the first: nothing recorded which draft either decision was made from, so a re-approval of one draft and a collision between two looked identical, and the operator was given the same success message either way.

`campaigns.source_campaign_draft_hash` is what tells them apart. It holds the approved draft's own content hash — deliberately not a foreign key, because a draft lives in a JSON artifact and has no table behind it. Rows approved before the column existed hold nil, which reads as "unknown draft".

### Why the collision is reported rather than refused

Refusing the second approval outright is the tidier rule, and it is the wrong one here.

The `(bill_id, name)` unique index means a second same-name row cannot exist, so the only choices are to refuse or to replace. Refusing would be correct if one campaign really did produce exactly one draft — which is the model above, and is what the grouping stage is meant to deliver. It is not what it delivers today: on bill 25-0064 a single multi-bill campaign is split across eight drafts. An operator working that bill would approve the campaign once and then be refused seven times, with no way to fix the cause from that screen and no honest way to record the remaining letters short of inventing seven distinct names.

So the replacement stands, and `:approved_replacing_draft` says so — in the flash message the operator reads and in the decision log, which records the hash of the draft that was replaced. That turns a silent overwrite into a stated one. It is a deliberately temporary shape: once fragmentation is fixed, a same-name approval from a different draft becomes genuinely suspicious, and refusing it becomes the right rule.

The general point is that a validation which is correct against the intended data can still be wrong against the data you actually have, and a guard whose only escape hatch is for the operator to falsify their input is worse than no guard.

## Why the name bound sits on the model

A campaign's name comes from text a member of the public wrote — a letter's own signature block, or an operator's rename.

`MAX_NAME_CHARS` bounds it on the model, at the one place every writer passes through, rather than in `ApproveCampaignPositionService` alone, so a future writer (a bulk import, a console fix) gets the same guarantee for free.

It matches `Category::MAX_NAME_CHARS`'s shape with a higher ceiling, because a campaign's name can be a whole sentence ("Complete streets letter") where a category label is short.

## Why the stance map is a copy

`Campaign::STANCE_TO_SUPPORT` is an independent copy of `OrganizationBillPosition::STANCE_TO_SUPPORT`, not a shared reference.

`ApproveCampaignPositionService` is never allowed to name `Organization` at all, and grepping that file for "Organization" is how the rule stays true rather than merely claimed. Sharing the constant would have put the word back.

`Campaign.normalize_support` returns nil for an unrecognised input, and callers refuse on nil, so an unknown stance word cannot slip through silently.

## Why destroying a bill destroys its campaigns

`campaigns.bill_id` is `NOT NULL` with a foreign key, so destroying a bill that drew a campaign raises without `dependent: :destroy`.

Nothing declared the equivalent for the table this replaced, so that path was already unguarded before the rescope — the association is new, the exposure is not.

## What the bill prop carries about campaigns

`BillsController` sends a `campaigns:` prop holding the campaigns already approved **on the bill being viewed**.

It did not always. Under the corrected scope, the prop's original job — offering campaigns from elsewhere in the locale to match against — had nothing left to feed, so it was removed outright, and the surface that replaces that job is the organization picker, which does not exist yet. What brought a prop back is a different need: an approved campaign was otherwise invisible, so a draft card looked untouched after a successful approval and after a reload, and an operator working many drafts could not tell which they had already handled.

The distinction is worth holding onto, because the two look alike and only one is wanted. Showing an operator **what they have already done on this bill** is not the same as offering them **things from other bills to match against**. A future reader tempted to widen the query past `@bill.campaigns` is rebuilding the match step that was deliberately removed.

### What this means for the retired non-vacuity guard

Removing the prop once closed off the last path by which a campaign name could reach the pipeline tab (`TestimonyCampaignDraftResource` never carried one either — see its own comment).

`spec/system/admin_testimony_report_layout_spec.rb`'s long-text example had proved a campaign name reached the page before asserting the report never printed it, guarding against the assertion passing on a page that was never served the string. With no prop left to carry one, that guard became unsatisfiable by construction rather than by the report's own restraint, so it was retired (both the E2 and E4 rows' campaign-name halves).

`CampaignResource` carries `name`, so **that guard is satisfiable again** — a bill with an approved campaign now does serve a campaign name to every tab, including the one whose report must not print it. The retired example was not reinstated afterwards, so the report's restraint is currently unproven rather than proven vacuously. That is a smaller gap than it was, but it is a real one, and it is recorded rather than left implicit here.

The long-campaign-name measurement meanwhile still lives in `spec/system/admin_position_cards_layout_spec.rb`, which now has a second way to put a long name on screen: an operator pasting into the campaign card, and a card opening on a long name read back from an earlier approval.

## A note on the migration

Both campaign tables were dropped and rebuilt rather than altered.

They exist only on the phase branch — nothing on `claude` creates them and no deploy has run them — so there was no production row to preserve, and any dev row predated the bill column with no value to backfill it from. The migration's `down` is reversible in schema and not in data, which is the honest description of dropping a table.
