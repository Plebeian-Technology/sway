// @lat: [[mobile-jest-first-pass-test-notes#useSession.test.ts]]
import { renderHook, act, waitFor } from "@testing-library/react-native";

import { apiClient } from "../../src/api/client";
import { tokenStore } from "../../src/auth/tokenStore";
import { sessionStore } from "../../src/auth/sessionStore";
import { authEvents } from "../../src/auth/authEvents";
import { purgeAll } from "../../src/cache/db";
import { bootstrapCache } from "../../src/cache/bootstrapCache";
import { useSession } from "../../src/hooks/useSession";

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: jest.fn(),
        post: jest.fn(async () => undefined),
        patch: jest.fn(),
        delete: jest.fn(async () => undefined),
    },
}));

jest.mock("../../src/auth/tokenStore", () => ({
    tokenStore: {
        get: jest.fn(),
        set: jest.fn(async () => {}),
        clear: jest.fn(async () => {}),
    },
}));

jest.mock("../../src/auth/sessionStore", () => ({
    sessionStore: {
        get: jest.fn(),
        set: jest.fn(async () => {}),
        clear: jest.fn(async () => {}),
    },
}));

jest.mock("../../src/cache/db", () => ({
    purgeAll: jest.fn(async () => {}),
    openDatabase: jest.fn(),
}));

jest.mock("../../src/cache/bootstrapCache", () => ({
    bootstrapCache: {
        get: jest.fn(),
        set: jest.fn(),
        purge: jest.fn(async () => {}),
    },
}));

const mockClearCapturedCategories = jest.fn();
jest.mock("../../src/hooks/useBills", () => ({
    clearCapturedCategories: (...args: unknown[]) => mockClearCapturedCategories(...args),
}));

describe("useSession", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("stops loading and reports signed-out when the session read throws", async () => {
        (sessionStore.get as jest.Mock).mockRejectedValueOnce(new Error("keychain unavailable"));
        const consoleError = jest.spyOn(console, "error").mockImplementation(() => {});

        const { result } = renderHook(() => useSession());
        await waitFor(() => expect(result.current.loading).toBe(false));

        expect(result.current.isAuthenticated).toBe(false);
        consoleError.mockRestore();
    });

    test("initializes isAuthenticated=false when sessionStore is empty", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue(null);
        const { result } = renderHook(() => useSession());
        await act(async () => {});
        expect(result.current.isAuthenticated).toBe(false);
        expect(result.current.loading).toBe(false);
    });

    test("initializes isAuthenticated=true when sessionStore has bearer_token", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk_x",
            device_id: 1,
            user_id: 2,
            expires_at: "2026-12-31T00:00:00Z",
        });
        const { result } = renderHook(() => useSession());
        await act(async () => {});
        expect(result.current.isAuthenticated).toBe(true);
    });

    test("signOut reads sessionStore.get() and DELETEs /api/v1/devices/:device_id (D2)", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 12345,
            user_id: 7,
            expires_at: "2026-12-31T00:00:00Z",
        });
        const emitSpy = jest.spyOn(authEvents, "emit");
        const { result } = renderHook(() => useSession());
        await act(async () => {});

        await act(async () => {
            await result.current.signOut();
        });

        expect(sessionStore.get).toHaveBeenCalled();
        expect(apiClient.delete).toHaveBeenCalledWith("/api/v1/devices/12345");
        expect(tokenStore.clear).toHaveBeenCalled();
        expect(sessionStore.clear).toHaveBeenCalled();
        expect(purgeAll).toHaveBeenCalled();
        expect(bootstrapCache.purge).toHaveBeenCalled();
        expect(mockClearCapturedCategories).toHaveBeenCalled();
        expect(emitSpy).toHaveBeenCalledWith("signed_out");
    });

    test("signOut still clears local state when apiClient.delete throws", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 999,
            user_id: 7,
            expires_at: "2026-12-31T00:00:00Z",
        });
        (apiClient.delete as jest.Mock).mockRejectedValueOnce(new Error("network down"));

        const { result } = renderHook(() => useSession());
        await act(async () => {});
        await act(async () => {
            await result.current.signOut();
        });

        expect(tokenStore.clear).toHaveBeenCalled();
        expect(sessionStore.clear).toHaveBeenCalled();
        expect(purgeAll).toHaveBeenCalled();
        expect(bootstrapCache.purge).toHaveBeenCalled();
        expect(mockClearCapturedCategories).toHaveBeenCalled();
    });

    test("signOut skips DELETE when sessionStore is empty (no device_id)", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue(null);
        const { result } = renderHook(() => useSession());
        await act(async () => {});
        await act(async () => {
            await result.current.signOut();
        });
        expect(apiClient.delete).not.toHaveBeenCalled();
        expect(tokenStore.clear).toHaveBeenCalled();
        expect(sessionStore.clear).toHaveBeenCalled();
    });

    test("signOutAll POSTs /api/v1/sessions/revoke_all and clears local state", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 1,
            user_id: 2,
            expires_at: "2026-12-31T00:00:00Z",
        });
        const emitSpy = jest.spyOn(authEvents, "emit");

        const { result } = renderHook(() => useSession());
        await act(async () => {});
        await act(async () => {
            await result.current.signOutAll();
        });

        expect(apiClient.post).toHaveBeenCalledWith("/api/v1/sessions/revoke_all", {});
        expect(tokenStore.clear).toHaveBeenCalled();
        expect(sessionStore.clear).toHaveBeenCalled();
        expect(purgeAll).toHaveBeenCalled();
        expect(bootstrapCache.purge).toHaveBeenCalled();
        expect(mockClearCapturedCategories).toHaveBeenCalled();
        expect(emitSpy).toHaveBeenCalledWith("signed_out");
    });

    test("signOutAll still clears local state when revoke_all POST throws", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 1,
            user_id: 2,
            expires_at: "2026-12-31T00:00:00Z",
        });
        (apiClient.post as jest.Mock).mockRejectedValueOnce(new Error("nope"));
        const { result } = renderHook(() => useSession());
        await act(async () => {});
        await act(async () => {
            await result.current.signOutAll();
        });
        expect(tokenStore.clear).toHaveBeenCalled();
        expect(sessionStore.clear).toHaveBeenCalled();
        expect(purgeAll).toHaveBeenCalled();
        expect(bootstrapCache.purge).toHaveBeenCalled();
        expect(mockClearCapturedCategories).toHaveBeenCalled();
    });

    test("authEvents 'signed_in' flips isAuthenticated to true", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue(null);
        const { result } = renderHook(() => useSession());
        await act(async () => {});
        expect(result.current.isAuthenticated).toBe(false);
        await act(async () => {
            authEvents.emit("signed_in");
        });
        expect(result.current.isAuthenticated).toBe(true);
    });

    test("authEvents 'unauthenticated' flips isAuthenticated to false", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 1,
            user_id: 2,
            expires_at: "2026-12-31T00:00:00Z",
        });
        const { result } = renderHook(() => useSession());
        await act(async () => {});
        expect(result.current.isAuthenticated).toBe(true);
        await act(async () => {
            authEvents.emit("unauthenticated");
        });
        expect(result.current.isAuthenticated).toBe(false);
    });

    test("authEvents 'unauthenticated' wipes local caches", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 1,
            user_id: 2,
            expires_at: "2026-12-31T00:00:00Z",
        });
        (purgeAll as jest.Mock).mockClear();
        (bootstrapCache.purge as jest.Mock).mockClear();
        mockClearCapturedCategories.mockClear();

        renderHook(() => useSession());
        await act(async () => {});
        await act(async () => {
            authEvents.emit("unauthenticated");
        });
        // Give the fire-and-forget wipeLocalCaches() call time to finish.
        await act(async () => {
            await new Promise((r) => setImmediate(r));
        });

        expect(purgeAll).toHaveBeenCalled();
        expect(bootstrapCache.purge).toHaveBeenCalled();
        expect(mockClearCapturedCategories).toHaveBeenCalled();
    });

    test("deduplicates concurrent wipeLocalCaches calls across multiple mounted useSession instances on 'unauthenticated'", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 1,
            user_id: 2,
            expires_at: "2026-12-31T00:00:00Z",
        });

        let resolvePurge!: () => void;
        (purgeAll as jest.Mock).mockImplementationOnce(
            () =>
                new Promise<void>((resolve) => {
                    resolvePurge = resolve;
                }),
        );

        renderHook(() => useSession());
        renderHook(() => useSession());
        renderHook(() => useSession());
        await act(async () => {});

        (purgeAll as jest.Mock).mockClear();
        (bootstrapCache.purge as jest.Mock).mockClear();
        mockClearCapturedCategories.mockClear();

        await act(async () => {
            authEvents.emit("unauthenticated");
        });

        expect(purgeAll).toHaveBeenCalledTimes(1);
        expect(bootstrapCache.purge).toHaveBeenCalledTimes(1);
        expect(mockClearCapturedCategories).toHaveBeenCalledTimes(1);

        await act(async () => {
            resolvePurge();
            await new Promise((r) => setImmediate(r));
        });
    });

    test("signOut({ skipServerRevoke: true }) clears local state and emits signed_out without calling apiClient.delete", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue({
            bearer_token: "tk",
            device_id: 12345,
            user_id: 7,
            expires_at: "2026-12-31T00:00:00Z",
        });
        const emitSpy = jest.spyOn(authEvents, "emit");
        const { result } = renderHook(() => useSession());
        await act(async () => {});

        await act(async () => {
            await result.current.signOut({ skipServerRevoke: true });
        });

        expect(apiClient.delete).not.toHaveBeenCalled();
        expect(tokenStore.clear).toHaveBeenCalled();
        expect(sessionStore.clear).toHaveBeenCalled();
        expect(purgeAll).toHaveBeenCalled();
        expect(bootstrapCache.purge).toHaveBeenCalled();
        expect(mockClearCapturedCategories).toHaveBeenCalled();
        expect(emitSpy).toHaveBeenCalledWith("signed_out");
    });

    test("signOut leaves no cache-wipe timeout pending once the wipe has finished", async () => {
        (sessionStore.get as jest.Mock).mockResolvedValue(null);
        jest.useFakeTimers({ doNotFake: ["nextTick", "queueMicrotask", "setImmediate", "clearImmediate"] });
        try {
            const { result } = renderHook(() => useSession());
            await act(async () => {});

            await act(async () => {
                await result.current.signOut();
            });

            expect(jest.getTimerCount()).toBe(0);
        } finally {
            jest.useRealTimers();
        }
    });
});
