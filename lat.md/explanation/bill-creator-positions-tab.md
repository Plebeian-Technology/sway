---
lat:
  mode: explanation
---

# The Bill Creator positions tab

Positions is the Bill Creator tab where an operator works through what an organization put on the record: the testimony pasted in by hand, the draft positions a run wrote from it, and the arguments the bill publishes.

## Why positions are a tab of their own

Testimony and advocacy are excluded from the summary prompt by construction, and a screen that showed the summary and the positions together invited the reader to assume otherwise.

`BillSummaryPromptBuilder` states the exclusion in the header it sends, and its user message carries only the bill's metadata, one source text, the law-section citation allow list, and news articles. No testimony letter and no organization position has ever reached the summary model. Nothing in the code changed here; what changed is the screen that described it. An operator reading the model's summary directly above a list of organization stances and a box of pasted testimony has every reason to read the second half as an input to the first.

The split is presentational, and it is worth the extra tab because the wrong belief it corrected is the expensive kind. A summary that a reader believes was written from advocacy material is a summary they cannot trust as a neutral description of a bill, and that trust is the whole point of publishing one.

The two tabs still describe one run. A summary run writes both the public summary and the draft positions, so the operator moves between the tabs after a run rather than working one to completion. Placement follows what each control acts on, not which job produced it — the same rule that already put the run controls under the summary box rather than beside the drafts.

## Saving testimony is what commits it to a run

The supplemental testimony field lives on the positions tab, and the text an operator types there reaches a run only once Save testimony has written it to the bill.

While both halves shared one tab, the field's live value rode along with every generate and regenerate request, so typing into the box and pressing Regenerate used the typed text without saving it. With the field off the summary tab that is no longer possible, and it is no longer wanted: a run started from the summary tab now uses whatever testimony is stored on the bill.

Nothing is lost by the change. `GenerateBillSummaryService` already treats a blank supplemental value as "nothing supplied" and never overwrites the stored testimony from a run, so a run has always read the stored value in every case except the one where an operator had unsaved text in the box. That case is now an explicit two-step: save on this tab, then run. The field's own copy says so, since the alternative is an operator who types, runs, and cannot tell whether the run read what they typed.

### The box takes a newer server value only when nothing is unsaved in it

The testimony box tracks the server value it was last synced to, and adopts a newer one only while it still holds the old one — a comparison made during render rather than in an effect.

Both simpler rules are wrong in one direction. Seeding once at mount leaves a tab that opened on an empty column showing nothing forever, however much testimony lands afterwards. Taking the newest prop unconditionally throws away a half-typed edit the moment the tab's own five-second poll returns. Adjusting the state during render rather than in a `useEffect` is what avoids a second render pass and the flash of the old value that comes with it.

## Why Approve says on this tab why it is off

A notice above the draft positions says why Approve is greyed out, and the Approve buttons point at it with `aria-describedby`.

The sentence used to come from the summary panel's in-flight notice, which sits above the summary box. With the drafts on their own tab that notice is no longer on the same screen as the button it explains, so a pointer to it would name an element the page does not have — silence for a screen-reader user and an unexplained dead button for everyone else.

The notice keeps the id the cards already point at, so only one of the two ever renders: the summary panel's on the summary tab, this one on the positions tab. It also covers a case the older notice never did. A clean-testimony run rewrites the letters a draft was written from and the server refuses Approve throughout, but that run leaves `generation_status` alone, so the summary-side notice stayed hidden and the button's pointer went nowhere. Across [[app/frontend/components/admin/creator/BillCreatorPositions.tsx#BillCreatorPositions]], [[app/frontend/components/admin/creator/BillCreatorTestimonyPositions.tsx#BillCreatorTestimonyPositions]], and [[app/frontend/components/admin/creator/BillCreatorOrganizations.tsx#BillCreatorOrganizations]], status callouts, coverage warnings, claimed-affiliation cards, and draft position badges use semantic theme tokens (`bg-surface-2`, `text-foreground`, `border-border-strong`, `bg-warning/12`, `bg-success/15`, `bg-destructive/15`) rather than raw Tailwind palette classes or `dark:` media-query variants so legibility holds across all seven Sway themes regardless of OS appearance.

## The acknowledgement returns to the only tab that offers it

Acknowledging missing testimony redirects to the positions tab, named outright rather than guessed from the request's referrer.

The button reaches the server from one place: `LlmSummaryOrgPositions` renders the coverage notice, and only `BillCreatorTestimonyPositions` renders that. Reading the referrer to choose between two tabs therefore decided a question with one answer, and decided it wrongly whenever the header was missing — a referrer is not sent on every request, and a stripped one sent the admin to the summary tab, away from the notice they had just cleared.

### Every write on the positions tab returns to the positions tab

Every controller action triggered from `/admin/bill_creator/:id/positions` redirects back to `positions_bill_creator_path` rather than `summary_bill_creator_path`.

When supplemental testimony and organization positions lived on the summary tab, [[app/controllers/bills_controller.rb#BillsController#supplemental_testimony]], [[app/controllers/bills_controller.rb#BillsController#approve_org_position]], [[app/controllers/bill_draft_org_positions_controller.rb#BillDraftOrgPositionsController#update]], [[app/controllers/campaigns_controller.rb#CampaignsController#create]], [[app/controllers/organization_bill_positions_controller.rb#OrganizationBillPositionsController#destroy]], and [[app/controllers/organizations_controller.rb#OrganizationsController]] redirected to `summary_bill_creator_path`. Once those controls moved to the positions tab, redirecting to the summary tab pulled the operator off `/positions` on every click. Pointing every positions-tab write and fallback tab key in [[app/frontend/components/admin/creator/BillCreatorOrganizations.tsx#BillCreatorOrganizations]] to `positions` keeps the operator on the positions tab across approvals, rejections, supplemental testimony saves, organization position edits, and testimony letter stance overrides.

## Splitting the tab split the poll list

Each of the two tabs asks the server for its own list of props, and neither asks for a prop only the other one reads.

The summary tab reads the bill, the run that is truly in flight, and the sources ledger. The positions tab reads the bill, the same in-flight run, the organizations on the bill, the testimony coverage report, the campaign drafts, the claimed affiliations, the approved campaigns, the campaign organization candidates (`campaign_organization_candidates`), and the public testimony counts (`public_testimony_counts`). `bill` and the in-flight run are on both lists because both tabs read them: the bill carries the provisioning row every branch of both tabs is drawn from, and the shell's run-conflict banner renders above whichever tab is open.

The lists were split rather than left shared because a shared list makes each tab pay for the other's queries on every five-second tick. The testimony props are the expensive half and only one tab renders them.

`spec/requests/partial_reload_contracts_spec.rb` reads both tuples out of the TypeScript and makes the request the browser makes, so a list naming a prop the controller stopped sending fails there rather than going quietly stale on screen.

## What the positions tab polls for

The positions tab refreshes itself every five seconds while a summary run is in flight for this bill or this bill's pipeline is busy, and otherwise sits still.

Both conditions end on their own, so the poll stops with them. The summary tab's third trigger — a bill with no LLM provisioning row at all — is deliberately not repeated here. That branch exists so the summary tab's empty-state prompt guard learns the pipeline moved underneath a prepared prompt, and neither the prompt nor its guard is on this tab.

## Why testimony admin write controllers omit an else branch on service outcomes

[[app/controllers/campaigns_controller.rb#CampaignsController]], [[app/controllers/testimony_coverage_acknowledgements_controller.rb#TestimonyCoverageAcknowledgementsController]], and [[app/controllers/sending_service_domains_controller.rb#SendingServiceDomainsController]] map each service outcome Symbol to an explicit redirect branch without a catch-all fallback.

Omitting a catch-all branch ensures that any newly introduced refusal outcome fails loudly rather than falling through to a success redirect. In [[app/controllers/sending_service_domains_controller.rb#SendingServiceDomainsController#redirect_target]], the optional bill parameter only guides return navigation back to the Bill Creator tab (falling back to the admin root when absent), while the [[app/models/sending_service_domain.rb#SendingServiceDomain]] record itself remains locale-wide.

## Why testimony report resources expose raw counts and evidence without confidence scores

[[app/serializers/sending_service_domain_resource.rb#SendingServiceDomainResource]], [[app/serializers/testimony_campaign_draft_resource.rb#TestimonyCampaignDraftResource]], [[app/serializers/testimony_claimed_affiliation_resource.rb#TestimonyClaimedAffiliationResource]], and [[app/serializers/testimony_coverage_resource.rb#TestimonyCoverageResource]] serialize raw testimony counts, digests, and phrase evidence without heuristic confidence scores.

[[app/serializers/sending_service_domain_resource.rb#SendingServiceDomainResource]] exposes domain-level letter and distinct-bill counts (including the total-letter denominator and preloaded [[app/models/sending_service_domain_bill.rb#SendingServiceDomainBill]] join rows) without individual sender email addresses. [[app/serializers/testimony_campaign_draft_resource.rb#TestimonyCampaignDraftResource]] reads String-keyed cleaned artifact hashes via block attributes, using the content hash as draft identity and exposing added-words character length and sending domain origin rather than raw sender text. [[app/serializers/testimony_claimed_affiliation_resource.rb#TestimonyClaimedAffiliationResource]] surfaces raw phrase, role, sender, organization name, and position fields for human verification, while [[app/serializers/testimony_coverage_resource.rb#TestimonyCoverageResource]] serializes [[app/services/testimony/coverage_report.rb|Testimony::CoverageReport::Result]] counts and acknowledgement digests without precomputed percentages.
