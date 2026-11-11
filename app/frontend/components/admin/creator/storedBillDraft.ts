import { IStoredBillDraft } from "app/frontend/components/admin/creator/billDraftSummaryProvenance";
import { IApiBillCreator } from "app/frontend/components/admin/creator/types";

// @lat: [[temp-bill-storage-peek-parsing#Why TStoredBillDraft is a Partial]]
export type TStoredBillDraft = Partial<IApiBillCreator> & IStoredBillDraft;

// @lat: [[temp-bill-storage-peek-parsing#Why asStoredBillDraft is a shape check]]
export const asStoredBillDraft = (value: unknown): TStoredBillDraft | null =>
    typeof value === "object" && value !== null && !Array.isArray(value) ? (value as TStoredBillDraft) : null;
