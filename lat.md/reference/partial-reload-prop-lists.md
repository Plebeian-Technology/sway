---
lat:
  mode: reference
---

# Partial-reload prop lists by page

These lists are copied from the live frontend constants.

- The constants themselves are the source of truth — `spec/requests/partial_reload_contracts_spec.rb` pins these values so a change to a constant that isn't matched by a controller change fails the suite instead of shipping a stale panel.

| Page | Constant | Props |
|---|---|---|
| `pages/Bill.tsx` | `POLLING_PROPS` | `bill_score`, `organizations`, `user_legislator_emails` |
| `pages/BillOfTheMonth.tsx` | `POLLING_PROPS` | `bill`, `sponsor`, `organizations`, `user_vote`, `bill_score` (organization positions refresh on the same score-sync list, so nobody has to reload by hand) |
| `pages/Feed.tsx` | `NEWEST_KEYS_ONLY` | `newest_keys` |
| `pages/Feed.tsx` | `FEED_SEARCH_ONLY` | `items`, `feed_search`, `feed_match_count`, `newest_keys` |
| `pages/Feed.tsx` | `REFRESH_FEED_OPTIONS` | `items`, `feed_match_count`, `newest_keys` |
| `pages/Legislators.tsx` | `POLLING_PROPS` | `legislators` |
| `BillCreatorPipelineLlm.tsx` | `PIPELINE_LLM_ONLY_PROPS` | `bill`, `legislation_pipeline_run`, `active_legislation_pipeline_run`, `recent_pipeline_runs`, `bill_artifact_mirrors`, `fetched_bills`, `stale_pipeline_run_count`, `orphan_pipeline_run_count` |
| `BillCreatorSummaryAndPositions.tsx` | `SUMMARY_AND_POSITIONS_ONLY_PROPS` | `bill`, `organizations`, `active_legislation_pipeline_run` |
| `admin/PipelineRuns/Index.tsx` | `RUNS_ONLY_PROPS` | `runs` |

- Notes:

- `NEWEST_KEYS_ONLY` feeds both [[app/channels/feed_channel.rb#FeedChannel]] (via [[app/frontend/hooks/useFeedSubscription.ts#useFeedSubscription]]) and `pages/Feed.tsx`'s 60-second fallback poll.

- `active_legislation_pipeline_run` is in the `PIPELINE_LLM_ONLY_PROPS`
  list for `RunConflictBanner`, which sits in the shell above the tabs and
  stays on screen while the Pipeline tab refreshes.
- The `PIPELINE_LLM_ONLY_PROPS` constant feeds both the live WebSocket
  connection and the 5-second backup poll.
- `admin/PipelineRuns/Index.tsx` reloads `["runs"]` on a WebSocket message
  about the in-flight run, plus a 15-second poll as backup.
