import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";

interface IProps {
    pasteOwnsSummaryRun: boolean | undefined;
}

// @lat: [[lat.md/explanation/llm-summaries#Stand-downs are reported, not swallowed#The pipeline tab warns before it stands down]]
const PipelineOperatorPasteNotice: React.FC<IProps> = ({ pasteOwnsSummaryRun }) => {
    if (!pasteOwnsSummaryRun) return null;

    return (
        <Alert variant="info" data-testid="pipeline-operator-paste-notice">
            <AlertTitle>This summary was written by a person</AlertTitle>
            <AlertDescription>
                Run Pipeline will not replace it — the summarize-bill stage stands down rather than overwrite pasted
                text. Regenerate, on the Summary tab, is the control that replaces it.
            </AlertDescription>
        </Alert>
    );
};

export default PipelineOperatorPasteNotice;
