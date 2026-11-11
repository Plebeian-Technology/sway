---
lat:
  mode: reference
---

# News organization position grounding service contract

`NewsOrgPositionGroundingService` verifies and enriches candidate draft organization positions extracted from approved news reporting articles, ensuring direct quotation, authorized spokesperson attribution, and locale canonicalization.

## Validation rules and thresholds

Deterministic criteria evaluated by `NewsOrgPositionGroundingService.filter_draft_positions` before persisting draft positions to `BillLlmProvisioning#draft_org_positions`.

| Criterion | Specification / Limit |
|---|---|
| Eligible article gating | `BillNewsArticle` is approved (`approved: true`), `news_article.article_kind` is `reporting`, and `eligible_for_synthesis?` is true. |
| Verbatim excerpt match | Candidate `evidence_excerpt` appears verbatim within the selected `NewsArticleTextVersion#text`. |
| Direct quotation | `evidence_excerpt` (or its immediate sentence window) contains text enclosed in double or single quotation marks (`DIRECT_QUOTE_PATTERN`). |
| Authorized spokesperson role | `speaker_role` or surrounding sentence matches `SPOKESPERSON_ROLE_PATTERN` (e.g. director, president, vice president, chair, counsel, founder, ceo, spokesperson, official statement). |
| Decision model fallback | Non-regex leadership titles evaluated via decision model (`authorized_spokesperson` or `official_statement` choice with finite Numeric confidence >= 0.70 via `MIN_AUTHORITY_CONFIDENCE`). Inputs are capped at `MAX_ORG_NAME_CHARS` (200), `MAX_SPEAKER_ROLE_CHARS` (200), and `MAX_SENTENCE_CHARS` (1,000). |
| Rank-and-file exclusion | Descriptions matching `MERE_MEMBER_PATTERN` (e.g. member of, employee at, worker at, volunteer with, activist at without an officer title) are rejected deterministically and never overridden by a decision model. |
| Public body exclusion | Organization names matching `PUBLIC_BODY_PATTERN` (e.g. department, commission, agency, bureau, city council, general assembly, board of estimates) are rejected. |
| Self-attribution exclusion | Organization names matching `news_article.outlet_name` or `news_article.author_name` are rejected. |
| Organization matching | Matched against existing `Organization` records in `bill.sway_locale` using normalized name or Jaro-Winkler distance >= 0.90 (`NAME_MATCH_THRESHOLD`). |
| User membership refusal | Refused if the matched `Organization` has any `UserOrganizationMembership` records (`.organization_has_users?`). |

## Metadata enrichment attributes

Attributes populated on kept news-sourced draft positions by `NewsOrgPositionGroundingService.filter_draft_positions`.

| Attribute | Type | Description |
|---|---|---|
| `bill_news_article_id` | Integer | ID of the backing `BillNewsArticle` record. |
| `text_version_id` | Integer | ID of the backing `NewsArticleTextVersion` record. |
| `evidence_excerpt` | String | Verbatim quotation excerpt from article text (up to 1,000 characters). |
| `speaker_name` | String or nil | Identified speaker name (up to 200 characters). |
| `speaker_role` | String or nil | Identified speaker title or authorized role (up to 200 characters). |
| `source_url` | String | Canonical URL of the news article (`news_article.canonical_url`). |
| `outlet_name` | String | Name of the publishing news organization (`news_article.outlet_name`). |
| `article_title` | String | Headline of the news article (`news_article.title`). |
| `excerpt_offset` | Integer | 0-based character offset of `evidence_excerpt` in the text version. |
| `excerpt_length` | Integer | Length of `evidence_excerpt` in characters. |
| `excerpt_paragraph` | Integer | 1-based paragraph index of the excerpt within the text version. |
| `excerpt_page` | Integer or nil | 1-based page index if form-feed page markers exist in text, else `nil`. |
| `summary` | String | Formatted direct quotation, speaker attribution, outlet, stance, and source URL (capped at 500 characters). |

## Approval-time verification

`NewsOrgPositionGroundingService.entry_still_grounded?` checks whether a draft remains valid when an administrator approves it.

| Check | Passing condition |
|---|---|
| Article approval | `BillNewsArticle` remains approved and eligible for synthesis or testimony on `bill`. |
| Text version match | `entry["text_version_id"]` equals the article's `current_text_version_id`. |
| Excerpt presence | `entry["evidence_excerpt"]` appears in current text version text. |
| Attribution validity | Contains a direct quotation with authorized spokesperson authority (via regex or decision model) and no user memberships. |
