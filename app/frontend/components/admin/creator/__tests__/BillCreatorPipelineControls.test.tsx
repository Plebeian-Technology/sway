// Shows a red alert with data-testid=pipeline-conflict-alert when the page data has an
// errors.pipeline value; the server side of that clash lives in BillsController#run_pipeline.

import { fireEvent, render as rtlRender, screen } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

// The page data each test sets up for itself in beforeEach.
const pagePropsRef: { current: Record<string, unknown> } = { current: {} };

vi.mock("@inertiajs/react", async (importOriginal) => {
    const actual = await importOriginal<typeof import("@inertiajs/react")>();
    return {
        ...actual,
        usePage: () => ({ props: pagePropsRef.current }),
        // updatePipelineControlsState uses router.visit to record UI state in
        // the address bar.
        router: { post: vi.fn<() => void>(), reload: vi.fn<() => void>(), visit: vi.fn<() => void>() },
    };
});

// usePipelineRunSubscription opens a WebSocket, so it's replaced here to keep real
// connection code out of these tests. Defaults to no-banner state unless a test overrides it.
vi.mock("app/frontend/hooks/usePipelineRunSubscription", () => ({
    usePipelineRunSubscription: vi.fn<
        () => { connected: boolean; downgraded: boolean; lastDisconnectedAt: null | string }
    >(() => ({
        connected: false,
        downgraded: false,
        lastDisconnectedAt: null,
    })),
}));

import BillCreatorPipelineControls from "app/frontend/components/admin/creator/BillCreatorPipelineControls";
import { ConfirmProvider } from "app/frontend/components/ui/confirm-dialog";
import { usePipelineRunSubscription } from "app/frontend/hooks/usePipelineRunSubscription";

// Test data's type comes from the component's own props so the two can't drift. Tests
// default subscriptionState to connected/fine; the banner tests further down pass their own.
type ControlsProps = React.ComponentProps<typeof BillCreatorPipelineControls>;
const baseProps: ControlsProps = {
    subscriptionState: { connected: true, downgraded: false, lastDisconnectedAt: null },
};

const baseInertiaProps = {
    legislation_pipeline_run: null,
    bill: { id: 1, external_id: "X" },
    bills: [],
};

// BillCreatorPipelineControls calls useConfirm() before anything destructive,
// so every render has to sit inside a ConfirmProvider.
const render = (ui: Parameters<typeof rtlRender>[0], options?: Parameters<typeof rtlRender>[1]) =>
    rtlRender(ui, { wrapper: ConfirmProvider, ...options });

describe("BillCreatorPipelineControls — conflict Alert", () => {
    beforeEach(() => {
        pagePropsRef.current = { ...baseInertiaProps };
    });

    it("renders conflict Alert when errors.pipeline is set", () => {
        pagePropsRef.current = {
            ...baseInertiaProps,
            errors: {
                pipeline: "A pipeline run is already in progress. Clear any pinned run to see it.",
            },
        };
        render(<BillCreatorPipelineControls {...baseProps} />);
        const alert = screen.getByTestId("pipeline-conflict-alert");
        expect(alert).toBeInTheDocument();
        expect(alert).toHaveTextContent("Pipeline already running");
        // The copy rules say this wording is written into the component.
        expect(alert).toHaveTextContent("A pipeline run is already in progress. Clear any pinned run to see it.");
    });

    it("does not render Alert when errors.pipeline is undefined", () => {
        pagePropsRef.current = {
            ...baseInertiaProps,
            errors: {},
        };
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("pipeline-conflict-alert")).not.toBeInTheDocument();
    });

    // The alert's wording is now hardcoded, not printed from errors.pipeline, so nothing
    // server-sent can smuggle in markup — even an attacker's value only triggers the alert,
    // never its text.
    it("renders hardcoded description regardless of errors.pipeline content (XSS surface eliminated)", () => {
        const attacker = "<script>window.__pwn=1</script>raw <b>tag</b>";
        pagePropsRef.current = {
            ...baseInertiaProps,
            errors: { pipeline: attacker },
        };
        render(<BillCreatorPipelineControls {...baseProps} />);

        const alert = screen.getByTestId("pipeline-conflict-alert");
        expect(alert).toBeInTheDocument();
        expect(alert).not.toHaveTextContent(attacker);
        expect(alert).toHaveTextContent("A pipeline run is already in progress. Clear any pinned run to see it.");
        expect(alert.querySelector("script")).toBeNull();
        expect(alert.querySelector("b")).toBeNull();
    });
});

// @lat: [[bill-creator-pipeline-controls-panel#Why stage selection uses two buttons rather than a tick-all box#An auto-included stage does less than the same stage ticked]]
describe("BillCreatorPipelineControls — auto-include preview", () => {
    beforeEach(() => {
        pagePropsRef.current = { ...baseInertiaProps };
    });

    it("renders 'Also required' Alert with display-name chips when confirmation_required is true", () => {
        pagePropsRef.current = {
            ...baseInertiaProps,
            pipeline_preview: {
                stages_requested: ["parse-sections"],
                stages_will_run: ["fetch-bills", "fetch-law", "extract-text", "parse-sections"],
                stages_auto_included: ["fetch-bills", "fetch-law", "extract-text"],
                confirmation_required: true,
                confirmation_message:
                    "Selected stages require: fetch-bills, fetch-law, extract-text — these will run too. Continue?",
            },
        };
        render(<BillCreatorPipelineControls {...baseProps} />);

        const alert = screen.getByTestId("pipeline-auto-include-alert");
        expect(alert).toBeInTheDocument();
        expect(alert).toHaveTextContent("Also required");
        // Readable names, NOT the internal stage keys.
        expect(alert).toHaveTextContent("Fetch bills");
        expect(alert).toHaveTextContent("Fetch law");
        expect(alert).toHaveTextContent("Extract text");
        // An internal key must never show up on a chip.
        expect(alert).not.toHaveTextContent("fetch-bills");
    });

    it("does not render the Alert when confirmation_required is false", () => {
        pagePropsRef.current = {
            ...baseInertiaProps,
            pipeline_preview: {
                stages_requested: ["fetch-bills"],
                stages_will_run: ["fetch-bills"],
                stages_auto_included: [],
                confirmation_required: false,
                confirmation_message: null,
            },
        };
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("pipeline-auto-include-alert")).not.toBeInTheDocument();
    });

    it("does not render the Alert when pipeline_preview is null/missing", () => {
        pagePropsRef.current = { ...baseInertiaProps, pipeline_preview: null };
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("pipeline-auto-include-alert")).not.toBeInTheDocument();
    });
});

// @lat: [[bill-creator-pipeline-controls-test-notes#BillCreatorPipelineControls test notes]]
import { router as mockedRouter } from "@inertiajs/react";

type RunOverrides = Partial<{
    id: number;
    status: "queued" | "running" | "completed" | "succeeded" | "failed" | "partial" | "cancelled" | null;
    kind: "single" | "all_bills" | null;
    current_stage: string | null;
    parent_run_id: string | null;
    origin: "fresh" | "resume" | "restart" | null;
    bill_id: number | null;
    bill_external_id: string | null;
    pipeline_run_stages: Array<{
        stage_name: string;
        status: "pending" | "running" | "succeeded" | "failed" | "skipped";
        position: number;
    }>;
}>;

function makeRun(overrides: RunOverrides = {}) {
    return {
        id: 42,
        remote_run_id: "r-42",
        status: "failed" as const,
        processed: 1,
        total: 1,
        current_bill_external_id: null,
        phase: null,
        eta_seconds: null,
        errors: [],
        queued: [],
        bills_updated: null,
        error_message: null,
        current_stage: "extract-text",
        bill_id: 100 as number | null,
        bill_external_id: "B-100" as string | null,
        download_missing_assets: true,
        started_at: null,
        completed_at: null,
        kind: "single" as const,
        parent_run_id: null,
        origin: "fresh" as const,
        pipeline_run_stages: [
            {
                stage_name: "fetch-bills",
                status: "succeeded" as const,
                position: 1,
            },
            {
                stage_name: "extract-text",
                status: "failed" as const,
                position: 2,
            },
        ],
        ...overrides,
    };
}

describe("BillCreatorPipelineControls — failure surfaces", () => {
    beforeEach(() => {
        // The shared stand-in above makes router.post and router.reload once per
        // module load. Wipe what they recorded between tests, so one test's
        // calls cannot be counted by the next.

        // oxlint-disable-next-line typescript/unbound-method -- vi.mocked() handles binding
        vi.mocked(mockedRouter.post).mockClear();
        // oxlint-disable-next-line typescript/unbound-method -- vi.mocked() handles binding
        vi.mocked(mockedRouter.reload).mockClear();
        // oxlint-disable-next-line typescript/unbound-method -- vi.mocked() handles binding
        vi.mocked(mockedRouter.visit).mockClear();
        pagePropsRef.current = { ...baseInertiaProps, legislation_pipeline_run: makeRun() };
    });

    it("renders failure header when run.status === 'failed' && run.kind === 'single'", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);
        const alert = screen.getByTestId("pipeline-failure-alert");
        expect(alert).toBeInTheDocument();
        // The failure heading looks the stage up in STAGE_DISPLAY_NAMES, so the
        // operator reads "Extract text" instead of the bare key "extract-text"
        // — the same way the auto-include chips do it.
        expect(alert).toHaveTextContent("Failed at stage 2: Extract text");
    });

    // When we can't work out which stage failed — no stage row, and STAGES lookup finds
    // nothing — say "Failed during pipeline", not the misleading "Failed at stage 0: unknown".
    it("renders 'Failed during pipeline' when STAGES.indexOf returns -1 and pipeline_run_stages is empty", () => {
        pagePropsRef.current = {
            ...baseInertiaProps,
            legislation_pipeline_run: makeRun({
                current_stage: "totally-unknown-stage",
                pipeline_run_stages: [],
            }),
        };
        render(<BillCreatorPipelineControls {...baseProps} />);
        const alert = screen.getByTestId("pipeline-failure-alert");
        expect(alert).toHaveTextContent("Failed during pipeline");
        expect(alert).not.toHaveTextContent("stage 0");
    });

    it("renders Resume + Restart buttons in single-bill failed state", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.getByTestId("btn-resume-pipeline")).toBeInTheDocument();
        expect(screen.getByTestId("btn-restart-pipeline")).toBeInTheDocument();
        // The little arrow that opened a Restart menu is gone, so no such
        // button should be drawn.
        expect(screen.queryByTestId("btn-restart-menu-trigger")).toBeNull();
        // When we know which stage failed, the Resume button says its number.
        expect(screen.getByTestId("btn-resume-pipeline")).toHaveTextContent("Resume from stage 2");
    });

    it("Resume click calls router.post('/bills/legislation_pipeline_runs/:id/resume')", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);
        fireEvent.click(screen.getByTestId("btn-resume-pipeline"));
        // oxlint-disable-next-line typescript/unbound-method -- vi.mocked() handles binding
        expect(mockedRouter.post).toHaveBeenCalledWith(
            "/bills/legislation_pipeline_runs/42/resume",
            {},
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    // Restart must NOT send download_missing_assets at all — only when the controller finds
    // that key missing does the service copy the setting from the run being restarted.
    it("Restart click posts an empty body — no download_missing_assets (WR-12 inheritance)", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);
        fireEvent.click(screen.getByTestId("btn-restart-pipeline"));
        // oxlint-disable-next-line typescript/unbound-method -- vi.mocked() handles binding
        expect(mockedRouter.post).toHaveBeenCalledWith(
            "/bills/legislation_pipeline_runs/42/restart",
            {},
            expect.objectContaining({ preserveScroll: true }),
        );
    });

    it("no chevron split-menu trigger renders (chevron deleted)", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("btn-restart-menu-trigger")).toBeNull();
    });

    it("no 'Restart with refresh' menuitem renders (menuitem deleted)", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("btn-restart-with-refresh")).toBeNull();
    });

    it("no restart-with-refresh confirmation dialog renders (dialog file deleted)", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByText("Restart with refresh?")).toBeNull();
        expect(screen.queryByText("Restart and clear cache")).toBeNull();
    });
});

// showStandaloneOriginHint had no test before this — three clauses (not failed,
// resume/restart origin, parent run id exists). Each example flips one clause off a
// run that would show the hint.
describe("BillCreatorPipelineControls — standalone origin hint", () => {
    beforeEach(() => {
        pagePropsRef.current = { ...baseInertiaProps };
    });

    it("shows the hint for a running resume whose parent run id is known", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({
            status: "running",
            origin: "resume",
            parent_run_id: "abcdefgh12345678",
        });
        render(<BillCreatorPipelineControls {...baseProps} />);
        const hint = screen.getByTestId("pipeline-origin-hint");
        expect(hint).toHaveTextContent("Resume of run 12345678");
    });

    it("shows Restart wording for a restart origin", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({
            status: "running",
            origin: "restart",
            parent_run_id: "abcdefgh12345678",
        });
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.getByTestId("pipeline-origin-hint")).toHaveTextContent("Restart of run 12345678");
    });

    it("hides the hint once the run has failed, even mid-resume", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({
            status: "failed",
            origin: "resume",
            parent_run_id: "abcdefgh12345678",
        });
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("pipeline-origin-hint")).toBeNull();
    });

    it("hides the hint for a fresh run, even with a parent_run_id set", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({
            status: "running",
            origin: "fresh",
            parent_run_id: "abcdefgh12345678",
        });
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("pipeline-origin-hint")).toBeNull();
    });

    it("hides the hint when there is no parent run id to name", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({
            status: "running",
            origin: "resume",
            parent_run_id: null,
        });
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(screen.queryByTestId("pipeline-origin-hint")).toBeNull();
    });
});

// The Force-fail row's wrapper carried a test id nothing ever read — not coverage,
// just looked like it. Both gate clauses get an example, so the row can't appear on a
// finished run.
describe("BillCreatorPipelineControls — the in-flight actions row", () => {
    beforeEach(() => {
        pagePropsRef.current = { ...baseInertiaProps };
    });

    it("draws it while a run is going", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({ status: "running" });
        render(<BillCreatorPipelineControls {...baseProps} />);

        expect(screen.getByTestId("pipeline-inflight-actions")).toBeInTheDocument();
        expect(screen.getByTestId("btn-force-fail")).toBeInTheDocument();
    });

    it("hides it once the run has finished", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({ status: "succeeded" });
        render(<BillCreatorPipelineControls {...baseProps} />);

        expect(screen.queryByTestId("pipeline-inflight-actions")).toBeNull();
    });

    it("hides it when there is no run at all", () => {
        pagePropsRef.current.legislation_pipeline_run = null;
        render(<BillCreatorPipelineControls {...baseProps} />);

        expect(screen.queryByTestId("pipeline-inflight-actions")).toBeNull();
    });
});

describe("BillCreatorPipelineControls — in-progress signal", () => {
    beforeEach(() => {
        pagePropsRef.current = { ...baseInertiaProps };
    });

    it("shows the run spinner and marks the panel aria-busy while a run is going", () => {
        pagePropsRef.current.legislation_pipeline_run = makeRun({ status: "running" });
        render(<BillCreatorPipelineControls {...baseProps} />);

        expect(screen.getByTestId("pipeline-run-spinner")).toBeInTheDocument();
        expect(screen.getByTestId("pipeline-controls")).toHaveAttribute("aria-busy", "true");
    });

    it("shows no run spinner and no aria-busy when idle", () => {
        render(<BillCreatorPipelineControls {...baseProps} />);

        expect(screen.queryByTestId("pipeline-run-spinner")).toBeNull();
        expect(screen.getByTestId("pipeline-controls")).not.toHaveAttribute("aria-busy");
    });
});

// @lat: [[bill-creator-pipeline-controls-panel#Why the cable-downgrade banner needs its own isRunning gate]]
describe("BillCreatorPipelineControls — cable downgrade banner", () => {
    beforeEach(() => {
        pagePropsRef.current = {
            ...baseInertiaProps,
            // status: "running" — the banner only shows while a run is
            // actually in flight. A separate test below covers the terminal
            // case, where the socket can stay open with nothing polling
            // behind it.
            legislation_pipeline_run: { remote_run_id: "abc", status: "running" },
        };
    });

    // Only one place may open the connection — the panel. This component must never call
    // usePipelineRunSubscription; the test proves the prop is the only way data gets in.
    it("does not call usePipelineRunSubscription — host is the sole subscription owner", () => {
        vi.mocked(usePipelineRunSubscription).mockClear();
        render(<BillCreatorPipelineControls {...baseProps} />);
        expect(vi.mocked(usePipelineRunSubscription)).not.toHaveBeenCalled();
    });

    it("renders cable-downgrade-banner with locked copy when downgraded=true", () => {
        render(
            <BillCreatorPipelineControls
                {...baseProps}
                subscriptionState={{ connected: false, downgraded: true, lastDisconnectedAt: new Date() }}
            />,
        );
        const banner = screen.getByTestId("cable-downgrade-banner");
        expect(banner).toBeInTheDocument();
        expect(banner).toHaveTextContent("Live updates paused — polling every 5s. Reconnecting…");
        expect(banner).toHaveAttribute("role", "status");
        expect(banner).toHaveAttribute("aria-live", "polite");
    });

    it("does not render the banner when downgraded=false", () => {
        render(
            <BillCreatorPipelineControls
                {...baseProps}
                subscriptionState={{ connected: true, downgraded: false, lastDisconnectedAt: null }}
            />,
        );
        expect(screen.queryByTestId("cable-downgrade-banner")).not.toBeInTheDocument();
    });

    // The socket stays open for a finished run (remote_run_id non-null), but the 5s poll
    // is gated separately on the run being in flight (BillCreatorPipelineLlm.tsx's
    // isRunInFlight).
    it("does not render the banner when the run has already finished, even though downgraded=true", () => {
        pagePropsRef.current = {
            ...baseInertiaProps,
            legislation_pipeline_run: { remote_run_id: "abc", status: "completed" },
        };
        render(
            <BillCreatorPipelineControls
                {...baseProps}
                subscriptionState={{ connected: false, downgraded: true, lastDisconnectedAt: new Date() }}
            />,
        );
        expect(screen.queryByTestId("cable-downgrade-banner")).not.toBeInTheDocument();
    });
});
