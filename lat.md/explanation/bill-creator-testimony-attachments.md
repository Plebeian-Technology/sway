---
lat:
  mode: explanation
---

# Bill Creator testimony attachment warnings

The positions tab shows hearing attachments that need operator attention and refreshes those warnings while a pipeline run is active.

## Each warning answers a different question

The warning component renders separate lists for missing, truncated, reused, and denied text; clean attachments render no warning.

[[app/frontend/components/admin/creator/llm-summary/LlmSummaryTestimonyAttachmentWarning.tsx#LlmSummaryTestimonyAttachmentWarning]] gives the operator a distinct next step based on whether each attachment's text reached the stored testimony.

The fixture in [[spec/system/admin_testimony_attachments_spec.rb]] preserves the mirror invariant: a row marked as successfully extracted has corresponding text in `extracted_testimony`. The test checks both the attention-needed rows and the all-clear case, where none of the four warning lists is rendered.

## The clean attachment assertion is scoped to its component

The clean-attachment example checks that a healthy filename is absent inside the positions tab, where the warning component renders.

[[spec/rails_helper.rb]] configures Capybara to include hidden rendered text in text queries. Inertia's `data-page` prop payload is an HTML attribute, not text content, so this scope describes the rendered component under test rather than an Inertia-payload workaround.

## Polling updates attachment warnings without a page load

While a pipeline run is active, the positions tab polls testimony props.

The system example updates stored testimony and its attachment mirror, waits for the new warning to appear, and verifies that the same document remains loaded. The polling condition is described in [[bill-creator-positions-tab#The Bill Creator positions tab#What the positions tab polls for]].
