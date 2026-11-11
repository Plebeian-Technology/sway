import { router, usePage } from "@inertiajs/react";
import { useRef, useState } from "react";
import { notify } from "app/frontend/sway_utils";
import { landedOnBillCreator } from "app/frontend/components/admin/creator/billCreatorLanding";
import { Button } from "app/frontend/components/ui/button";
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from "app/frontend/components/ui/dialog";
import { Label } from "app/frontend/components/ui/label";
import { Textarea } from "app/frontend/components/ui/textarea";
import type { IValidationError } from "app/frontend/types/bill_creator";
import FeatureInfo from "app/frontend/components/admin/creator/FeatureInfo";
import PasteSummaryErrorList from "app/frontend/components/admin/creator/paste-summary/PasteSummaryErrorList";
import {
    arePasteSummaryErrorsDismissed,
    dismissPasteSummaryErrors,
} from "app/frontend/components/admin/creator/paste-summary/dismissedPasteSummaryErrors";
import SchemaReferenceAccordion from "app/frontend/components/admin/creator/paste-summary/SchemaReferenceAccordion";
import { resolveJsonPointerOffset } from "app/frontend/components/admin/creator/paste-summary/resolveJsonPointerOffset";

// @lat: [[paste-summary-dialog-mechanics#Why rejections come back via flash, not Inertia's shared errors]]

interface IProps {
    billId: number;
    open: boolean;
    onOpenChange: (open: boolean) => void;
    // @lat: [[paste-summary-dialog-mechanics#Why schemaExample is a plain string prop]]
    schemaExample: string;
}

// @lat: [[paste-summary-dialog-mechanics#Why NO_ERRORS is one shared empty array]]
const NO_ERRORS: IValidationError[] = [];

const PasteSummaryDialog: React.FC<IProps> = ({ billId, open, onOpenChange, schemaExample }) => {
    const [summaryJson, setSummaryJson] = useState<string>("");
    const [posting, setPosting] = useState<boolean>(false);
    const textareaRef = useRef<HTMLTextAreaElement | null>(null);

    // @lat: [[paste-summary-dialog-mechanics#Why the flash read has no manual-clear cleanup]]
    const pageProps = usePage().props as {
        flash?: { paste_summary_errors?: IValidationError[] };
    };
    const flashErrors: IValidationError[] = pageProps.flash?.paste_summary_errors ?? NO_ERRORS;

    // @lat: [[paste-summary-dialog-mechanics#Why dismissedErrors starts from the module-level registry, not null]]
    // @lat: [[dismissed-paste-summary-errors-tracking#Why identity, not content]]
    const [dismissedErrors, setDismissedErrors] = useState<IValidationError[] | null>(() =>
        arePasteSummaryErrorsDismissed(flashErrors) ? flashErrors : null,
    );
    const errors: IValidationError[] = flashErrors === dismissedErrors ? NO_ERRORS : flashErrors;

    const handleOpenChange = (next: boolean) => {
        if (!next) {
            setSummaryJson("");
            setDismissedErrors(flashErrors);
            dismissPasteSummaryErrors(flashErrors);
        }
        onOpenChange(next);
    };

    const handleCopyExample = async () => {
        try {
            await navigator.clipboard.writeText(schemaExample);
            notify({ level: "success", title: "Example copied to clipboard." });
        } catch {
            notify({ level: "error", title: "Could not copy — select the text and copy manually." });
        }
    };

    // @lat: [[paste-summary-dialog-mechanics#Why handleErrorClick falls back to scrolling to the top]]
    const handleErrorClick = (pointer: string) => {
        const ta = textareaRef.current;
        if (!ta) return;
        ta.focus();
        const offset = resolveJsonPointerOffset(summaryJson, pointer);
        if (offset !== null) {
            try {
                ta.setSelectionRange(offset, offset);
            } catch {
                // @lat: [[paste-summary-dialog-mechanics#Why handleErrorClick falls back to scrolling to the top]]
            }
        } else {
            ta.scrollTop = 0;
        }
    };

    const handleValidate = () => {
        if (posting) return;
        setPosting(true);
        router.post(
            `/bills/${billId}/paste_summary`,
            { summary_json: summaryJson },
            {
                preserveScroll: true,
                // @lat: [[paste-summary-dialog-mechanics#Why handleValidate's onSuccess reads the fresh page.props, not the earlier usePage() snapshot]]
                // @lat: [[paste-summary-dialog-draft-landing#Two bugs only a browser could catch]]
                onSuccess: (page) => {
                    const flash = (page.props as { flash?: { paste_summary_errors?: IValidationError[] } }).flash;
                    const pendingErrors = flash?.paste_summary_errors ?? [];
                    if (pendingErrors.length > 0) {
                        // @lat: [[paste-summary-dialog-mechanics#Why handleValidate's onSuccess reads the fresh page.props, not the earlier usePage() snapshot]]
                        return;
                    }
                    // @lat: [[paste-summary-dialog-mechanics#Why handleValidate's onSuccess reads the fresh page.props, not the earlier usePage() snapshot]]
                    // @lat: [[bill-creator-landed-write-detection#One refusal shares it — call pageExpired first]]
                    if (!landedOnBillCreator(page.url, billId)) {
                        notify({
                            level: "error",
                            title: "The paste was not saved to this bill. Sign in as an admin and try again.",
                        });
                        return;
                    }
                    setSummaryJson("");
                    onOpenChange(false);
                    // @lat: [[paste-summary-dialog-mechanics#Why there is no router.reload after a successful paste]]
                },
                onFinish: () => setPosting(false),
            },
        );
    };

    return (
        <Dialog open={open} onOpenChange={handleOpenChange}>
            <DialogContent
                className="inset-0 top-0 left-0 h-full max-h-none w-full max-w-none translate-x-0 translate-y-0 overflow-y-auto rounded-none border-0 p-4 sm:inset-auto sm:top-[50%] sm:left-[50%] sm:h-auto sm:max-h-[90dvh] sm:max-w-2xl sm:translate-x-[-50%] sm:translate-y-[-50%] sm:rounded-xl sm:border-neo sm:p-6"
                data-testid="paste-summary-dialog"
            >
                <DialogHeader>
                    <div className="flex min-w-0 items-center gap-1.5">
                        <DialogTitle>Paste bill summary JSON</DialogTitle>
                        <FeatureInfo note="summary.pasteDialog" />
                    </div>
                    <DialogDescription>
                        Paste a valid bill summary JSON payload to create a review draft. The schema is shown below for
                        reference.
                    </DialogDescription>
                </DialogHeader>
                <div className="flex flex-col gap-2">
                    <Label htmlFor="paste-summary-json">Bill summary JSON</Label>
                    <Textarea
                        id="paste-summary-json"
                        ref={textareaRef}
                        data-testid="input-paste-summary-json"
                        aria-label="Bill summary JSON"
                        rows={10}
                        value={summaryJson}
                        onChange={(e) => setSummaryJson(e.target.value)}
                        placeholder='{ "summary_markdown": "...", "full_breakdown_markdown": "..." }'
                        className="font-mono text-xs min-h-[180px] sm:min-h-[280px]"
                        disabled={posting}
                    />
                </div>
                {errors.length > 0 && <PasteSummaryErrorList errors={errors} onErrorClick={handleErrorClick} />}
                <SchemaReferenceAccordion schemaExample={schemaExample} onCopyExample={handleCopyExample} />
                <DialogFooter className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                    <Button
                        type="button"
                        variant="outline"
                        onClick={() => handleOpenChange(false)}
                        disabled={posting}
                        className="min-h-[44px] sm:min-h-9 w-full sm:w-auto"
                    >
                        Cancel
                    </Button>
                    <Button
                        type="button"
                        variant="default"
                        onClick={handleValidate}
                        disabled={posting || summaryJson.trim().length === 0}
                        data-testid="btn-validate-paste-summary"
                        className="min-h-[44px] sm:min-h-9 w-full sm:w-auto"
                    >
                        Validate &amp; paste
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};

export default PasteSummaryDialog;
