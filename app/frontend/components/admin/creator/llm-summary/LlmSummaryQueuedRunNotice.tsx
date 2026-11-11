import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";

// @lat: [[queued-run-notice-copy#The silence this fills]]
const LlmSummaryQueuedRunNotice: React.FC = () => (
    <Alert variant="info" data-testid="llm-queued-run-notice">
        <AlertTitle>A new summary is queued</AlertTitle>
        <AlertDescription>
            {"Sway is waiting for a worker to pick this run up, and then the run itself takes a couple of minutes. " +
                "This panel updates itself while you wait, so there is nothing to click and no need to reload the page."}
        </AlertDescription>
    </Alert>
);

export default LlmSummaryQueuedRunNotice;
