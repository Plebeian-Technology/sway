import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { sway } from "sway";

const usePageMock = vi.fn<() => { props: Record<string, unknown> }>();
vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
}));

import BillScheduleSidebar from "app/frontend/components/admin/creator/BillScheduleSidebar";

const onSelectBill = vi.fn<(bill: sway.IBillPickerOption) => void>();

const STORAGE_KEY = "sway:bill-schedule:accordion:unscheduled";

const unscheduledBill = (id: number, external_id: string) => ({
    id,
    external_id,
    title: `Bill ${external_id}`,
    scheduled_release_date_utc: null,
});

const pastScheduledBill = (id: number, external_id: string, date: string) => ({
    id,
    external_id,
    title: `Bill ${external_id}`,
    scheduled_release_date_utc: date,
});

const setBills = (bills: Record<string, unknown>[]) => usePageMock.mockReturnValue({ props: { bills } });

beforeEach(() => {
    window.localStorage.clear();
});

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    onSelectBill.mockClear();
});

describe("BillScheduleSidebar — upcoming list uses calendar-day comparison", () => {
    // @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
    it("keeps a bill scheduled for today in Upcoming, not filtered out a day early west of UTC", () => {
        const originalTz = process.env.TZ;
        process.env.TZ = "America/New_York";
        vi.useFakeTimers();
        vi.setSystemTime(new Date(2026, 8, 8, 9, 0, 0));
        try {
            setBills([{ id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-08" }]);
            render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

            expect(screen.getByTestId("sidebar-select-A-1")).toBeDefined();
        } finally {
            vi.useRealTimers();
            process.env.TZ = originalTz;
        }
    });
});

describe("BillScheduleSidebar — unscheduled panel starts collapsed", () => {
    it("hides the unscheduled rows until the panel is expanded", () => {
        setBills([unscheduledBill(1, "A-1"), unscheduledBill(2, "A-2")]);
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        expect(screen.queryByTestId("sidebar-select-A-1")).toBeNull();

        fireEvent.click(screen.getByTestId(`collapsible-panel-trigger-${STORAGE_KEY}`));

        expect(screen.getByTestId("sidebar-select-A-1")).toBeDefined();
        expect(screen.getByTestId("sidebar-select-A-2")).toBeDefined();
    });

    it("shows the unscheduled rows on first render when the operator left the panel open last time", () => {
        window.localStorage.setItem(STORAGE_KEY, "1");
        setBills([unscheduledBill(1, "A-1")]);
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        expect(screen.getByTestId("sidebar-select-A-1")).toBeDefined();
    });
});

describe("BillScheduleSidebar — unscheduled list is paged five at a time", () => {
    it("shows at most five rows and a Pagination control past that count", () => {
        window.localStorage.setItem(STORAGE_KEY, "1");
        setBills(Array.from({ length: 7 }, (_, i) => unscheduledBill(i + 1, `A-${i + 1}`)));
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        expect(screen.getAllByTestId(/^sidebar-select-A-/)).toHaveLength(5);
        expect(screen.getByRole("navigation", { name: "Pagination" })).toBeDefined();
    });

    it("moves the next five rows onto the page when Next is clicked", () => {
        window.localStorage.setItem(STORAGE_KEY, "1");
        setBills(Array.from({ length: 7 }, (_, i) => unscheduledBill(i + 1, `A-${i + 1}`)));
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        expect(screen.getByTestId("sidebar-select-A-1")).toBeDefined();
        expect(screen.queryByTestId("sidebar-select-A-6")).toBeNull();

        fireEvent.click(screen.getByRole("button", { name: "Next page" }));

        expect(screen.queryByTestId("sidebar-select-A-1")).toBeNull();
        expect(screen.getByTestId("sidebar-select-A-6")).toBeDefined();
        expect(screen.getByTestId("sidebar-select-A-7")).toBeDefined();
    });
});

describe("BillScheduleSidebar — past scheduled list is paged five at a time", () => {
    beforeEach(() => {
        vi.useFakeTimers({ toFake: ["Date"] });
        // Set clock to 2026-09-20 so dates earlier in September are strictly in the past
        vi.setSystemTime(new Date(2026, 8, 20, 9, 0, 0));
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    // @lat: [[bill-schedule-calendar-dates#Scheduler navigation, today control, and pagination]]
    it("renders 5 past scheduled bills on page 1 and 2 on page 2 with full total badge count", () => {
        const pastBills = Array.from({ length: 7 }, (_, i) =>
            pastScheduledBill(i + 1, `P-${i + 1}`, `2026-09-0${i + 1}`),
        );
        setBills(pastBills);
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        const pastSection = screen.getByText("Past scheduled").closest("section")!;

        // Full total badge count continues to show 7
        expect(within(pastSection).getByText("7")).toBeDefined();

        // Page 1 renders exactly 5 items
        expect(within(pastSection).getAllByTestId(/^sidebar-select-P-/)).toHaveLength(5);
        expect(screen.getByTestId("sidebar-select-P-1")).toBeDefined();
        expect(screen.getByTestId("sidebar-select-P-5")).toBeDefined();
        expect(screen.queryByTestId("sidebar-select-P-6")).toBeNull();
        expect(screen.queryByTestId("sidebar-select-P-7")).toBeNull();

        // Click next page
        const nextPageBtn = within(pastSection).getByRole("button", { name: "Next page" });
        fireEvent.click(nextPageBtn);

        // Page 2 renders remaining 2 items
        expect(within(pastSection).getAllByTestId(/^sidebar-select-P-/)).toHaveLength(2);
        expect(screen.queryByTestId("sidebar-select-P-1")).toBeNull();
        expect(screen.getByTestId("sidebar-select-P-6")).toBeDefined();
        expect(screen.getByTestId("sidebar-select-P-7")).toBeDefined();
    });

    it("cycles through all past bills using previous and next page navigation", () => {
        const pastBills = Array.from({ length: 7 }, (_, i) =>
            pastScheduledBill(i + 1, `P-${i + 1}`, `2026-09-0${i + 1}`),
        );
        setBills(pastBills);
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        const pastSection = screen.getByText("Past scheduled").closest("section")!;

        // Go to page 2
        fireEvent.click(within(pastSection).getByRole("button", { name: "Next page" }));
        expect(screen.getByTestId("sidebar-select-P-6")).toBeDefined();

        // Go back to page 1 using Previous page
        fireEvent.click(within(pastSection).getByRole("button", { name: "Previous page" }));
        expect(screen.getByTestId("sidebar-select-P-1")).toBeDefined();
        expect(screen.queryByTestId("sidebar-select-P-6")).toBeNull();
    });

    it("does not render pagination when past scheduled bills are 5 or fewer", () => {
        const pastBills = Array.from({ length: 4 }, (_, i) =>
            pastScheduledBill(i + 1, `P-${i + 1}`, `2026-09-0${i + 1}`),
        );
        setBills(pastBills);
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        const pastSection = screen.getByText("Past scheduled").closest("section")!;
        expect(within(pastSection).getByText("4")).toBeDefined();
        expect(within(pastSection).getAllByTestId(/^sidebar-select-P-/)).toHaveLength(4);
        expect(within(pastSection).queryByRole("navigation", { name: "Pagination" })).toBeNull();
    });

    it("maintains independent pagination state between Past scheduled and Unscheduled lists", () => {
        window.localStorage.setItem(STORAGE_KEY, "1"); // Keep unscheduled panel open
        const pastBills = Array.from({ length: 7 }, (_, i) =>
            pastScheduledBill(i + 1, `P-${i + 1}`, `2026-09-0${i + 1}`),
        );
        const unscheduledBills = Array.from({ length: 7 }, (_, i) => unscheduledBill(100 + i + 1, `U-${i + 1}`));
        setBills([...pastBills, ...unscheduledBills]);
        render(<BillScheduleSidebar selectedBillId={null} onSelectBill={onSelectBill} />);

        const pastSection = screen.getByText("Past scheduled").closest("section")!;
        const unscheduledSection = screen.getByText("Unscheduled").closest("section")!;

        // Initially both are on page 1
        expect(screen.getByTestId("sidebar-select-P-1")).toBeDefined();
        expect(screen.queryByTestId("sidebar-select-P-6")).toBeNull();
        expect(screen.getByTestId("sidebar-select-U-1")).toBeDefined();
        expect(screen.queryByTestId("sidebar-select-U-6")).toBeNull();

        // Advance Past scheduled to page 2
        fireEvent.click(within(pastSection).getByRole("button", { name: "Next page" }));

        // Past scheduled is on page 2
        expect(screen.queryByTestId("sidebar-select-P-1")).toBeNull();
        expect(screen.getByTestId("sidebar-select-P-6")).toBeDefined();

        // Unscheduled is STILL on page 1
        expect(screen.getByTestId("sidebar-select-U-1")).toBeDefined();
        expect(screen.queryByTestId("sidebar-select-U-6")).toBeNull();

        // Advance Unscheduled to page 2
        fireEvent.click(within(unscheduledSection).getByRole("button", { name: "Next page" }));

        // Both are now on page 2
        expect(screen.getByTestId("sidebar-select-P-6")).toBeDefined();
        expect(screen.queryByTestId("sidebar-select-U-1")).toBeNull();
        expect(screen.getByTestId("sidebar-select-U-6")).toBeDefined();
    });
});
