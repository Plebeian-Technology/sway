---
lat:
  mode: explanation
---
# Approving a campaign out of testimony

The Bill Creator collapses a bill's testimony into campaign drafts and offers each one for approval as a campaign position. A card is the operator's view of one draft and of whatever decision that draft already carries.

An approved card records a campaign position. It never creates an
organization: that is the organization picker's job, and keeping the two apart
is what stops a form full of testimony phrases from minting public
organizations. The card reuses the organization card's shell classes and its
submitting and disabled behaviour so the two read as one kind of object on
screen.

## The draft's content hash is its whole identity

Approve and reject both send the draft's content hash and no index.

A re-run of the clean-testimony stage reorders unchanged drafts, so a position
in the array names a different draft afterwards. The hash does not move.
Requiring both turned an ordinary re-run into a refusal of a correct approval.

## Why a decision is read back onto the card

The drafts are re-read from the cleaned artifact on every load, and the
artifact knows nothing about decisions, so a decision has to travel separately
or it is invisible.

Without it an approval left the card looking exactly as it had before — through
the redirect and through a reload — and an operator working many drafts of one
bill had no way to tell which they had already handled. The card now opens on
the recorded decision: its fields show what was approved, and a rejected draft
renders as rejected on first paint rather than being hidden in the browser,
which is also what makes a rejection survive a reload.

A campaign approved before the source draft was recorded carries no hash, so
the card treats a missing hash as "no decision recorded for this draft" rather
than as a match.

What travels back is bill-scoped, and that is the whole difference from the
locale-wide match step it replaced. That step offered campaigns from other
bills so an operator could say "this is that campaign again", which stopped
making sense once a campaign belonged to one bill. What ships now is only the
campaigns already approved on the bill being viewed — a record of what the
operator has done on this screen, not a matching aid, and it should not grow
into one. Which organization stands behind a campaign is a separate decision,
carried by its own attribute.

## Marking false-positive campaign drafts as individual letters

An unapproved campaign draft card provides a Mark as Individual Letters action alongside Reject to treat false-positive groups as constituent letters.

When an operator marks a draft as individual letters in [[app/frontend/components/admin/creator/BillCreatorCampaignPositionCard.tsx#BillCreatorCampaignPositionCard]], the card collapses into a compact status row displaying an `INDIVIDUAL LETTERS` warning badge, sender and letter counts, and a Restore button. Unlike Reject, which excludes the letters from constituent browsing, marking as individual letters releases constituent letters back into the browsable public testimony pool while keeping the campaign draft collapsed. Clicking Restore on an individual letters row posts to the restore draft endpoint and returns the card to its active unapproved state.

## An unnamed campaign is a complete record

The empty string is the name field's starting value and stays valid all the way
through Approve.

An unnamed campaign is a whole record rather than a half-finished one, so
nothing blocks the approval, and the operator types a name freely with no
matching step in between.

## Why the affiliation card seeds from the organization name

The claimed-affiliation card fills its name box from the regex's separate
capture of the organization, not from the whole matched phrase.

The phrase is the entire "role of the org" sentence. Seeding from it meant an
unedited Approve created a public organization named after a job title.

## How claimed-affiliation evidence is structured and guarded

[[app/frontend/components/admin/creator/claimed-affiliation-card/ClaimedAffiliationEvidence.tsx#ClaimedAffiliationEvidence]] renders the signature phrase, claimed role, and sender behind a claimed affiliation as plain text inside a description list.

The component accepts a single evidence object rather than loose phrase, role, and sender props because the jsx-a11y aria-role lint rule flags any JSX attribute named role regardless of which element it sits on. Long phrases clamp at [[app/frontend/components/admin/creator/claimed-affiliation-card/ClaimedAffiliationEvidence.tsx#PHRASE_DISCLOSURE_THRESHOLD_CHARS]] characters using a character-length heuristic rather than DOM measurement, and clamped text remains selectable so an operator can copy a misparsed phrase. If all three fields are empty, the component returns null independently of its caller, and every testimony string renders strictly as a plain text node rather than markup or a link target.

## Display clamp and support-to-stance lookup on the campaign card

`NAME_CLAMP_LENGTH` is a display-only clamp that keeps a card's heading to one line until expanded, while the server enforces the stored character bound on `Campaign`.

`SUPPORT_TO_STANCE` maps the stored `FOR`, `AGAINST`, and `ABSTAIN` values back to the editor's stance vocabulary explicitly rather than inverting `STANCE_TO_SUPPORT`, so an unrecognised wire value falls through to the default stance instead of handing `undefined` to the `Select`.

## Claimed affiliation card shape and partial-evidence rule

`IClaimedAffiliationDraft` keys each card by `position`, the letter's fixed slot in the cleaned artifact, while keeping `org_name` top-level to seed the editable name box.

When all three evidence fields (`phrase`, `role`, and `sender`) are blank, the card returns `null` rather than rendering an unsupported name-only claim. Because claimed-affiliation drafts have no stored per-entry database row, clicking Reject dismisses the card for the current render only, matching `BillCreatorCampaignPositionCard`.
