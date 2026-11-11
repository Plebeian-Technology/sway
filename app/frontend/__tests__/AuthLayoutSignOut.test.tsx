// @lat: [[auth-layout-sign-out-overlay-bug#Why the sign-out handler must clear its overlay on failure]]

import { afterEach, describe, expect, it, vi } from "vitest";
import { makeSignOutHandler } from "app/frontend/components/layouts/signOutHandler";

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

afterEach(() => vi.restoreAllMocks());

describe("makeSignOutHandler", () => {
    it("sets loading true immediately, then resets it when logout rejects", async () => {
        vi.spyOn(console, "error").mockImplementation(() => {});
        const setIsLoading = vi.fn<(loading: boolean) => void>();
        const logout = vi.fn<() => Promise<unknown>>(() => Promise.reject(new Error("boom")));

        makeSignOutHandler(logout, setIsLoading)();

        expect(setIsLoading).toHaveBeenNthCalledWith(1, true);
        await flush();
        expect(setIsLoading).toHaveBeenNthCalledWith(2, false);
    });

    it("keeps the overlay up while logout is still pending (inertia:finish clears it)", async () => {
        const setIsLoading = vi.fn<(loading: boolean) => void>();
        const logout = vi.fn<() => Promise<void>>(() => new Promise<void>(() => {})); // never settles

        makeSignOutHandler(logout, setIsLoading)();
        await flush();

        expect(setIsLoading).toHaveBeenCalledTimes(1);
        expect(setIsLoading).toHaveBeenCalledWith(true);
    });
});
