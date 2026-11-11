---
lat:
  mode: explanation
---

# About linking a campaign to an organization

Why naming the organization behind a campaign is a second approval with four states, how candidates are proposed from letters and bill positions, and why the two columns must agree.

## Why this is a second approval and not part of the first

Approving a campaign position answers one question: what is this group of letters arguing, and on which bill.

Naming the organization behind them is a different question, and often a harder one — several organizations can be plausible, or none can be identified at all.

The framing is that this is a **second approval**, used when the organization cannot be determined automatically, and that it **sits beside the position approval rather than replacing it**. Folding it into the first approval would force an operator to answer both questions at the same moment or answer neither, and the second one frequently cannot be answered then.

That is also why the decision lives on the campaign row rather than on the draft. A draft is derived data, re-read from the cleaned artifact on every request; a campaign is a record that already exists by the time this question is worth asking.

For a long time the column existed with no writer at all. `campaigns.organization_id` and `Campaign belongs_to :organization` shipped with the original campaign model, and nothing ever set them — the approval service built `Campaign.create!(name:, sway_locale:)` and stopped. This is the surface that fills them.

## Why there are four states and not two

An organization link that is merely present-or-absent cannot record the answer this step most often produces. Three decisions are stored, and the absence of a decision is a fourth state in its own right:

- **Linked** — the operator identified the organization.
- **None** — the operator looked and there is genuinely no organization behind
  this campaign. Members of the public do organize letter-writing without one.
- **Undetermined** — the operator looked and could not tell yet.
- **No decision recorded** — nobody has been asked.

The distinction that carries the most weight is the last two. "Nobody looked" and "somebody looked and could not tell" are different facts about the same campaign, and collapsing them would silently convert an unanswered question into an answered one. Because that fourth state is the absence of a row value, it is `NULL` rather than a fourth decision string: a campaign that has never been asked about should not have to be written to in order to say so.

## Why the two columns must agree

`organization_id` and `organization_link_decision` are validated against each other: `linked` requires an organization, and every other decision requires its absence.

Without that rule the table can hold two states nobody can read. A row saying `linked` with no organization asserts an identification that names nobody. A row carrying an organization under `none` says both that an organization was identified and that there is none. Neither is a state an operator could have intended, so both are refused at the model rather than tolerated and interpreted later.

This is why the two columns are written together under a lock, and why setting `organization` alone is now refused. A link nobody recorded a decision for is exactly the ambiguity this second approval exists to remove — an earlier model spec asserted that a campaign "may belong to an organization" with nothing else set, and that example now supplies the decision alongside it.

## How candidates are proposed, and why the evidence travels with them

Two kinds of evidence are read, and both are things that already exist rather than anything inferred:

- **Signature block** — organizations named in the signature blocks of this
  campaign's own non-repeat, non-excluded letters, matched case-insensitively
  against organizations in the bill's locale. This comes from
  `source_evidence["org_name"]` (written by `Testimony::SourceKindClassifier`
  onto a letter classified as someone speaking for an organization), falling
  back to `extracted_org["org_name"]` (extracted by
  [[app/services/testimony/organization_entity_extractor.rb#OrganizationEntityExtractor]]).
  Excluding repeat copies (`repeat: true`, which remain in `letter_positions`
  for disclosure) and manually removed letters (`excluded: true`) ensures the
  candidate's `letter_count` agrees with the campaign's active letter count and
  never proposes an organization from a removed letter.
- **Bill position** — organizations that already hold an active position on this bill.
  Weaker evidence, but it covers the common case of an organization running a
  letter campaign on a bill it had already taken a public position on. Deactivated (`active: false`) positions are excluded so soft-removed organizations are not falsely offered as holding a position on the bill.

A signature block is the stronger claim, because it is the campaign's own letters naming the organization rather than something that organization did elsewhere on the bill. So when both kinds name one organization it is offered once, with the signature-block evidence, rather than twice — asking an operator to choose between two rows that mean the same thing is not a choice.

The evidence is shipped to the screen with each candidate, and the operator is shown how many letters signed off with the name and the name **as a letter actually wrote it**. Sway is a civic transparency platform: someone asked to attribute a campaign to a named organization has to be able to see why it was offered before agreeing. A picker that listed bare names would be asking for a judgement while withholding the grounds for it.

Matching is deliberately literal. No fuzzy or embedding-based similarity is used here, for the same reason `Testimony::SourceKindClassifier` avoids it: "closest match in embedding space" is not an explanation an operator can read, and a wrong attribution of a campaign to a real organization is a public record about that organization.

An empty candidate list is a real answer — nothing on this bill matches — and not an inability to ask. Both decisions that need no organization stay recordable when the list is empty.

## Why an organization from another locale is refused

A campaign belongs to one bill, and a bill to one locale, so an organization from a different locale can never be the one behind it.

The write refuses rather than silently accepting, because this link is what an after-the-fact merge of a published organization position would key on — a cross-locale row would put that future correction on a foundation that was never true.

## Creating an organization when none of the candidates match

When the organization behind a campaign is not among the proposed candidates, the operator can create and link it directly in [[app/frontend/components/admin/creator/campaign-position-card/CampaignOrganizationLink.tsx#CampaignOrganizationLink]].

Approving a campaign position (the first approval) never creates an `Organization` row as a side effect, and linking by `organization_id` in [[app/services/link_campaign_organization_service.rb#LinkCampaignOrganizationService]] points strictly at an existing organization in the bill's locale. However, campaign letters frequently originate from coalitions, neighborhood associations, or advocacy groups that have not yet taken a standalone bill position on the current bill or been seeded into the locale's `Organization` table, leaving the candidate list empty or incomplete.

To let the operator resolve the second approval without leaving the campaign card:
- [[app/frontend/components/admin/creator/campaign-position-card/CampaignOrganizationLink.tsx#CampaignOrganizationLink]] renders a text input (`Create an organization` when no candidates exist, or `Or create a new organization` alongside the candidate dropdown).
- Typing a new name clears any selected dropdown candidate and updates the action label to `Create and link organization`; selecting a dropdown candidate clears the text input so the submission payload is never ambiguous.
- Pressing `Enter` inside the text input or clicking `Create and link organization` submits `{ decision: "linked", organization_name }` to [[app/controllers/campaigns_controller.rb#CampaignsController#link_organization]] and clears the input on success.
- Because the card stays mounted across Inertia redirects (`preserveScroll: true`), [[app/frontend/components/admin/creator/campaign-position-card/CampaignOrganizationLink.tsx#CampaignOrganizationLink]] synchronizes its selected `choice` state whenever `campaign.organization_id` or `campaign.organization_link_decision` changes in props (and restores `serverChoice` if the new-organization text input is cleared back to empty), appends a fallback `<SelectItem>` when a linked organization is not among the proposed `candidates`, and updates the empty-candidates message when `decision === "linked"` so the card never contradicts its own linked stamp.
- [[app/services/link_campaign_organization_service.rb#LinkCampaignOrganizationService]] normalizes whitespace, refuses names exceeding [[app/models/campaign.rb#Campaign#MAX_NAME_CHARS]] characters (`:organization_name_too_long`), looks up an existing organization in the bill's `sway_locale` case-insensitively before creating a new `Organization` row in that locale (falling back to a case-insensitive lookup on concurrent uniqueness races while re-raising non-race exceptions), and records the `linked` decision inside a transaction.
- [[app/controllers/bills_controller.rb#BillsController#bill_creator_props]] scopes the `organizations` prop to `@bill&.sway_locale || current_sway_locale` and [[app/frontend/components/admin/creator/organizations/BillCreatorOrgCombobox.tsx#BillCreatorOrgCombobox]] lists all unselected locale organizations in its scrollable dropdown so a newly created organization is immediately selectable under "Supporting / opposing arguments".

## What this does not do

Linking an organization never touches the campaign's own position.

Stance, name, summary, and counts are left exactly as the first approval set them, and linking by `organization_id` never creates an `Organization` row unless the operator explicitly submits a new `organization_name`.
