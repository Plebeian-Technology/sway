// @lat: [[mobile-jest-first-pass-test-notes#Notification preferences hook mock shape]]
let mockCapturedListener: ((s: string) => void) | null = null;

jest.mock("expo-constants", () => ({
    expoConfig: { version: "0.9.0", extra: { apiBaseUrl: "https://app.sway.vote" } },
}));

const mockCacheGet = jest.fn();
const mockCacheSet = jest.fn();
const mockCachePurge = jest.fn(async () => {});
jest.mock("../../src/cache/bootstrapCache", () => ({
    bootstrapCache: {
        get: (...a: unknown[]) => mockCacheGet(...a),
        set: (...a: unknown[]) => mockCacheSet(...a),
        purge: () => mockCachePurge(),
    },
}));

const mockPurgeAll = jest.fn(async () => {});
jest.mock("../../src/cache/db", () => {
    const actual = jest.requireActual("../../src/cache/db");
    return {
        ...actual,
        purgeAll: () => mockPurgeAll(),
    };
});

const mockApiGet = jest.fn();
const mockSetLocaleId = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...a: unknown[]) => mockApiGet(...a),
        post: jest.fn(),
        patch: jest.fn(),
        delete: jest.fn(),
        setLocaleId: (...a: unknown[]) => mockSetLocaleId(...a),
    },
}));

import React from "react";
import { renderHook, waitFor, act } from "@testing-library/react-native";
import { AppState } from "react-native";
import Constants from "expo-constants";
import { BootstrapProvider, useBootstrap } from "../../src/state/BootstrapContext";
import { authEvents } from "../../src/auth/authEvents";
import { tokenStore } from "../../src/auth/tokenStore";
import { sessionStore } from "../../src/auth/sessionStore";
import { UnauthorizedError } from "../../src/api/errors";
import { prefsCache, PREFS_KEYS } from "../../src/cache/prefsCache";
import { localeOverride } from "../../src/state/localeOverride";
import { getConsumer } from "../../src/channels/consumer";
import * as ActionCable from "@rails/actioncable";

// @lat: [[mobile-expo-config#The Expo config file and the mobile type check#What the mobile test environment has to stand in for]]
jest.spyOn(AppState, "addEventListener").mockImplementation(((evt: string, cb: (s: string) => void) => {
    if (evt === "change") mockCapturedListener = cb;
    return { remove: jest.fn(() => (mockCapturedListener = null)) };
}) as typeof AppState.addEventListener);

const wrap = ({ children }: { children: React.ReactNode }) => React.createElement(BootstrapProvider, null, children);

const sampleBootstrap = {
    current_user: { id: 7 },
    locale: { id: 1 },
    bill_of_the_month: null,
    feature_flags: {},
    unread_notification_count: 0,
    min_supported_version: "0.5.0",
    latest_version: "1.0.0",
};

describe("BootstrapProvider / useBootstrap", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        jest.useFakeTimers({ doNotFake: ["nextTick"], now: 1_000_000 });
        mockCapturedListener = null;
        mockCacheGet.mockResolvedValue(null);
        mockCacheSet.mockResolvedValue(undefined);
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    test("mount fetch populates bootstrap", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(result.current.bootstrap).not.toBeNull());
        expect(result.current.bootstrap).toEqual(sampleBootstrap);
        expect(result.current.error).toBeNull();
    });

    test("fetch failure falls back to bootstrapCache (NOT SecureStore)", async () => {
        mockApiGet.mockRejectedValueOnce(new Error("offline"));
        mockCacheGet.mockResolvedValue({ payload: sampleBootstrap, fetchedAt: new Date(500_000) });
        const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(result.current.bootstrap).not.toBeNull());
        expect(mockCacheGet).toHaveBeenCalledWith("anonymous");
        expect(result.current.bootstrap).toEqual(sampleBootstrap);
        expect(result.current.error).not.toBeNull();
    });

    test("refetch resolves true when it applied a fresh payload", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(result.current.bootstrap).not.toBeNull());

        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        let applied: boolean | undefined;
        await act(async () => {
            applied = await result.current.refetch();
        });

        expect(applied).toBe(true);
    });

    test("refetch resolves false when the fetch fails and the cached payload is used", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(result.current.bootstrap).not.toBeNull());

        mockApiGet.mockRejectedValueOnce(new Error("offline"));
        mockCacheGet.mockResolvedValue({ payload: sampleBootstrap, fetchedAt: new Date(500_000) });
        let applied: boolean | undefined;
        await act(async () => {
            applied = await result.current.refetch();
        });

        expect(applied).toBe(false);
    });

    test("successful fetch writes to bootstrapCache.set (NOT tokenStore)", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(mockCacheSet).toHaveBeenCalled());
        expect(mockCacheSet).toHaveBeenCalledWith("7", sampleBootstrap);
    });

    test("AppState 'active' transition with stale > 5min triggers refetch", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));

        await act(async () => {
            jest.setSystemTime(1_000_000 + 6 * 60 * 1000);
            mockApiGet.mockResolvedValueOnce(sampleBootstrap);
            mockCapturedListener!("active");
        });
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));
    });

    test("AppState 'active' transition within 5min does NOT refetch", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));

        await act(async () => {
            jest.setSystemTime(1_000_000 + 60 * 1000); // +1min
            mockCapturedListener!("active");
        });
        // Let any queued promise callbacks run.
        await act(async () => {
            await Promise.resolve();
        });
        expect(mockApiGet).toHaveBeenCalledTimes(1);
    });

    test("needsUpdate true when current build < latest_version", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(result.current.bootstrap).not.toBeNull());
        // The installed version is faked as "0.9.0"; the newest is "1.0.0"
        expect(result.current.needsUpdate).toBe(true);
    });

    test("on 'unauthenticated', awaits purgeAll and consumer cleanup before calling fetchIt", async () => {
        const order: string[] = [];
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));

        mockPurgeAll.mockImplementationOnce(async () => {
            order.push("purgeAll");
        });
        mockCachePurge.mockImplementationOnce(async () => {
            order.push("bootstrapCache.purge");
        });
        mockSetLocaleId.mockImplementationOnce(() => {
            order.push("setLocaleId");
        });
        mockApiGet.mockImplementationOnce(async () => {
            order.push("fetchIt");
            return { ...sampleBootstrap, current_user: null };
        });

        await act(async () => {
            authEvents.emit("unauthenticated");
        });

        await waitFor(() => expect(order).toContain("fetchIt"));
        expect(order.indexOf("setLocaleId")).toBeLessThan(order.indexOf("fetchIt"));
        expect(order.indexOf("purgeAll")).toBeLessThan(order.indexOf("fetchIt"));
        expect(order.indexOf("bootstrapCache.purge")).toBeLessThan(order.indexOf("fetchIt"));
    });

    test("a held bearer token answered with current_user null ends the session with the session_expired reason", async () => {
        jest.spyOn(tokenStore, "get").mockResolvedValueOnce("tok_held");
        mockApiGet.mockResolvedValue({ ...sampleBootstrap, current_user: null });
        renderHook(() => useBootstrap(), { wrapper: wrap });

        await waitFor(() => expect(authEvents.unauthenticatedReason()).toBe("session_expired"));

        await act(async () => {
            authEvents.emit("signed_out");
        });
        expect(authEvents.unauthenticatedReason()).toBeNull();
    });

    test("clears previous user's bootstrap immediately on 'signed_out' even if refetch fails offline", async () => {
        mockApiGet.mockResolvedValueOnce(sampleBootstrap);
        const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
        await waitFor(() => expect(result.current.bootstrap).toEqual(sampleBootstrap));

        mockApiGet.mockRejectedValueOnce(new Error("offline"));
        mockCacheGet.mockResolvedValue(null);

        await act(async () => {
            authEvents.emit("signed_out");
        });

        await waitFor(() => expect(result.current.loading).toBe(false));
        expect(result.current.bootstrap).toBeNull();
    });

    describe("overlapping fetches", () => {
        const anonymousBootstrap = { ...sampleBootstrap, current_user: null };

        const deferred = <T>() => {
            let resolve!: (value: T) => void;
            const promise = new Promise<T>((r) => {
                resolve = r;
            });
            return { promise, resolve };
        };

        test("an older anonymous response that resolves after sign-in does not overwrite the signed-in user", async () => {
            const anonymousFetch = deferred<typeof anonymousBootstrap>();
            mockApiGet.mockReturnValueOnce(anonymousFetch.promise);
            const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));

            mockApiGet.mockResolvedValueOnce(sampleBootstrap);
            await act(async () => {
                authEvents.emit("signed_in");
            });
            await waitFor(() => expect(result.current.bootstrap).toEqual(sampleBootstrap));

            await act(async () => {
                anonymousFetch.resolve(anonymousBootstrap);
            });

            expect(result.current.bootstrap).toEqual(sampleBootstrap);
            expect(mockCacheSet).not.toHaveBeenCalledWith("anonymous", anonymousBootstrap);
        });

        test("a superseded fetch is dropped and leaves loading to the newer fetch", async () => {
            const olderFetch = deferred<typeof sampleBootstrap>();
            const newerFetch = deferred<typeof sampleBootstrap>();
            mockApiGet.mockReturnValueOnce(olderFetch.promise);
            const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));

            mockApiGet.mockReturnValueOnce(newerFetch.promise);
            await act(async () => {
                void result.current.refetch();
            });
            await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(2));

            await act(async () => {
                olderFetch.resolve(sampleBootstrap);
            });

            expect(result.current.bootstrap).toBeNull();
            expect(result.current.loading).toBe(true);

            await act(async () => {
                newerFetch.resolve(sampleBootstrap);
            });
            await waitFor(() => expect(result.current.loading).toBe(false));
            expect(result.current.bootstrap).toEqual(sampleBootstrap);
        });
    });

    test("getConsumer destroys previous consumer when token changes", async () => {
        const createSpy = ActionCable.createConsumer as jest.Mock;
        createSpy.mockClear();
        const c1 = await getConsumer("tok_1");
        const c2 = await getConsumer("tok_1");
        expect(c1).toBe(c2);
        expect(createSpy).toHaveBeenCalledTimes(1);

        await getConsumer("tok_2");
        expect(c1.disconnect).toHaveBeenCalledTimes(1);
        expect(createSpy).toHaveBeenCalledTimes(2);
    });

    describe("locale hydration, overrides, errors, and version comparisons", () => {
        afterEach(() => {
            localeOverride.clear();
        });

        test("hydrates stored positive locale override and ignores non-positive values", async () => {
            const prefsGetSpy = jest.spyOn(prefsCache, "get").mockResolvedValueOnce("5");
            mockApiGet.mockResolvedValueOnce(sampleBootstrap);

            const first = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(first.result.current.selectedSwayLocaleId).toBe(5));
            expect(localeOverride.get()).toBe(5);
            first.unmount();

            localeOverride.clear();
            prefsGetSpy.mockResolvedValueOnce("0");
            mockApiGet.mockResolvedValueOnce(sampleBootstrap);

            const second = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(second.result.current.bootstrap).toEqual(sampleBootstrap));
            expect(second.result.current.selectedSwayLocaleId).toBeNull();
            prefsGetSpy.mockRestore();
        });

        test("cancels initial hydration if unmounted before prefsCache.get resolves", async () => {
            let resolvePrefs!: (value: string | null) => void;
            const prefsGetSpy = jest.spyOn(prefsCache, "get").mockReturnValueOnce(
                new Promise<string | null>((res) => {
                    resolvePrefs = res;
                }),
            );

            const view = renderHook(() => useBootstrap(), { wrapper: wrap });
            view.unmount();
            await act(async () => {
                resolvePrefs("7");
            });
            expect(mockApiGet).not.toHaveBeenCalled();
            prefsGetSpy.mockRestore();
        });

        test("refetch(swayLocaleId) persists locale override and updates state", async () => {
            const prefsSetSpy = jest.spyOn(prefsCache, "set").mockResolvedValue(undefined);
            mockApiGet.mockResolvedValue(sampleBootstrap);

            const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(result.current.bootstrap).toEqual(sampleBootstrap));

            await act(async () => {
                await result.current.refetch(42);
            });
            expect(result.current.selectedSwayLocaleId).toBe(42);
            expect(localeOverride.get()).toBe(42);
            expect(prefsSetSpy).toHaveBeenCalledWith(PREFS_KEYS.selectedSwayLocaleId, "42");
            prefsSetSpy.mockRestore();
        });

        test("UnauthorizedError clears bootstrap and purges cache without falling back to cached payload", async () => {
            mockApiGet.mockResolvedValueOnce(sampleBootstrap);
            const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(result.current.bootstrap).toEqual(sampleBootstrap));

            mockApiGet.mockRejectedValueOnce(new UnauthorizedError("unauthorized", "session invalid"));
            await act(async () => {
                await result.current.refetch();
            });
            expect(result.current.bootstrap).toBeNull();
            expect(mockCachePurge).toHaveBeenCalled();
        });

        test("non-Error fetch failure wraps into Error and falls back to signed-in user cache when session exists", async () => {
            const sessionSpy = jest.spyOn(sessionStore, "get").mockResolvedValueOnce({
                bearer_token: "tok",
                device_id: 1,
                user_id: 7,
                expires_at: "2099-01-01T00:00:00Z",
            });
            mockApiGet.mockRejectedValueOnce("raw offline string");
            mockCacheGet.mockResolvedValueOnce({ payload: sampleBootstrap, fetchedAt: new Date(500_000) });

            const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(result.current.bootstrap).toEqual(sampleBootstrap));
            expect(mockCacheGet).toHaveBeenCalledWith("7");
            expect(result.current.error?.message).toBe("raw offline string");
            sessionSpy.mockRestore();
        });

        test("ignores a superseded rejection after a newer fetch starts", async () => {
            let rejectOlder!: (err: Error) => void;
            mockApiGet.mockReturnValueOnce(
                new Promise((_res, rej) => {
                    rejectOlder = rej;
                }),
            );
            const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));

            mockApiGet.mockResolvedValueOnce(sampleBootstrap);
            await act(async () => {
                void result.current.refetch();
            });
            await waitFor(() => expect(result.current.bootstrap).toEqual(sampleBootstrap));

            await act(async () => {
                rejectOlder(new Error("stale failure"));
            });
            expect(result.current.error).toBeNull();
        });

        test("ignores non-active AppState transitions", async () => {
            mockApiGet.mockResolvedValueOnce(sampleBootstrap);
            renderHook(() => useBootstrap(), { wrapper: wrap });
            await waitFor(() => expect(mockApiGet).toHaveBeenCalledTimes(1));

            await act(async () => {
                mockCapturedListener?.("background");
            });
            expect(mockApiGet).toHaveBeenCalledTimes(1);
        });

        test("needsUpdate is false when two-part versions match", async () => {
            const cfg = Constants.expoConfig as { version: string };
            const prevVersion = cfg.version;
            cfg.version = "1.0";
            mockApiGet.mockResolvedValueOnce({ ...sampleBootstrap, latest_version: "1.0" });
            try {
                const { result } = renderHook(() => useBootstrap(), { wrapper: wrap });
                await waitFor(() => expect(result.current.bootstrap).not.toBeNull());
                expect(result.current.needsUpdate).toBe(false);
            } finally {
                cfg.version = prevVersion;
            }
        });
    });
});
