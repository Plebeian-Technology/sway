import { renderHook } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach, afterEach } from "vitest";

// @lat: [[frontend-test-infrastructure-notes#Warming a module transform out of a test's own budget]]
await import("app/frontend/hooks/useReachability");

describe("useReachability", () => {
    let fetchMock: ReturnType<typeof vi.fn>;

    beforeEach(() => {
        vi.useFakeTimers();
        fetchMock = vi
            .fn<(url: string, options?: RequestInit) => Promise<Response>>()
            .mockResolvedValue({ ok: true } as Response);
        vi.stubGlobal("fetch", fetchMock);
        Object.defineProperty(navigator, "onLine", { value: true, configurable: true });
    });

    afterEach(() => {
        vi.clearAllMocks();
        vi.useRealTimers();
    });

    it("initializes isOnline=true and probes HEAD /up on mount", async () => {
        const { useReachability } = await import("app/frontend/hooks/useReachability");
        const { result } = renderHook(() => useReachability());
        // the value it starts with
        expect(result.current.isOnline).toBe(true);
        // give the awaited fetch's promise callbacks a chance to run
        await vi.waitFor(() => {
            expect(fetchMock).toHaveBeenCalledWith(
                "/up",
                expect.objectContaining({ method: "HEAD", cache: "no-store" }),
            );
        });
    });

    it("sets isOnline=false when navigator.onLine is false without calling fetch", async () => {
        Object.defineProperty(navigator, "onLine", { value: false, configurable: true });
        const { useReachability } = await import("app/frontend/hooks/useReachability");
        const { result } = renderHook(() => useReachability());
        await vi.waitFor(() => {
            expect(result.current.isOnline).toBe(false);
        });
        expect(fetchMock).not.toHaveBeenCalled();
    });

    it("sets isOnline=false when heartbeat fetch rejects", async () => {
        fetchMock.mockRejectedValue(new Error("network down"));
        const { useReachability } = await import("app/frontend/hooks/useReachability");
        const { result } = renderHook(() => useReachability());
        await vi.waitFor(() => {
            expect(result.current.isOnline).toBe(false);
        });
    });

    it("re-probes every 30 seconds", async () => {
        const { useReachability } = await import("app/frontend/hooks/useReachability");
        renderHook(() => useReachability());
        await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
        await vi.advanceTimersByTimeAsync(30_000);
        expect(fetchMock).toHaveBeenCalledTimes(2);
        await vi.advanceTimersByTimeAsync(30_000);
        expect(fetchMock).toHaveBeenCalledTimes(3);
    });
});
