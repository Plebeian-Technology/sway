---
lat:
  mode: explanation
---
# Grounding published opinion testimony in article evidence

Published opinion articles supply attributable civic commentary for bills without conflating editorial perspectives with official legislative hearing testimony.

## Why published opinion is distinct from hearing submissions

Legislative hearing testimony constitutes official committee records, while published opinion pieces represent journalistic and community commentary.

Hearing testimony consists of formal letters and public hearing oral remarks submitted directly to a legislative body and cataloged by committee clerks. Conflating news commentary with hearing testimony would corrupt legislative record audits and distort official stakeholder engagement metrics.

For this reason, opinion commentary resides in a distinct model, [[app/models/news_article_testimony.rb#NewsArticleTestimony]], rather than in [[app/models/organization_bill_position.rb#OrganizationBillPosition]] or [[app/models/organization.rb#Organization]]. Processing opinion commentary never creates organizations, never modifies hearing letter or speaker counts, and never marks `BillLlmProvisioning#testimony_present?` as true. Legislative hearing data remains an uncorrupted reflection of the official legislative record.

## Why testimony requires approved opinion articles and text versions

Synthesizing opinion commentary requires affirmative administrative review and immutable article text to prevent ungrounded claims.

Unvetted search results and raw web links can introduce mischaracterized arguments or fabricated quotes. Commentary synthesis is restricted by [[app/models/bill_news_article.rb#BillNewsArticle#eligible_for_testimony?]] to articles explicitly reviewed and approved by administrators, carrying a designated stance of support or oppose, classified as an op-ed or editorial, and possessing extracted full text via [[app/models/news_article_text_version.rb#NewsArticleTextVersion]].

Prompt construction in [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]] encloses eligible opinion text within untrusted delimiters. By verifying that article text versions contain substantive non-whitespace text prior to generation, the system ensures models synthesize positions grounded strictly in verified journalism.

## Why source snapshots and draft persistence precede publication

Generated opinion commentary persists as draft records tied to immutable evidence snapshots to guarantee provenance and verifiable grounding.

Every synthesis run captures a point-in-time [[app/models/news_article_source_snapshot.rb#NewsArticleSourceSnapshot]] recording the exact text version IDs and digests utilized during generation. [[app/services/news_article_testimony_service.rb#NewsArticleTestimonyService]] records draft commentary with publication state set to `draft` and associates corresponding [[app/models/news_article_source_use.rb#NewsArticleSourceUse]] records in `pending` grounding status.

Validations in [[app/models/news_article_testimony.rb#NewsArticleTestimony]] enforce that every evidence excerpt exists verbatim within the referenced text version and that snapshot, association, and bill boundaries align. Persisting records as drafts allows downstream verification gates to audit citation accuracy before publication on public bill pages.

## Why commentary attribution separates author and publisher roles

Published commentary distinguishes between individual authors and publishing outlets to prevent misattributing viewpoints to institutions or fabricating speakers.

Opinion journalism features two distinct attribution dimensions: the speaker who formulated the argument and the publisher circulating the work. In an op-ed, an individual author represents their own perspective, while in an unsigned editorial, the publishing outlet represents an institutional editorial board consensus without an individual author. Conflating these roles risks misattributing personal arguments to news institutions or treating institutional consensus as an individual's personal position.

Generative models synthesize arguments and locate evidence excerpts, but they lack authority over journalistic provenance. Because semantic grounding evaluates claim support against source text rather than attribution validity, models can hallucinate plausible-sounding or fabricated bylines for an argument.

To preserve civic trust, [[app/services/news_article_testimony_service.rb#NewsArticleTestimonyService]] binds commentary attribution directly to the verified [[app/models/news_article.rb#NewsArticle]] records approved during administrative review. Payloads that supply conflicting author or outlet names, or fabricate authors for unsigned editorial pieces, are refused during draft recording. Persisted [[app/models/news_article_testimony.rb#NewsArticleTestimony]] records and reader serializers like [[app/serializers/news_article_testimony_resource.rb#NewsArticleTestimonyResource]] thus reflect authentic journalistic attribution rather than generated hallucinations.

