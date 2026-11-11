import { Button } from "app/frontend/components/ui/button";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";

interface IProps {
    submitting: boolean;
    // @lat: [[org-position-approval-guard-chain#The pre-check / re-check split#run_in_flight?]]
    approveDisabled?: boolean;
    // @lat: [[org-position-card-editing-and-approval-ui#Why the Approve button stays a real disabled attribute]]
    approveDisabledReasonId?: string;
    onApprove: () => void;
    onReject: () => void;
    onEdit: () => void;
}

const BillCreatorOrgPositionCardActions: React.FC<IProps> = ({
    submitting,
    approveDisabled = false,
    approveDisabledReasonId,
    onApprove,
    onReject,
    onEdit,
}) => (
    <div className="flex flex-wrap items-center gap-3">
        <span className="flex items-center gap-1.5">
            <Button
                type="button"
                size="sm"
                variant="default"
                onClick={onApprove}
                disabled={submitting || approveDisabled}
                aria-describedby={approveDisabled ? approveDisabledReasonId : undefined}
                data-testid="btn-approve-org-position"
            >
                Approve
            </Button>
            <FeatureInfo note="summary.approvePosition" />
        </span>
        <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={onReject}
            disabled={submitting}
            data-testid="btn-reject-org-position"
        >
            Reject
        </Button>
        <span className="flex items-center gap-1.5">
            <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={onEdit}
                disabled={submitting}
                data-testid="btn-edit-org-position"
            >
                Edit
            </Button>
            <FeatureInfo note="summary.editPosition" />
        </span>
    </div>
);

export default BillCreatorOrgPositionCardActions;
