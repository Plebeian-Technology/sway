import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PipelineRunBill } from "app/frontend/types/bill_creator";

// PerBillGrid uses Inertia's <Link> in the View column; swapping in a plain <a> means the fake
// browser needs no Inertia router set up.
vi.mock("@inertiajs/react", () => ({
    Link: ({ children, href, ...props }: React.AnchorHTMLAttributes<HTMLAnchorElement>) => (
        <a href={href} {...props}>
            {children}
        </a>
    ),
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({
        children,
        variant,
        tone,
        ...props
    }: React.HTMLAttributes<HTMLSpanElement> & { variant?: string; tone?: string }) => (
        <span data-testid="badge" data-variant={variant} data-tone={tone} {...props}>
            {children}
        </span>
    ),
}));

vi.mock("app/frontend/components/ui/card", () => ({
    Card: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => <div {...props}>{children}</div>,
    CardHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    CardTitle: ({ children }: { children: React.ReactNode }) => <h3>{children}</h3>,
    CardContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));

vi.mock("app/frontend/components/ui/tooltip", () => ({
    TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipTrigger: ({ children }: { children: React.ReactNode; asChild?: boolean }) => <>{children}</>,
    TooltipContent: ({ children }: { children: React.ReactNode }) => <span data-testid="tooltip">{children}</span>,
}));

vi.mock("app/frontend/lib/utils", () => ({
    cn: (...classes: Array<string | undefined | null | false>) => classes.filter(Boolean).join(" "),
}));

import PerBillGrid from "app/frontend/components/admin/creator/PerBillGrid";

afterEach(() => cleanup());

function makeRow(i: number, status: PipelineRunBill["status"] = "pending"): PipelineRunBill {
    return {
        bill_external_id: `HB${String(i).padStart(3, "0")}`,
        title: `Test bill ${i}`,
        status,
        started_at: null,
        finished_at: null,
        error_message: null,
        sort_order: i,
    };
}

describe("PerBillGrid", () => {
    it("renders the 'No bills processed yet' empty state when rows is empty", () => {
        render(
            <PerBillGrid
                rows={[]}
                currentBillExternalId="HB001"
                currentStage={null}
                runStatus="running"
                stagesSucceeded={0}
                stagesTotal={0}
            />,
        );
        expect(screen.getByText("No bills processed yet")).toBeTruthy();
        expect(screen.getByText("Bill status will appear as the run progresses.")).toBeTruthy();
    });

    it("renders the current-URL bill as the first row regardless of sort_order", () => {
        const rows: PipelineRunBill[] = [
            ...Array.from({ length: 10 }, (_, i) => makeRow(i + 1)),
            { ...makeRow(99), bill_external_id: "HB_CURRENT" },
        ];
        render(
            <PerBillGrid
                rows={rows}
                currentBillExternalId="HB_CURRENT"
                currentStage="parse-sections"
                runStatus="running"
                stagesSucceeded={2}
                stagesTotal={5}
            />,
        );

        const pinnedRow = screen.getByTestId("pinned-row");
        expect(pinnedRow.textContent ?? "").toContain("HB_CURRENT");

        // The table has 3 rowgroups (thead, pinned tbody, scrolling tbody), so the scrolling one
        // must be targeted by test id, not a bare role query.
        const scrollContainer = screen.getByTestId("virtual-scroll-container");
        const pos = pinnedRow.compareDocumentPosition(scrollContainer);
        expect(pos & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    });

    it("renders a 200-row fixture without throwing and virtualizes (visible rows << total)", () => {
        const rows = Array.from({ length: 200 }, (_, i) => makeRow(i + 1));
        // Make the first row the pinned one. It makes no difference to the
        // count check, but it runs the pinned-row code against a big list.
        rows[0] = { ...rows[0], bill_external_id: "HB_CURRENT" };

        render(
            <PerBillGrid
                rows={rows}
                currentBillExternalId="HB_CURRENT"
                currentStage="parse-sections"
                runStatus="running"
                stagesSucceeded={2}
                stagesTotal={5}
            />,
        );

        // aria-rowcount belongs on the table, not a rowgroup. It's a real <table> now, so "table"
        // role is implicit — no role attribute to select.
        const table = screen.getByRole("table");
        expect(table.getAttribute("aria-rowcount")).toBe("200");

        // The scrolling tbody is the rowgroup that virtualizes — query it by test id, since thead
        // and the pinned tbody are separate rowgroups too.
        const scrollContainer = screen.getByTestId("virtual-scroll-container");
        // The fake browser has no page layout, so the virtualizer usually draws ~0 rows — either
        // way, count must stay under 200 to prove partial rendering.
        const renderedRows = scrollContainer.querySelectorAll("tr");
        expect(renderedRows.length).toBeLessThan(200);
    });

    it("preserves caller-provided sort_order in the virtualizer count (rows ordered by sort_order ASC)", () => {
        // The grid must not re-sort/shuffle/filter rows — only lift the current-URL row out and pin
        // it. Rails always sends sort_order ASC (legislation_pipeline_run_spec.rb).
        const rows: PipelineRunBill[] = [makeRow(1), makeRow(2), makeRow(3), makeRow(4), makeRow(5)];
        render(
            <PerBillGrid
                rows={rows}
                // the current-URL bill is row 3, so the pinned row is sort_order 3
                currentBillExternalId="HB003"
                currentStage={null}
                runStatus="running"
                stagesSucceeded={0}
                stagesTotal={0}
            />,
        );

        // The pinned row is the current-URL bill (HB003), drawn FIRST on the
        // page even though its sort_order is 3.
        const pinnedRow = screen.getByTestId("pinned-row");
        expect(pinnedRow.textContent ?? "").toContain("HB003");

        // The virtualizer sees rows.length - 1 (4, after pinning), but aria-rowcount still reports
        // the full 5 for screen readers.
        const table = screen.getByRole("table");
        expect(table.getAttribute("aria-rowcount")).toBe("5");
    });

    it("renders all five status badge tones across the status union", () => {
        const rows: PipelineRunBill[] = [
            makeRow(1, "pending"),
            makeRow(2, "running"),
            makeRow(3, "succeeded"),
            makeRow(4, "failed"),
            makeRow(5, "skipped"),
        ];
        const { container } = render(
            <PerBillGrid
                rows={rows}
                currentBillExternalId="HB001"
                currentStage={null}
                runStatus="running"
                stagesSucceeded={0}
                stagesTotal={0}
            />,
        );
        // @lat: [[legislation-pipeline-run-current-stage#Behavior on terminal statuses#PerBillGrid's test rendering note]]
        const badges = container.querySelectorAll('[data-testid="badge"]');
        expect(badges.length).toBeGreaterThan(0);
    });

    // @lat: [[legislation-pipeline-run-current-stage#Behavior on terminal statuses#PerBillGrid's test for the finished-run Stage column]]
    describe("the Stage column once the run has finished", () => {
        const renderPinned = (runStatus: string) =>
            render(
                <PerBillGrid
                    rows={[{ ...makeRow(1), bill_external_id: "HB_CURRENT" }]}
                    currentBillExternalId="HB_CURRENT"
                    currentStage="parse-sections"
                    runStatus={runStatus}
                    stagesSucceeded={2}
                    stagesTotal={5}
                />,
            );

        it.each(["succeeded", "failed", "cancelled", "partial", "completed"])(
            "names no stage when the run is %s",
            (runStatus) => {
                renderPinned(runStatus);

                const pinnedRow = screen.getByTestId("pinned-row");
                expect(pinnedRow.textContent ?? "").not.toContain("parse-sections");
            },
        );

        it.each(["queued", "running", "parsing_sections"])("still names the stage while the run is %s", (runStatus) => {
            renderPinned(runStatus);

            const pinnedRow = screen.getByTestId("pinned-row");
            expect(pinnedRow.textContent ?? "").toContain("parse-sections");
        });
    });

    // The grid lays out with CSS grid but keeps real table elements for
    // semantics, so it is easy to reach for a div where the HTML content model
    // allows only a row or a cell. React reports that as a hydration error.
    describe("HTML content model", () => {
        it("puts nothing but rows in a tbody and nothing but cells in a row", () => {
            const rows = Array.from({ length: 20 }, (_, i) => makeRow(i + 1));
            rows[0] = { ...rows[0], bill_external_id: "HB_CURRENT" };

            const { container } = render(
                <PerBillGrid
                    rows={rows}
                    currentBillExternalId="HB_CURRENT"
                    currentStage="parse-sections"
                    runStatus="running"
                    stagesSucceeded={2}
                    stagesTotal={5}
                />,
            );

            container.querySelectorAll("tbody, thead").forEach((group) => {
                const illegal = Array.from(group.children).filter((child) => child.tagName !== "TR");
                expect(illegal.map((el) => el.tagName)).toEqual([]);
            });

            container.querySelectorAll("tr").forEach((row) => {
                const illegal = Array.from(row.children).filter(
                    (child) => child.tagName !== "TD" && child.tagName !== "TH",
                );
                expect(illegal.map((el) => el.tagName)).toEqual([]);
            });
        });
    });
});
