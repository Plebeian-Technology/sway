import { useCallback, useEffect, useRef, useState } from "react";
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
import { cn } from "app/frontend/lib/utils";
import { isOperatorPasted } from "app/frontend/components/admin/creator/llm-summary/provenance";
import { offeredModelLabel } from "app/frontend/components/admin/creator/llm-summary/summaryModelSelection";
import { ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    open: boolean;
    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
    llmProvider?: string | null;
    // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#The confirm dialog names the model]]
    modelOptions?: ISummaryModelOption[];
    selectedModel?: string;
    // @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Operator instructions for one regeneration#The regeneration confirmation dialog and draft lifecycle]]
    initialInstructions?: string;

    isSubmitting?: boolean;
    onClose: () => void;
    onConfirm: (instructions?: string) => void;
    onDiscard?: () => void;
}

const LlmSummaryRegenerateConfirmDialog: React.FC<IProps> = ({
    open,
    llmProvider,
    modelOptions = [],
    selectedModel = "",
    initialInstructions = "",
    isSubmitting = false,
    onClose,
    onConfirm,
    onDiscard,
}) => {
    const label = offeredModelLabel(modelOptions, selectedModel);
    const [instructions, setInstructions] = useState<string>(initialInstructions);
    const prevOpenRef = useRef(open);

    useEffect(() => {
        if (open && !prevOpenRef.current) {
            setInstructions(initialInstructions);
        }
        prevOpenRef.current = open;
    }, [open, initialInstructions]);

    const trimAscii = (str: string) => str.replace(/^[\x20\t\r\n\f\v]+|[\x20\t\r\n\f\v]+$/g, "");
    const trimmed = trimAscii(instructions);
    const codePointCount = Array.from(trimmed).length;
    const isOverLimit = codePointCount > 2000;

    const handleClose = useCallback(() => {
        setInstructions("");
        onDiscard?.();
        onClose();
    }, [onClose, onDiscard]);

    const handleConfirm = useCallback(() => {
        if (isOverLimit || isSubmitting) return;
        onConfirm(trimmed);
    }, [isOverLimit, isSubmitting, onConfirm, trimmed]);

    return (
        <Dialog open={open} onOpenChange={(next) => !next && handleClose()}>
            <DialogContent data-testid="confirmation-dialog" className="w-[calc(100vw-2rem)] max-w-lg p-4 sm:p-6">
                <DialogHeader>
                    <DialogTitle>Regenerate summary?</DialogTitle>
                    <DialogDescription>
                        {isOperatorPasted(llmProvider)
                            ? "This summary was pasted by an operator, not generated. Regenerating replaces the " +
                              "hand-written text with model output, and the original cannot be recovered. Continue?"
                            : "This will replace the model's draft summary. The published summary below is not " +
                              "changed by this. Continue?"}
                    </DialogDescription>
                </DialogHeader>

                <div className="flex flex-col gap-1.5 mt-2">
                    <Label htmlFor="summary-instructions" className="text-sm font-medium">
                        Additional instructions (optional)
                    </Label>
                    <Textarea
                        id="summary-instructions"
                        data-testid="textarea-summary-instructions"
                        placeholder="e.g. Request a missing property tax rate if stated in the bill"
                        rows={4}
                        value={instructions}
                        onChange={(e) => setInstructions(e.target.value)}
                        disabled={isSubmitting}
                        aria-describedby={
                            isOverLimit
                                ? "summary-instructions-help summary-instructions-error"
                                : "summary-instructions-help"
                        }
                        aria-invalid={isOverLimit}
                        className="text-sm"
                    />
                    <div className="flex items-center justify-between text-xs">
                        <p id="summary-instructions-help" className="text-muted-foreground">
                            Instructions apply to this regeneration only. Details must be supported by source material
                            and cannot override factual grounding or neutrality.
                        </p>
                        <span
                            className={cn(
                                "tabular-nums",
                                isOverLimit ? "text-destructive font-semibold" : "text-muted-foreground",
                            )}
                        >
                            {codePointCount.toLocaleString()} / 2,000
                        </span>
                    </div>
                    {isOverLimit && (
                        <p
                            id="summary-instructions-error"
                            data-testid="summary-instructions-error"
                            className="text-xs font-medium text-destructive"
                            role="alert"
                        >
                            Instructions exceed the 2,000 code point limit. Please shorten them before regenerating.
                        </p>
                    )}
                </div>

                <p data-testid="confirm-dialog-model" className="mt-1 text-sm">
                    {label ? (
                        <>
                            This run uses <span className="font-semibold">{label}</span>.
                        </>
                    ) : (
                        "This run uses the standing default model."
                    )}
                </p>
                <DialogFooter className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                    <Button
                        variant="outline"
                        onClick={handleClose}
                        data-testid="btn-confirm-dialog-cancel"
                        className="min-h-[44px] sm:min-h-9 w-full sm:w-auto"
                        disabled={isSubmitting}
                    >
                        Cancel
                    </Button>
                    <Button
                        variant="destructive"
                        onClick={handleConfirm}
                        data-testid="btn-confirm-dialog-confirm"
                        className="min-h-[44px] sm:min-h-9 w-full sm:w-auto"
                        disabled={isOverLimit || isSubmitting}
                    >
                        Regenerate
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
};

export default LlmSummaryRegenerateConfirmDialog;
