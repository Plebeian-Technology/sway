import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
    NAVIGATION_IDLE,
    NAVIGATION_TREATMENT_MAX_MS,
    NAVIGATION_TREATMENT_UNATTRIBUTED_MS,
    navigationSnapshot,
    subscribeNavigation,
} from "app/frontend/navigation/navigationStore";
import { pendingVisitFixture } from "app/frontend/navigation/__tests__/pendingVisitFixture";

// @lat: [[navigation-placeholder-tracer#Why the store sets on before and clears on three attributed events]]

const dispatchInertia = (name: string, detail: Record<string, unknown> = {}): void => {
    document.dispatchEvent(new CustomEvent(`inertia:${name}`, { cancelable: true, detail }));
};

// An attributed clear: a matching before/success pair, which is the only way to reach idle
// synchronously now that the unattributed events only shorten the bound.
const clear = (): void => {
    dispatchInertia("before", {
        visit: pendingVisitFixture({ id: "reset-visit", url: new URL("https://sway.test/bills") }),
    });
    dispatchInertia("success", { page: {}, visitId: "reset-visit" });
};

beforeEach(() => {
    clear();
});

// Leaves no pending watchdog timer behind for the next file.
afterEach(() => {
    clear();
});

describe("navigationStore", () => {
    it("draws the treatment for a prefetch-consuming visit that fires no start and no finish, then clears on success alone", () => {
        dispatchInertia("before", {
            visit: pendingVisitFixture({ id: "visit-a", url: new URL("https://sway.test/bills") }),
        });

        expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);
        expect(navigationSnapshot().dim).toBe(true);

        dispatchInertia("success", { page: {}, visitId: "visit-a" });

        expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
    });

    it("holds visit B's treatment when an interrupted visit A's finish lands after B's before", () => {
        // The order Router#visit produces: B's before fires, then the cancel of the
        // in-flight A fires A's finish synchronously, then B's own success.
        dispatchInertia("before", {
            visit: pendingVisitFixture({ id: "visit-a", url: new URL("https://sway.test/bills") }),
        });
        dispatchInertia("before", {
            visit: pendingVisitFixture({ id: "visit-b", url: new URL("https://sway.test/legislators") }),
        });
        dispatchInertia("finish", {
            visit: pendingVisitFixture({ id: "visit-a", url: new URL("https://sway.test/bills") }),
        });

        const held = navigationSnapshot();
        expect(held).not.toEqual(NAVIGATION_IDLE);
        expect(held.pageName).toBe("Representatives");
        expect(held.placeholder).toBe("list");

        dispatchInertia("success", { page: {}, visitId: "visit-b" });

        expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
    });

    it("holds the treatment when a background poll's finish lands during a navigation", () => {
        dispatchInertia("before", {
            visit: pendingVisitFixture({ id: "visit-b", url: new URL("https://sway.test/legislators") }),
        });
        dispatchInertia("finish", {
            visit: pendingVisitFixture({ id: "poll-visit", only: ["scores"], async: true }),
        });

        expect(navigationSnapshot().placeholder).toBe("list");
        expect(navigationSnapshot().pageName).toBe("Representatives");
    });

    it("releases the treatment on the watchdog when a consumed prefetch fires no clearing event at all", () => {
        vi.useFakeTimers();
        try {
            dispatchInertia("before", {
                visit: pendingVisitFixture({ id: "visit-a", url: new URL("https://sway.test/bills") }),
            });
            expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);

            vi.advanceTimersByTime(NAVIGATION_TREATMENT_MAX_MS - 1);
            expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);

            vi.advanceTimersByTime(1);
            expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
        } finally {
            vi.useRealTimers();
        }
    });

    it("holds the treatment on httpException and releases it on the shortened bound", () => {
        vi.useFakeTimers();
        try {
            dispatchInertia("before", {
                visit: pendingVisitFixture({ id: "visit-a", url: new URL("https://sway.test/bills") }),
            });
            expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);

            // A background poll's 500 must not un-inert the body while the navigation is
            // still downloading its destination chunk.
            dispatchInertia("httpException", { response: { status: 500 } });
            expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);

            vi.advanceTimersByTime(NAVIGATION_TREATMENT_UNATTRIBUTED_MS - 1);
            expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);

            vi.advanceTimersByTime(1);
            expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
        } finally {
            vi.useRealTimers();
        }
    });

    it("leaves the snapshot untouched at idle for a before that does not qualify", () => {
        dispatchInertia("before", {
            visit: pendingVisitFixture({
                only: ["bills"],
                async: true,
                preserveState: true,
                url: new URL("https://sway.test/bills"),
            }),
        });

        expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
    });

    it("holds the treatment when a background poll's networkError lands during a navigation", () => {
        vi.useFakeTimers();
        try {
            dispatchInertia("before", { visit: pendingVisitFixture({ url: new URL("https://sway.test/bills") }) });
            expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);

            dispatchInertia("networkError", { error: new Error("offline") });
            expect(navigationSnapshot()).not.toEqual(NAVIGATION_IDLE);

            vi.advanceTimersByTime(NAVIGATION_TREATMENT_UNATTRIBUTED_MS);
            expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
        } finally {
            vi.useRealTimers();
        }
    });

    it("leaves the snapshot idle when an unattributed failure lands with no treatment up", () => {
        vi.useFakeTimers();
        try {
            dispatchInertia("networkError", { error: new Error("offline") });
            expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);

            vi.advanceTimersByTime(NAVIGATION_TREATMENT_MAX_MS);
            expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
        } finally {
            vi.useRealTimers();
        }
    });

    it("leaves the snapshot idle and notifies subscribers without throwing across duplicate clears", () => {
        const listener = vi.fn<() => void>();
        const unsubscribe = subscribeNavigation(listener);

        dispatchInertia("before", {
            visit: pendingVisitFixture({ id: "visit-a", url: new URL("https://sway.test/bills") }),
        });
        listener.mockClear();

        expect(() => {
            dispatchInertia("finish", {
                visit: pendingVisitFixture({ id: "visit-a", url: new URL("https://sway.test/bills") }),
            });
            dispatchInertia("success", { page: {}, visitId: "visit-a" });
            dispatchInertia("error", { errors: {}, visitId: "visit-a" });
        }).not.toThrow();

        expect(navigationSnapshot()).toEqual(NAVIGATION_IDLE);
        expect(listener).toHaveBeenCalledTimes(3);

        unsubscribe();
    });

    it("subscribeNavigation's returned function stops further notifications", () => {
        const listener = vi.fn<() => void>();
        const unsubscribe = subscribeNavigation(listener);

        unsubscribe();
        dispatchInertia("before", { visit: pendingVisitFixture({ url: new URL("https://sway.test/bills") }) });

        expect(listener).not.toHaveBeenCalled();
    });
});
