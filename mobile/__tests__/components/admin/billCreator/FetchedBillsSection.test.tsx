import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

jest.mock("../../../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
}));

import FetchedBillsSection, {
    type FetchedBillsRow,
} from "../../../../src/components/admin/billCreator/FetchedBillsSection";

const row = (overrides: Partial<FetchedBillsRow>): FetchedBillsRow => ({
    external_id: "25-0001",
    bill_id: 1,
    title: "Rent relief",
    fetched_at: "2026-11-23T12:00:00Z",
    pdf_present: true,
    metadata_present: true,
    bill_row_exists: true,
    ...overrides,
});

const rows: FetchedBillsRow[] = [
    row({}),
    row({ external_id: "25-0002", title: "Zoning", fetched_at: "2026-11-01T12:00:00Z", pdf_present: false }),
    row({
        external_id: "24-0099",
        title: null,
        bill_id: null,
        bill_row_exists: false,
        fetched_at: "2026-08-01T12:00:00Z",
    }),
];

const open = () => fireEvent.press(screen.getByTestId("admin-fetched-bills-toggle"));

// @lat: [[mobile-bill-creator#Sections#The pipeline read-only panels]]
describe("FetchedBillsSection", () => {
    beforeEach(() => {
        jest.useFakeTimers();
        jest.setSystemTime(new Date("2026-11-24T12:00:00Z"));
    });

    afterEach(() => jest.useRealTimers());

    it("starts collapsed and names the count in its title", () => {
        render(<FetchedBillsSection rows={rows} />);

        expect(screen.getByTestId("admin-fetched-bills-toggle")).toHaveTextContent(/Fetched bills \(on disk\)/);
        expect(screen.queryByTestId("admin-fetched-bill-25-0001")).toBeNull();
    });

    it("shows external id, bill title or orphan marker, freshness, age and PDF", () => {
        render(<FetchedBillsSection rows={rows} />);
        open();

        expect(screen.getByTestId("admin-fetched-bills-count")).toHaveTextContent(/3 bills/);
        const fresh = screen.getByTestId("admin-fetched-bill-25-0001");
        expect(fresh).toHaveTextContent(/25-0001/);
        expect(fresh).toHaveTextContent(/Rent relief/);
        expect(fresh).toHaveTextContent(/fresh 1d ago/);
        expect(fresh).toHaveTextContent(/1d ago/);
        expect(fresh).toHaveTextContent(/PDF ✓/);
        const stale = screen.getByTestId("admin-fetched-bill-25-0002");
        expect(stale).toHaveTextContent(/^25-0002Zoningstale 23d ago/);
        expect(stale).toHaveTextContent(/PDF —/);
        const orphan = screen.getByTestId("admin-fetched-bill-24-0099");
        expect(orphan).toHaveTextContent(/\(orphan on disk\)/);
        expect(orphan).toHaveTextContent(/very stale/);
    });

    it("says there are no artifacts when the list is empty", () => {
        render(<FetchedBillsSection rows={[]} />);
        open();

        expect(screen.getByText("No bill artifacts on disk yet. Run the fetch-bills stage to populate.")).toBeTruthy();
    });

    it("filters by search text on id or title", () => {
        render(<FetchedBillsSection rows={rows} />);
        open();

        fireEvent.changeText(screen.getByTestId("admin-fetched-bills-search-input"), "zoning");

        expect(screen.getByTestId("admin-fetched-bills-count")).toHaveTextContent(/1 of 3 bills/);
        expect(screen.getByTestId("admin-fetched-bill-25-0002")).toBeTruthy();
        expect(screen.queryByTestId("admin-fetched-bill-25-0001")).toBeNull();
    });

    it("filters by freshness and clears the filters when nothing matches", () => {
        render(<FetchedBillsSection rows={[rows[0]]} />);
        open();

        fireEvent.press(screen.getByTestId("admin-fetched-bills-filter-danger"));
        expect(screen.getByText("No bills match.")).toBeTruthy();

        fireEvent.press(screen.getByTestId("admin-fetched-bills-clear"));
        expect(screen.getByTestId("admin-fetched-bill-25-0001")).toBeTruthy();
    });
});
