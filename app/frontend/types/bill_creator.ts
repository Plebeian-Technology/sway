// @lat: [[bill-creator-artifact-panel-serializers#The frontend types (app/frontend/types/bill_creator.ts)#Why ILegislationPipelineRun and IBillLlmProvisioning are not redeclared there]]

export type PipelineRunBillStatus = "pending" | "running" | "succeeded" | "failed" | "skipped";

export interface PipelineRunBill {
    bill_external_id: string;
    title: string | null;
    status: PipelineRunBillStatus;
    started_at: string | null; // ISO 8601
    finished_at: string | null; // ISO 8601
    error_message: string | null;
    sort_order: number;
}

// @lat: [[bill-creator-artifact-panel-serializers#The frontend types (app/frontend/types/bill_creator.ts)#FetchedBillsRow vs ResourceCacheRow on the frontend]]
export type ResourceCacheTier = "pdf" | "extracted_text" | "parsed_sections" | "diff" | "summary";

export interface ResourceCacheRow {
    tier: ResourceCacheTier;
    last_generated_at: string; // ISO 8601 (NOT NULL in DB)
    version_id: string | null;
    stale: boolean;
    source_artifact_id: string | null;
    // @lat: [[bill-creator-artifact-panel-serializers#The frontend types (app/frontend/types/bill_creator.ts)]]
}

// @lat: [[bill-creator-artifact-panel-serializers#The frontend types (app/frontend/types/bill_creator.ts)#FetchedBillsRow vs ResourceCacheRow on the frontend]]
export interface FetchedBillsRow {
    external_id: string;
    bill_id: number | null;
    title: string | null;
    fetched_at: string; // ISO 8601 (TimeWithZone serialized by Rails)
    pdf_present: boolean;
    metadata_present: boolean;
    bill_row_exists: boolean;
}

// @lat: [[bill-paste-summary-response-outcomes#The frontend IValidationError type]]
export interface IValidationError {
    path: string;
    message: string;
}

export type NewsArticleKind = "reporting" | "op_ed" | "editorial" | "unknown";
export type NewsArticleStance = "support" | "oppose" | null;
export type NewsArticleMatchKind = "direct" | "context";
export type NewsArticleOrigin = "retrieved" | "manual";

// @lat: [[news-article-evidence#Article identity and bill association]]
export interface IAdminBillNewsArticle {
    id: number;
    bill_id: number;
    news_article_id: number;
    url: string | null;
    title: string | null;
    source_name: string | null;
    domain: string | null;
    author: string | null;
    published_at: string | null;
    approved: boolean;
    review_version: number;
    stance: NewsArticleStance;
    stance_version: number;
    current_text_version_id: number | null;
    has_text: boolean;
    text_digest: string | null;
    text_origin: NewsArticleOrigin | null;
    excerpt: string | null;
    created_at: string;
    updated_at: string;
    match_kind?: NewsArticleMatchKind | null;
    article_kind?: NewsArticleKind | null;
}

export type NewsUsage = "none" | "cited";

export interface ISourceUseInput {
    bill_news_article_id: number;
    text_version_id?: number | null;
    claim_text: string;
    evidence_excerpt: string;
    citation_url: string;
}

export type { IBillSummaryRevision } from "app/frontend/components/admin/creator/llm-summary/types";
