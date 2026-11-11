import { useState } from "react";
import { Button } from "app/frontend/components/ui/button";
import PasteSummaryDialog from "app/frontend/components/admin/creator/PasteSummaryDialog";
import { PASTE_SUMMARY_SCHEMA_EXAMPLE } from "app/frontend/components/admin/creator/llm-summary/pasteSummarySchemaExample";

interface IProps {
    billId: number;
    // @lat: [[bill-creator-empty-state-prompt-flow#LlmSummaryPasteFallback itself]]
    size?: "sm" | "default";
}

// @lat: [[bill-creator-empty-state-prompt-flow#LlmSummaryPasteFallback itself]]
const LlmSummaryPasteFallback: React.FC<IProps> = ({ billId, size }) => {
    const [open, setOpen] = useState<boolean>(false);

    return (
        <>
            <Button
                type="button"
                variant="outline"
                size={size}
                onClick={() => setOpen(true)}
                data-testid="btn-paste-summary-fallback"
            >
                Paste summary JSON
            </Button>
            <PasteSummaryDialog
                billId={billId}
                open={open}
                onOpenChange={setOpen}
                schemaExample={PASTE_SUMMARY_SCHEMA_EXAMPLE}
            />
        </>
    );
};

export default LlmSummaryPasteFallback;
