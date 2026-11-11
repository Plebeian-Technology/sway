import BillCreatorPipelineStatusBadge from "app/frontend/components/admin/creator/BillCreatorPipelineStatusBadge";
import { isPipelineBusy, TBillPipelineStatus } from "app/frontend/components/admin/creator/llm-summary/pipelineBusy";
import { PIPELINE_BUSY_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/pipelineBusyNoticeId";

interface IProps {
    billPipelineStatus: TBillPipelineStatus;
}

// @lat: [[pipeline-busy-terminal-status-inversion#LlmSummaryPipelineBusyNotice.test.tsx notes]]
const LlmSummaryPipelineBusyNotice: React.FC<IProps> = ({ billPipelineStatus }) => {
    if (!isPipelineBusy(billPipelineStatus)) return null;

    return (
        <div
            // @lat: [[llm-summary-notice-id-coordination#Why not data-testid]]
            id={PIPELINE_BUSY_NOTICE_ID}
            className="flex items-center gap-2"
            data-testid="bill-pipeline-refresh-status"
        >
            <BillCreatorPipelineStatusBadge status={billPipelineStatus} scope="bill" />
            <span className="text-xs uppercase tracking-widest text-muted-foreground">
                {billPipelineStatus === "queued"
                    ? "Generation is unavailable until this pipeline run starts and finishes."
                    : "Generation is unavailable until this pipeline run finishes."}
            </span>
        </div>
    );
};

export default LlmSummaryPipelineBusyNotice;
