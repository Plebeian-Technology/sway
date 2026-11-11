// @lat: [[mobile-bill-hooks#useBill]]
export interface RelatedNewsArticle {
    id: number;
    title: string;
    url: string;
    outlet_name: string;
    published_at: string | null;
    author_name: string | null;
    article_kind: "reporting" | "opinion" | "op_ed" | "editorial" | "analysis" | "other" | "unknown" | null;
    match_kind: "direct" | "context";
}

export interface NewsArticleTestimony {
    id: number;
    author_name?: string | null;
    outlet_name: string;
    stance: "support" | "oppose";
    url: string;
    argument: string;
}

export type PublicTestimonyStance = "support" | "oppose" | "neutral";

export interface PublicTestimonyCounts {
    total: number;
    support: number;
    oppose: number;
    neutral: number;
}

export interface PublicTestimonyLetter {
    position: number;
    label: string;
    stance: PublicTestimonyStance;
    body_text: string;
}

export type SummaryReportReason = "factual_inaccuracy" | "misleading_tone" | "missing_amendment" | "other";

export interface Bill {
    id: number;
    title: string;
    bill_number?: string;
    external_id?: string;
    chamber?: string;
    summary?: string | null;
    summary_ai_unreviewed?: boolean;
    body?: string | null;
    status?: string;
    status_color?: string;
    link?: string;
    sway_locale_id?: number;
    related_articles?: RelatedNewsArticle[];
    news_testimonies?: NewsArticleTestimony[];
}
