export type PipelineRunKind = "single" | "all_bills";

export type PipelineRunStatus =
    | "queued"
    | "running"
    | "fetching_bills"
    | "fetching_law"
    | "extracting_text"
    | "parsing_sections"
    | "generating_diffs"
    | "fetching_hearings"
    | "summarizing"
    | "succeeded"
    | "partial"
    | "completed"
    | "failed"
    | "cancelled";

export interface PipelineRunSummary {
    id: number;
    status: string;
    kind: PipelineRunKind;
    bill_id: number | null;
    bill_external_id: string | null;
    // @lat: [[pipeline-runs-history-page-design#Why the list still updates itself]]
    remote_run_id: string | null;
    started_at: string | null;
    completed_at: string | null;
    current_stage: string | null;
    bills_total: number;
    bills_succeeded: number;
    bills_failed: number;
    failing_stage: string | null;
}
