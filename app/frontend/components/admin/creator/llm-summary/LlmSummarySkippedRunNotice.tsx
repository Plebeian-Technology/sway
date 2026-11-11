import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    generationStatus: IBillLlmProvisioning["generation_status"];
    generationError: string | null;
    // @lat: [[skipped-run-notice-copy#No claim about who wrote the draft]]
    hasDraft: boolean;
}

// @lat: [[skipped-run-notice-copy#One copy, wherever it is offered]]
const LlmSummarySkippedRunNotice: React.FC<IProps> = ({ generationStatus, generationError, hasDraft }) => {
    if (generationStatus !== "skipped") return null;

    return (
        <Alert variant="warning" data-testid="llm-skip-notice">
            <AlertTitle>This run was dropped</AlertTitle>
            <AlertDescription>
                {generationError ||
                    "It waited in the queue too long, so the worker passed it over. Nothing failed. " +
                        "Try again when you are ready."}
                {hasDraft ? " A draft summary is still on this bill. The box below holds the published summary." : ""}
            </AlertDescription>
        </Alert>
    );
};

export default LlmSummarySkippedRunNotice;
