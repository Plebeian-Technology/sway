import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    generationStatus: IBillLlmProvisioning["generation_status"];
    generationError: string | null;
    hasDrafts: boolean;
}

// @lat: [[positions-error-notice-wording#Two things used to make this notice untrue]]
const LlmSummaryPositionsErrorNotice: React.FC<IProps> = ({ generationStatus, generationError, hasDrafts }) => {
    if (!generationError) return null;
    if (generationStatus !== "completed") return null;

    return (
        <Alert variant="warning" data-testid="llm-positions-error">
            <AlertTitle>
                {hasDrafts ? "Draft positions were not refreshed" : "Draft positions were not generated"}
            </AlertTitle>
            <AlertDescription>
                {/* @lat: [[positions-error-notice-wording#Why the notice says "before this run", not "from an earlier run"]] */}
                {generationError} — the summary this run produced is unaffected
                {hasDrafts ? "; the draft positions below are from before this run" : ""}. The "Public summary" field on
                this tab holds the published summary, which no run changes. Regenerate to try the positions call again.
            </AlertDescription>
        </Alert>
    );
};

export default LlmSummaryPositionsErrorNotice;
