import { TBillPipelineStatus } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import { TStaleChangeKind } from "app/frontend/components/admin/creator/llm-summary/staleChange";

import { TStance } from "app/frontend/components/admin/creator/org-position-card/constants";
import { sway } from "sway";

// @lat: [[llm-summary-types-contract#Why IOrgPosition cannot fall back to the old vocabulary]]
export interface IOrgPosition {
    org_name: string;
    stance: TStance;
    summary: string;
    // @lat: [[draft-org-position-identity#The frontend's IOrgPosition.draft_token]]
    draft_token?: string;
    // @lat: [[evidence-retraction#The frontend's IOrgPosition.evidence_retracted_at]]
    evidence_retracted_at?: string | null;
    // @lat: [[bill-creator-llm-summary-actions#Why orgPositions filters rejected drafts and records rawIndex before filtering]]
    rejected?: boolean;
    // @lat: [[news-org-position-grounding#Metadata enrichment attributes]]
    bill_news_article_id?: number | null;
    text_version_id?: number | null;
    evidence_excerpt?: string | null;
    speaker_name?: string | null;
    speaker_role?: string | null;
    source_url?: string | null;
    outlet_name?: string | null;
    article_title?: string | null;
    excerpt_page?: number | null;
    excerpt_paragraph?: number | null;
    excerpt_offset?: number | null;
    excerpt_length?: number | null;
}

// @lat: [[draft-org-position-identity#Why TDraftOrgPosition carries rawIndex]]
export type TDraftOrgPosition = IOrgPosition & { rawIndex: number };

export interface ITestimonyAttachment {
    filename: string;
    // @lat: [[admin-mirror-display-vs-identity#The frontend's ITestimonyAttachment.attachment_id]]
    attachment_id?: string | null;
    download_status: string;
    extraction_status: string;
    error: string | null;
}

export interface IBillLlmProvisioning {
    // @lat: [[llm-summary-types-contract#generation_status: skipped means superseded, not broken]]
    generation_status: "pending" | "generating" | "completed" | "failed" | "skipped" | null;
    generation_error: string | null;
    llm_summary: string | null;
    llm_full_breakdown: string | null;
    supplemental_testimony: string | null;
    draft_org_positions: IOrgPosition[] | null;
    // @lat: [[llm-summary-types-contract#stale]]
    stale: boolean;
    // @lat: [[llm-summary-types-contract#stale_change_kind / stale_change_at]]
    stale_change_kind: TStaleChangeKind | null;
    stale_change_at: string | null;
    // @lat: [[abandoned-run-reclaim#nil updated_at is NOT reclaimable]]
    reclaimable: boolean;
    // @lat: [[abandoned-run-reclaim#Which writer owns a reclaimable row]]
    paste_owns_summary_run: boolean;
    llm_generated_at: string | null;
    // @lat: [[llm-summary-types-contract#llm_provider: dropped at the type boundary]]
    llm_provider: string | null;
    // @lat: [[llm-summary-types-contract#has_testimony]]
    has_testimony: boolean;
    testimony_attachments: ITestimonyAttachment[] | null;
    citations_valid: boolean | null;
    invalid_citations: string[] | null;
}

// @lat: [[campaign-letter-disclosure#Why a repeat letter is marked, not hidden]]
// @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
export interface ISummaryModelOption {
    id: string;
    label: string;
    supports_reasoning?: boolean;
}

export interface ITestimonyCampaignLetter {
    position: number;
    text: string;
    sender_address: string | null;
    sender_domain: string | null;
    repeat: boolean;
}

// @lat: [[campaign-letter-disclosure#Why the letter text is a prop of its own]]
export interface ITestimonyCampaignLetterBundle {
    content_hash: string;
    letters: ITestimonyCampaignLetter[];
}

export interface ITestimonyCampaignDraft {
    content_hash: string;
    sender_count: number;
    letter_count: number;
    added_words_characters: number;
    senders_added_words_left_out: number;
    domain: string | null;
    // @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
    rejected?: boolean;
    marked_individual?: boolean;
}

// @lat: [[campaign-position-cards#Approving a campaign out of testimony#Why a decision is read back onto the card]]
export interface IApprovedCampaign {
    id: number;
    name: string | null;
    support: string;
    summary: string;
    sender_count: number | null;
    letter_count: number | null;
    source_campaign_draft_hash: string | null;
    // @lat: [[campaign-organization-link#Why there are four states and not two]]
    organization_link_decision: TOrganizationLinkDecision | null;
    organization_id: number | null;
    organization_name: string | null;
}

export type TOrganizationLinkDecision = "linked" | "none" | "undetermined";

// @lat: [[campaign-organization-link#How candidates are proposed, and why the evidence travels with them]]
export interface ICampaignOrganizationCandidate {
    organization_id: number;
    organization_name: string | null;
    evidence_kind: "signature_block" | "bill_position";
    letter_count: number;
    claimed_name: string | null;
}

// @lat: [[llm-summary-types-contract#Why ITestimonyCoverage is a top-level prop and carries a digest]]
export interface ITestimonyCoverage {
    state: "cleaned" | "never_run" | "failed" | "running" | "no_testimony" | "stale";
    coverage_gap: boolean;
    total_chars: number;
    reached_chars: number;
    removed_chars: number;
    repair_added_chars: number;
    left_out_chars: number;
    total_letters: number | null;
    reached_letters: number | null;
    removed_letters: number | null;
    left_out_letters: number | null;
    individual_letter_count: number | null;
    model_fallback_letter_count: number | null;
    attachment_cut_count: number;
    attachment_cut_cap: number | null;
    paste_present: boolean;
    paste_chars: number;
    paste_share_of_limit: number | null;
    displaced_letter_count: number | null;
    // @lat: [[llm-summary-types-contract#Why ITestimonyCoverage is a top-level prop and carries a digest]]
    digest: string;
    acknowledged: boolean;
    acknowledged_by_email: string | null;
    acknowledged_at: string | null;
}

// @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
export interface ISummarySourceRecord {
    source_kind: "diff" | "extracted" | "none";
    source_chars: number;
    source_cap: number;
    source_reached_chars: number;
    source_truncated: boolean;
    extracted_text_chars: number;
    diff_target: string | null;
    diff_sections_modified: number | null;
    diff_sections_referenced: number | null;
    diff_sections_not_found: number | null;
    diff_generated_at: string | null;
    citation_keys_offered: number;
    citation_keys_total: number;
    citation_sample_titles: string[];
    news_search_available: boolean;
    news_fetched_at: string | null;
    newsroom_domains: string[];
    news_articles_offered: number;
    news_articles_total: number;
    news_articles: Array<{ title: string; host: string }>;
}

// @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
export interface ISummarySourceRead extends ISummarySourceRecord {
    built_at: string;
    llm_model: string | null;
    llm_provider: string | null;
}

// @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
export interface ISummarySources {
    read?: ISummarySourceRead | null;
    now: ISummarySourceRecord;
    summary_generated_at: string | null;
    summary_model: string | null;
    summary_provider: string | null;
}

// @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
export interface ISummarySourceDocuments {
    origin: "run" | "now";
    built_at: string | null;
    bill_details: string | null;
    source_text: string | null;
    citations: string | null;
    news: string | null;
}

export interface IBillPipelineRefresh {
    status?: TBillPipelineStatus;
    error_message?: string | null;
}

// @lat: [[llm-summary-types-contract#Why IBillPipelineLastFailure carries no member count]]
export interface IBillPipelineLastFailure {
    // @lat: [[pipeline-run-id-cross-tab-coordination#The frontend's IBillPipelineLastFailure.run_id]]
    run_id: number;
    error_message: string;
    failed_at: string;
}

// @lat: [[bill-creator-llm-summary-actions#Why summary_prompt is a top-level prop, not nested in bill]]
export type TBill = sway.IBill & {
    bill_llm_provisioning?: IBillLlmProvisioning;
    bill_pipeline_refresh?: IBillPipelineRefresh | null;
    // @lat: [[bill-creator-empty-state-prompt-flow#The pipeline-failure alert]]
    bill_pipeline_last_failure?: IBillPipelineLastFailure | null;
};

// @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
export interface IBillSummaryRevision {
    id: number;
    bill_id: number;
    summary_markdown: string;
    origin: "model_generation" | "operator_edit" | "operator_paste" | "restoration" | "initial_baseline";
    actor_name?: string | null;
    llm_provider?: string | null;
    llm_model?: string | null;
    publication_role: "published" | "draft";
    review_state: "unreviewed" | "reviewed" | "unknown";
    restored_from_id?: number | null;
    created_at: string;
    news_source_snapshot_id?: number | null;
    has_snapshot?: boolean;
}
