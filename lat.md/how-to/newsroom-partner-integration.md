---
lat:
  mode: how-to
---
# Newsroom partner integration

How partner newsrooms embed interactive Sway bill cards into legislative coverage, configure attribution parameters, and track civic engagement while safeguarding voter privacy.

## Embedding the bill card widget

Newsroom partners embed Sway bill cards via a responsive iframe snippet positioned directly alongside relevant reporting.

The embed iframe code snippet is configured as follows:

```html
<iframe src="https://sway.vote/embed/bills/:id?partner=:slug" width="100%" height="320" frameborder="0" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-forms" loading="lazy"></iframe>
```

- `:id` is the numeric bill identifier on Sway (e.g. `42`).
- `:slug` is the partner's registered slug identifier (e.g. `the-banner`, `maryland-matters`).
- The `sandbox` attribute permits user interaction and form submission while isolating the host page.
- The embed layout operates cookie-free with public cache headers (`Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=600`) as documented in [[lat.md/explanation/embeddable-bill-widget#Embeddable bill widget]].

## Integration steps

Follow these steps to deploy the embed widget and verify attribution tracking across published news articles.

1. Register an approved partner newsroom organization in Sway's database with its canonical slug (e.g. `the-banner`).
2. Identify the target bill on Sway (`/bills/:id`) corresponding to the legislative topic reported in the story.
3. Insert the responsive iframe snippet into the CMS article template with the appropriate `:id` and `:slug` parameters.
4. Optionally append custom UTM campaign parameters (`&utm_campaign=budget-2026`) to segment audience referral sources.
5. Publish the article and verify that reader referral clicks and provisional votes record atomically via `ArticleBill` models ([[lat.md/explanation/partner-article-engagement#Data model and join relationship]]).
6. Review engagement reach, voter registration conversion, and aggregate sentiment on the administrative dashboard at `/admin/partner_reports`.

## Attribution and referral analytics

Attribution parameters capture audience engagement across article impressions, referral clicks, and constituent registrations.

The `?partner=:partner_slug` query parameter identifies the referring newsroom. When readers interact with the widget or click "Vote FOR" or "Vote AGAINST", Sway preserves attribution across the low-friction voting journey ([[lat.md/explanation/low-friction-voting#Low-friction voting]]). Referral data captures:

- Total article referral clicks (`clicks_count`).
- Verified constituent account registrations prompted by article embeds (`registrations_count`).
- Total verified constituent votes cast on the covered legislation (`votes_count`).

## Voter privacy and k-anonymity guarantee

Sway guarantees secret ballot integrity and enforces strict k-anonymity protections across all partner-facing reporting.

Individual voter choices are never linked to personal identities, IP addresses, or newsroom reporting. To prevent re-identification in low-volume reporting:

- When total votes on an article or partner report are fewer than 5 (`votes_count < 5`), sentiment counts and percentages are suppressed to `nil`.
- The partner reports dashboard and Alba serializers display `sentiment_suppressed: true` with a visual "Suppressed (k < 5)" badge.
- Only aggregate percentages are exposed once at least 5 verified constituent votes have been cast.

## Outcome

Newsroom partners successfully publish interactive civic widgets that inform readers and track democratic participation without compromising voter anonymity.

Embedding newsroom widgets provides transparent constituent engagement data for newsrooms and funders while upholding voter privacy and hardware isolation.
