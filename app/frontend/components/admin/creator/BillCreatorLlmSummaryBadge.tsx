import { Badge } from "app/frontend/components/ui/badge";
import type { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    status: IBillLlmProvisioning["generation_status"];
    // @lat: [[bill-creator-llm-summary-badge#Why reclaimable exists as a separate prop]]
    reclaimable?: boolean;
}

// @lat: [[bill-creator-llm-summary-badge#Why the wording matches the old badge word for word]]
const BillCreatorLlmSummaryBadge: React.FC<IProps> = ({ status, reclaimable = false }) => {
    // @lat: [[bill-creator-llm-summary-badge#Why reclaimable exists as a separate prop]]
    if (reclaimable && (status === "pending" || status === "generating")) {
        return (
            <Badge data-testid="llm-status-badge" variant="stamp" tone="warning">
                Abandoned
            </Badge>
        );
    }
    if (status === "completed") {
        return (
            <Badge data-testid="llm-status-badge" variant="stamp" tone="success">
                Ready
            </Badge>
        );
    }
    if (status === "failed") {
        return (
            <Badge data-testid="llm-status-badge" variant="stamp" tone="danger">
                Failed
            </Badge>
        );
    }
    if (status === "pending") {
        return (
            <Badge data-testid="llm-status-badge" variant="stamp" tone="neutral">
                Queued…
            </Badge>
        );
    }
    if (status === "generating") {
        return (
            <Badge data-testid="llm-status-badge" variant="stamp" tone="primary">
                Generating…
            </Badge>
        );
    }
    if (status === "skipped") {
        // @lat: [[bill-creator-llm-summary-badge#Why a skipped row gets a neutral tone]]
        return (
            <Badge data-testid="llm-status-badge" variant="stamp" tone="neutral">
                Skipped
            </Badge>
        );
    }
    return (
        <Badge data-testid="llm-status-badge" variant="stamp" tone="neutral">
            Not generated
        </Badge>
    );
};

export default BillCreatorLlmSummaryBadge;
