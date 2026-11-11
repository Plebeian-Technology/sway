# News article review in the Bill Creator

The Bill Creator summary tab integrates explicit newsroom discovery, candidate status alerts, and article review controls through Inertia props and 303 redirect responses.

## Explicit article retrieval

News discovery occurs strictly upon explicit administrator request rather than through automated pipeline executions, background polling, or tab navigation.

Implicit news discovery during pipeline runs or background intervals creates unintended network traffic, non-deterministic model inputs, and unreviewed external associations. By requiring an operator to press an explicit button, Sway ensures that newsroom queries are auditable, intentional, and bound to a specific administrator action.

## Integration into the Bill Creator summary tab

Placing article review directly below the summary component on the Summary tab couples evidence preparation with summary generation.

[[app/frontend/components/admin/creator/BillCreatorNewsArticles.tsx]] reads `news_articles`, `receipt_status`, and `errors.news_article` from Inertia page props provided by [[app/controllers/bills_controller.rb#BillsController]]. When discovery fails in [[app/controllers/admin/bill_news_articles_controller.rb#Admin#BillNewsArticlesController]], the 303 redirect carries the receipt's diagnostic failure message inside `inertia: {errors: {news_article: ...}}` so the summary tab surfaces the specific provider error alongside the failed alert. Article review update requests in the controller support both nested `bill_news_article` and flat parameter payloads, tolerating empty parameter maps without raising `ActionController::ParameterMissing`.

## Separation of article approval from summary generation

Article review operations increment association versions without automatically triggering summary regeneration or modifying published outputs.

When an administrator approves an article, assigns an opinion stance, or supplies manual text, the underlying review or stance version increases. Keeping review actions separate from generation avoids expensive or unexpected model invocations, allowing operators to complete a full batch of article decisions before requesting a new summary draft.

## Visual presentation of link-only versus synthesis eligibility

The interface distinguishes textless approved articles from text-bearing articles to clarify how each candidate participates in downstream features.

Approved articles lacking usable text receive a link-only designation, signaling that they will appear on reader surfaces as external related links but cannot participate in LLM summary prompt construction. Once attributable text is supplied, the article becomes eligible for synthesis without requiring a redundant re-approval step. Status badges, opinion stance badges, and candidate cards in [[app/frontend/components/admin/creator/BillCreatorNewsArticles.tsx]] use semantic theme tokens (`bg-surface-2`, `text-foreground`, `border-border-strong`, `bg-warning/15`, `bg-success/15`, `bg-destructive/15`) rather than raw palette classes or `dark:` media-query variants so contrast holds across all seven Sway themes when OS appearance differs from the active theme mode.

## Preservation of unsaved form state

Article review mutations preserve unsaved form drafts in the bill creator through targeted Inertia options.

Because article review updates bill-scoped association rows rather than the bill form itself, review actions use scroll and state preservation options coupled with targeted partial reloads of `news_articles`.
