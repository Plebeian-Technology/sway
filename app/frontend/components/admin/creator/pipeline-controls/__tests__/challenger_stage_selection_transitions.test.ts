import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DEFAULT_STAGE_KEYS, STAGES } from "app/frontend/components/admin/creator/pipeline-controls/stages";
import { usePipelineControlsState } from "app/frontend/components/admin/creator/pipeline-controls/usePipelineControlsState";
import { isIntentionalEmptyListParameter } from "app/frontend/sway_utils/addressWithEmptyList";
import { stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";
import { applyNavigationCarryToVisit } from "app/frontend/sway_utils/queryParamNavigationCarry";

// @lat: [[bill-creator-pipeline-controls-panel#Why an empty stage selection is spelled out on the wire]]
// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

const routerVisit = vi.fn<(...args: unknown[]) => void>();
let mockProps: Record<string, unknown> = {};

vi.mock("@inertiajs/react", () => ({
    router: { visit: (...args: unknown[]) => routerVisit(...args) },
    usePage: () => ({ props: mockProps }),
}));

const DEBOUNCE_MS = 250;
const flushDebounce = () =>
    act(() => {
        vi.advanceTimersByTime(DEBOUNCE_MS);
    });

const at = (address: string) => window.history.replaceState({}, "", address);
const visitUrl = () => routerVisit.mock.calls[0]?.[0] as string;
const visitOptions = () =>
    routerVisit.mock.calls[0]?.[1] as { data?: Record<string, unknown>; only?: string[] } | undefined;
const visitData = () => visitOptions()?.data;

describe("Empirical Challenger: Pipeline controls stage selection state transitions", () => {
    beforeEach(() => {
        vi.useFakeTimers();
        routerVisit.mockReset();
        mockProps = {};
        at("/admin/bill_creator/42/pipeline");
    });

    afterEach(() => {
        vi.useRealTimers();
        routerVisit.mockReset();
        mockProps = {};
        at("/");
    });

    describe("Transition 1: Initial state (7 of 8 default stages, summarize-bill off)", () => {
        it("initial state has NO selected_stages or stages parameter on the URL", () => {
            const currentUrl = new URL(window.location.href);
            expect(currentUrl.searchParams.has("selected_stages")).toBe(false);
            expect(currentUrl.searchParams.has("selected_stages[]")).toBe(false);
            expect(currentUrl.searchParams.has("stages")).toBe(false);
            expect(currentUrl.searchParams.has("stages[]")).toBe(false);

            const { result } = renderHook(() => usePipelineControlsState());
            expect(result.current.selectedStages.length).toBe(DEFAULT_STAGE_KEYS.length);
            expect(result.current.selectedStages).toEqual(DEFAULT_STAGE_KEYS);
            expect(result.current.selectedStages).not.toContain("summarize-bill");

            expect(routerVisit).not.toHaveBeenCalled();
        });
    });

    describe("Transition 2: Deselect all (0 of 8 stages)", () => {
        it("deselecting all results in selected_stages= and NO stages parameter", () => {
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([]));
            expect(result.current.selectedStages).toEqual([]);

            flushDebounce();

            expect(routerVisit).toHaveBeenCalledTimes(1);
            const targetUrl = visitUrl();
            const data = visitData();

            expect(targetUrl).toMatch(/[?&]selected_stages=(&|$)/);
            expect(targetUrl).not.toMatch(/[?&]stages(\[\])?=/);
            expect(data).not.toHaveProperty("selected_stages");

            const stripped = stripClearedQueryParams(targetUrl);
            expect(stripped).toMatch(/[?&]selected_stages=(&|$)/);
            expect(stripped).not.toMatch(/[?&]stages(\[\])?=/);
        });

        it("deselecting all does NOT result in an empty query string '?' when no other params exist", () => {
            at("/admin/bill_creator/42/pipeline");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([]));
            flushDebounce();

            const targetUrl = visitUrl();
            expect(targetUrl).toBe("/admin/bill_creator/42/pipeline?selected_stages=");
            expect(targetUrl).not.toBe("/admin/bill_creator/42/pipeline?");
            expect(targetUrl).not.toBe("/admin/bill_creator/42/pipeline");

            const stripped = stripClearedQueryParams(targetUrl);
            expect(stripped).toBe("/admin/bill_creator/42/pipeline?selected_stages=");
        });

        it("deselecting all retains other query parameters and does not leave residual stages", () => {
            at("/admin/bill_creator/42/pipeline?run_id=99&stages=fetch-bills");
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([]));
            flushDebounce();

            const targetUrl = visitUrl();
            expect(targetUrl).toContain("run_id=99");
            expect(targetUrl).toMatch(/[?&]selected_stages=(&|$)/);
            expect(targetUrl).not.toMatch(/[?&]stages(\[\])?=/);

            const stripped = stripClearedQueryParams(targetUrl);
            expect(stripped).toContain("run_id=99");
            expect(stripped).toMatch(/[?&]selected_stages=(&|$)/);
            expect(stripped).not.toMatch(/[?&]stages(\[\])?=/);
        });
    });

    describe("Transition 3: Select some stages (partial selection)", () => {
        it("selecting some stages sends selected_stages and removes stages", () => {
            at("/admin/bill_creator/42/pipeline?selected_stages=");
            const { result } = renderHook(() => usePipelineControlsState());

            const partialStages = ["fetch-bills", "fetch-hearings"];
            act(() => result.current.setSelectedStages(partialStages));
            expect(result.current.selectedStages).toEqual(partialStages);

            flushDebounce();

            expect(routerVisit).toHaveBeenCalledTimes(1);
            const targetUrl = visitUrl();
            const data = visitData();

            expect(targetUrl).not.toMatch(/[?&]selected_stages(\[\])?=/);
            expect(targetUrl).not.toMatch(/[?&]stages(\[\])?=/);
            expect(data?.selected_stages).toEqual(partialStages);
        });

        it("correctly identifies intentional empty list parameters", () => {
            expect(isIntentionalEmptyListParameter("selected_stages")).toBe(true);
            expect(isIntentionalEmptyListParameter("stages")).toBe(true);
            expect(isIntentionalEmptyListParameter("run_id")).toBe(false);
            expect(isIntentionalEmptyListParameter("search")).toBe(false);
            expect(isIntentionalEmptyListParameter("page")).toBe(false);
        });
    });

    describe("Transition 4: Re-select default stages (7 of 8) vs all stages (8 of 8)", () => {
        it("re-selecting default stages removes selected_stages and stages completely from URL and data", () => {
            at("/admin/bill_creator/42/pipeline?selected_stages=");
            mockProps = { selected_stages: [] };
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
            expect(result.current.selectedStages.length).toBe(DEFAULT_STAGE_KEYS.length);

            flushDebounce();

            expect(routerVisit).toHaveBeenCalledTimes(1);
            const targetUrl = visitUrl();
            const data = visitData();

            expect(targetUrl).not.toContain("selected_stages");
            expect(targetUrl).not.toContain("stages");
            expect(data).not.toHaveProperty("selected_stages");

            const stripped = stripClearedQueryParams(targetUrl);
            expect(stripped).toBe("/admin/bill_creator/42/pipeline");
            expect(stripped).not.toContain("?");
        });

        it("re-selecting default stages from a partial state removes selected_stages", () => {
            at("/admin/bill_creator/42/pipeline?selected_stages[]=fetch-bills");
            mockProps = { selected_stages: ["fetch-bills"] };
            const { result } = renderHook(() => usePipelineControlsState());

            act(() => result.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
            flushDebounce();

            const targetUrl = visitUrl();
            const data = visitData();

            expect(targetUrl).not.toContain("selected_stages");
            expect(targetUrl).not.toContain("stages");
            expect(data).not.toHaveProperty("selected_stages");
        });

        it("selecting all 8 stages (including summarize-bill) sends selected_stages in data", () => {
            at("/admin/bill_creator/42/pipeline?selected_stages[]=fetch-bills");
            mockProps = { selected_stages: ["fetch-bills"] };
            const { result } = renderHook(() => usePipelineControlsState());
            const allStages = STAGES.map((s) => s.key);

            act(() => result.current.setSelectedStages(allStages));
            flushDebounce();

            const targetUrl = visitUrl();
            const data = visitData();

            expect(targetUrl).not.toContain("selected_stages");
            expect(targetUrl).not.toContain("stages");
            expect(data?.selected_stages).toEqual(allStages);
        });

        it("transitioning from all 8 stages or 0 stages to the 7 default stages keeps selected_stages and stages absent after applyNavigationCarryToVisit while preserving run_id", () => {
            const allStages = STAGES.map((s) => s.key);
            const allStagesQuery = allStages.map((s) => `selected_stages[]=${s}`).join("&");
            const allStagesAddress = `/admin/bill_creator/42/pipeline?${allStagesQuery}&run_id=99`;
            at(allStagesAddress);
            mockProps = { selected_stages: allStages };

            const { result, unmount } = renderHook(() => usePipelineControlsState());
            act(() => result.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
            flushDebounce();

            const visitFromAll = {
                url: visitUrl(),
                method: "get" as const,
                data: visitData() ?? {},
                only: visitOptions()?.only,
            } as any;

            applyNavigationCarryToVisit(visitFromAll, {
                currentUrl: new URL(allStagesAddress, "http://localhost"),
            });

            const carriedFromAll =
                visitFromAll.url instanceof URL ? visitFromAll.url : new URL(visitFromAll.url, "http://localhost");
            expect(carriedFromAll.searchParams.has("selected_stages")).toBe(false);
            expect(carriedFromAll.searchParams.has("selected_stages[]")).toBe(false);
            expect(carriedFromAll.searchParams.has("stages")).toBe(false);
            expect(carriedFromAll.searchParams.has("stages[]")).toBe(false);
            expect(carriedFromAll.searchParams.get("run_id")).toBe("99");

            unmount();
            routerVisit.mockReset();

            const emptyStagesAddress = "/admin/bill_creator/42/pipeline?selected_stages=&run_id=99";
            at(emptyStagesAddress);
            mockProps = { selected_stages: [] };

            const { result: resultFromZero } = renderHook(() => usePipelineControlsState());
            act(() => resultFromZero.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
            flushDebounce();

            const visitFromZero = {
                url: visitUrl(),
                method: "get" as const,
                data: visitData() ?? {},
                only: visitOptions()?.only,
            } as any;

            applyNavigationCarryToVisit(visitFromZero, {
                currentUrl: new URL(emptyStagesAddress, "http://localhost"),
            });

            const carriedFromZero =
                visitFromZero.url instanceof URL ? visitFromZero.url : new URL(visitFromZero.url, "http://localhost");
            expect(carriedFromZero.searchParams.has("selected_stages")).toBe(false);
            expect(carriedFromZero.searchParams.has("selected_stages[]")).toBe(false);
            expect(carriedFromZero.searchParams.has("stages")).toBe(false);
            expect(carriedFromZero.searchParams.has("stages[]")).toBe(false);
            expect(carriedFromZero.searchParams.get("run_id")).toBe("99");
        });
    });

    describe("Full Cycle Stress: default (7/8) -> 0/8 -> partial -> default (7/8) -> 0/8", () => {
        it("survives the entire sequence of operator state transitions", () => {
            const { result } = renderHook(() => usePipelineControlsState());

            expect(result.current.selectedStages.length).toBe(DEFAULT_STAGE_KEYS.length);

            act(() => result.current.setSelectedStages([]));
            flushDebounce();
            expect(visitUrl()).toBe("/admin/bill_creator/42/pipeline?selected_stages=");
            expect(stripClearedQueryParams(visitUrl())).toBe("/admin/bill_creator/42/pipeline?selected_stages=");

            routerVisit.mockReset();
            at("/admin/bill_creator/42/pipeline?selected_stages=");

            act(() => result.current.setSelectedStages(["fetch-bills", "extract-text"]));
            flushDebounce();
            expect(visitUrl()).toBe("/admin/bill_creator/42/pipeline");
            expect(visitData()?.selected_stages).toEqual(["fetch-bills", "extract-text"]);

            routerVisit.mockReset();
            at("/admin/bill_creator/42/pipeline?selected_stages[]=fetch-bills&selected_stages[]=extract-text");

            act(() => result.current.setSelectedStages([...DEFAULT_STAGE_KEYS]));
            flushDebounce();
            expect(visitUrl()).toBe("/admin/bill_creator/42/pipeline");
            expect(visitData()).not.toHaveProperty("selected_stages");
            expect(stripClearedQueryParams(visitUrl())).toBe("/admin/bill_creator/42/pipeline");

            routerVisit.mockReset();
            at("/admin/bill_creator/42/pipeline");

            act(() => result.current.setSelectedStages([]));
            flushDebounce();
            expect(visitUrl()).toBe("/admin/bill_creator/42/pipeline?selected_stages=");
            expect(stripClearedQueryParams(visitUrl())).toBe("/admin/bill_creator/42/pipeline?selected_stages=");
        });
    });

    describe("Navigation Carry & Visit Interceptor Edge Cases", () => {
        it("applyNavigationCarryToVisit carries selected_stages= when allowed parameter", () => {
            at("/admin/bill_creator/42/pipeline?selected_stages=&run_id=99");
            const visit = {
                url: new URL("http://localhost/admin/bill_creator/42/summary"),
                method: "get" as const,
                data: {},
            } as any;

            applyNavigationCarryToVisit(visit, {
                allowedParameters: ["selected_stages", "run_id"],
                currentUrl: new URL("http://localhost/admin/bill_creator/42/pipeline?selected_stages=&run_id=99"),
            });

            const carriedUrl = visit.url instanceof URL ? visit.url : new URL(visit.url, "http://localhost");
            expect(carriedUrl.searchParams.has("selected_stages")).toBe(true);
            expect(carriedUrl.searchParams.get("selected_stages")).toBe("");
            expect(carriedUrl.searchParams.get("run_id")).toBe("99");
        });

        it("stripClearedQueryParams removes generic cleared parameters but leaves intentional empty list", () => {
            const input = "/admin/bill_creator/42/pipeline?run_id=&search=&selected_stages=";
            const stripped = stripClearedQueryParams(input);
            expect(stripped).toBe("/admin/bill_creator/42/pipeline?selected_stages=");
            expect(stripped).not.toContain("run_id");
            expect(stripped).not.toContain("search");
        });

        it("stripClearedQueryParams completely strips query string when only generic cleared parameters exist", () => {
            const input = "/admin/bill_creator/42/pipeline?run_id=&search=";
            const stripped = stripClearedQueryParams(input);
            expect(stripped).toBe("/admin/bill_creator/42/pipeline");
            expect(stripped).not.toContain("?");
        });
    });
});
