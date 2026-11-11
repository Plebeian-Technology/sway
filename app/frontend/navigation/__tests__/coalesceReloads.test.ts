import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { HttpNetworkError, type PendingVisit } from "@inertiajs/core";
import {
    COALESCE_WINDOW_MS,
    getReloadKey,
    handleBeforeReload,
    handleReloadFailure,
    handleReloadFinish,
    clearReloadCoalescing,
    isTransportError,
} from "app/frontend/navigation/coalesceReloads";

const showPage = (pathWithQuery: string): void => {
    window.history.replaceState({}, "", pathWithQuery);
};

describe("coalesceReloads", () => {
    beforeEach(() => {
        clearReloadCoalescing();
        showPage("/bills/1");
        vi.useFakeTimers();
    });

    afterEach(() => {
        vi.useRealTimers();
    });

    const createVisit = (
        only: string[],
        pathname: string = "/bills/1",
        id: string = "visit-1",
        method: string = "get",
    ): PendingVisit => {
        return {
            id,
            url: new URL(pathname, "http://localhost"),
            only,
            except: [],
            reset: [],
            method,
            data: {},
            replace: false,
            preserveScroll: true,
            preserveState: true,
            headers: {},
            errorBag: null,
            forceFormData: false,
            queryStringArrayFormat: "brackets",
            async: true,
            showProgress: false,
            prefetch: false,
            fresh: false,
            preserveUrl: false,
            preserveErrors: false,
            invalidateCacheTags: "",
            viewTransition: false,
            component: null,
            pageProps: null,
            cached: false,
            completed: false,
            cancelled: false,
            interrupted: false,
        } as unknown as PendingVisit;
    };

    it("generates deterministic keys regardless of prop ordering", () => {
        const v1 = createVisit(["bill_score", "organizations"]);
        const v2 = createVisit(["organizations", "bill_score"]);
        expect(getReloadKey(v1)).toBe("/bills/1::bill_score,organizations");
        expect(getReloadKey(v2)).toBe("/bills/1::bill_score,organizations");
    });

    it("keys the query string, so two filter selections are two pages", () => {
        const unfiltered = createVisit(["bills"], "/bills?sway_locale_id=1");
        const filtered = createVisit(["bills"], "/bills?sway_locale_id=1&categories=Housing");
        expect(getReloadKey(unfiltered)).not.toBe(getReloadKey(filtered));
    });

    it("returns null for non-partial visits (no only props)", () => {
        const v = createVisit([]);
        expect(getReloadKey(v)).toBeNull();
        expect(handleBeforeReload(v)).toBe(true);
    });

    it("allows the first reload and suppresses an immediate duplicate for the same props", () => {
        const v1 = createVisit(["bill_score"], "/bills/1", "v-1");
        const v2 = createVisit(["bill_score"], "/bills/1", "v-2");

        // First reload passes
        expect(handleBeforeReload(v1, 1000)).toBe(true);

        // Immediate duplicate at 1100ms (100ms later) is suppressed
        expect(handleBeforeReload(v2, 1100)).toBe(false);
    });

    it("allows a reload with different props within the coalesce window", () => {
        const v1 = createVisit(["bill_score"], "/bills/1", "v-1");
        const v2 = createVisit(["bill"], "/bills/1", "v-2");

        expect(handleBeforeReload(v1, 1000)).toBe(true);
        expect(handleBeforeReload(v2, 1100)).toBe(true);
    });

    it("allows a reload on a different page within the coalesce window", () => {
        const v1 = createVisit(["bill_score"], "/bills/1", "v-1");
        const v2 = createVisit(["bill_score"], "/bills/2", "v-2");

        expect(handleBeforeReload(v1, 1000)).toBe(true);
        showPage("/bills/2");
        expect(handleBeforeReload(v2, 1100)).toBe(true);
    });

    it("allows a subsequent reload after the coalesce window expires", () => {
        const v1 = createVisit(["bill_score"], "/bills/1", "v-1");
        const v2 = createVisit(["bill_score"], "/bills/1", "v-2");

        expect(handleBeforeReload(v1, 1000)).toBe(true);
        // After COALESCE_WINDOW_MS (2000ms), reload passes
        expect(handleBeforeReload(v2, 1000 + COALESCE_WINDOW_MS)).toBe(true);
    });

    it("clears cooldown on failure so a retry proceeds immediately", () => {
        const v1 = createVisit(["bill_score"], "/bills/1", "v-1");
        const v2 = createVisit(["bill_score"], "/bills/1", "v-2");

        expect(handleBeforeReload(v1, 1000)).toBe(true);

        // v1 fails at 1050ms
        handleReloadFailure("v-1");

        // Retry at 1100ms is allowed because failure cleared the window
        expect(handleBeforeReload(v2, 1100)).toBe(true);
    });

    it("clears visit ID mapping on finish without clearing the time cooldown", () => {
        const v1 = createVisit(["bill_score"], "/bills/1", "v-1");
        const v2 = createVisit(["bill_score"], "/bills/1", "v-2");

        expect(handleBeforeReload(v1, 1000)).toBe(true);
        handleReloadFinish("v-1");

        // Finished visit still respects the cooldown
        expect(handleBeforeReload(v2, 1500)).toBe(false);
        expect(handleBeforeReload(v2, 1000 + COALESCE_WINDOW_MS)).toBe(true);
    });

    // @lat: [[system-shape#Keeping scores fresh#Two refreshes of one page collapse into one]]
    it("always sends a visit that navigates away from the page on screen", () => {
        showPage("/bills?sway_locale_id=1");
        const stay = createVisit(["bills"], "/bills?sway_locale_id=1", "v-1");
        const leave = createVisit(["bills"], "/bills?sway_locale_id=1&categories=Housing", "v-2");
        const comeBack = createVisit(["bills"], "/bills?sway_locale_id=1", "v-3");

        expect(handleBeforeReload(stay, 1000)).toBe(true);
        expect(handleBeforeReload(leave, 1100)).toBe(true);
        // Inertia moves the address bar once the visit lands.
        showPage("/bills?sway_locale_id=1&categories=Housing");
        expect(handleBeforeReload(comeBack, 1200)).toBe(true);
    });

    it("always sends a write, and lets the read that follows it through", () => {
        const read = createVisit(["subscriptions"], "/bills/1", "v-1");
        const write = createVisit([], "/bills/1", "v-2", "post");
        const readAgain = createVisit(["subscriptions"], "/bills/1", "v-3");

        expect(handleBeforeReload(read, 1000)).toBe(true);
        expect(handleBeforeReload(write, 1100)).toBe(true);
        expect(handleBeforeReload(readAgain, 1200)).toBe(true);
    });

    it("never suppresses Inertia deferredProps visits even within the coalesce window", () => {
        showPage("/past_bills_of_the_month?sway_locale_id=3");
        const firstDeferred = Object.assign(
            createVisit(["bills"], "/past_bills_of_the_month?sway_locale_id=3", "v-1"),
            { deferredProps: true },
        );
        const secondDeferred = Object.assign(
            createVisit(["bills"], "/past_bills_of_the_month?sway_locale_id=3", "v-2"),
            { deferredProps: true },
        );
        const scoreReload = createVisit(["bills"], "/past_bills_of_the_month?sway_locale_id=3", "v-3");
        const thirdDeferred = Object.assign(
            createVisit(["bills"], "/past_bills_of_the_month?sway_locale_id=3", "v-4"),
            { deferredProps: true },
        );

        expect(handleBeforeReload(firstDeferred, 1000)).toBe(true);
        expect(handleBeforeReload(secondDeferred, 1100)).toBe(true);
        expect(handleBeforeReload(scoreReload, 1200)).toBe(true);
        expect(handleBeforeReload(thirdDeferred, 1300)).toBe(true);
    });

    it("clears reload cooldown on non-prefetch full-page GET navigation so returning within the window reloads", () => {
        showPage("/past_bills_of_the_month?sway_locale_id=3");
        const reloadBeforeLeave = createVisit(["bills"], "/past_bills_of_the_month?sway_locale_id=3", "v-1");
        const fullPageNavigateAway = createVisit([], "/bills?sway_locale_id=3", "v-2");
        const reloadAfterReturn = createVisit(["bills"], "/past_bills_of_the_month?sway_locale_id=3", "v-3");

        expect(handleBeforeReload(reloadBeforeLeave, 1000)).toBe(true);
        expect(handleBeforeReload(fullPageNavigateAway, 1100)).toBe(true);
        expect(handleBeforeReload(reloadAfterReturn, 1200)).toBe(true);
    });

    // @lat: [[system-shape#What a reader sees during the round trip#Transport failures need a handled exit]]
    describe("isTransportError (Handle Inertia transport failures without unhandled rejections)", () => {
        it("returns true for HttpNetworkError instances", () => {
            const error = new HttpNetworkError("Network error", "/bills/1", new Error("connection reset"));
            expect(isTransportError(error)).toBe(true);
        });

        it("returns true for errors with name 'HttpNetworkError'", () => {
            const error = new Error("Transport failed");
            error.name = "HttpNetworkError";
            expect(isTransportError(error)).toBe(true);
        });

        it("returns true for errors with code 'ERR_NETWORK'", () => {
            const error = new Error("Network connectivity lost");
            Object.assign(error, { code: "ERR_NETWORK" });
            expect(isTransportError(error)).toBe(true);
        });

        it("returns false for non-transport errors", () => {
            expect(isTransportError(new TypeError("Cannot read properties of undefined"))).toBe(false);
            expect(isTransportError(new SyntaxError("Unexpected token"))).toBe(false);
            expect(isTransportError(new Error("Generic application failure"))).toBe(false);
            expect(isTransportError(null)).toBe(false);
            expect(isTransportError(undefined)).toBe(false);
            expect(isTransportError({})).toBe(false);
            expect(isTransportError("ERR_NETWORK")).toBe(false);
        });
    });

    // @lat: [[system-shape#What a reader sees during the round trip#Transport failures need a handled exit]]
    describe("networkError event handling (Handle Inertia transport failures without unhandled rejections)", () => {
        it("cancels the event when error is a recognized transport error", () => {
            const error = new HttpNetworkError("Network error", "/bills/1", new Error("offline"));
            const event = new CustomEvent("inertia:networkError", {
                cancelable: true,
                detail: { error },
            });

            document.dispatchEvent(event);

            expect(event.defaultPrevented).toBe(true);
        });

        it("clears reload cooldown on transport error so subsequent reload proceeds immediately", () => {
            const v1 = createVisit(["bill_score"], "/bills/1", "v-1");
            const v2 = createVisit(["bill_score"], "/bills/1", "v-2");

            expect(handleBeforeReload(v1, 1000)).toBe(true);
            expect(handleBeforeReload(v2, 1100)).toBe(false); // Coalesced

            const error = new HttpNetworkError("Network error", "/bills/1", new Error("offline"));
            const event = new CustomEvent("inertia:networkError", {
                cancelable: true,
                detail: { error },
            });
            document.dispatchEvent(event);

            expect(event.defaultPrevented).toBe(true);
            // After transport error, cooldown is reset and subsequent poll/reload proceeds
            expect(handleBeforeReload(v2, 1200)).toBe(true);
        });

        it("does not cancel the event for non-transport errors to preserve defect visibility", () => {
            const typeError = new TypeError("Cannot read properties of undefined (reading 'data')");
            const event = new CustomEvent("inertia:networkError", {
                cancelable: true,
                detail: { error: typeError },
            });

            document.dispatchEvent(event);

            expect(event.defaultPrevented).toBe(false);
        });
    });
});
