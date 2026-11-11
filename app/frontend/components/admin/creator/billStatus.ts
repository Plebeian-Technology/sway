import { sway } from "sway";

// @lat: [[bill-creator-initial-values-and-draft-restore#billStatus.ts: EVERY_BILL_STATUS and asBillStatus]]
const EVERY_BILL_STATUS = {
    passed: "passed",
    failed: "failed",
    committee: "committee",
    vetoed: "vetoed",
} as const satisfies Record<sway.TBillStatus, sway.TBillStatus>;

// @lat: [[bill-creator-initial-values-and-draft-restore#billStatus.ts: EVERY_BILL_STATUS and asBillStatus]]
export const asBillStatus = (value: string | null | undefined): sway.TBillStatus | undefined =>
    Object.values(EVERY_BILL_STATUS).find((status) => status === value?.trim());
