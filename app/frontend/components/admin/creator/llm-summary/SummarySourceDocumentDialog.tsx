import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { ISummarySourceDocuments } from "app/frontend/components/admin/creator/llm-summary/types";
import { formatDate } from "app/frontend/sway_utils/datetimes";

export type TSummaryDocumentField = "bill_details" | "source_text" | "citations" | "news";

interface IProps {
    rowKey: string;
    name: string;
    field: TSummaryDocumentField;
    open: boolean;
    onOpenChange: (open: boolean) => void;
    documents: ISummarySourceDocuments | null;
    loading: boolean;
}

const originSentence = (documents: ISummarySourceDocuments | null, loading: boolean): string => {
    if (loading) return "Loading the text.";
    if (documents === null) return "The text could not be loaded.";
    if (documents.origin === "now") return "Rebuilt just now from the bill as it stands.";
    return documents.built_at
        ? `The text the run of ${formatDate(documents.built_at)} sent, byte for byte.`
        : "The text the run sent, byte for byte.";
};

// @lat: [[bill-creator-summary-tab#Why each input opens a modal of its own]]
const SummarySourceDocumentDialog: React.FC<IProps> = ({
    rowKey,
    name,
    field,
    open,
    onOpenChange,
    documents,
    loading,
}) => {
    const text = documents === null ? null : documents[field];

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                className="max-h-[90vh] w-[calc(100vw-2rem)] overflow-y-auto p-4 sm:max-h-[85vh] sm:max-w-3xl sm:p-6"
                data-testid={`summary-source-document-dialog-${rowKey}`}
            >
                <DialogHeader>
                    <DialogTitle>{name}</DialogTitle>
                    <DialogDescription data-testid="summary-source-document-origin">
                        {originSentence(documents, loading)}
                    </DialogDescription>
                </DialogHeader>
                {loading && (
                    <p className="text-sm text-muted-foreground" data-testid="summary-source-document-loading">
                        Loading the text the model was given…
                    </p>
                )}
                {!loading && documents === null && (
                    <p className="text-sm text-muted-foreground" data-testid="summary-source-document-failed">
                        Could not load the text. Close this and open it again.
                    </p>
                )}
                {!loading && documents !== null && documents.origin === "now" && (
                    <p
                        className="rounded-lg bg-warning/12 p-2 text-sm text-foreground ring-1 ring-warning ring-inset"
                        data-testid="summary-source-document-rebuilt"
                    >
                        No run was recorded for this bill, so this text was rebuilt just now. It is what a run would
                        send today, not what one sent.
                    </p>
                )}
                {!loading && documents !== null && text === null && (
                    <p className="text-sm text-muted-foreground" data-testid="summary-source-document-absent">
                        The prompt carried no {name.toLowerCase()} section at all, so the model read none.
                    </p>
                )}
                {!loading && text !== null && text.trim().length === 0 && (
                    <p className="text-sm text-muted-foreground" data-testid="summary-source-document-empty">
                        The prompt carried a {name.toLowerCase()} section with no text in it.
                    </p>
                )}
                {!loading && text !== null && text.trim().length > 0 && (
                    <pre
                        className="max-h-[60vh] overflow-auto rounded-lg bg-muted/30 p-3 font-mono text-xs wrap-break-word whitespace-pre-wrap select-text"
                        data-testid="summary-source-document-text"
                    >
                        {text}
                    </pre>
                )}
                <DialogFooter className="flex sm:justify-end">
                    <Button
                        type="button"
                        variant="outline"
                        onClick={() => onOpenChange(false)}
                        className="min-h-[44px] sm:min-h-9 w-full sm:w-auto"
                    >
                        Close
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};

export default SummarySourceDocumentDialog;
