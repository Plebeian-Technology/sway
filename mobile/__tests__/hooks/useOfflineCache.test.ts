let mockIsOnlineState = true;
jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: mockIsOnlineState, lastChecked: new Date() }),
}));

import React from "react";
import { renderHook, waitFor } from "@testing-library/react-native";
import { useOfflineCache, assertOnlineForWrite } from "../../src/hooks/useOfflineCache";

describe("useOfflineCache", () => {
    beforeEach(() => {
        mockIsOnlineState = true;
    });

    test("returns cached rows then refreshes from fetcher", async () => {
        const cached = [{ id: 1 }];
        const fresh = [{ id: 1 }, { id: 2 }];
        const cache = {
            get: jest.fn(async () => cached),
            set: jest.fn(async () => {}),
        };
        const fetcher = jest.fn(async () => fresh);

        const { result } = renderHook(() => useOfflineCache({ cache, fetcher }));

        await waitFor(() => expect(result.current.data).toEqual(fresh));
        expect(cache.get).toHaveBeenCalled();
        expect(fetcher).toHaveBeenCalled();
        expect(cache.set).toHaveBeenCalledWith(fresh);
    });

    test("offline: returns cache rows but skips fetcher", async () => {
        mockIsOnlineState = false;
        const cached = [{ id: 1 }];
        const cache = {
            get: jest.fn(async () => cached),
            set: jest.fn(async () => {}),
        };
        const fetcher = jest.fn(async () => [{ id: 99 }]);

        const { result } = renderHook(() => useOfflineCache({ cache, fetcher }));
        await waitFor(() => expect(result.current.data).toEqual(cached));
        expect(fetcher).not.toHaveBeenCalled();
        expect(cache.set).not.toHaveBeenCalled();
    });

    test("assertOnlineForWrite throws offline_write_blocked when offline", () => {
        expect(() => assertOnlineForWrite(false)).toThrow(/offline_write_blocked/);
        expect(() => assertOnlineForWrite(true)).not.toThrow();
    });

    test("propagates fetcher errors", async () => {
        const cache = {
            get: jest.fn(async () => []),
            set: jest.fn(async () => {}),
        };
        const fetcher = jest.fn(async () => {
            throw new Error("boom");
        });
        const { result } = renderHook(() => useOfflineCache({ cache, fetcher }));
        await waitFor(() => expect(result.current.error).not.toBeNull());
        expect(result.current.error?.message).toBe("boom");
    });
});

void React;
