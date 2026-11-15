---
lat:
  mode: explanation
---
# Home feed

The home feed collects a user's relevant legislative activity across all of their Sway locales into one reverse-chronological list.

## What items a user sees and how paging works

[[app/services/feed_query.rb#FeedQuery]] builds a user's feed items in Ruby, sorts them newest first, and slices pages in memory using an opaque cursor.

Every user receives a `user_joined` item dated at account creation, a `representatives_found` item dated at the earliest active `user_legislator` assignment when active representatives exist, and one `legislative_term_began` item per declared locale.

Each declared locale also contributes `bill_of_the_month_released` items for bills whose `scheduled_release_date_utc` falls between that locale's term start and today in UTC, carrying the bill, its locale, and the user's vote when present. Bills without a release date, scheduled for a future UTC date, or released before the current term are excluded.

Confirmed votes by the user's active legislators produce `legislator_voted` items on any bill in a declared locale, including archived bills from earlier sessions in the current term loaded via `Bill.unscope(where: :archived_at)`. Inferred votes (`inferred: true`) are excluded until pipeline confirmation sets `inferred` to `false`. Each vote's timestamp uses the legislator's chamber vote date on the bill (`senate_vote_date_time_utc` for senators, `house_vote_date_time_utc` otherwise), falling back to the other chamber's date and then `legislator_vote.created_at`, and drops votes earlier than the locale's term start.

Active positions by organizations the user follows produce `organization_position_taken` items on bills in declared locales, dated by `activated_at` rather than `created_at` so draft positions approved later appear when published. Inactive positions, unfollowed organizations, and positions activated before the locale's term start are excluded.

All bill-backed feed items (`bill_of_the_month_released`, `legislator_voted`, and `organization_position_taken`) also require the bill itself to belong to the locale's current term: neither its `legislative_session` `start_date` nor its `introduced_date_time_utc` may precede the locale's term start.

Undeclared locales produce no term-start items because only declared jurisdictions have configured term rules in [[app/models/term_window.rb#TermWindow]]. Each term-start timestamp uses midnight UTC on the convening date returned by [[app/services/feed_query.rb#FeedQuery#term_start_on|FeedQuery.term_start_on]].

Items sort by `occurred_at` descending and break ties by `key` descending. The cursor encodes the last returned item's UTC timestamp at nanosecond precision alongside its `key`, so the next page resumes strictly after that boundary without skips or duplicates; malformed or tampered cursors fall back to the first page.

## Searching the feed

[[app/services/feed_query.rb#FeedQuery]] filters built items in memory before cursor paging when `query` is non-blank after stripping whitespace.

Matching ignores letter case across the bill's `title` and `external_id`, the `full_name` of the item's `legislator` or `legislators`, the locale's `human_name` and displayed short locale name ([[app/models/sway_locale.rb#SwayLocale#short_name|SwayLocale#short_name]], `"U.S. Congress"` for Congress), and the organization's `name`. Because `user_joined` carries none of those fields, it never matches a non-blank search, and cursor paging advances only through matching items.

## Serving the feed

[[app/controllers/feed_controller.rb#FeedController]] serves the authenticated feed at `GET /feed` as an Inertia scroll response backed by [[app/services/feed_query.rb#FeedQuery]] and [[app/serializers/feed_item_resource.rb#FeedItemResource]]. On mobile, [[mobile/src/screens/FeedScreen.tsx]] and [[mobile/src/hooks/useFeed.ts]] consume the JSON form of `GET /feed` with `feed_cursor`, `feed_search`, and `PARITY_COPY.feed`.

The endpoint relies on `ApplicationController`'s default `authenticate_sway_user!` filter and intentionally skips any locale redirect because feed items span all of a user's declared locales. It accepts `feed_search` and `feed_cursor` under the decided query-parameter namespaces and configures `InertiaRails.scroll` inside a callable with `page_name: "feed_cursor"`, `current_page`, `next_page`, and `previous_page: nil` so cursor paging integrates with Inertia's infinite scroll without running page queries on `newest_keys`-only partial reloads. An `InertiaRails.optional` `newest_keys` prop computes first-page item keys (respecting `feed_search` and ignoring `feed_cursor`) only on partial reloads, sharing the memoized first-page [[app/services/feed_query.rb#FeedQuery]] when `items` and `newest_keys` are requested together without a cursor. When serializing the current page, [[app/controllers/feed_controller.rb#FeedController#bill_count_params]] bulk-loads `vote_count` from [[app/models/bill_score.rb#BillScore]] (`for + against`), `view_count` from [[app/models/bill_view.rb#BillView]], and `share_count` from distinct `user_id` rows in [[app/models/user_bill_share.rb#UserBillShare]] so [[app/serializers/feed_item_resource.rb#FeedItemResource]] attaches all three counts without per-item queries. [[app/serializers/feed_item_resource.rb#FeedItemResource]] also runs `position.support` through [[app/models/organization_bill_position.rb#OrganizationBillPosition#normalize_support|OrganizationBillPosition.normalize_support]] before looking up its display label so rows storing lowercase `"support"`, `"oppose"`, or `"neutral"` serialize as `"Support"`, `"Oppose"`, and `"Neutral"` alongside `"FOR"`, `"AGAINST"`, and `"ABSTAIN"`. For bearer-authenticated or JSON requests (`mobile_api_request?`), `FeedController` renders via [[app/controllers/concerns/mobile_format_negotiation.rb#MobileFormatNegotiation#render_inertia_or_json]] with `items`, `feed_cursor` (the next page cursor or `nil`), `feed_search`, and `feed_match_count`, omitting `newest_keys` so the mobile client does not compute web live-update keys. Both the Inertia and JSON responses carry `feed_match_count`, [[app/services/feed_query.rb#FeedQuery#match_count|FeedQuery#match_count]] — the number of items matching `feed_search` across every page, not only the loaded ones — which the web and mobile search summaries display.

Only `bill_of_the_month_released` items show a summary excerpt, so [[app/serializers/feed_item_resource.rb#FeedItemResource]] fills a bill's `summary` and `summary_ai_unreviewed` on those items alone and sends `nil` and `false` on every other kind. [[app/models/bill.rb#Bill#summary_ai_unreviewed?]] reads each bill's published summary revision and LLM provisioning, and [[app/controllers/feed_controller.rb#FeedController#serialized_items]] preloads both for the page's Bill of the Month bills, so the flag adds a fixed two queries per page however many such items it holds. The flag drives the notice described in [[ai-unreviewed-notice-component-design#The server sends a derived boolean, not the source text]].

## Live feed updates

[[app/channels/feed_channel.rb#FeedChannel]] and [[app/services/feed_broadcaster.rb#FeedBroadcaster]] deliver lightweight per-user invalidation signals so open home feeds refresh without pushing feed item payloads over ActionCable.

Each signed-in connection subscribes to `feed_<user_id>`, and subscriptions without a user are rejected. Broadcasting only `{type: "feed_updated"}` keeps authorization, locale filtering, cursor state, and serialization in `GET /feed` instead of duplicating query logic in ActionCable. `FeedBroadcaster.users_for_locale` selects distinct users who have an active `UserLegislator` in the target locale.

[[app/jobs/feed_update_broadcast_job.rb#FeedUpdateBroadcastJob]] runs asynchronously from three feed-source triggers: when [[app/jobs/notify_bill_of_the_month_users_job.rb#NotifyBillOfTheMonthUsersJob]] releases a Bill of the Month to its locale's users, when a [[app/models/legislator_vote.rb#LegislatorVote]] becomes visible (created with `inferred: false` or confirmed from `inferred: true` to `false`) for users with an active `UserLegislator` for that legislator, and when an [[app/models/organization_bill_position.rb#OrganizationBillPosition]] becomes active (`activated_at` changes while `active` is true) for that organization's followers. A vote imported late is dated by its vote date, so it can sort below the first page and `'Show N new'` counts it as zero.

