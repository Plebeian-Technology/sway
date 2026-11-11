import { Badge } from "app/frontend/components/ui/badge";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "app/frontend/components/ui/tooltip";
import { isOperatorPasted } from "app/frontend/components/admin/creator/llm-summary/provenance";

interface IProps {
    llmProvider: string | null;
}

// @lat: [[operator-paste-provenance-marker#LlmSummaryProvenanceChip]]
const LlmSummaryProvenanceChip: React.FC<IProps> = ({ llmProvider }) => {
    if (!isOperatorPasted(llmProvider)) return null;

    return (
        <TooltipProvider delayDuration={150}>
            <Tooltip>
                <TooltipTrigger asChild>
                    <Badge variant="stamp" tone="warning" data-testid="llm-operator-paste-chip">
                        Operator-pasted
                    </Badge>
                </TooltipTrigger>
                <TooltipContent>
                    This summary was written by hand, not generated. Regenerating replaces it and the original cannot be
                    recovered.
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
};

export default LlmSummaryProvenanceChip;
