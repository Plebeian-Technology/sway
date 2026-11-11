import type { PipelineRunBill } from "app/frontend/types/bill_creator";
import type { sway } from "sway";
import type { TPipelineRunStatus } from "app/frontend/components/admin/creator/pipeline-controls/stages";

// @lat: [[pipeline-preview-reply-shape#PipelinePreviewService's reply shape]]
export interface IPipelinePreview {
    stages_requested: string[];
    stages_will_run: string[];
    stages_auto_included: string[];
    confirmation_required: boolean;
    confirmation_message: string | null;
    prereq_violations?: Array<{
        stage: string;
        missing_artifact: string;
        bill_count: number;
        prerequisite: string;
    }>;
}

export interface IPipelineRunStage {
    stage_name: string;
    status: "pending" | "running" | "succeeded" | "failed" | "skipped";
    position: number;
    started_at?: string | null;
    finished_at?: string | null;
}

// @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
export interface ISummaryBatchProgress {
    awaiting: boolean;
    batches_total: number;
    batches_ingested: number;
    items_total: number;
    items_succeeded: number;
    items_failed: number;
    first_submitted_at: string | null;
    expires_at: string | null;
}

export interface ILegislationPipelineRun {
    id: number;
    remote_run_id: string | null;
    // @lat: [[pipeline-busy-terminal-status-inversion#The status field on ILegislationPipelineRun]]
    status: TPipelineRunStatus | null;
    // @lat: [[pipeline-run-optional-progress-fields#The crash this prevents]]
    processed?: number;
    total?: number | null;
    current_bill_external_id?: string | null;
    phase?: "downloading" | "extracting" | "saving" | null;
    eta_seconds?: number | null;
    errors?: Array<{ external_id: string; phase: string; message: string; at: string }>;
    queued?: string[];
    // @lat: [[pipeline-run-optional-progress-fields#Why cancelled_at is absent and download_missing_assets is nullable]]
    bills_updated: number | null;
    error_message: string | null;
    current_stage: string | null;
    bill_id: number | null;
    bill_external_id: string | null;
    sway_locale_id?: number | null;
    // @lat: [[pipeline-run-optional-progress-fields#Why cancelled_at is absent and download_missing_assets is nullable]]
    download_missing_assets: boolean | null;
    started_at: string | null;
    completed_at: string | null;
    // @lat: [[reclaim-abandoned-pipeline-runs-job-design#The frontend abandoned field]]
    abandoned?: boolean | null;
    kind: "single" | "all_bills" | null;
    parent_run_id: string | null;
    origin: "fresh" | "resume" | "restart" | null;
    // @lat: [[resume-stage-history-walk#The rest of the audit trail in to_builder]]
    pipeline_run_stages?: IPipelineRunStage[];
    pipeline_run_bills?: PipelineRunBill[];
    // @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
    summary_batch?: ISummaryBatchProgress | null;
}

export interface IRecentPipelineRun {
    id: number;
    status: ILegislationPipelineRun["status"];
    kind: "single" | "all_bills";
    bill_external_id: string | null;
    created_at: string | null;
    completed_at: string | null;
}

export interface IPageProps {
    legislation_pipeline_run?: ILegislationPipelineRun | null;
    // @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]
    stale_pipeline_run_count?: number | null;
    // @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]
    orphan_pipeline_run_count?: number | null;
    bill?: { id?: number; external_id?: string };
    bills?: sway.IBillPickerOption[];
    pipeline_preview?: IPipelinePreview | null;
    // @lat: [[bill-creator-pipeline-controls-panel#The page's control props follow URL precedence]]
    selected_stages?: string[];
    // @lat: [[bill-creator-pipeline-controls-panel#The page's control props follow URL precedence]]
    download_missing_assets?: boolean;
    [key: string]: unknown;
}
