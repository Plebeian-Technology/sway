---
lat:
  mode: explanation
---
# News claim assessment

Claim grounding separates structural reference integrity from semantic assessment of declared claims against administrator-approved article text.

## Two-phase verification architecture

Deterministic validation precedes semantic inference to prevent ungrounded or structurally invalid citations from incurring model latency, financial cost, or prompt injection risks.

When candidate claims fail basic integrity checks—such as text version mismatches, revoked approvals, missing claim substrings, or absent verbatim evidence excerpts—the service immediately returns an unsupported verdict without invoking language models. This ordering guarantees that language models only evaluate claims whose source provenance is structurally sound.

## Structured inference and strict schema contracts

Semantic claim assessment relies on strict JSON schema validation to eliminate ambiguous natural language responses and enforce machine-checkable verdicts.

The assessment schema constrains outputs to three mutually exclusive verdicts: supported, unsupported, or indeterminate, along with a bounded textual rationale. By enforcing schema validation through [[config/initializers/news_claim_grounding_schema.rb#NEWS_CLAIM_GROUNDING_SCHEMA]], the system prevents parsing anomalies from corrupting downstream evaluation pipelines.

## Fail-closed handling of uncertainty and errors

Transport timeouts, rate limits, unparseable model completions, and schema mismatches evaluate to indeterminate rather than failing open or throwing unhandled exceptions.

Downstream publication gates in the news evidence architecture treat indeterminate results as non-passing. Treating uncertainty and external infrastructure failures as indeterminate ensures that transient network issues or malformed model responses never cause ungrounded claims to be published.

## Bounded context and prompt injection defense

All article excerpts and generated claims passed to language models are wrapped in structured security boundaries to neutralize adversarial prompt injection attempts.

News articles and claims represent untrusted external text that may contain adversarial instructions attempting to hijack the assessment prompt. Encapsulating both inputs within [[app/services/llm/untrusted_text_block.rb#UntrustedTextBlock]] demarcates external content from instructions and instructs the evaluator to assess entailment exclusively.

## Invariant boundaries and verification limits

Exact evidence excerpt containment demonstrates that text exists within an article version, but containment does not guarantee external empirical truth.

Language models evaluate semantic entailment between the provided excerpt and the asserted claim, which remains fallible. The architecture does not claim universal fact verification. Immutable article snapshots establish which text was available for assessing a declared claim.

The [[app/services/summary_citation_validator.rb#SummaryCitationValidator#extract_prose_urls|URL scanner]] parses reader-visible Markdown constructs, recognizing inline links, used reference links, angle-bracket autolinks, and plain URLs outside definition blocks. Unused reference definitions, HTML comments, and code blocks do not satisfy citation presence.

The [[app/services/news_claim_grounding_service.rb#NewsClaimGroundingService|assessment service]] evaluates candidate news-attributed prose independently of manifest declarations. Candidate sentences citing an approved news URL are assessed against eligible article text, and unmanifested or contradictory claims sharing a URL return unsupported to block publication.
