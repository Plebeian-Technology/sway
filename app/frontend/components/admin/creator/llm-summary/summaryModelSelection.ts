import { ISummaryModelOption } from "app/frontend/components/admin/creator/llm-summary/types";

// @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
export const offeredModel = (modelOptions: ISummaryModelOption[], selectedModel: string): string | undefined =>
    modelOptions.find((option) => option.id === selectedModel)?.id;

export const offeredModelLabel = (modelOptions: ISummaryModelOption[], selectedModel: string): string | null =>
    modelOptions.find((option) => option.id === selectedModel)?.label ?? null;
