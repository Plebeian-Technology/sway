// RunSelector pins one saved pipeline run via ?run_id= in the URL, so the pipeline tab shows that
// run instead of whatever the page would pick on its own.

import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The only outside thing RunSelector calls is router.get. Faking it means the
// tests need no real Inertia router, and lets them check what it was called with.
const routerGet = vi.fn<(...args: unknown[]) => void>();
vi.mock("@inertiajs/react", () => ({
    router: { get: (...args: unknown[]) => routerGet(...args) },
}));

import RunSelector from "app/frontend/components/admin/creator/RunSelector";
import { formatDateTime } from "app/frontend/sway_utils/datetimes";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";
import type { IRecentPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

function makeRun(overrides: Partial<IRecentPipelineRun> = {}): IRecentPipelineRun {
    return {
        id: 1,
        status: "succeeded",
        kind: "all_bills",
        bill_external_id: null,
        created_at: "2026-06-03T12:00:00Z",
        completed_at: null,
        ...overrides,
    };
}

const getSelect = () => screen.getByTestId("run-selector") as HTMLSelectElement;

const NOW = new Date("2026-08-19T15:26:14.000Z");
const TWELVE_MINUTES_AGO = "2026-08-19T15:14:14.000Z"; // 12 minutes before NOW
const CREATED_AT = "2026-06-03T12:00:00Z";
const EXPECTED_CREATED_WHEN = formatDateTime(CREATED_AT);

afterEach(() => {
    vi.useRealTimers();
    cleanup();
});

// Only the relative-age examples need a fixed clock; mocked timers hang RTL helpers
// and Radix animation callbacks, so the rest of the file runs on the real one.
const freezeClock = (): void => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
};

beforeEach(() => {
    routerGet.mockClear();
    // Start each test on a plain URL with NO ?run_id=, so "follow the latest
    // run" is the starting point. Tests about a pinned run set their own URL.
    window.history.pushState({}, "", "/admin/bills/new");
});

describe("RunSelector", () => {
    it("renders nothing when there are no runs", () => {
        const { container } = render(<RunSelector runs={[]} currentRunId={null} />);
        expect(container.firstChild).toBeNull();
        expect(screen.queryByTestId("run-selector")).toBeNull();
    });

    it("renders one option per run plus the auto-latest sentinel", () => {
        const runs = [makeRun({ id: 8 }), makeRun({ id: 5, status: "failed" })];
        render(<RunSelector runs={runs} currentRunId={8} />);

        const select = getSelect();
        expect(select.options).toHaveLength(3);
        expect(select.options[0].value).toBe("");
        expect(select.options[0].textContent).toContain("Latest run (auto)");
        expect(select.options[1].value).toBe("8");
        expect(select.options[2].value).toBe("5");
    });

    it("keeps the auto-latest sentinel selected when no run_id is pinned, even if currentRunId is the newest", () => {
        // currentRunId is the newest run, but the URL has no ?run_id=, so the
        // page is still FOLLOWING the latest run. "Latest run (auto)" has to
        // stay selected.
        render(<RunSelector runs={[makeRun({ id: 8 }), makeRun({ id: 5 })]} currentRunId={8} />);
        expect(getSelect().value).toBe("");
    });

    it("selects the pinned run when ?run_id= is present in the URL", () => {
        window.history.pushState({}, "", "/admin/bills/new?run_id=5");
        render(<RunSelector runs={[makeRun({ id: 8 }), makeRun({ id: 5 })]} currentRunId={5} />);
        expect(getSelect().value).toBe("5");
    });

    it("pins ?run_id= via router.get with the partial-reload tuple when a run is chosen", () => {
        render(<RunSelector runs={[makeRun({ id: 8 }), makeRun({ id: 5 })]} currentRunId={8} />);

        fireEvent.change(getSelect(), { target: { value: "5" } });

        expect(routerGet).toHaveBeenCalledTimes(1);
        const [url, data, options] = routerGet.mock.calls[0] as [
            string,
            unknown,
            { only: string[]; preserveScroll: boolean; preserveState: boolean },
        ];
        expect(url).toBe("/admin/bills/new?run_id=5");
        expect(data).toBeUndefined();
        // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props]]
        expect(options.only).toEqual([
            "legislation_pipeline_run",
            "active_legislation_pipeline_run",
            "recent_pipeline_runs",
            "stale_pipeline_run_count",
            "orphan_pipeline_run_count",
        ]);
        expect(options.preserveScroll).toBe(true);
        expect(options.preserveState).toBe(true);
    });

    it("clears ?run_id= with the cleared signal when the auto-latest sentinel is chosen", () => {
        window.history.pushState({}, "", "/admin/bills/new?run_id=5");
        render(<RunSelector runs={[makeRun({ id: 8 }), makeRun({ id: 5 })]} currentRunId={5} />);

        fireEvent.change(getSelect(), { target: { value: "" } });

        expect(routerGet).toHaveBeenCalledTimes(1);
        const calledUrl = routerGet.mock.calls[0][0] as string;
        expect(calledUrl).toBe("/admin/bills/new?run_id=");
        expect(isQueryParamCleared(new URL(calledUrl, "https://sway.test").searchParams, "run_id")).toBe(true);
        expect(stripClearedQueryParams(calledUrl)).toBe("/admin/bills/new");
    });

    it("labels a single-bill run with its external id and a global run as 'all bills'", () => {
        const runs = [
            makeRun({ id: 8, kind: "all_bills", status: "succeeded" }),
            makeRun({ id: 7, kind: "single", bill_external_id: "HB1234", status: "failed" }),
        ];
        render(<RunSelector runs={runs} currentRunId={8} />);

        const labels = Array.from(getSelect().options).map((o) => o.textContent ?? "");
        expect(labels.some((t) => t.includes("Run #8") && t.includes("all bills") && t.includes("succeeded"))).toBe(
            true,
        );
        expect(labels.some((t) => t.includes("Run #7") && t.includes("HB1234") && t.includes("failed"))).toBe(true);
    });

    it("appends the failure age to the status word for a failed run with a terminal timestamp", () => {
        freezeClock();
        const runs = [
            makeRun({
                id: 12,
                status: "failed",
                kind: "single",
                bill_external_id: "HB0123",
                created_at: CREATED_AT,
                completed_at: TWELVE_MINUTES_AGO,
            }),
        ];
        render(<RunSelector runs={runs} currentRunId={12} />);
        expect(getSelect().options[1].textContent).toBe(
            `Run #12 · ✗ failed 12m ago · HB0123 · ${EXPECTED_CREATED_WHEN}`,
        );
    });

    it("renders a failed run with no terminal timestamp exactly as it did before this change", () => {
        const runs = [
            makeRun({
                id: 12,
                status: "failed",
                kind: "single",
                bill_external_id: "HB0123",
                created_at: CREATED_AT,
                completed_at: null,
            }),
        ];
        render(<RunSelector runs={runs} currentRunId={12} />);
        expect(getSelect().options[1].textContent).toBe(`Run #12 · ✗ failed · HB0123 · ${EXPECTED_CREATED_WHEN}`);
    });

    it("renders a failed run with an unreadable terminal timestamp exactly as it did before this change", () => {
        const runs = [
            makeRun({
                id: 12,
                status: "failed",
                kind: "single",
                bill_external_id: "HB0123",
                created_at: CREATED_AT,
                completed_at: "not-a-date",
            }),
        ];
        render(<RunSelector runs={runs} currentRunId={12} />);
        expect(getSelect().options[1].textContent).toBe(`Run #12 · ✗ failed · HB0123 · ${EXPECTED_CREATED_WHEN}`);
    });

    it("leaves a succeeded run's label unaffected by the presence of a terminal timestamp", () => {
        const runs = [
            makeRun({
                id: 8,
                status: "succeeded",
                kind: "all_bills",
                created_at: CREATED_AT,
                completed_at: TWELVE_MINUTES_AGO,
            }),
        ];
        render(<RunSelector runs={runs} currentRunId={8} />);
        expect(getSelect().options[1].textContent).toBe(`Run #8 · ✓ succeeded · all bills · ${EXPECTED_CREATED_WHEN}`);
    });

    it("keeps the scope word and creation-time suffix unchanged on a failed all_bills run that gains the age", () => {
        freezeClock();
        const runs = [
            makeRun({
                id: 20,
                status: "failed",
                kind: "all_bills",
                created_at: CREATED_AT,
                completed_at: TWELVE_MINUTES_AGO,
            }),
        ];
        render(<RunSelector runs={runs} currentRunId={20} />);
        expect(getSelect().options[1].textContent).toBe(
            `Run #20 · ✗ failed 12m ago · all bills · ${EXPECTED_CREATED_WHEN}`,
        );
    });
});
