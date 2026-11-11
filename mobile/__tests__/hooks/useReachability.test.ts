let netInfoListener: ((state: { isConnected: boolean | null }) => void) | null = null;

jest.mock("@react-native-community/netinfo", () => ({
    addEventListener: jest.fn((cb: (s: { isConnected: boolean | null }) => void) => {
        netInfoListener = cb;
        return () => {
            netInfoListener = null;
        };
    }),
    fetch: jest.fn(async () => ({ isConnected: true })),
}));

import React from "react";
import { renderHook, act, waitFor } from "@testing-library/react-native";
import { useReachability } from "../../src/hooks/useReachability";

const originalFetch = global.fetch;

describe("useReachability", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        jest.useFakeTimers();
        netInfoListener = null;
        global.fetch = jest.fn(
            async () =>
                ({
                    ok: true,
                    status: 200,
                }) as unknown as Response,
        ) as unknown as typeof fetch;
    });

    afterEach(() => {
        jest.useRealTimers();
        global.fetch = originalFetch;
    });

    test("initial probe HEAD /up sets isOnline true", async () => {
        const { result } = renderHook(() => useReachability());
        await act(async () => {
            await Promise.resolve();
        });
        await waitFor(() => expect(global.fetch).toHaveBeenCalled());
        const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
        expect(String(url)).toContain("/up");
        expect(init.method).toBe("HEAD");
        expect(result.current.isOnline).toBe(true);
    });

    test("NetInfo offline event sets isOnline false instantly", async () => {
        const { result } = renderHook(() => useReachability());
        await act(async () => {
            await Promise.resolve();
        });
        expect(typeof netInfoListener).toBe("function");
        await act(async () => {
            netInfoListener!({ isConnected: false });
        });
        expect(result.current.isOnline).toBe(false);
    });

    test("re-polls on the 30s interval", async () => {
        renderHook(() => useReachability());
        await act(async () => {
            await Promise.resolve();
        });
        const initialCalls = (global.fetch as jest.Mock).mock.calls.length;
        await act(async () => {
            jest.advanceTimersByTime(30_000);
            await Promise.resolve();
        });
        expect((global.fetch as jest.Mock).mock.calls.length).toBeGreaterThan(initialCalls);
    });

    test("clears timeout in finally block when fetch rejects", async () => {
        const clearTimeoutSpy = jest.spyOn(global, "clearTimeout");
        (global.fetch as jest.Mock).mockRejectedValueOnce(new Error("offline"));
        const { result } = renderHook(() => useReachability());
        await act(async () => {
            await Promise.resolve();
        });
        expect(clearTimeoutSpy).toHaveBeenCalled();
        expect(result.current.isOnline).toBe(false);
        clearTimeoutSpy.mockRestore();
    });
});

// Jest needs React imported whenever a file pulls renderHook out of the native
// testing library. This line uses the import so it is not stripped as unused.
void React;
