import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ResourceCacheRow } from "app/frontend/types/bill_creator";

// Simple stand-ins for the shared UI pieces, so these tests run
// ResourceCachePanel's own code without pulling in shadcn's styling variables
// or the inner workings of Radix.
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
    Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipProvider: ({ children }: { children: React.ReactNode; delayDuration?: number }) => <>{children}</>,
    TooltipTrigger: ({ children }: { children: React.ReactNode; asChild?: boolean }) => <>{children}</>,
    TooltipContent: ({ children }: { children: React.ReactNode }) => <span data-testid="tooltip">{children}</span>,
}));

vi.mock("app/frontend/components/ui/table", () => ({
    Table: ({ children }: { children: React.ReactNode }) => <table>{children}</table>,
    TableHeader: ({ children }: { children: React.ReactNode }) => <thead>{children}</thead>,
    TableBody: ({ children }: { children: React.ReactNode }) => <tbody>{children}</tbody>,
    TableRow: ({ children, ...props }: React.HTMLAttributes<HTMLTableRowElement>) => <tr {...props}>{children}</tr>,
    TableHead: ({ children }: { children: React.ReactNode }) => <th>{children}</th>,
    TableCell: ({ children, ...props }: React.HTMLAttributes<HTMLTableCellElement>) => <td {...props}>{children}</td>,
}));

import ResourceCachePanel from "app/frontend/components/admin/creator/ResourceCachePanel";

afterEach(() => cleanup());

function makeMirror(overrides: Partial<ResourceCacheRow> = {}): ResourceCacheRow {
    return {
        tier: "pdf",
        last_generated_at: new Date(Date.now() - 60_000).toISOString(),
        version_id: "v1",
        stale: false,
        source_artifact_id: "art-1",
        // `path` was dropped from what the server sends; the UI never read it.
        ...overrides,
    };
}

describe("ResourceCachePanel", () => {
    it("renders 5 rows in the locked tier order even when mirrors is empty", () => {
        render(<ResourceCachePanel mirrors={[]} />);
        const rows = screen.getAllByTestId(/tier-row-/);
        expect(rows).toHaveLength(5);
        expect(rows[0]).toHaveAttribute("data-testid", "tier-row-pdf");
        expect(rows[1]).toHaveAttribute("data-testid", "tier-row-extracted_text");
        expect(rows[2]).toHaveAttribute("data-testid", "tier-row-parsed_sections");
        expect(rows[3]).toHaveAttribute("data-testid", "tier-row-diff");
        expect(rows[4]).toHaveAttribute("data-testid", "tier-row-summary");
    });

    it("renders tier labels in document order: PDF → Extracted Text → Parsed Sections → Diff → Summary", () => {
        const { container } = render(<ResourceCachePanel mirrors={[]} />);
        const text = container.textContent ?? "";
        const order = ["PDF", "Extracted Text", "Parsed Sections", "Diff", "Summary"].map((label) =>
            text.indexOf(label),
        );
        expect(order.every((i) => i >= 0)).toBe(true);
        expect(order).toEqual([...order].sort((a, b) => a - b));
    });

    it("missing tiers show 'Not cached'", () => {
        render(<ResourceCachePanel mirrors={[]} />);
        const notCached = screen.getAllByText("Not cached");
        expect(notCached.length).toBe(5);
    });

    it("stale row shows Badge stamp/warning with text 'Stale'", () => {
        render(<ResourceCachePanel mirrors={[makeMirror({ tier: "diff", stale: true, version_id: "v2" })]} />);
        const staleBadge = screen.getByText("Stale");
        expect(staleBadge).toHaveAttribute("data-variant", "stamp");
        expect(staleBadge).toHaveAttribute("data-tone", "warning");
    });

    it("fresh row shows Badge with text 'Fresh'", () => {
        render(<ResourceCachePanel mirrors={[makeMirror({ tier: "pdf", stale: false })]} />);
        expect(screen.getByText("Fresh")).toBeTruthy();
    });

    it("renders relative time for cached rows", () => {
        const tenMinutesAgo = new Date(Date.now() - 10 * 60_000).toISOString();
        render(<ResourceCachePanel mirrors={[makeMirror({ tier: "summary", last_generated_at: tenMinutesAgo })]} />);
        expect(screen.getByText(/m ago/)).toBeTruthy();
    });
});
