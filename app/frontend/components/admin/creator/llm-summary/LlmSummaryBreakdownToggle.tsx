import { useState } from "react";
import { Button } from "app/frontend/components/ui/button";

interface IProps {
    breakdown: string | null;
}

// @lat: [[bill-creator-summary-tab#Why a run with no breakdown says so]]
const LlmSummaryBreakdownToggle: React.FC<IProps> = ({ breakdown }) => {
    const [showBreakdown, setShowBreakdown] = useState<boolean>(false);
    const hasBreakdown = (breakdown ?? "").trim().length > 0;

    if (!hasBreakdown) {
        return (
            <p className="text-xs text-muted-foreground" data-testid="llm-breakdown-absent">
                This run wrote no section breakdown. The breakdown is an optional part of the model&rsquo;s answer, and
                a run that leaves it out still writes the public summary above.
            </p>
        );
    }

    return (
        <div className="flex flex-col gap-2">
            <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={() => setShowBreakdown((p) => !p)}
                data-testid="btn-toggle-breakdown"
                aria-expanded={showBreakdown}
                aria-controls="llm-full-breakdown"
                className="self-start hover:underline"
            >
                {showBreakdown ? "Hide full section breakdown" : "Show full section breakdown"}
            </Button>
            {showBreakdown && (
                <pre
                    id="llm-full-breakdown"
                    data-testid="llm-full-breakdown"
                    className="max-h-96 select-text overflow-auto whitespace-pre-wrap rounded-xl border-neo border-border bg-surface-2 p-3 text-xs"
                >
                    {breakdown}
                </pre>
            )}
        </div>
    );
};

export default LlmSummaryBreakdownToggle;
