import {
    type Phase52NonTerminalStatus,
    TERMINAL_RUN_STATUSES,
    type TerminalRunStatus,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";

// @lat: [[pipeline-busy-terminal-status-inversion#Listing FINISHED statuses, not busy ones]]
export type TBillPipelineStatus = Phase52NonTerminalStatus | TerminalRunStatus | null;

// @lat: [[pipeline-busy-terminal-status-inversion#LlmSummaryPipelineBusyNotice.test.tsx notes]]
export const isPipelineBusy = (status: TBillPipelineStatus): status is Phase52NonTerminalStatus =>
    status !== null && !(TERMINAL_RUN_STATUSES as readonly string[]).includes(status);
