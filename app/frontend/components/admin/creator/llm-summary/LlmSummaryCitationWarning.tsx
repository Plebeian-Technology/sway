import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";

interface IProps {
    citationsValid: boolean | null;
    invalidCitations: string[] | null;
}

// @lat: [[bill-creator-summary-tab#The citation warning does not block the operator's writes]]
const LlmSummaryCitationWarning: React.FC<IProps> = ({ citationsValid, invalidCitations }) => {
    if (citationsValid !== false || !invalidCitations?.length) return null;

    const plural = invalidCitations.length > 1;

    return (
        <Alert variant="warning" data-testid="llm-citation-warning">
            <AlertTitle>Unverified citation{plural ? "s" : ""}</AlertTitle>
            <AlertDescription>
                This summary cites section key{plural ? "s" : ""} not found in the bill's parsed sections:{" "}
                <span className="font-mono text-xs">{invalidCitations.join(", ")}</span>. Review before publishing —
                this does not block saving or approving.
            </AlertDescription>
        </Alert>
    );
};

export default LlmSummaryCitationWarning;
