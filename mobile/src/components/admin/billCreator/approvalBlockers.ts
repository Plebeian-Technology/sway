// @lat: [[mobile-bill-creator#Sections#The draft positions section#Approval blockers shared by the Positions tab sections]]
import type { BillCreatorProps } from "../../../hooks/admin/useBillCreator";

export interface ApprovalBlockers {
    testimonyMissing: boolean;
    summaryRunInFlight: boolean;
    cleanTestimonyRunning: boolean;
    runInFlight: boolean;
    testimonyLeftOutUnacknowledged: boolean;
}

interface ProvisioningProps {
    bill_llm_provisioning?: { generation_status?: string | null; has_testimony?: boolean } | null;
}

interface ActiveRun {
    status?: string | null;
    bill_id?: number | null;
}

interface Coverage {
    coverage_gap?: boolean;
    acknowledged?: boolean;
}

export const approvalBlockers = (data: BillCreatorProps, billId: number | null): ApprovalBlockers => {
    const provisioning = ((data.bill ?? {}) as ProvisioningProps).bill_llm_provisioning ?? null;
    const generationStatus = provisioning?.generation_status ?? null;
    const activeRun = (data.active_legislation_pipeline_run ?? null) as ActiveRun | null;
    const coverage = (data.testimony_coverage ?? null) as Coverage | null;

    const summaryRunInFlight = generationStatus === "pending" || generationStatus === "generating";
    const cleanTestimonyRunning =
        activeRun?.status === "cleaning_testimony" && (activeRun.bill_id === null || activeRun.bill_id === billId);

    return {
        testimonyMissing: !provisioning?.has_testimony,
        summaryRunInFlight,
        cleanTestimonyRunning,
        runInFlight: summaryRunInFlight || cleanTestimonyRunning,
        testimonyLeftOutUnacknowledged: !!coverage && !!coverage.coverage_gap && !coverage.acknowledged,
    };
};
