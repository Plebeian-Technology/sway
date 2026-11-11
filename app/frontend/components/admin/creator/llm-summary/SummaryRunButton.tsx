import { Button } from "app/frontend/components/ui/button";
import { PIPELINE_BUSY_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/pipelineBusyNoticeId";

// @lat: [[bill-summary-run-button-unification#Call-site echoes]]
export const SUMMARY_RUN_BUSY_LABEL = "Queueing…";

interface IProps {
    label: string;
    busy: boolean;
    // @lat: [[bill-summary-run-button-unification#Field-level notes]]
    disabled?: boolean;
    // @lat: [[bill-summary-run-button-unification#Field-level notes]]
    pipelineBlocked?: boolean;
    onClick: () => void;
    testId: string;
    variant?: "default" | "outline";
    size?: "sm";
    className?: string;
    title?: string;
}

// @lat: [[bill-summary-run-button-unification#WHY IT IS ONE COMPONENT]]
const SummaryRunButton: React.FC<IProps> = ({
    label,
    busy,
    disabled = false,
    pipelineBlocked = false,
    onClick,
    testId,
    variant = "default",
    size,
    className,
    title,
}) => (
    <Button
        type="button"
        variant={variant}
        size={size}
        className={className}
        onClick={onClick}
        disabled={busy || disabled}
        aria-describedby={pipelineBlocked ? PIPELINE_BUSY_NOTICE_ID : undefined}
        data-testid={testId}
        title={title}
    >
        {busy ? SUMMARY_RUN_BUSY_LABEL : label}
    </Button>
);

export default SummaryRunButton;
