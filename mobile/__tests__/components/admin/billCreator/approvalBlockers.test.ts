import type { BillCreatorProps } from "../../../../src/hooks/admin/useBillCreator";
import { approvalBlockers } from "../../../../src/components/admin/billCreator/approvalBlockers";

const tabData = (
    provisioning: Record<string, unknown> = {},
    overrides: Record<string, unknown> = {},
): BillCreatorProps =>
    ({
        bill: {
            id: 42,
            external_id: "25-0001",
            title: "A bill",
            bill_llm_provisioning: { generation_status: "completed", has_testimony: true, ...provisioning },
        },
        active_legislation_pipeline_run: null,
        testimony_coverage: null,
        ...overrides,
    }) as BillCreatorProps;

describe("approvalBlockers", () => {
    it("blocks nothing when testimony is on file, no run is in flight and no gap is open", () => {
        expect(approvalBlockers(tabData(), 42)).toEqual({
            testimonyMissing: false,
            summaryRunInFlight: false,
            cleanTestimonyRunning: false,
            runInFlight: false,
            testimonyLeftOutUnacknowledged: false,
        });
    });

    it("reports missing testimony when the bill has none or has no provisioning", () => {
        expect(approvalBlockers(tabData({ has_testimony: false }), 42).testimonyMissing).toBe(true);
        expect(approvalBlockers({ bill: { id: 42, external_id: null, title: null } }, 42).testimonyMissing).toBe(true);
        expect(approvalBlockers({}, 42).testimonyMissing).toBe(true);
    });

    it.each(["pending", "generating"])("reports a summary run in flight while generation is %s", (status) => {
        const blockers = approvalBlockers(tabData({ generation_status: status }), 42);
        expect(blockers.summaryRunInFlight).toBe(true);
        expect(blockers.cleanTestimonyRunning).toBe(false);
        expect(blockers.runInFlight).toBe(true);
    });

    it("does not treat a finished or unset generation as in flight", () => {
        expect(approvalBlockers(tabData({ generation_status: "failed" }), 42).runInFlight).toBe(false);
        expect(approvalBlockers(tabData({ generation_status: null }), 42).runInFlight).toBe(false);
    });

    it("reports a clean-testimony run in flight for this bill or for no bill", () => {
        const forThisBill = tabData(
            {},
            { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: 42 } },
        );
        const forNoBill = tabData(
            {},
            { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: null } },
        );
        for (const data of [forThisBill, forNoBill]) {
            const blockers = approvalBlockers(data, 42);
            expect(blockers.cleanTestimonyRunning).toBe(true);
            expect(blockers.summaryRunInFlight).toBe(false);
            expect(blockers.runInFlight).toBe(true);
        }
    });

    it("ignores a clean-testimony run for another bill and runs in other stages", () => {
        const otherBill = tabData(
            {},
            { active_legislation_pipeline_run: { status: "cleaning_testimony", bill_id: 7 } },
        );
        const otherStage = tabData({}, { active_legislation_pipeline_run: { status: "fetching", bill_id: 42 } });
        expect(approvalBlockers(otherBill, 42).runInFlight).toBe(false);
        expect(approvalBlockers(otherStage, 42).runInFlight).toBe(false);
    });

    it("reports left-out testimony only while a coverage gap is unacknowledged", () => {
        const withCoverage = (coverage: Record<string, unknown> | null) =>
            approvalBlockers(tabData({}, { testimony_coverage: coverage }), 42).testimonyLeftOutUnacknowledged;
        expect(withCoverage({ coverage_gap: true, acknowledged: false })).toBe(true);
        expect(withCoverage({ coverage_gap: true })).toBe(true);
        expect(withCoverage({ coverage_gap: true, acknowledged: true })).toBe(false);
        expect(withCoverage({ coverage_gap: false, acknowledged: false })).toBe(false);
        expect(withCoverage(null)).toBe(false);
    });
});
