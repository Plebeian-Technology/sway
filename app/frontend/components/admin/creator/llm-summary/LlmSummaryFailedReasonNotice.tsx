import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    generationStatus: IBillLlmProvisioning["generation_status"];
    generationError: string | null;
    // @lat: [[skipped-run-notice-copy#No claim about who wrote the draft]]
    hasDraft: boolean;
}

// @lat: [[skipped-run-notice-copy#No claim about who wrote the draft#LlmSummaryFailedReasonNotice field and component notes]]
const LlmSummaryFailedReasonNotice: React.FC<IProps> = ({ generationStatus, generationError, hasDraft }) => {
    if (!generationError) return null;
    if (generationStatus !== "failed") return null;

    return (
        <Alert variant="destructive" data-testid="llm-generation-error">
            <AlertTitle>Summary generation failed</AlertTitle>
            <AlertDescription>
                {generationError}
                {/* @lat: [[skipped-run-notice-copy#No claim about who wrote the draft]] */}
                {hasDraft ? " A draft summary is still on this bill. The box below holds the published summary." : ""}
            </AlertDescription>
        </Alert>
    );
};

export default LlmSummaryFailedReasonNotice;
