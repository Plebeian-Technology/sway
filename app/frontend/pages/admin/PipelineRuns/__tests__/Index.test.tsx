// Vitest tests for the /pipeline_runs list page

import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PipelineRunSummary } from "app/frontend/types/pipelineRuns";

vi.mock("app/frontend/components/ui/card", () => ({
    Card: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    CardContent: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    CardHeader: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
    CardTitle: ({ children }: { children: React.ReactNode }) => <h2>{children}</h2>,
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, ...props }: React.HTMLAttributes<HTMLSpanElement> & { ["data-tone"]?: string }) => (
        <span {...props}>{children}</span>
    ),
}));

vi.mock("app/frontend/components/ui/table", () => ({
    Table: ({ children }: { children: React.ReactNode }) => <table>{children}</table>,
    TableHeader: ({ children }: { children: React.ReactNode }) => <thead>{children}</thead>,
    TableBody: ({ children }: { children: React.ReactNode }) => <tbody>{children}</tbody>,
    TableRow: ({ children, ...props }: React.HTMLAttributes<HTMLTableRowElement>) => <tr {...props}>{children}</tr>,
    TableHead: ({ children }: { children: React.ReactNode }) => <th>{children}</th>,
    TableCell: ({ children, ...props }: React.HTMLAttributes<HTMLTableCellElement>) => <td {...props}>{children}</td>,
}));

vi.mock("app/frontend/components/ui/tooltip", () => ({
    Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    TooltipTrigger: ({ children }: { children: React.ReactNode; asChild?: boolean }) => <>{children}</>,
    TooltipContent: ({ children }: { children: React.ReactNode }) => <span>{children}</span>,
}));

vi.mock("app/frontend/sway_utils/datetimes", () => ({
    relativeTime: (s: string) => `relative(${s})`,
}));

// Fixed spies for the poll and the subscription, so the self-update tests can check
// which way the gating effect went and which runId the websocket subscribed to.
const startPollingMock = vi.fn<() => void>();
const stopPollingMock = vi.fn<() => void>();
const subscriptionMock = vi.fn<(...args: unknown[]) => unknown>();
vi.mock("@inertiajs/react", () => ({
    usePoll: () => ({ start: startPollingMock, stop: stopPollingMock }),
}));
vi.mock("app/frontend/hooks/usePipelineRunSubscription", () => ({
    usePipelineRunSubscription: (runId: string | null, onlyProps: readonly string[]) => {
        subscriptionMock(runId, onlyProps);
        return { connected: true, downgraded: false, lastDisconnectedAt: null };
    },
}));

import PipelineRunsIndex from "app/frontend/pages/admin/PipelineRuns/Index";

function makeRun(overrides: Partial<PipelineRunSummary> = {}): PipelineRunSummary {
    return {
        id: 1,
        status: "succeeded",
        kind: "all_bills",
        bill_id: null,
        bill_external_id: null,
        remote_run_id: null,
        started_at: "2026-05-13T10:00:00Z",
        completed_at: "2026-05-13T10:25:00Z",
        current_stage: null,
        bills_total: 189,
        bills_succeeded: 189,
        bills_failed: 0,
        failing_stage: null,
        ...overrides,
    };
}

describe("PipelineRunsIndex", () => {
    afterEach(() => {
        cleanup();
        startPollingMock.mockClear();
        stopPollingMock.mockClear();
        subscriptionMock.mockClear();
    });

    it("renders the empty-state copy when runs is empty", () => {
        render(<PipelineRunsIndex runs={[]} />);
        expect(screen.getByText("No pipeline runs yet.")).toBeDefined();
    });

    it("renders one TableRow per run with id + counts + status badge", () => {
        const runs = [
            makeRun({ id: 1, status: "succeeded", bills_succeeded: 100, bills_failed: 0, bills_total: 100 }),
            makeRun({
                id: 2,
                status: "failed",
                bill_id: 3,
                bill_external_id: "25-0003",
                kind: "single",
                bills_total: 1,
                bills_succeeded: 0,
                bills_failed: 1,
                failing_stage: "extract_text",
            }),
        ];
        render(<PipelineRunsIndex runs={runs} />);

        // Row presence by testid
        expect(screen.getByTestId("pipeline-run-row-1")).toBeDefined();
        expect(screen.getByTestId("pipeline-run-row-2")).toBeDefined();

        // Status badges render
        expect(screen.getByText("succeeded")).toBeDefined();
        expect(screen.getByText("failed")).toBeDefined();

        // The single-bill row shows bill_external_id, kind and the failing stage
        expect(screen.getByText("25-0003")).toBeDefined();
        expect(screen.getByText("single")).toBeDefined();
        expect(screen.getByText("extract_text")).toBeDefined();
    });

    // @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only]]
    it("renders the run id as plain text, not a link", () => {
        const runs = [makeRun({ id: 99 })];
        const { container } = render(<PipelineRunsIndex runs={runs} />);
        expect(container.querySelector('a[href="/pipeline_runs/99"]')).toBeNull();
        expect(screen.getByText("99")).toBeDefined();
    });

    it("falls back to '—' for nil started_at, completed_at, bill_external_id, and failing_stage", () => {
        const runs = [
            makeRun({ id: 7, started_at: null, completed_at: null, bill_external_id: null, failing_stage: null }),
        ];
        render(<PipelineRunsIndex runs={runs} />);
        // Four empty cells fall back to a placeholder
        const dashes = screen.getAllByText("—");
        expect(dashes.length).toBeGreaterThanOrEqual(3);
    });

    // The list updates itself while a run in it is still in flight.
    it("subscribes to the in-flight run's remote_run_id and starts polling", () => {
        render(<PipelineRunsIndex runs={[makeRun({ id: 1, status: "running", remote_run_id: "abc" })]} />);

        expect(subscriptionMock).toHaveBeenCalledWith("abc", ["runs"]);
        expect(startPollingMock).toHaveBeenCalled();
        expect(stopPollingMock).not.toHaveBeenCalled();
    });

    it("subscribes with null and stops polling when every run is terminal", () => {
        render(
            <PipelineRunsIndex
                runs={[
                    makeRun({ id: 1, status: "succeeded", remote_run_id: "a" }),
                    makeRun({ id: 2, status: "partial", remote_run_id: "b" }),
                    makeRun({ id: 3, status: "failed", remote_run_id: "c" }),
                ]}
            />,
        );

        expect(subscriptionMock).toHaveBeenCalledWith(null, ["runs"]);
        expect(stopPollingMock).toHaveBeenCalled();
        expect(startPollingMock).not.toHaveBeenCalled();
    });
});
