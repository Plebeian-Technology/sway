// @lat: [[bill-creator-pipeline-controls-panel#Why pickedBillId falls back to "run every bill"]]
export const pickedBillIdFor = (billId: number | null | undefined): string =>
    billId && billId > 0 ? String(billId) : "";
