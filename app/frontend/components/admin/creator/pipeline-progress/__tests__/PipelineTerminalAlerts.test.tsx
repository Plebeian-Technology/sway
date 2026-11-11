import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

vi.mock("app/frontend/components/ui/alert", () => ({
    Alert: ({ children, ...props }: React.HTMLAttributes<HTMLDivElement>) => <div {...props}>{children}</div>,
    AlertTitle: ({ children }: { children: React.ReactNode }) => <strong>{children}</strong>,
    AlertDescription: ({ children }: { children: React.ReactNode }) => <p>{children}</p>,
}));

vi.mock("app/frontend/components/ui/badge", () => ({
    Badge: ({ children, ...props }: React.HTMLAttributes<HTMLSpanElement>) => <span {...props}>{children}</span>,
}));

import PipelineTerminalAlerts from "app/frontend/components/admin/creator/pipeline-progress/PipelineTerminalAlerts";

const run = (overrides: Partial<ILegislationPipelineRun> = {}): ILegislationPipelineRun =>
    ({
        id: 1,
        remote_run_id: null,
        status: "completed",
        processed: 0,
        total: 0,
        current_bill_external_id: null,
        phase: null,
        eta_seconds: null,
        errors: [],
        queued: [],
        bills_updated: 0,
        error_message: null,
        current_stage: null,
        bill_id: null,
        bill_external_id: null,
        refresh: null,
        started_at: null,
        completed_at: null,
        kind: "single",
        parent_run_id: null,
        origin: "fresh",
        ...overrides,
    }) as ILegislationPipelineRun;

const renderAlerts = (props: Partial<React.ComponentProps<typeof PipelineTerminalAlerts>> = {}) =>
    render(<PipelineTerminalAlerts run={run()} processed={0} total={0} phase={null} pickedBillId="" {...props} />);

const NOW = new Date("2026-08-19T15:26:14.000Z");
const TWELVE_MINUTES_AGO = "2026-08-19T15:14:14.000Z"; // 12 minutes before NOW

const EXPECTED_EXACT_TIME = (() => {
    const d = new Date(TWELVE_MINUTES_AGO);
    const datePart = d.toLocaleDateString("en-US", { month: "long", day: "2-digit", year: "numeric" });
    const timePart = d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit", hour12: true });
    return `${datePart} at ${timePart}`;
})();

// Only the relative-age example needs a fixed clock; mocked timers hang RTL helpers
// and Radix animation callbacks, so the rest of the file runs on the real one.
const freezeClock = (): void => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
};

afterEach(() => {
    vi.useRealTimers();
    cleanup();
});

describe("PipelineTerminalAlerts", () => {
    it("renders the success alert with the updated-bill count when completed", () => {
        renderAlerts({ run: run({ status: "completed", bills_updated: 3 }) });
        expect(screen.getByTestId("pipeline-success-alert")).toHaveTextContent("3 bill(s) updated.");
    });

    it("renders the succeeded alert", () => {
        renderAlerts({ run: run({ status: "succeeded" }) });
        expect(screen.getByTestId("pipeline-succeeded-alert")).toBeInTheDocument();
    });

    it("renders the partial alert", () => {
        renderAlerts({ run: run({ status: "partial" }) });
        expect(screen.getByTestId("pipeline-partial-alert")).toBeInTheDocument();
    });

    it("renders the failed alert with the error message and a phase label", () => {
        renderAlerts({ run: run({ status: "failed", error_message: "OCR timeout" }), phase: "extracting" });
        const alert = screen.getByTestId("pipeline-error-alert");
        expect(alert).toHaveTextContent("Extracting text");
        expect(alert).toHaveTextContent("OCR timeout");
        // @lat: [[pipeline-terminal-alert-remedy-wording#Why the remedy names Resume/Restart only on a failed single-bill run]]
        expect(alert.textContent ?? "").not.toMatch(/solid queue|job logs/i);
    });

    // @lat: [[pipeline-terminal-alert-remedy-wording#Why the remedy names Resume/Restart only on a failed single-bill run]]
    it("names Resume and Restart on a failed single-bill run, which has both", () => {
        renderAlerts({ run: run({ status: "failed", kind: "single", error_message: "OCR timeout" }) });

        const alert = screen.getByTestId("pipeline-error-alert");
        expect(alert).toHaveTextContent(/resume/i);
        expect(alert).toHaveTextContent(/restart/i);
    });

    // @lat: [[pipeline-terminal-alert-remedy-wording#Why the remedy names Resume/Restart only on a failed single-bill run]]
    it("names the stage picker on a failed all-bills run, which has no Resume", () => {
        renderAlerts({ run: run({ status: "failed", kind: "all_bills", error_message: "OCR timeout" }) });

        const alert = screen.getByTestId("pipeline-error-alert");
        expect(alert).not.toHaveTextContent(/resume/i);
        expect(alert).not.toHaveTextContent(/restart/i);
        expect(alert).toHaveTextContent(/run pipeline/i);
        expect(alert).toHaveTextContent(/every bill/i);
    });

    // @lat: [[pipeline-terminal-alert-remedy-wording#Why the remedy no longer says the button retries the whole run]]
    it("says Run pipeline covers one bill when the picker holds one, on a failed all-bills run", () => {
        renderAlerts({
            run: run({ status: "failed", kind: "all_bills", error_message: "OCR timeout" }),
            pickedBillId: "42",
        });

        const alert = screen.getByTestId("pipeline-error-alert");
        expect(alert).toHaveTextContent(/run pipeline starts a run for that bill alone/i);
        expect(alert.textContent ?? "").not.toMatch(/try it again/i);
        expect(alert.textContent ?? "").not.toMatch(/every bill/i);
    });

    it("says Run pipeline covers every bill when the picker is on All Bills", () => {
        renderAlerts({
            run: run({ status: "failed", kind: null, error_message: "OCR timeout" }),
            pickedBillId: "",
        });

        const alert = screen.getByTestId("pipeline-error-alert");
        expect(alert).toHaveTextContent(/run pipeline, which starts a run over every bill/i);
        expect(alert.textContent ?? "").not.toMatch(/try it again/i);
    });

    it("renders the cancelled alert with the processed/total counts", () => {
        renderAlerts({ run: run({ status: "cancelled", completed_at: "2026-05-21" }), processed: 2, total: 5 });
        const alert = screen.getByTestId("pipeline-cancelled-alert");
        expect(alert).toHaveTextContent("2");
        expect(alert).toHaveTextContent("5");
    });

    it("renders succeeded/failed stage chips for a single-bill failed run", () => {
        renderAlerts({
            run: run({
                status: "failed",
                kind: "single",
                pipeline_run_stages: [
                    { stage_name: "fetch-bills", status: "succeeded", position: 1 },
                    { stage_name: "extract-text", status: "failed", position: 2 },
                ],
            }),
        });
        const list = screen.getByTestId("pipeline-cached-stages");
        expect(within(list).getByText("succeeded")).toBeInTheDocument();
        expect(within(list).getByText("failed")).toBeInTheDocument();
        expect(within(list).getByText("fetch-bills")).toBeInTheDocument();
    });

    it("omits the stage chips for an all_bills failed run", () => {
        renderAlerts({
            run: run({
                status: "failed",
                kind: "all_bills",
                pipeline_run_stages: [{ stage_name: "fetch-bills", status: "succeeded", position: 1 }],
            }),
        });
        expect(screen.queryByTestId("pipeline-cached-stages")).not.toBeInTheDocument();
    });

    it("renders the failure timing line for a failed run with a terminal timestamp", () => {
        freezeClock();
        renderAlerts({
            run: run({ status: "failed", error_message: "OCR timeout", completed_at: TWELVE_MINUTES_AGO }),
        });
        const timing = screen.getByTestId("pipeline-failure-timing");
        expect(timing).toHaveTextContent(`Failed 12m ago — ${EXPECTED_EXACT_TIME}`);
    });

    it("gives the failure timing line the small text size and tabular numerals", () => {
        renderAlerts({
            run: run({ status: "failed", error_message: "OCR timeout", completed_at: TWELVE_MINUTES_AGO }),
        });
        const timing = screen.getByTestId("pipeline-failure-timing");
        expect(timing.className).toContain("text-sm");
        expect(timing.className).toContain("tabular-nums");
        expect(timing.className).toContain("lining-nums");
    });

    it("omits the failure timing line for a failed run with no terminal timestamp", () => {
        renderAlerts({ run: run({ status: "failed", error_message: "OCR timeout", completed_at: null }) });
        expect(screen.queryByTestId("pipeline-failure-timing")).not.toBeInTheDocument();
    });

    it("omits the failure timing line for a failed run with an unreadable terminal timestamp", () => {
        renderAlerts({ run: run({ status: "failed", error_message: "OCR timeout", completed_at: "not-a-date" }) });
        expect(screen.queryByTestId("pipeline-failure-timing")).not.toBeInTheDocument();
    });

    it("renders the failed stage's exact finish time", () => {
        renderAlerts({
            run: run({
                status: "failed",
                kind: "single",
                pipeline_run_stages: [
                    { stage_name: "fetch-bills", status: "succeeded", position: 1 },
                    { stage_name: "extract-text", status: "failed", position: 2, finished_at: TWELVE_MINUTES_AGO },
                ],
            }),
        });
        const rows = within(screen.getByTestId("pipeline-cached-stages")).getAllByRole("listitem");
        const failedRow = rows.find((row) => row.textContent?.includes("extract-text"));
        expect(failedRow).toBeDefined();
        const timestamp = within(failedRow as HTMLElement).getByTestId("pipeline-stage-finished-at");
        expect(timestamp).toHaveTextContent(EXPECTED_EXACT_TIME);
        expect(timestamp.className).toContain("text-xs");
        expect(timestamp.className).toContain("text-muted-foreground");
        expect(timestamp.className).toContain("tabular-nums");
        expect(timestamp.className).toContain("lining-nums");
    });

    it("omits the stage timestamp when finished_at is null, leaving the name and badge unchanged", () => {
        renderAlerts({
            run: run({
                status: "failed",
                kind: "single",
                pipeline_run_stages: [{ stage_name: "extract-text", status: "failed", position: 2, finished_at: null }],
            }),
        });
        const list = screen.getByTestId("pipeline-cached-stages");
        expect(within(list).getByText("extract-text")).toBeInTheDocument();
        expect(within(list).getByText("failed")).toBeInTheDocument();
        expect(within(list).queryByTestId("pipeline-stage-finished-at")).not.toBeInTheDocument();
    });

    it("does not render a timestamp for a stage that did not fail", () => {
        renderAlerts({
            run: run({
                status: "failed",
                kind: "single",
                pipeline_run_stages: [
                    { stage_name: "fetch-bills", status: "succeeded", position: 1, finished_at: TWELVE_MINUTES_AGO },
                ],
            }),
        });
        expect(screen.queryByTestId("pipeline-stage-finished-at")).not.toBeInTheDocument();
    });

    it("renders the cancelled clause with the formatted exact time rather than the stored value", () => {
        renderAlerts({ run: run({ status: "cancelled", completed_at: TWELVE_MINUTES_AGO }), processed: 2, total: 5 });
        const alert = screen.getByTestId("pipeline-cancelled-alert");
        expect(alert).toHaveTextContent(`Cancelled at ${EXPECTED_EXACT_TIME}`);
    });

    it("omits the whole cancelled-at clause when completed_at is null, while the processed sentence still renders", () => {
        renderAlerts({ run: run({ status: "cancelled", completed_at: null }), processed: 2, total: 5 });
        const alert = screen.getByTestId("pipeline-cancelled-alert");
        expect(alert.textContent ?? "").not.toMatch(/cancelled at/i);
        expect(alert).toHaveTextContent("2");
        expect(alert).toHaveTextContent("5");
        expect(alert).toHaveTextContent("bills processed before cancel");
    });
});
