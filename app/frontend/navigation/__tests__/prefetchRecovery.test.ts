import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { router, http, HttpNetworkError } from "@inertiajs/core";
import { clearReloadCoalescing } from "app/frontend/navigation/coalesceReloads";

// @lat: [[system-shape#What a reader sees during the round trip#Transport failures need a handled exit]]
describe("Prefetch navigation recovery after transport failure", () => {
    let originalClient: ReturnType<typeof http.getClient>;
    let requests = 0;
    let failHttp = true;
    let unhandledRejections: unknown[] = [];

    const onUnhandled = (reason: unknown) => {
        unhandledRejections.push(reason);
    };

    beforeEach(() => {
        clearReloadCoalescing();
        requests = 0;
        failHttp = true;
        unhandledRejections = [];
        process.on("unhandledRejection", onUnhandled);

        originalClient = http.getClient();

        // Stub DOM gaps in JSDOM
        if (typeof window.performance.getEntriesByType !== "function") {
            window.performance.getEntriesByType = () => [];
        }
        window.scrollTo = vi.fn<() => void>();

        router.init({
            initialPage: {
                component: "Legislators",
                props: { errors: {} },
                url: "/legislators",
                version: "test",
                clearHistory: false,
                encryptHistory: false,
                rescuedProps: [],
                flash: {},
                rememberedState: {},
            },
            resolveComponent: async (name: string) => ({ name }),
            swapComponent: async () => {},
        });

        http.setClient({
            request: async (config) => {
                requests++;
                if (failHttp) {
                    throw new HttpNetworkError("Network error", config.url);
                }
                const url = new URL(config.url, "https://sway.test");
                const component = url.pathname === "/organizations" ? "Organizations" : "Bills";
                return {
                    status: 200,
                    headers: { "x-inertia": "true" },
                    data: JSON.stringify({
                        component,
                        props: { errors: {} },
                        url: url.pathname,
                        version: "test",
                    }),
                };
            },
        });
    });

    afterEach(() => {
        process.off("unhandledRejection", onUnhandled);
        clearReloadCoalescing();
        router.flushAll();
        http.setClient(originalClient);
    });

    const pause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

    it("purges in-flight prefetch cache on transport failure and enables recovered navigation", async () => {
        // Step 1: Trigger prefetch during offline network state
        router.prefetch("/bills", {}, { cacheFor: "1s" });
        await pause(60);

        // Assert: 1 prefetch request was attempted, in-flight entry was purged, zero unhandled rejections
        expect(requests).toBe(1);
        expect(router.getPrefetching("/bills")).toBeNull();
        expect(unhandledRejections).toHaveLength(0);

        // Step 2: Restore connectivity and perform user navigation to identical URL
        failHttp = false;
        let successCalled = false;

        router.visit("/bills", {
            onSuccess: () => {
                successCalled = true;
            },
        });
        await pause(60);

        // Assert: Request count advanced to 2 (fresh network request), visit succeeded, zero unhandled rejections
        expect(requests).toBe(2);
        expect(successCalled).toBe(true);
        expect(router.getPrefetching("/bills")).toBeNull();
        expect(unhandledRejections).toHaveLength(0);
    });

    it("handles prefetch URLs with query parameters and hash fragments", async () => {
        router.prefetch("/bills?sort=name#top", {}, { cacheFor: "1s" });
        await pause(60);

        expect(requests).toBe(1);
        expect(router.getPrefetching("/bills?sort=name#top")).toBeNull();
        expect(unhandledRejections).toHaveLength(0);

        failHttp = false;
        let successCalled = false;
        router.visit("/bills?sort=name#top", {
            onSuccess: () => {
                successCalled = true;
            },
        });
        await pause(60);

        expect(requests).toBe(2);
        expect(successCalled).toBe(true);
        expect(unhandledRejections).toHaveLength(0);
    });

    it("clears multiple in-flight prefetch requests on transport failure without unhandled rejections", async () => {
        router.prefetch("/bills", {}, { cacheFor: "1s" });
        router.prefetch("/organizations", {}, { cacheFor: "1s" });
        await pause(60);

        expect(requests).toBe(2);
        expect(router.getPrefetching("/bills")).toBeNull();
        expect(router.getPrefetching("/organizations")).toBeNull();
        expect(unhandledRejections).toHaveLength(0);

        // Both destinations recover cleanly upon restored connectivity
        failHttp = false;
        let visitedBills = false;
        let visitedOrgs = false;

        router.visit("/bills", {
            onSuccess: () => {
                visitedBills = true;
            },
        });
        await pause(60);
        expect(visitedBills).toBe(true);
        expect(requests).toBe(3);

        router.visit("/organizations", {
            onSuccess: () => {
                visitedOrgs = true;
            },
        });
        await pause(60);
        expect(visitedOrgs).toBe(true);
        expect(requests).toBe(4);
        expect(unhandledRejections).toHaveLength(0);
    });

    it("preserves background reload cooldown reset on transport failure", async () => {
        // Background reload fails due to network outage
        router.reload({ only: ["bill_score"] });
        await pause(60);

        expect(requests).toBe(1);
        expect(unhandledRejections).toHaveLength(0);

        // Failure reset cooldown so immediate retry succeeds
        failHttp = false;
        router.reload({ only: ["bill_score"] });
        await pause(60);

        expect(requests).toBe(2);
        expect(unhandledRejections).toHaveLength(0);
    });

    it("does not suppress non-transport errors to maintain defect visibility", () => {
        const typeError = new TypeError("Cannot read properties of undefined");
        const event = new CustomEvent("inertia:networkError", {
            cancelable: true,
            detail: { error: typeError },
        });

        document.dispatchEvent(event);

        expect(event.defaultPrevented).toBe(false);
    });
});
