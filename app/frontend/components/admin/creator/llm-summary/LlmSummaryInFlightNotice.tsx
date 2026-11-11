import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { RUN_IN_FLIGHT_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/runInFlightNoticeId";
import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    generationStatus: IBillLlmProvisioning["generation_status"];
    // @lat: [[bill-creator-summary-tab#Why the summary tab's in-flight notice says nothing about positions]]
    hasDraft: boolean;
    pasted: boolean;
    pasteOwnsSummaryRun: boolean;
    abandoned: boolean;
}

// @lat: [[bill-creator-summary-tab#Why the summary tab's in-flight notice says nothing about positions]]
const LlmSummaryInFlightNotice: React.FC<IProps> = ({
    generationStatus,
    hasDraft,
    pasted,
    pasteOwnsSummaryRun,
    abandoned,
}) => {
    if (generationStatus !== "pending" && generationStatus !== "generating") return null;
    if (!hasDraft) return null;

    const draftPredatesThisRun = generationStatus === "pending";

    const held = pasted
        ? "the summary you pasted"
        : draftPredatesThisRun
          ? "the draft summary from the last run"
          : "the draft summary on this bill";

    const abandonedRunFate = generationStatus === "pending" ? "The new run never started" : "This run stopped part-way";

    const sweepSettlesThePaste = abandoned && pasteOwnsSummaryRun;

    return (
        <Alert variant="info" id={RUN_IN_FLIGHT_NOTICE_ID} data-testid="llm-run-in-flight">
            <AlertTitle>
                {sweepSettlesThePaste
                    ? "Nothing is working on this row"
                    : abandoned
                      ? abandonedRunFate
                      : generationStatus === "pending"
                        ? "A new summary is queued"
                        : "A new summary is being written"}
            </AlertTitle>
            <AlertDescription>
                {`You are looking at ${held}. `}
                {sweepSettlesThePaste
                    ? "Nothing is working on this row now. Sway settles a summary you pasted on its own and keeps your " +
                      "text, so there is nothing to do. Regenerating would replace it. "
                    : abandoned
                      ? `${abandonedRunFate}, and nothing is working on it now. Regenerate to start a new one. `
                      : "The new run replaces it when it finishes. "}
                {"The published summary in the box below is not changed by a run."}
            </AlertDescription>
        </Alert>
    );
};

export default LlmSummaryInFlightNotice;
