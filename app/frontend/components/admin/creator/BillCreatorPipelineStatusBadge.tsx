import { Badge } from "app/frontend/components/ui/badge";
import {
    PHASE_52_STAGE_STATUS_LABELS,
    type Phase52StageStatus,
    type TPipelineRunStatus,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";

// @lat: [[bill-creator-pipeline-status-badge-fallback#How the status vocabulary is shaped, and why it isn't copied]]
type PipelineStatus = TPipelineRunStatus | null;

interface IProps {
    status: PipelineStatus;
    scope?: "global" | "bill";
    // @lat: [[bill-creator-pipeline-status-badge-fallback#Why stale and the empty_artifact marker are checked ahead of status]]
    stale?: boolean;
    // @lat: [[bill-creator-pipeline-status-badge-fallback#Why stale and the empty_artifact marker are checked ahead of status]]
    errorMessage?: string | null;
}

const BillCreatorPipelineStatusBadge: React.FC<IProps> = ({
    status,
    scope = "global",
    stale = false,
    errorMessage = null,
}) => {
    const testId = scope === "bill" ? "bill-pipeline-status-badge" : "pipeline-status-badge";

    // @lat: [[bill-creator-pipeline-status-badge-fallback#Why stale and the empty_artifact marker are checked ahead of status]]
    if (stale) {
        return (
            <Badge data-testid={testId} variant="stamp" tone="warning">
                Stale — bill amended
            </Badge>
        );
    }

    // @lat: [[bill-creator-pipeline-status-badge-fallback#Why stale and the empty_artifact marker are checked ahead of status]]
    if (status === "failed" && typeof errorMessage === "string" && errorMessage.startsWith("empty_artifact:")) {
        return (
            <Badge data-testid={testId} variant="stamp" tone="danger">
                Failed — no output
            </Badge>
        );
    }

    if (status === "completed") {
        return (
            <Badge data-testid={testId} variant="stamp" tone="success">
                {scope === "bill" ? "Pipeline ready" : "Done"}
            </Badge>
        );
    }
    if (status === "succeeded") {
        return (
            <Badge data-testid={testId} variant="stamp" tone="success">
                Succeeded
            </Badge>
        );
    }
    if (status === "partial") {
        return (
            <Badge data-testid={testId} variant="stamp" tone="warning">
                Partial
            </Badge>
        );
    }
    if (status === "failed") {
        return (
            <Badge data-testid={testId} variant="stamp" tone="danger">
                {scope === "bill" ? "Pipeline failed" : "Failed"}
            </Badge>
        );
    }
    if (status === "cancelled") {
        return (
            <Badge data-testid={testId} variant="stamp" tone="neutral">
                {scope === "bill" ? "Pipeline cancelled" : "Cancelled"}
            </Badge>
        );
    }
    // @lat: [[bill-creator-pipeline-status-badge-fallback#Why bill scope uses "Refreshing…" instead of "Running"/"Queued"]]
    if (status === "running" || status === "queued") {
        return (
            <Badge data-testid={testId} variant="stamp" tone="primary">
                {status === "queued" ? "Queued" : scope === "bill" ? "Refreshing…" : "Running"}
            </Badge>
        );
    }
    // @lat: [[bill-creator-pipeline-status-badge-fallback#How the status vocabulary is shaped, and why it isn't copied]]
    if (status !== null && status in PHASE_52_STAGE_STATUS_LABELS) {
        return (
            <Badge data-testid={testId} variant="stamp" tone="primary">
                {scope === "bill" ? "Refreshing…" : PHASE_52_STAGE_STATUS_LABELS[status as Phase52StageStatus]}
            </Badge>
        );
    }
    // @lat: [[bill-creator-pipeline-status-badge-fallback#How the status vocabulary is shaped, and why it isn't copied]]
    return (
        <Badge data-testid={testId} variant="stamp" tone="neutral">
            {status ?? "Unknown status"}
        </Badge>
    );
};

export default BillCreatorPipelineStatusBadge;
