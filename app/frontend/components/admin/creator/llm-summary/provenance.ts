// @lat: [[operator-paste-provenance-marker#LlmSummaryProvenanceChip]]
export const OPERATOR_PASTE_PROVIDER = "operator_paste";

export const isOperatorPasted = (llmProvider: string | null | undefined): boolean =>
    llmProvider === OPERATOR_PASTE_PROVIDER;
