import { IBillLlmProvisioning } from "app/frontend/components/admin/creator/llm-summary/types";

interface IProps {
    // @lat: [[llm-summary-notice-phrase-pairing#LlmSummaryAbandonedRunNotice field notes]]
    generationStatus: IBillLlmProvisioning["generation_status"];
    // @lat: [[llm-summary-notice-phrase-pairing#LlmSummaryAbandonedRunNotice field notes]]
    hasTestimony: boolean;
}

// @lat: [[llm-summary-notice-phrase-pairing#LlmSummaryAbandonedRunNotice field notes]]
const LlmSummaryAbandonedRunNotice: React.FC<IProps> = ({ generationStatus, hasTestimony }) => (
    <p className="text-sm text-foreground/80" data-testid="llm-abandoned-run-notice">
        {generationStatus === "pending"
            ? "This run never started, and nothing is working on it now. "
            : "This run stopped part-way, and nothing is working on it now. "}
        Starting a new run takes it over.{" "}
        {hasTestimony
            ? "It costs no more than two model calls: one for the summary, one for the organization positions."
            : "This bill has no testimony, so a run asks for no organization positions. It costs no more than one " +
              "model call, for the summary."}
    </p>
);

export default LlmSummaryAbandonedRunNotice;
