---
lat:
  mode: explanation
---
# Decoupling news discovery from pipeline execution

Automated pipeline runs and batch submissions do not perform external news discovery. News retrieval requires explicit administrative authorization.

## Why automatic news discovery was removed

Implicit news retrieval during summary generation introduced non-deterministic external dependencies, provider lock-in, and unreviewed external content into the automated pipeline.

When [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] and [[app/services/summary_batch_submission.rb#SummaryBatchSubmission]] fetched news articles automatically before constructing prompts, ordinary pipeline runs and database seeding incurred external latency and network failure modes. External web search could fail intermittently, requiring rescue blocks that complicated job failure accounting. More fundamentally, automatically fetched search results were unreviewed, risking prompt injection or irrelevant articles influencing generated summaries without human oversight.

Decoupling discovery from routine summarization ensures that pipeline execution remains fully deterministic and grounded in official legislative sources. News discovery is reserved for explicit administrator action via administrative interfaces, where retrieved candidates remain unapproved until a human reviewer verifies and approves them.

## Impact on pipeline and batch workflows

Pipeline jobs, single-bill summarization, and batch submissions proceed using official bill text and pre-existing approved evidence.

Neither `GenerateBillSummaryJob` nor `SummaryBatchSubmission` calls `BillNewsArticleFetchService`. When no approved news articles are present on a bill, [[app/services/bill_summary_prompt_builder.rb#BillSummaryPromptBuilder]] builds the prompt without news boundary tags, producing an authoritative summary grounded solely in statutory text and the official bill link. Existing persisted draft articles in `bill_llm_provisionings` remain intact, preserving historical data without automatic overwrites. See [[llm-summaries]] and [[news-article-evidence]] for evidence and publication contracts.
