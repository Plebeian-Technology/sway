// @lat: [[paste-summary-schema-example#Why PASTE_SUMMARY_SCHEMA_EXAMPLE is written by hand]]
// @lat: [[paste-summary-draft-positions-testimony-guard#Why a non-empty list requires testimony]]
export const PASTE_SUMMARY_SCHEMA_EXAMPLE: string = JSON.stringify(
    {
        summary_markdown: "Short plain-language summary of the bill.",
        full_breakdown_markdown: "Optional detailed section-by-section breakdown.",
        news_usage: "none",
        source_uses: [
            {
                bill_news_article_id: 10,
                text_version_id: 20,
                claim_text: "The council advanced the housing measure",
                evidence_excerpt: "The city council voted to advance the comprehensive housing reform bill",
                citation_url: "https://thebaltimorebanner.com/transit",
            },
        ],
        // @lat: [[bill-summary-call-preconditions#Citation validation#When the check runs]]
        categories: ["Housing", "Transportation"],
        cited_section_keys: ["art_14__sec_301"],
    },
    null,
    2,
);
