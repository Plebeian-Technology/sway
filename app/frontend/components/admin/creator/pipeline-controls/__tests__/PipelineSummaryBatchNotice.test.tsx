import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import PipelineSummaryBatchNotice from "../PipelineSummaryBatchNotice";
import type { ISummaryBatchProgress } from "../types";
import { formatDateTime } from "app/frontend/sway_utils/datetimes";

afterEach(cleanup);

const TWELVE_MINUTES_MS = 12 * 60 * 1000;

const progress = (overrides: Partial<ISummaryBatchProgress> = {}): ISummaryBatchProgress => ({
    awaiting: true,
    batches_total: 4,
    batches_ingested: 1,
    items_total: 400,
    items_succeeded: 98,
    items_failed: 2,
    first_submitted_at: new Date(Date.now() - TWELVE_MINUTES_MS).toISOString(),
    expires_at: "2026-09-05T14:30:00Z",
    ...overrides,
});

const notice = () => screen.queryByTestId("pipeline-summary-batch-notice");

// @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
describe("PipelineSummaryBatchNotice", () => {
    it("renders nothing when the run carries no summary batch data", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={undefined} />);
        expect(notice()).toBeNull();

        cleanup();

        render(<PipelineSummaryBatchNotice summaryBatch={null} />);
        expect(notice()).toBeNull();
    });

    it("renders nothing once the run is no longer awaiting its batches", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress({ awaiting: false })} />);
        expect(notice()).toBeNull();
    });

    it("names the chunks read back out of the chunks submitted", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress()} />);

        expect(notice()!.textContent).toMatch(/Chunks read back:\s*1 of 4/);
    });

    it("names the items returned, split into succeeded and failed, out of the total submitted", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress()} />);

        expect(notice()!.textContent).toMatch(/Items returned:\s*100 of 400 submitted/);
        expect(notice()!.textContent).toMatch(/98 succeeded, 2 failed/);
    });

    it("says nothing is stuck, and says why a chunk is the smallest step", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress()} />);

        expect(notice()!.textContent).toMatch(/Nothing is stuck/i);
        expect(notice()!.textContent).toMatch(/one chunk at a time/i);
    });

    it("reports how long it has been since the first submission", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress()} />);

        expect(notice()!.textContent).toMatch(/First submitted 12m ago/);
    });

    it("omits the elapsed line when nothing has been submitted yet", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress({ first_submitted_at: null })} />);

        expect(notice()!.textContent).not.toMatch(/First submitted/);
    });

    it("shows the 24-hour expiry as the only deadline", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress()} />);

        expect(notice()!.textContent).toMatch(/hard 24-hour expiry/);
        expect(notice()!.textContent).toContain(formatDateTime("2026-09-05T14:30:00Z"));
    });

    it("predicts no finish time and shows no progress finer than a chunk", () => {
        render(<PipelineSummaryBatchNotice summaryBatch={progress()} />);
        const text = notice()!.textContent ?? "";

        expect(text).toMatch(/No completion estimate is available/);
        expect(text).not.toMatch(/\bETA\b/i);
        expect(text).not.toMatch(/remaining/i);
        expect(text).not.toMatch(/%/);
        expect(text).not.toMatch(/finish(es|ed)? (by|at|around)/i);
        expect(notice()!.querySelector("progress")).toBeNull();
        expect(notice()!.querySelector('[role="progressbar"]')).toBeNull();
    });
});
