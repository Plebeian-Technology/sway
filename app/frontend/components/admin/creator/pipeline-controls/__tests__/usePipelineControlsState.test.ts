import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";
import { DEFAULT_STAGE_KEYS, STAGES } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { usePipelineControlsState } from "app/frontend/components/admin/creator/pipeline-controls/usePipelineControlsState";

const routerVisit = vi.fn<(...args: unknown[]) => void>();
let mockProps: Record<string, unknown> = {};

vi.mock("@inertiajs/react", () => ({
    router: { visit: (...args: unknown[]) => routerVisit(...args) },
    usePage: () => ({ props: mockProps }),
}));

const visitData = () => (routerVisit.mock.calls[0][1] as { data: Record<string, unknown> }).data;
const visitOpts = () => routerVisit.mock.calls[0][1] as Record<string, unknown>;
// The address the router was HANDED, not anything the hook keeps to itself.
const visitUrl = () => routerVisit.mock.calls[0][0] as string;
const at = (address: string) => window.history.replaceState({}, "", address);

// The URL update waits 250ms after the last change. These tests use fake timers
// and flushDebounce() to jump past that wait predictably.
const DEBOUNCE_MS = 250;
const flushDebounce = () =>
    act(() => {
        vi.advanceTimersByTime(DEBOUNCE_MS);
    });

beforeEach(() => {
    vi.useFakeTimers();
});

afterEach(() => {
    vi.useRealTimers();
    routerVisit.mockReset();
    mockProps = {};
    at("/");
});

describe("usePipelineControlsState", () => {
    it("defaults selectedStages to the default stage keys (summarize-bill off) when the prop is absent", () => {
        const { result } = renderHook(() => usePipelineControlsState());
        expect(result.current.selectedStages).toEqual(DEFAULT_STAGE_KEYS);
        expect(result.current.selectedStages).not.toContain("summarize-bill");
    });

    it("reflects props.selected_stages when set", () => {
        mockProps = { selected_stages: ["fetch-bills", "extract-text"] };
        const { result } = renderHook(() => usePipelineControlsState());
        expect(result.current.selectedStages).toEqual(["fetch-bills", "extract-text"]);
    });

    it("serializes a partial stage selection into the visit data", () => {
        const { result } = renderHook(() => usePipelineControlsState());
        act(() => result.current.setSelectedStages(["fetch-bills"]));
        flushDebounce();
        expect(visitData().selected_stages).toEqual(["fetch-bills"]);
    });

    // @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
    it("says no stages in the address, where nothing can drop it", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77");
        const { result } = renderHook(() => usePipelineControlsState());
        act(() => result.current.setSelectedStages([]));
        flushDebounce();

        expect(visitUrl()).toMatch(/[?&]selected_stages=(&|$)/);
        // Not in both places: the merge would overwrite the address with it.
        expect(visitData()).not.toHaveProperty("selected_stages");
        expect(visitUrl()).toContain("run_id=77");
        expect(stripClearedQueryParams(visitUrl())).toMatch(/[?&]selected_stages=(&|$)/);
    });

    it("says no stages in the address when the download toggle is also off", () => {
        at("/admin/bill_creator/12/pipeline?run_id=77");
        const { result } = renderHook(() => usePipelineControlsState());
        act(() => result.current.setDownloadMissingAssets(false));
        act(() => result.current.setSelectedStages([]));
        flushDebounce();

        expect(visitUrl()).toMatch(/[?&]selected_stages=(&|$)/);
        expect(visitData().download_missing_assets).toBe("0");
    });

    it("omits selected_stages when the default stage set is selected (matches the Rails default)", () => {
        const { result } = renderHook(() => usePipelineControlsState());
        act(() => result.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
        flushDebounce();
        expect(visitData()).not.toHaveProperty("selected_stages");
    });

    it("serializes selected_stages when every stage including summarize-bill is selected", () => {
        const { result } = renderHook(() => usePipelineControlsState());
        const allStages = STAGES.map((s) => s.key);
        act(() => result.current.setSelectedStages(allStages));
        flushDebounce();
        expect(visitData().selected_stages).toEqual(allStages);
    });

    it("serializes download_missing_assets as '0' when flipped to false", () => {
        const { result } = renderHook(() => usePipelineControlsState());
        act(() => result.current.setDownloadMissingAssets(false));
        flushDebounce();
        expect(visitData().download_missing_assets).toBe("0");

        routerVisit.mockReset();
        act(() => result.current.setDownloadMissingAssets(true));
        flushDebounce();
        // Default is true so it stays out of the URL when explicitly true.
        expect(visitData()).not.toHaveProperty("download_missing_assets");
    });

    it("defaults downloadMissingAssets to true when the prop is omitted", () => {
        const { result } = renderHook(() => usePipelineControlsState());
        expect(result.current.downloadMissingAssets).toBe(true);
    });

    it("reflects props.download_missing_assets=false when set", () => {
        mockProps = { download_missing_assets: false };
        const { result } = renderHook(() => usePipelineControlsState());
        expect(result.current.downloadMissingAssets).toBe(false);
    });

    it("issues a replace, async GET scoped to the pipeline-controls props", () => {
        const { result } = renderHook(() => usePipelineControlsState());
        act(() => result.current.setDownloadMissingAssets(false));
        flushDebounce();
        expect(visitOpts().method).toBe("get");
        expect(visitOpts().replace).toBe(true);
        expect(visitOpts().async).toBe(true);
        expect(visitOpts().only).toEqual(["selected_stages", "download_missing_assets", "pipeline_preview"]);
    });

    // @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]
    describe("WR29-02 the address the visit is sent to", () => {
        it("keeps the run pin when a stage is ticked", () => {
            at("/admin/bill_creator/12/pipeline?run_id=77");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages(["fetch-bills"]));
            flushDebounce();

            expect(visitUrl()).toContain("run_id=77");
        });

        it("keeps the run pin when the download toggle is flipped", () => {
            at("/admin/bill_creator/12/pipeline?run_id=77&sway_locale_id=3");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setDownloadMissingAssets(false));
            flushDebounce();

            expect(visitUrl()).toContain("run_id=77");
            expect(visitUrl()).toContain("sway_locale_id=3");
        });

        it("stays on the path holding the bill and the tab", () => {
            at("/admin/bill_creator/12/pipeline?run_id=77");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages(["fetch-bills"]));
            flushDebounce();

            expect(visitUrl()).toMatch(/^\/admin\/bill_creator\/12\/pipeline\?/);
        });

        // @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]
        it("omits a stage list when setting the default stages so Rails defaults", () => {
            at("/admin/bill_creator/12/pipeline?run_id=77&selected_stages%5B%5D=fetch-bills");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
            flushDebounce();

            expect(visitData()).not.toHaveProperty("selected_stages");
            expect(visitUrl()).not.toContain("selected_stages");
            expect(stripClearedQueryParams(visitUrl())).not.toContain("selected_stages");
            expect(visitUrl()).toContain("run_id=77");
        });

        // @lat: [[bill-creator-pipeline-controls-panel#Pipeline actions preserve the working address]]
        it("omits a LEGACY ?stages= list when setting the default stages so Rails defaults", () => {
            at("/admin/bill_creator/12/pipeline?run_id=77&stages=fetch-bills");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
            flushDebounce();

            expect(visitUrl()).not.toMatch(/[?&]stages(\[\])?=/);
            expect(stripClearedQueryParams(visitUrl())).not.toMatch(/[?&]stages(\[\])?=/);
            expect(stripClearedQueryParams(visitUrl())).not.toMatch(/[?&]selected_stages(\[\])?=/);
            expect(visitUrl()).toContain("run_id=77");
        });

        it("does not leave a legacy ?stages= beside the empty selection it writes", () => {
            at("/admin/bill_creator/12/pipeline?run_id=77&stages=fetch-bills");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([]));
            flushDebounce();

            expect(visitUrl()).toMatch(/[?&]selected_stages=(&|$)/);
            expect(visitUrl()).not.toMatch(/[?&]stages(\[\])?=/);
            expect(stripClearedQueryParams(visitUrl())).not.toMatch(/[?&]stages(\[\])?=/);
            expect(stripClearedQueryParams(visitUrl())).toMatch(/[?&]selected_stages=(&|$)/);
        });

        it("clears a download_missing_assets it is no longer setting", () => {
            at("/admin/bill_creator/12/pipeline?run_id=77&download_missing_assets=0");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setDownloadMissingAssets(true));
            flushDebounce();

            expect(isQueryParamCleared(visitUrl(), "download_missing_assets")).toBe(true);
            expect(stripClearedQueryParams(visitUrl())).not.toContain("download_missing_assets");
            expect(visitUrl()).toContain("run_id=77");
        });
    });

    // @lat: [[bill-creator-pipeline-controls-panel#Why pipeline controls debounce URL updates]]
    describe("WR-09 debounce", () => {
        it("coalesces 7 rapid toggles into a single router.visit", () => {
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => {
                result.current.setSelectedStages(["fetch-bills"]);
                result.current.setSelectedStages(["fetch-bills", "extract-text"]);
                result.current.setSelectedStages(["fetch-bills"]);
                result.current.setSelectedStages([]);
                result.current.setSelectedStages(["fetch-bills"]);
                result.current.setSelectedStages(["fetch-bills", "extract-text"]);
                result.current.setSelectedStages(["fetch-bills", "extract-text", "parse-sections"]);
            });

            // Before the timer fires, no visit yet.
            expect(routerVisit).not.toHaveBeenCalled();

            flushDebounce();

            // Only the last value reaches the router.
            expect(routerVisit).toHaveBeenCalledTimes(1);
            expect(visitData().selected_stages).toEqual(["fetch-bills", "extract-text", "parse-sections"]);
        });

        it("delays the router.visit until the debounce window elapses", () => {
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setDownloadMissingAssets(false));
            // Halfway through the wait — still no visit.
            act(() => {
                vi.advanceTimersByTime(DEBOUNCE_MS - 50);
            });
            expect(routerVisit).not.toHaveBeenCalled();

            // Now let the wait finish.
            act(() => {
                vi.advanceTimersByTime(50);
            });
            expect(routerVisit).toHaveBeenCalledTimes(1);
        });
    });

    // @lat: [[bill-creator-pipeline-controls-panel#Why deriving state during render reconciles server responses]]
    describe("WR-NEW-02 pending-override reconciliation", () => {
        it("drops pendingStages after the server prop echoes back the same value", () => {
            const { result, rerender } = renderHook(() => usePipelineControlsState());

            // The operator clicks; the local copy updates at once.
            act(() => result.current.setSelectedStages(["fetch-bills"]));
            expect(result.current.selectedStages).toEqual(["fetch-bills"]);

            flushDebounce();

            // Simulate the server roundtrip landing with the same value.
            mockProps = { selected_stages: ["fetch-bills"] };
            rerender();

            // The local copy MUST be dropped, so later clicks work out their
            // new list from the server's value rather than the stale copy.
            expect(result.current.selectedStages).toEqual(["fetch-bills"]);

            // Now the next click. If the local copy had survived, reading
            // selectedStages on the next render would still give the stale
            // value; once it is dropped, both reads agree.
            act(() => result.current.setSelectedStages(["fetch-bills", "extract-text"]));
            expect(result.current.selectedStages).toEqual(["fetch-bills", "extract-text"]);
        });

        it("drops pendingDma after the server prop echoes back the same value", () => {
            const { result, rerender } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setDownloadMissingAssets(false));
            expect(result.current.downloadMissingAssets).toBe(false);

            flushDebounce();

            // Server roundtrip lands with the same value.
            mockProps = { download_missing_assets: false };
            rerender();

            // The local copy is gone; reads come from the server's value now.
            expect(result.current.downloadMissingAssets).toBe(false);

            // Flip back; should reflect immediately.
            act(() => result.current.setDownloadMissingAssets(true));
            expect(result.current.downloadMissingAssets).toBe(true);
        });

        // @lat: [[bill-creator-pipeline-controls-panel#Why pending state caches prevent click loss during round trips]]
        it("keeps a change the operator has made but we have not sent yet", () => {
            const { result, rerender } = renderHook(() => usePipelineControlsState());

            // First uncheck, and its URL update goes out.
            act(() => result.current.setSelectedStages(["fetch-bills", "fetch-hearings"]));
            flushDebounce();

            // Second uncheck. Nothing has been sent for it yet — the debounce
            // is still counting.
            act(() => result.current.setSelectedStages(["fetch-bills"]));
            expect(result.current.selectedStages).toEqual(["fetch-bills"]);

            // The FIRST update's answer lands now, describing the older
            // selection.
            mockProps = { selected_stages: ["fetch-bills", "fetch-hearings"] };
            rerender();

            expect(result.current.selectedStages).toEqual(["fetch-bills"]);
        });

        it("drops pendingStages when the server normalizes (drops unknown keys)", () => {
            const { result, rerender } = renderHook(() => usePipelineControlsState());

            // The operator picks a pair the server will clean up — here by
            // dropping a key it does not recognise.
            act(() => result.current.setSelectedStages(["fetch-bills", "garbage"]));
            expect(result.current.selectedStages).toEqual(["fetch-bills", "garbage"]);

            flushDebounce();

            // The server cleans it up: the value comes back without "garbage".
            mockProps = { selected_stages: ["fetch-bills"] };
            rerender();

            // What is read now should be the server's cleaned-up value. Before
            // the fix, it still showed ["fetch-bills", "garbage"].
            expect(result.current.selectedStages).toEqual(["fetch-bills"]);
        });
    });

    // @lat: [[bill-creator-pipeline-controls-panel#Why partial parameter updates retransmit full state snapshots]]
    describe("full snapshot on partial change", () => {
        it("flushes the CURRENT selected_stages when toggling DMA after a server echo", () => {
            mockProps = { selected_stages: ["fetch-bills", "fetch-law"], download_missing_assets: true };
            const { result, rerender } = renderHook(() => usePipelineControlsState());
            expect(result.current.selectedStages).toEqual(["fetch-bills", "fetch-law"]);

            // Server echoes a changed stage list.
            mockProps = { selected_stages: ["extract-text"], download_missing_assets: true };
            rerender();
            expect(result.current.selectedStages).toEqual(["extract-text"]);

            // Switch the download toggle off. The URL update must carry the
            // CURRENT stages, not the stale mount-time list.
            act(() => result.current.setDownloadMissingAssets(false));
            flushDebounce();

            expect(routerVisit).toHaveBeenCalledTimes(1);
            expect(visitData().selected_stages).toEqual(["extract-text"]);
            expect(visitData().download_missing_assets).toBe("0");
        });
    });
});
