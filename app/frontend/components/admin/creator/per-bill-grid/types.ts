import type { PipelineRunBill } from "app/frontend/types/bill_creator";

// @lat: [[bill-creator-pipeline-llm-tab#Why billIdByExternalId is built from the picker's bill list]]
export interface BillExternalIdLookup {
    [external_id: string]: number;
}

export interface IRowCellsProps {
    row: PipelineRunBill;
    currentStage: string | null;
    // @lat: [[legislation-pipeline-run-current-stage#Behavior on terminal statuses#PerBillGrid's test for the finished-run Stage column]]
    runStatus: string | null;
    stagesSucceeded: number;
    stagesTotal: number;
    showActions: boolean;
    billId?: number;
}
