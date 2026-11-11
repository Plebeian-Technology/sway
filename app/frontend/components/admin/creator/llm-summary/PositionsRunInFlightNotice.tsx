import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { RUN_IN_FLIGHT_NOTICE_ID } from "app/frontend/components/admin/creator/llm-summary/runInFlightNoticeId";

interface IProps {
    summaryRunInFlight: boolean;
    cleanTestimonyRunning: boolean;
    draftCount: number;
    abandoned: boolean;
}

// @lat: [[bill-creator-positions-tab#Why Approve says on this tab why it is off]]
const PositionsRunInFlightNotice: React.FC<IProps> = ({
    summaryRunInFlight,
    cleanTestimonyRunning,
    draftCount,
    abandoned,
}) => {
    if (!summaryRunInFlight && !cleanTestimonyRunning) return null;

    const held =
        draftCount > 0
            ? `You are looking at ${draftCount} draft position${draftCount === 1 ? "" : "s"} already on this bill. `
            : "";

    return (
        <Alert variant="info" id={RUN_IN_FLIGHT_NOTICE_ID} data-testid="positions-run-in-flight">
            <AlertTitle>
                {cleanTestimonyRunning && !summaryRunInFlight
                    ? "The testimony behind these positions is being rewritten"
                    : abandoned
                      ? "Nothing is working on this row"
                      : "A new set of draft positions is on the way"}
            </AlertTitle>
            <AlertDescription>
                {held}
                {cleanTestimonyRunning && !summaryRunInFlight
                    ? "A clean-testimony run is regrouping the letters these drafts were written from. Approve is off " +
                      "while this row is queued or running. It comes back when the run finishes."
                    : abandoned
                      ? "Approve is off while this row is queued or running. It comes back when Sway releases the " +
                        "run, which changes no drafts."
                      : "The new run replaces them when it finishes. Approve is off while this row is queued or " +
                        "running. It comes back when the run finishes."}
            </AlertDescription>
        </Alert>
    );
};

export default PositionsRunInFlightNotice;
