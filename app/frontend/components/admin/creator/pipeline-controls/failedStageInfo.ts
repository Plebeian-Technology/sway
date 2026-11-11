import { STAGES, STAGE_DISPLAY_NAMES } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

export interface FailedStageInfo {
    failedStageNumber: number | null;
    failedStageName: string;
    failedStageDisplay: string;
    parentShortId: string;
}

// @lat: [[pipeline-failed-stage-display#Why PipelineResumeActions dropped the old split button]]
export function failedStageInfo(run: ILegislationPipelineRun | null): FailedStageInfo {
    const failedStage = run?.pipeline_run_stages?.find((s) => s.status === "failed") ?? null;
    const stagesIndexOfCurrent = STAGES.findIndex((s) => s.key === (run?.current_stage ?? ""));
    const failedStageNumber = failedStage?.position ?? (stagesIndexOfCurrent >= 0 ? stagesIndexOfCurrent + 1 : null);
    const failedStageName = failedStage?.stage_name ?? run?.current_stage ?? "unknown";
    const failedStageDisplay = STAGE_DISPLAY_NAMES[failedStageName] ?? failedStageName;
    const parentShortId = run?.parent_run_id ? run.parent_run_id.slice(-8) : "";
    return { failedStageNumber, failedStageName, failedStageDisplay, parentShortId };
}
