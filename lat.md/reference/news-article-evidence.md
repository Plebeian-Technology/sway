# News article evidence contract

This planned storage and publication contract gives implementation tasks a shared interface. Source configuration rules are owned by [[news-source-configuration]]. Product intent is owned by [[llm-summaries#LLM bill summaries#Output is validated, not trusted#Cited local news reporting and domain-restricted web search#Decision on reader-facing news article credits: in-prose links over dedicated credit block]].

## Article identity and bill association

Article identity is shared; approval, matching and an administrator's position classification belong to a particular bill association.

| Proposed record | Fields and invariants |
| --- | --- |
| NewsArticle | canonical_url, title, outlet_name, author_name, published_at, article_kind; optional facts remain absent. article_kind is reporting, op_ed, editorial or unknown. |
| BillNewsArticle | bill_id, news_article_id, match_kind direct/context, match_evidence, approved default false, approved_by_id, approved_at, review_version, stance support/oppose/null, stance_by_id, stance_version. Unique bill/article pair. Locale/session derive from the bill. |
| Review versions | Approval withdrawal or a stance change increments the relevant version. Duplicate discovery does not replace review decisions. |
| Ordinary removal | Withdraws association approval; referenced article identities and text versions cannot be hard-deleted while retained snapshots use them. |
| Explicit bill deletion | Follows existing bill deletion authorization. Removes that bill's source uses, snapshots, commentary and associations transactionally with its revisions. Shared article identities/text versions remain; this feature adds no garbage collector. |

## Immutable article text

Retrieved and administrator-supplied text versions preserve the exact material used by earlier outputs, without changing another bill's selected evidence implicitly.

| Proposed record or operation | Contract |
| --- | --- |
| NewsArticleTextVersion | news_article_id, text, digest, origin retrieved/admin, actor_id when supplied, requested_url, final_url, extraction_status, created_at; text is immutable. |
| Selected version | BillNewsArticle selects current_text_version_id belonging to its NewsArticle. Text supplied for one association does not move another association's selection. |
| Link eligibility | The bill association is approved; article text is not required. |
| Synthesis eligibility | The association is approved and selects attributable usable text. Search snippets alone do not qualify. |
| Text after approval | Adding text retains approval and enables a subsequent requested generation; it never triggers automatic regeneration. |
| Replacement | A new version replaces the association's selected version, preserving all older versions and invalidating stale in-flight results. |

## Discovery request receipt

A discovery request records explicit administrative authorization and distinguishes unsupported capability or retrieval failure from no matches.

| Proposed NewsArticleDiscoveryRequest field | Contract |
| --- | --- |
| bill_id, requested_by_id | Required persisted bill and sway-admin actor. |
| status | queued, running, succeeded, no_matches, partial_failure, failed or unsupported. |
| source_config_digest | Deterministic SHA256 digest of the validated source configuration used by this request, matching [[news-source-configuration]]. |
| provider, model | Recorded search provider (`brave_search`) and model capability (`web_search`), decoupled from LLM route resolution. |
| match_counts, diagnostics | Direct/context/ambiguous/unmatched counts and bounded failure reasons with UTF-8 scrubbing and API-key redaction; private administrative data. |
| Failure telemetry | Unhandled retrieval exceptions mark the receipt failed first, emit a structured `bill_news_article_fetch.failed` error log, and report the exception to Sentry with bill and receipt context. |
| Retry identity | Retrying a receipt is idempotent; a fresh explicit request creates a new receipt. |

## Source snapshots and claim uses

An immutable snapshot binds an output to the bill associations, text versions and review state supplied to that generation or manual review.

| Proposed record or field | Contract |
| --- | --- |
| NewsArticleSourceSnapshot | bill_id, purpose summary/testimony, run_receipt or manual actor, captured source entries with association ID, text-version ID, review_version and stance_version. |
| Snapshot construction | NewsArticleSourceSnapshotService builds NewsArticleSourceSnapshot records; service and model have distinct Rails autoload constants. |
| NewsArticleSourceUse | snapshot_id, bill_news_article_id, text_version_id, claim_text, evidence_excerpt, citation_url, grounding_status, grounding_reason. claim_text appears in the output; evidence_excerpt appears verbatim in the captured text. |
| BillSummaryRevision | Optional news_source_snapshot_id; existing legacy revisions may lack it. Published revisions retain their original snapshot. |
| New output envelope | news_usage is none or cited. cited requires either a nonempty source-use manifest or markdown links in the summary prose to approved text-bearing news articles for the bill. none requires an empty manifest and no news-source links in the submitted output. Official bill citations are handled separately. |
| NewsArticleTestimony | bill_news_article_id, snapshot_id, argument_markdown, captured stance/stance_version, attribution and publication state; separate from hearing submissions and organization positions. |
| Commentary eligibility | Approved, attributable, text-bearing opinion with a bill-specific administrator stance can reach single and batch commentary generation without hearing text. News eligibility does not establish hearing testimony or organization participation. |
| News organization positions | Extracted draft organization positions grounded against approved reporting articles; requires verbatim excerpt, direct quotation, spokesperson role authorization, and locale canonicalization without user memberships. |

## Grounding decisions

Deterministic reference checks and a separate semantic assessment have different guarantees; uncertainty blocks new news-bearing publication rather than becoming a passing verdict.

| Check | Passing condition |
| --- | --- |
| References | Correct bill, eligible association, matching canonical URL, captured/current usable text and review versions, and when a source-use manifest is supplied, exact evidence excerpt, output claim substring, and visible citation agreement. |
| Bidirectional citations | Every visible news link in prose must match an approved text-bearing news article for the bill (either directly by canonical URL or through a manifest entry); every manifest citation URL must appear in visible prose. Deterministic failure skips all semantic assessor calls. |
| Text version binding | Current selected text version on the bill association must be present, match the cited text version, and have usable text. When a snapshot is present, the cited version must match the captured text_version_id. |
| Article URL binding | The citation URL must match the canonical URL of the referenced news article. |
| Semantic assessment | A separate assessment of claim plus source context returns supported with a reason; unsupported or indeterminate fails. Contradictory claims and invented quantities must fail the adjudicated fixtures even when their URL and excerpt are valid. |
| Assessment route | Existing LLM client and configured summary route; recorded route/prompt version, structured supported/unsupported/indeterminate results, no silent vendor fallback. Errors or malformed responses become indeterminate. |
| Limits | Exact excerpts prove text membership, not truth. A semantic model is fallible; deterministic replay tests and independently labeled claim/context fixtures measure its behavior. An undeclared use of news without links cannot be proven absent by URL validation. |
| News organization positions | [[app/services/news_org_position_grounding_service.rb#NewsOrgPositionGroundingService]] enforces verbatim excerpt match in eligible reporting article text version, containing direct quotation from official statement or authorized spokesperson role (matching spokesperson patterns and rejecting rank-and-file member descriptions), absence of user memberships, and locale organization canonicalization. |

## Manual and historical publication

Manual publication validates the proposed text before changing the current summary; an existing published version is not evidence that an edited claim remains supported.

| Operation | Contract |
| --- | --- |
| New edit or paste | Requires news_usage. cited validates markdown news links or optional claim/excerpt references against approved text-bearing associations; none declares no news use. Existing source references can be carried forward only after revalidating the changed output. |
| Missing declaration | Refused with actionable validation and preserved submitted draft text; no silent conversion to none. |
| Administrator controls | Actual edit and paste requests carry declarations and claim references. Legacy restore enters evidence review; publication is a separate explicit action. Article discovery and approval remain a separate workflow. |
| Restore with snapshot | Revalidates the captured references against current eligibility before publication. |
| Legacy restore without snapshot | Creates a recoverable review draft. Publication requires an administrator to supply cited evidence or explicitly declare no news use; existing historical public content remains untouched meanwhile. |
| Failure | Leaves the last valid published content unchanged and retains the attempted draft for correction. |
| Service coordination | [[app/services/manual_news_summary_publication_service.rb#ManualNewsSummaryPublicationService]] executes pre-write validation under row lock, quarantines ungrounded edits and snapshotless legacy restorations as draft revisions, and commits valid publications. |

## Changes after publication

Current eligibility controls future synthesis and related content, while historical snapshots continue to explain previously published summaries.

| Change | Reader and generation behavior |
| --- | --- |
| Approval withdrawn | Removes the current related link and associated current commentary; excludes future synthesis. Previously published summary prose and its historical citation snapshot remain intact until an explicit replacement. |
| Text replaced | Blocks stale in-flight outputs and hides commentary tied to the old selected version. Existing summary prose and historical evidence remain intact; no automatic regeneration. |
| Stance changed | Hides commentary generated for the previous stance. New requested testimony generation uses the new admin classification and actual source argument. |
| Related links | Current approved associations, including textless articles; never private article text or unapproved diagnostics. |

## News organization position grounding

News-sourced draft positions require deterministic grounding against approved reporting articles before admission into bill draft positions.

| Rule | Enforcement |
| --- | --- |
| Verbatim excerpt | The cited excerpt must occur verbatim in the selected text version of an approved reporting article. |
| Direct quotation | The excerpt must contain a quoted phrase enclosed in quotation marks rather than a journalist paraphrase. |
| Authorized speaker | The quote must be attributed to an official organizational statement or authorized officer/spokesperson role. |
| Member exclusion | Rank-and-file descriptions (e.g. member, employee, volunteer, activist) are rejected as unauthorized. |
| Public body exclusion | Statements from government bodies or agencies are excluded from organization positions. |
| Citation enrichment | Grounded entries are enriched with source URL, outlet name, article title, page number, paragraph, and character offset. |
| Organization matching | Organization names are canonicalized against existing locale organizations using Jaro-Winkler similarity (>= 0.9). |
| User exclusion | Positions are refused if the matched organization has any UserOrganizationMembership records. |
| Polling isolation | Partial reload polling (bill_score, organizations) skips the deferred :bill lambda and executes zero queries touching news tables. |
| Reader query bounds | Preloaded associations are reused without per-record reload, maintaining bounded O(1) query counts regardless of testimony volume while reflecting freshness on the next request. |
