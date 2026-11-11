// Date is derived from props/URL each render, not stored — preserveState keeps the component alive
// across bill switches, so stale stored state would leak the old bill's date.

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const usePageMock = vi.fn<() => { props: Record<string, unknown> }>();
const routerGet = vi.fn<(...args: unknown[]) => void>();
const routerPut = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", () => ({
    usePage: () => usePageMock(),
    router: {
        get: (...args: unknown[]) => routerGet(...args),
        put: (...args: unknown[]) => routerPut(...args),
    },
}));

// Stand-in: the sidebar is big, and is not what is tested here.
vi.mock("app/frontend/components/admin/creator/BillScheduleSidebar", () => ({
    __esModule: true,
    default: () => <div data-testid="sidebar" />,
}));

import BillSchedule from "app/frontend/components/admin/creator/BillSchedule";

const D1 = "2026-08-01";

const setBill = (bill: Record<string, unknown>) => usePageMock.mockReturnValue({ props: { bill, bills: [] } });

const setBillAndBills = (bill: Record<string, unknown>, bills: Record<string, unknown>[]) =>
    usePageMock.mockReturnValue({ props: { bill, bills } });

afterEach(() => {
    cleanup();
    usePageMock.mockReset();
    routerGet.mockReset();
    routerPut.mockReset();
});

describe("BillSchedule — selected date derives from props + URL", () => {
    it("clears the selected date when switching to an unscheduled bill (no leftover, disabled schedule)", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        setBill({ id: 1, external_id: "A-1", scheduled_release_date_utc: D1 });
        const { rerender } = render(<BillSchedule />);
        // A scheduled bill shows the remove action, proving the date was found.
        expect(screen.queryByTestId("btn-remove-bill-schedule")).not.toBeNull();

        // rerender (not a fresh render) mimics Inertia's preserveState, which keeps this component
        // instance mounted across bill switches.
        window.history.replaceState({}, "", "/admin/bill_creator/2/schedule");
        setBill({ id: 2, external_id: "B-2", scheduled_release_date_utc: null });
        rerender(<BillSchedule />);

        // Must be DISABLED — enabled would let one click schedule bill B for the wrong (bill A's) date.
        const scheduleBtn = screen.getByTestId("btn-schedule-bill") as HTMLButtonElement;
        expect(scheduleBtn.disabled).toBe(true);
    });

    // @lat: [[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]
    it("shows the day the bill is scheduled for, not the day before, in Eastern time", () => {
        const original = process.env.TZ;
        process.env.TZ = "America/New_York";
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date(2026, 8, 1, 9, 0, 0));
        try {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-08" };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            expect(screen.getAllByText("September 08, 2026")).toHaveLength(2);

            const selectedCell = screen.getByTestId("calendar-day-2026-09-08");
            expect(selectedCell.getAttribute("data-selected")).toBe("true");
            expect(selectedCell.getAttribute("data-state")).toBe("scheduled-this-bill");
        } finally {
            vi.useRealTimers();
            process.env.TZ = original;
        }
    });
});

describe("BillSchedule — picking a day", () => {
    beforeEach(() => {
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date(2026, 8, 1, 9, 0, 0));
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    // @lat: [[bill-schedule-calendar-dates#Why picking a day reaches no server]]
    it("puts the day in the address without asking the server for anything", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?bill_creator_tab=schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        const today = new Date();
        const cell = screen.getByTestId(
            `calendar-day-${new Date(today.getFullYear(), today.getMonth(), 15).toISOString().slice(0, 10)}`,
        );
        fireEvent.click(cell);

        expect(routerGet).not.toHaveBeenCalled();
        expect(new URLSearchParams(window.location.search).get("date")).toBeTruthy();
        expect(window.location.pathname).toBe("/admin/bill_creator/1/schedule");
        expect(new URLSearchParams(window.location.search).get("bill_creator_tab")).toBe("schedule");
    });

    it("shows the picked day as selected once the address has been rewritten", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        const today = new Date();
        const testId = `calendar-day-${new Date(today.getFullYear(), today.getMonth(), 15).toISOString().slice(0, 10)}`;
        fireEvent.click(screen.getByTestId(testId));

        expect(screen.getByTestId(testId).getAttribute("data-selected")).toBe("true");
    });
});

describe("BillSchedule — what the submit sends", () => {
    const ORIGINAL_TZ = process.env.TZ;

    afterEach(() => {
        process.env.TZ = ORIGINAL_TZ;
    });

    // @lat: [[bill-schedule-calendar-dates#Why a picked day travels as a bare day]]
    it.each(["Asia/Tokyo", "America/New_York"])("sends the day the operator clicked, not an instant, in %s", (tz) => {
        process.env.TZ = tz;
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?date=2026-09-08");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        fireEvent.click(screen.getByTestId("btn-schedule-bill"));

        expect(routerPut.mock.calls.at(-1)?.[0]).toBe("/bill_of_the_month_schedule/0");
        const body = routerPut.mock.calls.at(-1)?.[1] as {
            scheduled_release_date_utc: string;
            bill_id: number;
            bill_creator_tab: string;
        };
        expect(body.scheduled_release_date_utc).toBe("2026-09-08");
        expect(body.bill_id).toBe(1);
        expect(body.bill_creator_tab).toBe("schedule");
    });

    it("sends null when the operator takes a bill off the schedule", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-08" };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        fireEvent.click(screen.getByTestId("btn-remove-bill-schedule"));

        expect(routerPut.mock.calls.at(-1)?.[0]).toBe("/bill_of_the_month_schedule/0");
        const body = routerPut.mock.calls.at(-1)?.[1] as {
            scheduled_release_date_utc: string | null;
            bill_id: number;
            bill_creator_tab: string;
        };
        expect(body.scheduled_release_date_utc).toBeNull();
        expect(body.bill_id).toBe(1);
        expect(body.bill_creator_tab).toBe("schedule");
    });

    it("does not call router.put when bill is unsaved or id <= 0", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/0/schedule?date=2026-09-08");
        const bill = { id: 0, external_id: "A-1", title: "Unsaved Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        fireEvent.click(screen.getByTestId("btn-schedule-bill"));

        expect(routerPut).not.toHaveBeenCalled();
    });
});

describe("BillSchedule — mobile phone adaptations (Adapt bill scheduling for phone browsers)", () => {
    beforeEach(() => {
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date(2026, 8, 1, 9, 0, 0));
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    it("renders calendar day cells with 44px mobile touch target classes (h-11 min-h-11)", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        const dayButton = screen.getByTestId("calendar-day-2026-09-15");
        expect(dayButton.className).toContain("h-11");
        expect(dayButton.className).toContain("min-h-11");
    });

    it("toggles between Month view and Agenda view", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-15" };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        expect(screen.getByTestId("calendar-day-2026-09-15")).toBeTruthy();
        expect(screen.queryByTestId("agenda-view-list")).toBeNull();

        // Switch to Agenda
        fireEvent.click(screen.getByTestId("view-mode-agenda"));
        expect(screen.getByTestId("agenda-view-list")).toBeTruthy();
        expect(screen.getByTestId("agenda-row-2026-09-15")).toBeTruthy();

        // Switch back to Month
        fireEvent.click(screen.getByTestId("view-mode-month"));
        expect(screen.queryByTestId("agenda-view-list")).toBeNull();
        expect(screen.getByTestId("calendar-day-2026-09-15")).toBeTruthy();
    });

    it("allows picking a date from Agenda view and rewriting the URL", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        fireEvent.click(screen.getByTestId("view-mode-agenda"));

        const selectDateBtn = screen.getByTestId("btn-select-agenda-date-2026-09-20");
        fireEvent.click(selectDateBtn);

        expect(new URLSearchParams(window.location.search).get("date")).toBe("2026-09-20");
    });
});

describe("BillSchedule — URL date precedence, month synchronization, and Today button", () => {
    beforeEach(() => {
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date(2026, 8, 1, 9, 0, 0));
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    // @lat: [[bill-schedule-calendar-dates#Scheduler navigation, today control, and pagination]]
    it("prioritizes valid URL date over scheduled_release_date_utc and displays selected month", () => {
        // Bill is scheduled for 2026-09-08, but URL explicitly requests 2026-10-13
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?date=2026-10-13");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-08" };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        // Displays October 2026
        expect(screen.getByText("October 2026")).toBeDefined();

        // 2026-10-13 is highlighted as selected
        const oct13Cell = screen.getByTestId("calendar-day-2026-10-13");
        expect(oct13Cell.getAttribute("data-selected")).toBe("true");

        // Selected bill card shows October 13, 2026 as selected date
        expect(screen.getByText("October 13, 2026")).toBeDefined();

        // Stored release marker remains accurate: September 08 is rendered in Current release
        expect(screen.getByText("September 08, 2026")).toBeDefined();
    });

    it("falls back to scheduled_release_date_utc when URL date is invalid or absent", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?date=invalid-date");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-08" };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        // Falls back to September 2026
        expect(screen.getByText("September 2026")).toBeDefined();
        const sep08Cell = screen.getByTestId("calendar-day-2026-09-08");
        expect(sep08Cell.getAttribute("data-selected")).toBe("true");
        expect(sep08Cell.getAttribute("data-state")).toBe("scheduled-this-bill");
    });

    it("falls back to scheduled_release_date_utc when URL date has out-of-range calendar components (?date=2026-99-99)", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?date=2026-99-99");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-08" };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        // Falls back to September 2026 and highlights 2026-09-08 instead of overflowing to 2034
        expect(screen.getByText("September 2026")).toBeDefined();
        expect(screen.queryByText("June 2034")).toBeNull();
        const sep08Cell = screen.getByTestId("calendar-day-2026-09-08");
        expect(sep08Cell.getAttribute("data-selected")).toBe("true");
        expect(sep08Cell.getAttribute("data-state")).toBe("scheduled-this-bill");
    });

    it("falls back to scheduled_release_date_utc when URL date is invalid calendar day (?date=2026-02-31)", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?date=2026-02-31");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: "2026-09-08" };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        // Falls back to September 2026 and highlights 2026-09-08 instead of overflowing to March
        expect(screen.getByText("September 2026")).toBeDefined();
        expect(screen.queryByText("March 2026")).toBeNull();
        const sep08Cell = screen.getByTestId("calendar-day-2026-09-08");
        expect(sep08Cell.getAttribute("data-selected")).toBe("true");
        expect(sep08Cell.getAttribute("data-state")).toBe("scheduled-this-bill");
    });

    it("synchronizes displayed month and year when selectedDate changes across preserved navigation", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const billA = { id: 1, external_id: "A-1", title: "Bill A", scheduled_release_date_utc: "2026-08-01" };
        setBillAndBills(billA, [billA]);
        const { rerender } = render(<BillSchedule />);

        expect(screen.getByText("August 2026")).toBeDefined();
        expect(screen.getByTestId("calendar-day-2026-08-01").getAttribute("data-selected")).toBe("true");

        // Preserve state across bill switch with new scheduled date in October
        window.history.replaceState({}, "", "/admin/bill_creator/2/schedule");
        const billB = { id: 2, external_id: "B-2", title: "Bill B", scheduled_release_date_utc: "2026-10-15" };
        setBillAndBills(billB, [billA, billB]);
        rerender(<BillSchedule />);

        expect(screen.getByText("October 2026")).toBeDefined();
        expect(screen.getByTestId("calendar-day-2026-10-15").getAttribute("data-selected")).toBe("true");
    });

    it("navigates to current month using Today button without clearing selected date or mutating schedule in Month view", () => {
        // Start in December 2026 with a date selected
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?date=2026-12-25");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        expect(screen.getByText("December 2026")).toBeDefined();

        // Click Today button
        const todayBtn = screen.getByRole("button", { name: "Today" });
        fireEvent.click(todayBtn);

        // Displays current month (September 2026)
        expect(screen.getByText("September 2026")).toBeDefined();

        // Selected date is NOT cleared: Selected date card still displays December 25, 2026
        expect(screen.getByText("December 25, 2026")).toBeDefined();

        // Zero network/server calls
        expect(routerGet).not.toHaveBeenCalled();
        expect(routerPut).not.toHaveBeenCalled();

        // Navigate back to December using Next month button
        const nextBtn = screen.getByRole("button", { name: "Next month" });
        fireEvent.click(nextBtn); // October
        fireEvent.click(nextBtn); // November
        fireEvent.click(nextBtn); // December
        expect(screen.getByText("December 2026")).toBeDefined();

        // December 25 is still highlighted
        const dec25Cell = screen.getByTestId("calendar-day-2026-12-25");
        expect(dec25Cell.getAttribute("data-selected")).toBe("true");
    });

    it("navigates to current month using Today button in Agenda view without mutating schedule", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?date=2026-11-20");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        // Switch to Agenda view
        fireEvent.click(screen.getByTestId("view-mode-agenda"));
        expect(screen.getByTestId("agenda-view-list")).toBeDefined();
        expect(screen.getByTestId("agenda-row-2026-11-20")).toBeDefined();

        // Click Today button
        fireEvent.click(screen.getByRole("button", { name: "Today" }));

        // Agenda view now displays September 2026 days
        expect(screen.getByText("September 2026")).toBeDefined();
        expect(screen.getByTestId("agenda-row-2026-09-15")).toBeDefined();
        expect(screen.queryByTestId("agenda-row-2026-11-20")).toBeNull();

        // Zero network/server calls
        expect(routerGet).not.toHaveBeenCalled();
        expect(routerPut).not.toHaveBeenCalled();
    });

    it("renders Today button with mobile touch-target classes", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        const todayBtn = screen.getByRole("button", { name: "Today" });
        expect(todayBtn.className).toContain("h-11");
        expect(todayBtn.className).toContain("min-h-[44px]");
    });

    it("matches the Today button accessible name to its visible label", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
        setBillAndBills(bill, [bill]);
        render(<BillSchedule />);

        const todayBtn = screen.getByRole("button", { name: "Today" });
        expect(todayBtn).toBeDefined();
        expect(todayBtn.textContent?.trim()).toBe("Today");
        expect(todayBtn.getAttribute("data-testid")).toBe("btn-calendar-today");
        expect(todayBtn.getAttribute("aria-label")).toBeNull();
        expect(screen.queryByRole("button", { name: "Current month" })).toBeNull();
    });
});

describe("BillSchedule — selected bill fallback label", () => {
    it("renders New Bill of the Month fallback when the selected bill has no title", () => {
        window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
        setBill({ id: 1, external_id: "A-1", title: null, scheduled_release_date_utc: null });
        render(<BillSchedule />);

        expect(screen.getByText(/— New Bill of the Month/)).toBeDefined();
    });
});
