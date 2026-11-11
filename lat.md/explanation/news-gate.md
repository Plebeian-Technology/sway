---
lat:
  mode: explanation
---
# News publication gating

News publication combines evidence assessment and snapshot eligibility checks. The [[news-article-evidence#Grounding decisions|grounding contract]] exceeds the current [[news-claim-assessment#Invariant boundaries and verification limits|assessment guarantees]].

## Why ungrounded generations are quarantined as draft revisions

Ungrounded or hallucinated news assertions compromise public legislative trust if displayed immediately to readers.

When [[app/services/bill_summary_publication.rb#BillSummaryPublication#evaluate]] detects unsupported claims, undeclared citations, missing snapshots, or indeterminate verification from [[app/services/news_claim_grounding_service.rb#NewsClaimGroundingService]], [[app/services/summary_run_persist_guard.rb#SummaryRunPersistGuard#call]] stores the generation as a draft revision under `publication_role: "draft"` rather than updating `bill.summary`. The failure reasons are recorded in `provisioning.generation_error` so administrators can diagnose why public release was withheld while preserving the generated text for inspection.

Before candidate source uses are persisted to the database, [[app/services/news_summary_manifest_validator.rb#NewsSummaryManifestValidator]] validates the raw generation envelope across [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] and [[app/services/summary_batch_result_persister.rb#SummaryBatchResultPersister]]. Any malformed source use, excerpt mismatch, undeclared citation, or missing `news_usage` declaration rejects the output as a whole, preventing partial manifest pruning. This envelope check validates submitted entries; it does not establish that they cover every news claim in the candidate prose.

## Why version lock freshness is re-checked under lock

Article text and approval status can change between prompt creation, model generation, and final persistence.

A generation run executes asynchronously and may take several seconds or minutes. During this window, an administrator might revoke approval for an article or a new text version might be fetched. Re-checking [[app/models/news_article_source_snapshot.rb#NewsArticleSourceSnapshot#current_eligibility_comparison]] inside the persistence transaction prevents race conditions where stale or retracted evidence becomes public.

When an article version mismatch is detected at persistence time, the publication decision returns `:stale_version_lock` and retains the revision as a draft.

## Why opinion commentary is gated separately from hearing testimony

Civic commentary derived from news opinion pieces serves a distinct role from official committee hearing records.

Both [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] and [[app/services/summary_batch_result_persister.rb#SummaryBatchResultPersister]] invoke [[app/services/news_article_testimony_service.rb#NewsArticleTestimonyService#publish_commentary!]] under database row lock immediately after persisting draft commentary. The publisher evaluates argument markdown grounding against cited article excerpts and re-verifies snapshot eligibility before promoting draft commentary to `publication_state: "published"`. Verified commentary becomes reader-visible through [[app/serializers/bill_resource.rb#BillResource]] while unsupported, indeterminate, stale, or superseded attempts remain quarantined drafts. When newly verified commentary publishes for an article, prior published commentary for that article transitions to `"withdrawn"`, maintaining a single current perspective per approved news source while leaving official hearing testimony and organization positions untouched.

## Why manual edits and restorations require evidence validation under lock

Manual publication needs an assessment of the proposed text because an earlier published revision cannot establish support for a changed claim.

When an administrator edits a summary or restores a previous revision, [[app/services/manual_news_summary_publication_service.rb#ManualNewsSummaryPublicationService]] validates the proposed text under a database row lock before modifying `bill.summary`. Restorations of legacy revisions lacking source snapshots or edits failing grounding evaluation are quarantined as draft revisions under `publication_role: "draft"` rather than updating public content, preserving editorial work for subsequent review while retaining the previous public summary when those checks reject the attempt. In the cited edit and legacy-restore branches, final assessment verdicts are strictly evaluated before publication, ensuring unsupported or indeterminate claim evaluations refuse publication and quarantine the text as a draft. In addition, article approval and text version freshness are re-evaluated under lock at the final write seam, and dry-run evaluations execute without persisting snapshots or source uses to the database.

