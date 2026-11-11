import { Alert, AlertDescription, AlertTitle } from "app/frontend/components/ui/alert";
import { Button } from "app/frontend/components/ui/button";
import { isOperatorPasted } from "app/frontend/components/admin/creator/llm-summary/provenance";

interface IProps {
    llmDraft: string | null;
    // @lat: [[operator-paste-provenance-marker#LlmSummaryRegenerateConfirmDialog's llmProvider prop]]
    llmProvider: string | null;
    // @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
    publishedSummary: string;
    onUseDraft: () => void;
}

// @lat: [[paste-summary-dialog-draft-landing#LlmSummaryDraftNotice field notes]]
const LlmSummaryDraftNotice: React.FC<IProps> = ({ llmDraft, llmProvider, publishedSummary, onUseDraft }) => {
    const draft = llmDraft ?? "";
    if (!draft || draft === publishedSummary) return null;

    const pasted = isOperatorPasted(llmProvider);

    return (
        <Alert variant="info" className="shadow-none!" data-testid="llm-draft-notice">
            <AlertTitle>
                {pasted ? "Your pasted summary is not on the bill yet" : "The model wrote a different summary"}
            </AlertTitle>
            <AlertDescription>
                <div className="flex flex-col gap-2">
                    <p className="text-sm">
                        {pasted ? "This is the text you pasted." : "This is the draft from the last run."} It is not on
                        the bill. Copy it into the Public summary field above, then click Save summary to publish it, or
                        leave it and keep the summary that is already there.
                    </p>
                    <p
                        className="max-h-24 overflow-y-auto whitespace-pre-wrap rounded border border-border bg-card p-2 text-xs"
                        data-testid="llm-draft-body"
                    >
                        {draft}
                    </p>
                    <div>
                        <Button
                            type="button"
                            size="sm"
                            variant="ghost"
                            onClick={onUseDraft}
                            data-testid="btn-use-llm-draft"
                        >
                            Copy the draft into the box
                        </Button>
                    </div>
                </div>
            </AlertDescription>
        </Alert>
    );
};

export default LlmSummaryDraftNotice;
