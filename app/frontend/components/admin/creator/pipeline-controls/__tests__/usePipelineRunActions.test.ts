import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { useConfirm } from "app/frontend/components/ui/confirm-dialog";
import type { ILegislationPipelineRun } from "app/frontend/components/admin/creator/pipeline-controls/types";
import {
    type PipelineRunActions,
    usePipelineRunActions,
} from "app/frontend/components/admin/creator/pipeline-controls/usePipelineRunActions";

const routerPost = vi.fn<(...args: unknown[]) => void>();
const routerDelete = vi.fn<(...args: unknown[]) => void>();
const notifyMock = vi.fn<(args: unknown) => string>();

vi.mock("@inertiajs/react", () => ({
    router: {
        post: (...args: unknown[]) => routerPost(...args),
        delete: (...args: unknown[]) => routerDelete(...args),
    },
}));

vi.mock("app/frontend/sway_utils", async (importOriginal) => {
    const actual = await importOriginal<typeof import("app/frontend/sway_utils")>();
    return { ...actual, notify: (args: unknown) => notifyMock(args) };
});

afterEach(() => {
    routerPost.mockReset();
    routerDelete.mockReset();
    notifyMock.mockReset();
});

// Minimal run stub — usePipelineRunActions only reads run.id.
const RUN_STUB = { id: 42 } as unknown as ILegislationPipelineRun;
const NOOP_CONFIRM = (async () => true) as unknown as ReturnType<typeof useConfirm>;

const renderActions = (overrides: Partial<Parameters<typeof usePipelineRunActions>[0]> = {}) =>
    renderHook(() =>
        usePipelineRunActions({
            run: RUN_STUB,
            selectedStages: [],
            pickedBillId: "",
            downloadMissingAssets: true,
            staleCount: 0,
            orphanCount: 0,
            confirm: NOOP_CONFIRM,
            ...overrides,
        }),
    );

describe("usePipelineRunActions", () => {
    // @lat: [[bill-creator-pipeline-controls-panel#usePipelineRunActions notes]]
    describe("handleRestart (WR-12)", () => {
        it("posts to the restart route with an empty body — no download_missing_assets key", () => {
            const { result } = renderActions({ downloadMissingAssets: false });
            act(() => result.current.handleRestart());

            expect(routerPost).toHaveBeenCalledTimes(1);
            const [path, body] = routerPost.mock.calls[0] as [string, Record<string, unknown>];
            expect(path).toBe("/bills/legislation_pipeline_runs/42/restart");
            expect(body).not.toHaveProperty("download_missing_assets");
        });

        it("posts an empty body regardless of the current downloadMissingAssets value", () => {
            const { result: trueResult } = renderActions({ downloadMissingAssets: true });
            act(() => trueResult.current.handleRestart());
            const [, trueBody] = routerPost.mock.calls[0] as [string, Record<string, unknown>];
            expect(trueBody).not.toHaveProperty("download_missing_assets");

            routerPost.mockReset();

            const { result: falseResult } = renderActions({ downloadMissingAssets: false });
            act(() => falseResult.current.handleRestart());
            const [, falseBody] = routerPost.mock.calls[0] as [string, Record<string, unknown>];
            expect(falseBody).not.toHaveProperty("download_missing_assets");
        });

        it("no-ops when run is null", () => {
            const { result } = renderActions({ run: null });
            act(() => result.current.handleRestart());
            expect(routerPost).not.toHaveBeenCalled();
        });
    });

    // A guard against over-correcting: handleRun starts a fresh run over all
    // bills, unlike restart, and it MUST keep sending download_missing_assets.
    // On a new run the toggle is exactly what the operator wants applied.
    describe("handleRun (sanity — opposite of restart)", () => {
        it("DOES include download_missing_assets in the run body", () => {
            const { result } = renderActions({
                selectedStages: ["fetch-bills"],
                downloadMissingAssets: false,
            });
            act(() => result.current.handleRun());

            const [, body] = routerPost.mock.calls[0] as [string, Record<string, unknown>];
            expect(body).toHaveProperty("download_missing_assets", false);
        });

        it("DOES include sway_locale_id in the run body when provided", () => {
            const { result } = renderActions({
                selectedStages: ["fetch-bills"],
                swayLocaleId: 3,
            });
            act(() => result.current.handleRun());

            const [, body] = routerPost.mock.calls[0] as [string, Record<string, unknown>];
            expect(body).toHaveProperty("sway_locale_id", 3);
        });
    });
});

// @lat: [[notify-server-refusal-pattern#Why serverRefusalMessage checks the shape carefully]]
describe("usePipelineRunActions — server refusals (extent)", () => {
    const optionsFor = (call: unknown[]) => call[call.length - 1] as Record<string, unknown>;

    it.each([
        ["handleResume", (a: PipelineRunActions) => a.handleResume, "Could not resume the pipeline run."],
        ["handleRestart", (a: PipelineRunActions) => a.handleRestart, "Could not restart the pipeline run."],
        ["handleRun", (a: PipelineRunActions) => a.handleRun, "Could not start the pipeline run."],
    ])("%s toasts the server's refusal copy", (_label, pick, fallback) => {
        const { result } = renderActions({ selectedStages: ["fetch-bills"] });
        act(() => pick(result.current)());

        const onError = optionsFor(routerPost.mock.calls[0]).onError as (errors: unknown) => void;
        expect(typeof onError).toBe("function");

        onError({ pipeline: "Resume is not allowed from status=succeeded" });
        expect(notifyMock).toHaveBeenCalledWith({
            level: "error",
            title: "Resume is not allowed from status=succeeded",
        });

        notifyMock.mockClear();
        onError({});
        expect(notifyMock).toHaveBeenCalledWith({ level: "error", title: fallback });
    });
});
