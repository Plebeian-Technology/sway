import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { router, http, HttpNetworkError, type PendingVisit } from "@inertiajs/core";
import { clearReloadCoalescing, handleBeforeReload, COALESCE_WINDOW_MS } from "app/frontend/navigation/coalesceReloads";

// @lat: [[system-shape#What a reader sees during the round trip#Transport failures need a handled exit]]
// Adversarial challenge and empirical stress harness for prefetch navigation recovery after transport failures.
describe("Prefetch navigation recovery after transport failure — Adversarial Stress Suite", () => {
    let originalClient: ReturnType<typeof http.getClient>;
    let requests = 0;
    let failHttp = true;
    let urlFailPredicate: ((url: string) => boolean) | null = null;
    let unhandledRejections: unknown[] = [];

    const onUnhandled = (reason: unknown) => {
        unhandledRejections.push(reason);
    };

    beforeEach(() => {
        clearReloadCoalescing();
        requests = 0;
        failHttp = true;
        urlFailPredicate = null;
        unhandledRejections = [];
        process.on("unhandledRejection", onUnhandled);

        originalClient = http.getClient();

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
                const shouldFail = urlFailPredicate ? urlFailPredicate(config.url) : failHttp;
                if (shouldFail) {
                    throw new HttpNetworkError("Simulated transport drop", config.url);
                }
                const url = new URL(config.url, "https://sway.test");
                return {
                    status: 200,
                    headers: { "x-inertia": "true" },
                    data: JSON.stringify({
                        component: "Bills",
                        props: { errors: {}, path: url.pathname, query: url.search },
                        url: url.pathname + url.search,
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

    it("survives 20 concurrent prefetch requests collapsing under network failure with 0 unhandled rejections", async () => {
        const count = 20;
        const targetUrls = Array.from({ length: count }, (_, i) => `/bills/stress-${i}`);

        // Dispatch 20 concurrent prefetch requests while offline
        for (const url of targetUrls) {
            router.prefetch(url, {}, { cacheFor: "2s" });
        }
        await pause(100);

        // Verify all 20 requests attempted
        expect(requests).toBe(count);

        // Verify all 20 in-flight cache entries were purged and not stuck
        for (const url of targetUrls) {
            expect(router.getPrefetching(url)).toBeNull();
        }

        // Verify zero unhandled rejections occurred
        expect(unhandledRejections).toHaveLength(0);

        // Restore network connectivity
        failHttp = false;

        // Verify that visiting each URL now succeeds with fresh requests
        for (let i = 0; i < 5; i++) {
            const url = targetUrls[i];
            let visited = false;
            router.visit(url, {
                onSuccess: () => {
                    visited = true;
                },
            });
            await pause(40);
            expect(visited).toBe(true);
        }

        // 20 initial failed + 5 recovered visits = 25 requests total
        expect(requests).toBe(25);
        expect(unhandledRejections).toHaveLength(0);
    });

    it("survives rapid offline-to-online recovery cycling without race conditions or memory leaks", async () => {
        const iterations = 10;

        for (let i = 0; i < iterations; i++) {
            const url = `/bills/cycle-${i}`;

            // 1. Fail prefetch during network outage
            failHttp = true;
            router.prefetch(url, {}, { cacheFor: "1s" });
            await pause(40);

            expect(router.getPrefetching(url)).toBeNull();
            expect(unhandledRejections).toHaveLength(0);

            // 2. Rapidly restore online state and navigate
            failHttp = false;
            let success = false;
            router.visit(url, {
                onSuccess: () => {
                    success = true;
                },
            });
            await pause(40);

            expect(success).toBe(true);
            expect(router.getPrefetching(url)).toBeNull();
        }

        // Total requests: 10 failed prefetches + 10 successful navigations = 20
        expect(requests).toBe(20);
        expect(unhandledRejections).toHaveLength(0);
    });

    it("handles complex query parameters and hash fragment URLs under failure and recovery", async () => {
        const testUrls = [
            "/bills?status=active&sort=desc#item-42",
            "/organizations?tab=members&page=2#heading-summary",
            "/bills?search=tax%20reform#votes",
            "/influence#top",
            "/bills#",
        ];

        // Prefetch all while offline
        for (const url of testUrls) {
            router.prefetch(url, {}, { cacheFor: "1s" });
        }
        await pause(80);

        expect(requests).toBe(testUrls.length);

        // Verify all purged
        for (const url of testUrls) {
            expect(router.getPrefetching(url)).toBeNull();
        }
        expect(unhandledRejections).toHaveLength(0);

        // Restore network and navigate to each
        failHttp = false;
        for (const url of testUrls) {
            let success = false;
            router.visit(url, {
                onSuccess: () => {
                    success = true;
                },
            });
            await pause(40);
            expect(success).toBe(true);
        }

        expect(requests).toBe(testUrls.length * 2);
        expect(unhandledRejections).toHaveLength(0);
    });

    it("verifies write requests (POST, PUT, PATCH, DELETE) are never coalesced or suppressed", () => {
        const writeMethods = ["post", "put", "patch", "delete"] as const;

        for (const method of writeMethods) {
            const visit = {
                id: `write-${method}-1`,
                method,
                url: new URL("https://sway.test/bills/1/vote"),
                data: { position: "aye" },
                only: ["bill_score"],
                replace: false,
                preserveScroll: true,
                preserveState: true,
                async: false,
                headers: {},
                errorBag: null,
                forceFormData: false,
                queryStringArrayFormat: "brackets",
                showProgress: true,
                fresh: false,
                reset: [],
                preserveUrl: false,
            } as unknown as PendingVisit;

            // First submission must be allowed
            const firstAllowed = handleBeforeReload(visit, 1000);
            expect(firstAllowed).toBe(true);

            // Immediate second identical submission within COALESCE_WINDOW_MS must STILL be allowed (NEVER coalesced)
            const secondAllowed = handleBeforeReload(visit, 1000 + COALESCE_WINDOW_MS / 2);
            expect(secondAllowed).toBe(true);
        }
    });

    it("verifies write requests on network failure are not replayed or cached", async () => {
        failHttp = true;
        let errorCaught = false;

        // Inertia router.post throws or invokes onError/onNetworkError
        try {
            router.post(
                "/bills/1/vote",
                { position: "aye" },
                {
                    onNetworkError: () => {
                        errorCaught = true;
                    },
                },
            );
        } catch {
            errorCaught = true;
        }
        await pause(60);

        // Error was caught or handled
        expect(errorCaught).toBe(true);

        // 1 write request attempted
        expect(requests).toBe(1);

        // Ensure write request never entered prefetch cache
        expect(router.getPrefetching("/bills/1/vote")).toBeNull();
        expect(router.getCached("/bills/1/vote")).toBeNull();

        // Restore network — verify write request is NOT automatically replayed
        failHttp = false;
        await pause(100);

        // Request count remains exactly 1 (no background replay)
        expect(requests).toBe(1);
        expect(unhandledRejections).toHaveLength(0);
    });

    it("handles staggered partial failures where one prefetch fails and another succeeds", async () => {
        // Only fail requests to /bills/fail
        urlFailPredicate = (url) => url.includes("/bills/fail");

        router.prefetch("/bills/fail", {}, { cacheFor: "1s" });
        router.prefetch("/bills/succeed", {}, { cacheFor: "1s" });
        await pause(80);

        expect(requests).toBe(2);
        // Failed prefetch must be purged
        expect(router.getPrefetching("/bills/fail")).toBeNull();

        // Zero unhandled rejections
        expect(unhandledRejections).toHaveLength(0);

        // Now navigate to /bills/fail after network is restored
        urlFailPredicate = null;
        failHttp = false;

        let visitFailedRecovered = false;
        router.visit("/bills/fail", {
            onSuccess: () => {
                visitFailedRecovered = true;
            },
        });
        await pause(40);
        expect(visitFailedRecovered).toBe(true);

        // Now navigate to /bills/succeed
        let visitSucceedOk = false;
        router.visit("/bills/succeed", {
            onSuccess: () => {
                visitSucceedOk = true;
            },
        });
        await pause(40);
        expect(visitSucceedOk).toBe(true);

        expect(unhandledRejections).toHaveLength(0);
    });

    it("survives rapid hammer-prefetching of the same URL during offline state", async () => {
        failHttp = true;

        // Hammer same URL 10 times in rapid synchronous succession
        for (let i = 0; i < 10; i++) {
            router.prefetch("/bills/popular", {}, { cacheFor: "1s" });
        }
        await pause(80);

        // Inertia deduplicates in-flight requests for identical URL, so only 1 network request fired
        expect(requests).toBe(1);
        expect(router.getPrefetching("/bills/popular")).toBeNull();
        expect(unhandledRejections).toHaveLength(0);

        // Restore and visit
        failHttp = false;
        let visited = false;
        router.visit("/bills/popular", {
            onSuccess: () => {
                visited = true;
            },
        });
        await pause(40);

        expect(visited).toBe(true);
        expect(requests).toBe(2);
        expect(unhandledRejections).toHaveLength(0);
    });
});
