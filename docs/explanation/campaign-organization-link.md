---
mode: explanation
summary: "Why naming the organization behind a campaign is a second approval with four states, how candidates are proposed from letters and bill positions, and why the two columns must agree."
status: agent-extracted
related: ["docs/explanation/campaign-scope-and-identity.md", "docs/explanation/campaign-draft-rejection.md", "docs/explanation/campaign-approval-guard-chain.md"]
---
<!-- vale Vale.Spelling = NO -->

# About linking a campaign to an organization

## Why this is a second approval and not part of the first

Approving a campaign position answers one question: what is this group of
letters arguing, and on which bill. Naming the organization behind them is a
different question, and often a harder one — several organizations can be
plausible, or none can be identified at all.

The framing is that this is a **second approval**,
used when the organization cannot be determined automatically, and that it
**sits beside the position approval rather than replacing it**. Folding it into
the first approval would force an operator to answer both questions at the same
moment or answer neither, and the second one frequently cannot be answered then.

That is also why the decision lives on the campaign row rather than on the
draft. A draft is derived data, re-read from the cleaned artifact on every
request; a campaign is a record that already exists by the time this question is
worth asking.

For a long time the column existed with no writer at all. `campaigns.organization_id`
and `Campaign belongs_to :organization` shipped with the original campaign
model, and nothing ever set them — the approval service built
`Campaign.create!(name:, sway_locale:)` and stopped. This is the surface that
fills them.

## Why there are four states and not two

An organization link that is merely present-or-absent cannot record the answer
this step most often produces. Three decisions are stored, and the absence of a
decision is a fourth state in its own right:

- **Linked** — the operator identified the organization.
- **None** — the operator looked and there is genuinely no organization behind
  this campaign. Members of the public do organize letter-writing without one.
- **Undetermined** — the operator looked and could not tell yet.
- **No decision recorded** — nobody has been asked.

The distinction that carries the most weight is the last two. "Nobody looked"
and "somebody looked and could not tell" are different facts about the same
campaign, and collapsing them would silently convert an unanswered question into
an answered one. Because that fourth state is the absence of a row value, it is
`NULL` rather than a fourth decision string: a campaign that has never been
asked about should not have to be written to in order to say so.

## Why the two columns must agree

`organization_id` and `organization_link_decision` are validated against each
other: `linked` requires an organization, and every other decision requires its
absence.

Without that rule the table can hold two states nobody can read. A row saying
`linked` with no organization asserts an identification that names nobody. A row
carrying an organization under `none` says both that an organization was
identified and that there is none. Neither is a state an operator could have
intended, so both are refused at the model rather than tolerated and interpreted
later.

This is why the two columns are written together under a lock, and why setting
`organization` alone is now refused. A link nobody recorded a decision for is
exactly the ambiguity this second approval exists to remove — an earlier model
spec asserted that a campaign "may belong to an organization" with nothing else
set, and that example now supplies the decision alongside it.

## How candidates are proposed, and why the evidence travels with them

Two kinds of evidence are read, and both are things that already exist rather
than anything inferred:

- **Signature block** — organizations named in the signature blocks of this
  campaign's own letters, matched case-insensitively against organizations in
  the bill's locale. This comes from `source_evidence["org_name"]`, which
  `Testimony::SourceKindClassifier` writes onto a letter it classified as
  someone speaking for an organization.
- **Bill position** — organizations that already hold a position on this bill.
  Weaker evidence, but it covers the common case of an organization running a
  letter campaign on a bill it had already taken a public position on.

A signature block is the stronger claim, because it is the campaign's own
letters naming the organization rather than something that organization did
elsewhere on the bill. So when both kinds name one organization it is offered
once, with the signature-block evidence, rather than twice — asking an operator
to choose between two rows that mean the same thing is not a choice.

The evidence is shipped to the screen with each candidate, and the operator is
shown how many letters signed off with the name and the name **as a letter
actually wrote it**. Sway is a civic transparency platform: someone asked to
attribute a campaign to a named organization has to be able to see why it was
offered before agreeing. A picker that listed bare names would be asking for a
judgement while withholding the grounds for it.

Matching is deliberately literal. No fuzzy or embedding-based similarity is used
here, for the same reason `Testimony::SourceKindClassifier` avoids it: "closest
match in embedding space" is not an explanation an operator can read, and a
wrong attribution of a campaign to a real organization is a public record about
that organization.

An empty candidate list is a real answer — nothing on this bill matches — and
not an inability to ask. Both decisions that need no organization stay
recordable when the list is empty.

## Why an organization from another locale is refused

A campaign belongs to one bill, and a bill to one locale, so an organization
from a different locale can never be the one behind it. The write refuses rather
than silently accepting, because this link is what an after-the-fact merge of a
published organization position would key on — a cross-locale row
would put that future correction on a foundation that was never true.

## What this does not do

It never creates an `Organization` row. It only points at one that already
exists, or records that there is none to point at. That is the same guarantee
the position approval carries, and for the same reason: an operator
working through testimony must not be able to bring a public organization record
into being as a side effect of classifying letters.

It also never touches the campaign's own position. Stance, name, summary and
counts are left exactly as the first approval set them.
