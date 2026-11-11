# Administrator article review actions

Review operations separate link-only eligibility from synthesis eligibility and preserve historical snapshots across version increments.

## Review versions invalidate stale in-flight outputs

Incrementing review_version and stance_version detects concurrent modifications and invalidates in-flight summary generation without rewriting published history.

When an administrator approves or withdraws an article, or supplies manual text, review_version increments. When stance changes, stance_version increments. These versions ensure that any background publication running against older snapshot data will detect the version mismatch and abort cleanly.

## Manual text enables synthesis without mandatory re-approval

Adding manual text establishes attributable evidence for a previously link-only approved article without requiring a redundant re-approval step.

A textless approved article serves as a related link. Providing manual source text transitions its eligibility to synthesis without erasing approval or triggering automatic generation.

## Review action protocol and format negotiation

Format negotiation satisfies Inertia browser transitions while preserving JSON responses for non-Inertia clients.

The Bill Creator summary tab executes review mutations and explicit discovery through Inertia requests. When processing requests with Inertia headers, [[app/controllers/admin/bill_news_articles_controller.rb#Admin#BillNewsArticlesController]] returns HTTP 303 See Other redirects back to the summary tab, conveying both review validation failures and explicit discovery receipt errors through the `news_article` key in the Inertia error bag. Non-Inertia clients receive standard JSON payloads with appropriate HTTP status codes, keeping API contracts intact.

Review parameters accept either flat attributes or nested `bill_news_article` objects. Empty nested payloads such as `{"bill_news_article":{}}` are permitted without raising `ActionController::ParameterMissing`, while unhandled parameter errors are caught and surfaced via the standard Inertia redirect with error bag or JSON 422 response.

## Admin article review actions
Placeholder.
