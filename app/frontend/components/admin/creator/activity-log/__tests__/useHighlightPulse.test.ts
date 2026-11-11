// @lat: [[activity-log-stream#Why the highlight param is removed after use]]
// @lat: [[query-parameter-navigation-carry#The cleared-on-purpose signal]]

import { cleanup, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { router } from "@inertiajs/react";
import { useHighlightPulse } from "app/frontend/components/admin/creator/activity-log/useHighlightPulse";
import { isQueryParamCleared, stripClearedQueryParams } from "app/frontend/sway_utils/queryParamClearedSignal";

const CARRIED_REGISTRY = new Set([
    "bill_creator_tab",
    "tab_key",
    "bills_sort",
    "bills_direction",
    "bills_page",
    "bills_search",
    "sort",
    "direction",
    "page",
    "search",
    "legislators_tab",
    "legislators_search",
    "notifications_tab",
    "org_tab",
    "sway_locale_id",
    "run_id",
    "highlight_bill_id",
]);

function applyNavigationCarry(arrivalUrl: string, currentUrl: string, destinationPath: string): URL {
    const arrivalParams = new URL(arrivalUrl, "https://sway.test").searchParams;
    const currentParams = new URL(currentUrl, "https://sway.test").searchParams;
    const dest = new URL(destinationPath, "https://sway.test");

    for (const [key, value] of currentParams.entries()) {
        dest.searchParams.set(key, value);
    }

    for (const [key, value] of arrivalParams.entries()) {
        if (isQueryParamCleared(currentParams, key)) {
            continue;
        }

        if (!currentParams.has(key)) {
            if (key === "highlight" || CARRIED_REGISTRY.has(key)) {
                dest.searchParams.set(key, value);
            }
        } else {
            if (!CARRIED_REGISTRY.has(key)) {
                dest.searchParams.delete(key);
            }
        }
    }

    stripClearedQueryParams(dest);
    return dest;
}

describe("useHighlightPulse — one-shot highlight clearing signal", () => {
    let replaceStateSpy: ReturnType<typeof vi.spyOn>;
    let targetRow: HTMLDivElement;
    let scrollIntoViewMock: ReturnType<typeof vi.fn<(...args: unknown[]) => void>>;

    beforeEach(() => {
        targetRow = document.createElement("div");
        targetRow.id = "activity-log-entry-42";
        scrollIntoViewMock = vi.fn<(...args: unknown[]) => void>();
        targetRow.scrollIntoView = scrollIntoViewMock;
        document.body.appendChild(targetRow);

        replaceStateSpy = vi.spyOn(history, "replaceState").mockImplementation(() => {});

        Object.defineProperty(window, "location", {
            value: Object.assign(Object.create(Object.getPrototypeOf(window.location)), window.location, {
                search: "?highlight=42",
                pathname: "/admin/bills/pipeline",
                href: "https://sway.test/admin/bills/pipeline?highlight=42",
            }),
            writable: true,
        });
    });

    afterEach(() => {
        replaceStateSpy.mockRestore();
        cleanup();
        targetRow.remove();
    });

    it("mounts with a highlight in the address, asserts the pulse runs once, and asserts the outgoing address marks the parameter cleared rather than merely omitting it", () => {
        renderHook(() => useHighlightPulse());

        expect(scrollIntoViewMock).toHaveBeenCalledTimes(1);
        expect(targetRow.classList.contains("animate-[activity-log-pulse_3s_ease-out_1_forwards]")).toBe(true);

        expect(replaceStateSpy).toHaveBeenCalledTimes(1);
        const replacedUrl = replaceStateSpy.mock.calls[0][2] as string;
        const searchParams = new URL(replacedUrl, "https://sway.test").searchParams;

        expect(searchParams.has("highlight")).toBe(true);
        expect(searchParams.get("highlight")).toBe("");
        expect(isQueryParamCleared(searchParams, "highlight")).toBe(true);
    });

    it("drives a second navigation after the pulse and asserts the highlight parameter is not carried onto it", () => {
        const arrivalUrl = window.location.href;

        renderHook(() => useHighlightPulse());

        expect(replaceStateSpy).toHaveBeenCalledTimes(1);
        const replacedUrl = replaceStateSpy.mock.calls[0][2] as string;
        const currentUrl = new URL(replacedUrl, "https://sway.test");

        expect(isQueryParamCleared(currentUrl.searchParams, "highlight")).toBe(true);

        const destination = applyNavigationCarry(arrivalUrl, currentUrl.toString(), "/admin/bills/summary");

        expect(destination.searchParams.has("highlight")).toBe(false);
        expect(destination.toString()).not.toContain("highlight");
    });

    it("covers the non-mounting case: with the activity log not rendered, a navigation must not carry a highlight that arrived in the address", () => {
        const arrivalUrl = "https://sway.test/admin/bill_creator/42/creator?highlight=42";
        const currentUnmountedUrl = arrivalUrl;

        const destination = applyNavigationCarry(arrivalUrl, currentUnmountedUrl, "/admin/bill_creator/42/summary");

        expect(destination.searchParams.has("highlight")).toBe(false);
        expect(destination.toString()).not.toContain("highlight");
    });

    it("re-applies highlight clearance when an Inertia navigate event occurs with highlight restored by an asynchronous history write", () => {
        let navigateCallback: (() => void) | undefined;
        const onSpy = vi.spyOn(router, "on").mockImplementation(((
            event: string,
            callback: (...args: unknown[]) => void,
        ) => {
            if (event === "navigate") {
                navigateCallback = callback as () => void;
            }
            return () => {};
        }) as unknown as typeof router.on);

        renderHook(() => useHighlightPulse());

        expect(replaceStateSpy).toHaveBeenCalledTimes(1);

        window.location.search = "?highlight=42";
        window.location.href = "https://sway.test/admin/bills/pipeline?highlight=42";

        expect(navigateCallback).toBeDefined();
        navigateCallback!();

        expect(replaceStateSpy).toHaveBeenCalledTimes(2);
        const secondReplacedUrl = replaceStateSpy.mock.calls[1][2] as string;
        const searchParams = new URL(secondReplacedUrl, "https://sway.test").searchParams;
        expect(searchParams.get("highlight")).toBe("");
        expect(isQueryParamCleared(searchParams, "highlight")).toBe(true);

        onSpy.mockRestore();
    });

    it("unregisters Inertia event listeners and cleans up timers on unmount", () => {
        const unregisterNavigate = vi.fn<() => void>();
        const unregisterFinish = vi.fn<() => void>();
        const onSpy = vi.spyOn(router, "on").mockImplementation(((event: string) => {
            if (event === "navigate") return unregisterNavigate;
            if (event === "finish") return unregisterFinish;
            return () => {};
        }) as unknown as typeof router.on);

        const { unmount } = renderHook(() => useHighlightPulse());

        expect(unregisterNavigate).not.toHaveBeenCalled();
        expect(unregisterFinish).not.toHaveBeenCalled();

        unmount();

        expect(unregisterNavigate).toHaveBeenCalledTimes(1);
        expect(unregisterFinish).toHaveBeenCalledTimes(1);

        onSpy.mockRestore();
    });

    it("does not redundantly call replaceState when navigate event fires if highlight is already cleared", () => {
        let navigateCallback: (() => void) | undefined;
        const onSpy = vi.spyOn(router, "on").mockImplementation(((
            event: string,
            callback: (...args: unknown[]) => void,
        ) => {
            if (event === "navigate") {
                navigateCallback = callback as () => void;
            }
            return () => {};
        }) as unknown as typeof router.on);

        renderHook(() => useHighlightPulse());
        expect(replaceStateSpy).toHaveBeenCalledTimes(1);

        window.location.search = "?highlight=";
        window.location.href = "https://sway.test/admin/bills/pipeline?highlight=";

        navigateCallback!();

        expect(replaceStateSpy).toHaveBeenCalledTimes(1);

        onSpy.mockRestore();
    });

    it("clears the highlight parameter even if the target entry is absent from the DOM", () => {
        targetRow.remove();

        renderHook(() => useHighlightPulse());

        expect(replaceStateSpy).toHaveBeenCalledTimes(1);
        const replacedUrl = replaceStateSpy.mock.calls[0][2] as string;
        const searchParams = new URL(replacedUrl, "https://sway.test").searchParams;
        expect(isQueryParamCleared(searchParams, "highlight")).toBe(true);
    });
});
