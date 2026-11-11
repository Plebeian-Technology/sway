// Search, freshness filter, and scrollable body.

import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { FetchedBillsRow } from "app/frontend/types/bill_creator";

vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href, className }: { children: React.ReactNode; href: string; className?: string }) => (
        <a href={href} className={className}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, ...props }: React.HTMLAttributes<HTMLSpanElement>) => <span {...props}>{children}</span>,
}));

vi.mock("app/frontend/components/ui/button", () => ({
    Button: ({ children, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement>) => (
        <button {...props}>{children}</button>
    ),
}));

vi.mock("app/frontend/components/ui/input", () => ({
    Input: (props: React.InputHTMLAttributes<HTMLInputElement>) => <input {...props} />,
}));

vi.mock("app/frontend/components/ui/table", () => ({
    Table: ({ children }: { children: React.ReactNode }) => <table>{children}</table>,
    TableHeader: ({ children }: { children: React.ReactNode }) => <thead>{children}</thead>,
    TableBody: ({ children }: { children: React.ReactNode }) => <tbody>{children}</tbody>,
    TableRow: ({ children, ...props }: React.HTMLAttributes<HTMLTableRowElement>) => <tr {...props}>{children}</tr>,
    TableHead: ({ children }: { children: React.ReactNode }) => <th>{children}</th>,
    TableCell: ({ children, ...props }: React.HTMLAttributes<HTMLTableCellElement>) => <td {...props}>{children}</td>,
}));

vi.mock("app/frontend/sway_utils/datetimes", () => ({
    relativeTime: (s: string) => `relative(${s})`,
}));

import FetchedBillsPanel from "app/frontend/components/admin/creator/FetchedBillsPanel";

const DAY = 24 * 60 * 60 * 1000;

function makeRow(overrides: Partial<FetchedBillsRow> = {}): FetchedBillsRow {
    return {
        external_id: "25-0001",
        bill_id: 1,
        title: "Default Bill",
        fetched_at: new Date(Date.now() - 1 * DAY).toISOString(),
        pdf_present: true,
        metadata_present: true,
        bill_row_exists: true,
        ...overrides,
    };
}

describe("FetchedBillsPanel", () => {
    afterEach(() => cleanup());

    it("renders the zero-state copy when rows is empty", () => {
        render(<FetchedBillsPanel rows={[]} />);
        expect(screen.getByText(/No bill artifacts on disk yet\./)).toBeDefined();
    });

    it("shows total count and all rows when unfiltered", () => {
        const rows = [
            makeRow({ external_id: "25-0001" }),
            makeRow({ external_id: "25-0002", bill_id: 2, title: "Second" }),
            makeRow({ external_id: "25-0003", bill_id: 3, title: "Third" }),
        ];
        render(<FetchedBillsPanel rows={rows} />);
        expect(screen.getByTestId("fetched-bills-count").textContent).toBe("3 bills");
        expect(screen.getByTestId("fetched-bill-row-25-0001")).toBeDefined();
        expect(screen.getByTestId("fetched-bill-row-25-0003")).toBeDefined();
    });

    it("narrows by external_id substring (case-insensitive)", () => {
        const rows = [
            makeRow({ external_id: "25-0001", title: "Alpha" }),
            makeRow({ external_id: "25-0123", bill_id: 2, title: "Beta" }),
            makeRow({ external_id: "26-9999", bill_id: 3, title: "Gamma" }),
        ];
        render(<FetchedBillsPanel rows={rows} />);
        fireEvent.change(screen.getByTestId("fetched-bills-search"), { target: { value: "0123" } });
        expect(screen.queryByTestId("fetched-bill-row-25-0001")).toBeNull();
        expect(screen.getByTestId("fetched-bill-row-25-0123")).toBeDefined();
        expect(screen.queryByTestId("fetched-bill-row-26-9999")).toBeNull();
        expect(screen.getByTestId("fetched-bills-count").textContent).toBe("1 of 3 bills");
    });

    it("narrows by title substring", () => {
        const rows = [
            makeRow({ external_id: "25-0001", title: "Education Funding Act" }),
            makeRow({ external_id: "25-0002", bill_id: 2, title: "Highway Repair" }),
        ];
        render(<FetchedBillsPanel rows={rows} />);
        fireEvent.change(screen.getByTestId("fetched-bills-search"), { target: { value: "highway" } });
        expect(screen.queryByTestId("fetched-bill-row-25-0001")).toBeNull();
        expect(screen.getByTestId("fetched-bill-row-25-0002")).toBeDefined();
    });

    it("filters by freshness chip (very stale)", () => {
        const rows = [
            makeRow({ external_id: "fresh-1", fetched_at: new Date(Date.now() - 1 * DAY).toISOString() }),
            makeRow({
                external_id: "stale-1",
                bill_id: 2,
                fetched_at: new Date(Date.now() - 14 * DAY).toISOString(),
            }),
            makeRow({
                external_id: "very-stale-1",
                bill_id: 3,
                fetched_at: new Date(Date.now() - 90 * DAY).toISOString(),
            }),
        ];
        render(<FetchedBillsPanel rows={rows} />);
        fireEvent.click(screen.getByTestId("fetched-bills-filter-danger"));
        expect(screen.queryByTestId("fetched-bill-row-fresh-1")).toBeNull();
        expect(screen.queryByTestId("fetched-bill-row-stale-1")).toBeNull();
        expect(screen.getByTestId("fetched-bill-row-very-stale-1")).toBeDefined();
        expect(screen.getByTestId("fetched-bills-count").textContent).toBe("1 of 3 bills");
    });

    it("composes search AND filter", () => {
        const rows = [
            makeRow({
                external_id: "25-0001",
                title: "Education",
                fetched_at: new Date(Date.now() - 1 * DAY).toISOString(),
            }),
            makeRow({
                external_id: "25-0002",
                bill_id: 2,
                title: "Education Renewal",
                fetched_at: new Date(Date.now() - 90 * DAY).toISOString(),
            }),
            makeRow({
                external_id: "25-0003",
                bill_id: 3,
                title: "Highway",
                fetched_at: new Date(Date.now() - 90 * DAY).toISOString(),
            }),
        ];
        render(<FetchedBillsPanel rows={rows} />);
        fireEvent.change(screen.getByTestId("fetched-bills-search"), { target: { value: "education" } });
        fireEvent.click(screen.getByTestId("fetched-bills-filter-danger"));
        expect(screen.queryByTestId("fetched-bill-row-25-0001")).toBeNull();
        expect(screen.getByTestId("fetched-bill-row-25-0002")).toBeDefined();
        expect(screen.queryByTestId("fetched-bill-row-25-0003")).toBeNull();
    });

    it("renders empty-filtered state with a clear button that restores", () => {
        const rows = [makeRow({ external_id: "25-0001", title: "Alpha" })];
        render(<FetchedBillsPanel rows={rows} />);
        fireEvent.change(screen.getByTestId("fetched-bills-search"), { target: { value: "nope" } });
        const empty = screen.getByTestId("fetched-bills-empty-filtered");
        expect(within(empty).getByText("No bills match.")).toBeDefined();
        fireEvent.click(screen.getByTestId("fetched-bills-clear"));
        expect(screen.getByTestId("fetched-bill-row-25-0001")).toBeDefined();
        expect((screen.getByTestId("fetched-bills-search") as HTMLInputElement).value).toBe("");
    });

    it("marks the active freshness chip via aria-pressed", () => {
        render(<FetchedBillsPanel rows={[makeRow()]} />);
        expect(screen.getByTestId("fetched-bills-filter-all").getAttribute("aria-pressed")).toBe("true");
        fireEvent.click(screen.getByTestId("fetched-bills-filter-success"));
        expect(screen.getByTestId("fetched-bills-filter-success").getAttribute("aria-pressed")).toBe("true");
        expect(screen.getByTestId("fetched-bills-filter-all").getAttribute("aria-pressed")).toBe("false");
    });
});
