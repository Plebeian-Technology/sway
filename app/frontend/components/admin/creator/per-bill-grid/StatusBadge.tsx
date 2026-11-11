import { Badge } from "app/frontend/components/ui/badge";
import type { PipelineRunBillStatus } from "app/frontend/types/bill_creator";
import { DEFAULT_STATUS_TONE, STATUS_TONE } from "app/frontend/components/admin/creator/per-bill-grid/constants";

export const StatusBadge: React.FC<{ status: PipelineRunBillStatus }> = ({ status }) => {
    const { variant, tone } = STATUS_TONE[status] ?? DEFAULT_STATUS_TONE;
    return (
        <Badge variant={variant} tone={tone}>
            {status}
        </Badge>
    );
};

export default StatusBadge;
