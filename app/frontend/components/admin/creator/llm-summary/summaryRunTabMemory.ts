// @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]

const NO_GENERATION = "none";

const pendingKey = (billId: number): string => `sway.summaryRegeneratePending.${billId}`;
const modelKey = (billId: number): string => `sway.summaryModel.${billId}`;
const reasoningEffortKey = (billId: number): string => `sway.summaryReasoningEffort.${billId}`;

const read = (key: string): string | null => {
    try {
        return window.sessionStorage.getItem(key);
    } catch {
        return null;
    }
};

const write = (key: string, value: string): void => {
    try {
        window.sessionStorage.setItem(key, value);
    } catch {
        // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]
    }
};

const remove = (key: string): void => {
    try {
        window.sessionStorage.removeItem(key);
    } catch {
        // @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]
    }
};

export const markRegenerateRequested = (billId: number, llmGeneratedAt: string | null): void =>
    write(pendingKey(billId), llmGeneratedAt ?? NO_GENERATION);

// @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]
export const clearRegenerateRequested = (billId: number): void => remove(pendingKey(billId));

// @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration#A new draft takes the place of the text in the box]]
export const takeLandedRegenerate = (billId: number, llmGeneratedAt: string | null): boolean => {
    const pending = read(pendingKey(billId));
    if (pending === null) return false;
    if (pending === (llmGeneratedAt ?? NO_GENERATION)) return false;

    remove(pendingKey(billId));
    return true;
};

export const rememberSummaryModel = (billId: number, model: string): void => write(modelKey(billId), model);

export const recallSummaryModel = (billId: number): string | null => read(modelKey(billId));

export const rememberSummaryReasoningEffort = (billId: number, effort: string): void =>
    effort ? write(reasoningEffortKey(billId), effort) : remove(reasoningEffortKey(billId));

export const recallSummaryReasoningEffort = (billId: number): string | null => read(reasoningEffortKey(billId));
