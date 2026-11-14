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
import { BootstrapProvider, useBootstrap } from "../../src/state/BootstrapContext";
import { authEvents } from "../../src/auth/authEvents";
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
});
