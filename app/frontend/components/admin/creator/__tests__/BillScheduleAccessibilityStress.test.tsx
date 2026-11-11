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

vi.mock("app/frontend/components/admin/creator/BillScheduleSidebar", () => ({
    __esModule: true,
    default: () => <div data-testid="sidebar" />,
}));

import BillSchedule from "app/frontend/components/admin/creator/BillSchedule";

const setBillAndBills = (bill: Record<string, unknown>, bills: Record<string, unknown>[]) =>
    usePageMock.mockReturnValue({ props: { bill, bills } });

describe("BillSchedule — Empirical Challenger Stress Harness", () => {
    beforeEach(() => {
        vi.useFakeTimers({ toFake: ["Date"] });
        vi.setSystemTime(new Date(2026, 8, 14, 11, 0, 0)); // September 14, 2026
    });

    afterEach(() => {
        cleanup();
        vi.useRealTimers();
        usePageMock.mockReset();
        routerGet.mockReset();
        routerPut.mockReset();
    });

    describe("1. Touch targets and responsive sizing (WCAG 2.5.5 / 2.5.8)", () => {
        it("guarantees 44px touch targets on mobile for all navigation and view-toggle controls", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            // Today button
            const todayBtn = screen.getByRole("button", { name: "Today" });
            expect(todayBtn.className).toContain("h-11");
            expect(todayBtn.className).toContain("min-h-[44px]");

            // Prev and Next month buttons
            const prevBtn = screen.getByRole("button", { name: "Previous month" });
            const nextBtn = screen.getByRole("button", { name: "Next month" });
            expect(prevBtn.className).toContain("size-11");
            expect(nextBtn.className).toContain("size-11");

            // View mode toggle buttons (Month, Agenda)
            const monthToggle = screen.getByRole("button", { name: "Month" });
            const agendaToggle = screen.getByRole("button", { name: "Agenda" });
            expect(monthToggle.className).toContain("h-11");
            expect(monthToggle.className).toContain("min-h-[44px]");
            expect(agendaToggle.className).toContain("h-11");
            expect(agendaToggle.className).toContain("min-h-[44px]");

            // Calendar days in Month view
            const dayButton = screen.getByTestId("calendar-day-2026-09-15");
            expect(dayButton.className).toContain("h-11");
            expect(dayButton.className).toContain("min-h-11");
        });

        it("guarantees 44px touch targets on mobile for agenda action buttons", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            // Switch to Agenda view
            fireEvent.click(screen.getByRole("button", { name: "Agenda" }));
            const selectDateBtn = screen.getByTestId("btn-select-agenda-date-2026-09-20");
            expect(selectDateBtn.className).toContain("min-h-[44px]");
        });
    });

    describe("2. Accessible name and WCAG 2.5.3 (Label in Name)", () => {
        it("exposes 'Today' as the accessible name without override or hidden strings", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            // Role query finds button with name 'Today'
            const todayBtn = screen.getByRole("button", { name: "Today" });
            expect(todayBtn).toBeDefined();
            expect(todayBtn.getAttribute("aria-label")).toBeNull();
            expect(todayBtn.getAttribute("aria-labelledby")).toBeNull();
            expect(todayBtn.textContent?.trim()).toBe("Today");

            // Legacy overridden name 'Current month' must not resolve
            expect(screen.queryByRole("button", { name: "Current month" })).toBeNull();
            expect(screen.queryByRole("button", { name: /current month/i })).toBeNull();
        });

        it("maintains accessible names across Month and Agenda view switches", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            // Month view
            expect(screen.getByRole("button", { name: "Today" })).toBeDefined();

            // Agenda view
            fireEvent.click(screen.getByRole("button", { name: "Agenda" }));
            expect(screen.getByRole("button", { name: "Today" })).toBeDefined();
            expect(screen.queryByRole("button", { name: "Current month" })).toBeNull();

            // Back to Month view
            fireEvent.click(screen.getByRole("button", { name: "Month" }));
            expect(screen.getByRole("button", { name: "Today" })).toBeDefined();
            expect(screen.queryByRole("button", { name: "Current month" })).toBeNull();
        });
    });

    describe("3. Click responsiveness, idempotency, and rapid stress", () => {
        it("navigates back to current month after distant future navigation", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            expect(screen.getByText("September 2026")).toBeDefined();

            // Advance 6 months to March 2027
            const nextBtn = screen.getByRole("button", { name: "Next month" });
            for (let i = 0; i < 6; i++) {
                fireEvent.click(nextBtn);
            }
            expect(screen.getByText("March 2027")).toBeDefined();

            // Click Today
            const todayBtn = screen.getByRole("button", { name: "Today" });
            fireEvent.click(todayBtn);

            expect(screen.getByText("September 2026")).toBeDefined();
            expect(screen.queryByText("March 2027")).toBeNull();
            expect(routerGet).not.toHaveBeenCalled();
            expect(routerPut).not.toHaveBeenCalled();
        }, 20000);

        it("navigates back to current month after distant past navigation", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            expect(screen.getByText("September 2026")).toBeDefined();

            // Move back 8 months to January 2026
            const prevBtn = screen.getByRole("button", { name: "Previous month" });
            for (let i = 0; i < 8; i++) {
                fireEvent.click(prevBtn);
            }
            expect(screen.getByText("January 2026")).toBeDefined();

            // Click Today
            fireEvent.click(screen.getByRole("button", { name: "Today" }));

            expect(screen.getByText("September 2026")).toBeDefined();
            expect(screen.queryByText("January 2026")).toBeNull();
        }, 20000);

        it("is idempotent under rapid consecutive clicks (50 iterations)", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            const todayBtn = screen.getByRole("button", { name: "Today" });

            // Fire 50 rapid clicks
            for (let i = 0; i < 50; i++) {
                fireEvent.click(todayBtn);
            }

            // Still stable at September 2026
            expect(screen.getByText("September 2026")).toBeDefined();
            expect(routerGet).not.toHaveBeenCalled();
            expect(routerPut).not.toHaveBeenCalled();
        });

        it("preserves URL query parameters when clicking Today", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule?tab_key=schedule&custom_filter=test");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            // Move month away
            fireEvent.click(screen.getByRole("button", { name: "Next month" }));
            expect(screen.getByText("October 2026")).toBeDefined();

            // Click Today
            fireEvent.click(screen.getByRole("button", { name: "Today" }));
            expect(screen.getByText("September 2026")).toBeDefined();

            // Location is untouched
            expect(window.location.search).toContain("tab_key=schedule");
            expect(window.location.search).toContain("custom_filter=test");
        });
    });

    describe("4. View-mode toggles (Month vs Agenda) and state consistency", () => {
        it("synchronizes displayed month across Month and Agenda view toggles", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            // Navigate to November 2026 in Month view
            const nextBtn = screen.getByRole("button", { name: "Next month" });
            fireEvent.click(nextBtn); // October
            fireEvent.click(nextBtn); // November
            expect(screen.getByText("November 2026")).toBeDefined();

            // Toggle to Agenda view — should still be November 2026
            fireEvent.click(screen.getByRole("button", { name: "Agenda" }));
            expect(screen.getByText("November 2026")).toBeDefined();
            expect(screen.getByTestId("agenda-row-2026-11-15")).toBeDefined();

            // Click Today in Agenda view
            fireEvent.click(screen.getByRole("button", { name: "Today" }));
            expect(screen.getByText("September 2026")).toBeDefined();
            expect(screen.getByTestId("agenda-row-2026-09-15")).toBeDefined();

            // Toggle back to Month view — should now be September 2026
            fireEvent.click(screen.getByRole("button", { name: "Month" }));
            expect(screen.getByText("September 2026")).toBeDefined();
            expect(screen.getByTestId("calendar-day-2026-09-15")).toBeDefined();
        });

        it("updates aria-pressed attributes accurately on view-mode controls", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            const monthBtn = screen.getByRole("button", { name: "Month" });
            const agendaBtn = screen.getByRole("button", { name: "Agenda" });

            // Default: Month is pressed
            expect(monthBtn.getAttribute("aria-pressed")).toBe("true");
            expect(agendaBtn.getAttribute("aria-pressed")).toBe("false");

            // Switch to Agenda
            fireEvent.click(agendaBtn);
            expect(monthBtn.getAttribute("aria-pressed")).toBe("false");
            expect(agendaBtn.getAttribute("aria-pressed")).toBe("true");

            // Switch to Month
            fireEvent.click(monthBtn);
            expect(monthBtn.getAttribute("aria-pressed")).toBe("true");
            expect(agendaBtn.getAttribute("aria-pressed")).toBe("false");
        });
    });

    describe("5. Keyboard accessibility & focus interaction", () => {
        it("allows programmatic focus on Today button and responds to keyboard Enter/Space", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            // Navigate to December 2026
            const nextBtn = screen.getByRole("button", { name: "Next month" });
            fireEvent.click(nextBtn);
            fireEvent.click(nextBtn);
            fireEvent.click(nextBtn);
            expect(screen.getByText("December 2026")).toBeDefined();

            const todayBtn = screen.getByRole("button", { name: "Today" });

            // Focus button
            todayBtn.focus();
            expect(document.activeElement).toBe(todayBtn);

            // Press Enter
            fireEvent.keyDown(todayBtn, { key: "Enter", code: "Enter" });
            fireEvent.click(todayBtn); // Standard browser event sequence for keyboard activation
            expect(screen.getByText("September 2026")).toBeDefined();

            // Navigate forward again
            fireEvent.click(nextBtn);
            expect(screen.getByText("October 2026")).toBeDefined();

            // Press Space
            todayBtn.focus();
            fireEvent.keyDown(todayBtn, { key: " ", code: "Space" });
            fireEvent.click(todayBtn);
            expect(screen.getByText("September 2026")).toBeDefined();
        });

        it("retains accessible day labels for screen readers in Month view", () => {
            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            const sep15Cell = screen.getByTestId("calendar-day-2026-09-15");
            expect(sep15Cell.getAttribute("aria-label")).toBe("September 15, 2026 — No scheduled bill");
        });
    });

    describe("6. Edge cases: Leap year and year transitions", () => {
        it("handles leap day (February 29, 2028) correctly when clicking Today", () => {
            vi.setSystemTime(new Date(2028, 1, 29, 12, 0, 0)); // Feb 29, 2028

            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            expect(screen.getByText("February 2028")).toBeDefined();
            expect(screen.getByTestId("calendar-day-2028-02-29")).toBeDefined();

            // Navigate to June 2028
            const nextBtn = screen.getByRole("button", { name: "Next month" });
            fireEvent.click(nextBtn);
            fireEvent.click(nextBtn);
            fireEvent.click(nextBtn);
            fireEvent.click(nextBtn);
            expect(screen.getByText("June 2028")).toBeDefined();

            // Click Today
            fireEvent.click(screen.getByRole("button", { name: "Today" }));
            expect(screen.getByText("February 2028")).toBeDefined();
            expect(screen.getByTestId("calendar-day-2028-02-29")).toBeDefined();
        });

        it("handles year transition boundary (December 31, 2026 23:59:59)", () => {
            vi.setSystemTime(new Date(2026, 11, 31, 23, 59, 59)); // Dec 31, 2026

            window.history.replaceState({}, "", "/admin/bill_creator/1/schedule");
            const bill = { id: 1, external_id: "A-1", title: "Test Bill", scheduled_release_date_utc: null };
            setBillAndBills(bill, [bill]);
            render(<BillSchedule />);

            expect(screen.getByText("December 2026")).toBeDefined();

            // Move to July 2026
            const prevBtn = screen.getByRole("button", { name: "Previous month" });
            for (let i = 0; i < 5; i++) {
                fireEvent.click(prevBtn);
            }
            expect(screen.getByText("July 2026")).toBeDefined();

            // Click Today
            fireEvent.click(screen.getByRole("button", { name: "Today" }));
            expect(screen.getByText("December 2026")).toBeDefined();
        });
    });
});
