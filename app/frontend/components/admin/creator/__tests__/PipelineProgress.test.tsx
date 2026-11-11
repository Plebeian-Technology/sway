import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

// Held as its own reference rather than read back off the mocked module, so the
// assertion that this panel never calls it names a plain function.
const routerDelete = vi.hoisted(() => vi.fn<(...args: unknown[]) => void>());

vi.mock("@inertiajs/react", async (importActual) => {
    const actual = (await importActual()) as Record<string, unknown>;
    return { ...actual, router: { delete: routerDelete, reload: vi.fn<() => void>() } };
});

vi.mock("app/frontend/hooks/usePipelineRunSubscription", () => ({
    usePipelineRunSubscription: vi.fn<() => { connected: boolean; downgraded: boolean; lastDisconnectedAt: unknown }>(
        () => ({
            connected: true,
            downgraded: false,
            lastDisconnectedAt: null,
        }),
    ),
}));

import PipelineProgress from "app/frontend/components/admin/creator/PipelineProgress";
import {
    PHASE_52_NON_TERMINAL_STATUSES,
    PHASE_52_STAGE_STATUSES,
} from "app/frontend/components/admin/creator/pipeline-controls/stages";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";

// The shell's cancel handler. Every render passes it, because the panel is not
// allowed to send the DELETE itself — see the describe at the bottom of this
// file.
const onCancelRun = vi.fn<(runId: number) => void>();

beforeEach(() => {
    onCancelRun.mockClear();
    routerDelete.mockClear();
});

const baseRun: ILegislationPipelineRun = {
    id: 1,
    remote_run_id: "abc",
    status: "running",
    processed: 0,
    total: null,
    current_bill_external_id: null,
    phase: null,
    eta_seconds: null,
    errors: [],
    queued: [],
    bills_updated: null,
    error_message: null,
    current_stage: null,
    bill_id: null,
    bill_external_id: null,
    download_missing_assets: null,
    started_at: null,
    completed_at: null,
    kind: null,
    parent_run_id: null,
    origin: null,
};

describe("PipelineProgress — cancellable predicate", () => {
    // @lat: [[partial-reload-poll-lists#Partial reload poll lists#What the run-conflict banner counts as finished]]

    it.each(["queued", "running"])("renders cancel button for status=%s", (status) => {
        render(
            <PipelineProgress
                run={{ ...baseRun, status: status as ILegislationPipelineRun["status"] }}
                pickedBillId=""
                onCancelRun={onCancelRun}
            />,
        );
        expect(screen.queryByTestId("btn-cancel-pipeline")).toBeInTheDocument();
    });

    it.each(PHASE_52_STAGE_STATUSES)("renders cancel button for per-stage status=%s", (status) => {
        render(<PipelineProgress run={{ ...baseRun, status }} pickedBillId="" onCancelRun={onCancelRun} />);
        expect(screen.queryByTestId("btn-cancel-pipeline")).toBeInTheDocument();
    });

    it.each(["completed", "succeeded", "partial", "failed", "cancelled"] as const)(
        "hides cancel button for terminal status=%s",
        (status) => {
            render(<PipelineProgress run={{ ...baseRun, status }} pickedBillId="" onCancelRun={onCancelRun} />);
            expect(screen.queryByTestId("btn-cancel-pipeline")).not.toBeInTheDocument();
        },
    );

    it("PHASE_52_NON_TERMINAL_STATUSES is the union the predicate uses", () => {
        expect(PHASE_52_NON_TERMINAL_STATUSES).toEqual(["queued", "running", ...PHASE_52_STAGE_STATUSES]);
    });
});

describe("PipelineProgress — the first render after a redirect", () => {
    // @lat: [[pipeline-run-optional-progress-fields#The crash this prevents]]
    const serverSentRun = {
        id: 2,
        remote_run_id: "def",
        status: "running",
        bills_updated: null,
        error_message: null,
        current_stage: null,
        bill_id: null,
        bill_external_id: null,
        download_missing_assets: null,
        started_at: null,
        completed_at: null,
        kind: null,
        parent_run_id: null,
        origin: null,
    } as unknown as ILegislationPipelineRun;

    it("renders when the live progress fields are absent", () => {
        render(<PipelineProgress run={serverSentRun} pickedBillId="" onCancelRun={onCancelRun} />);
        expect(screen.queryByTestId("btn-cancel-pipeline")).toBeInTheDocument();
    });
});

describe("PipelineProgress — an unrecognised status reads as not running", () => {
    // isTerminalRunStatus/isInFlightRunStatus are separate allow-lists, not complements — an
    // unrecognized status used to fall through `!isTerminal` and still draw the progress UI.
    const unknownStatus = "some_future_status" as unknown as ILegislationPipelineRun["status"];

    it("does not draw the progress bar for an unrecognised status", () => {
        render(
            <PipelineProgress run={{ ...baseRun, status: unknownStatus }} pickedBillId="" onCancelRun={onCancelRun} />,
        );
        expect(screen.queryByTestId("pipeline-progress-bar")).not.toBeInTheDocument();
    });

    it("does not claim live updates are paused-but-polling for an unrecognised status", () => {
        render(
            <PipelineProgress
                run={{ ...baseRun, status: unknownStatus }}
                pickedBillId=""
                subscription={{ connected: false, downgraded: false, lastDisconnectedAt: null }}
                onCancelRun={onCancelRun}
            />,
        );
        expect(screen.queryByText(/refreshing on poll/i)).not.toBeInTheDocument();
    });
});

// The Cancel DELETE used to bypass the unsaved-changes dialog that every other exit uses —
// RunConflictBanner had the same bug fixed already; this was its missed sibling.
describe("PipelineProgress — cancelling goes through the shell, not straight to the server", () => {
    const cancelButton = () => screen.getByTestId("btn-cancel-pipeline");

    it("hands the run id up on the second tap instead of sending the request", () => {
        render(<PipelineProgress run={baseRun} pickedBillId="" onCancelRun={onCancelRun} />);

        fireEvent.click(cancelButton());
        fireEvent.click(cancelButton());

        expect(onCancelRun).toHaveBeenCalledWith(baseRun.id);
        expect(routerDelete).not.toHaveBeenCalled();
    });

    // The two-tap confirm still belongs to this panel. One tap arms it and asks
    // nothing of the shell, so a stray click cannot cancel a run.
    it("asks for nothing on the first tap", () => {
        render(<PipelineProgress run={baseRun} pickedBillId="" onCancelRun={onCancelRun} />);

        fireEvent.click(cancelButton());

        expect(onCancelRun).not.toHaveBeenCalled();
    });
});
