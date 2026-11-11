import { renderHook, act } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";

describe("usePullToRefresh", () => {
    beforeEach(() => {
        vi.clearAllMocks();
        window.matchMedia = vi
            .fn<
                (
                    query: string,
                ) => Pick<MediaQueryList, "matches" | "media" | "addEventListener" | "removeEventListener">
            >()
            .mockImplementation((q: string) => ({
                matches: q === "(display-mode: standalone)",
                media: q,
                addEventListener: vi.fn<(...args: unknown[]) => void>(),
                removeEventListener: vi.fn<(...args: unknown[]) => void>(),
            })) as unknown as typeof window.matchMedia;
        Object.defineProperty(document, "scrollingElement", {
            value: { scrollTop: 0 },
            configurable: true,
        });
    });

    it("does not activate when not in standalone display mode", async () => {
        window.matchMedia = vi
            .fn<(query: string) => MediaQueryList>()
            .mockReturnValue({ matches: false } as unknown as MediaQueryList) as unknown as typeof window.matchMedia;
        const onRefresh = vi.fn<() => void>();
        const { usePullToRefresh } = await import("app/frontend/hooks/usePullToRefresh");
        renderHook(() => usePullToRefresh({ onRefresh }));
        document.dispatchEvent(new Event("touchstart"));
        expect(onRefresh).not.toHaveBeenCalled();
    });

    it("triggers onRefresh when pull exceeds threshold", async () => {
        const onRefresh = vi.fn<() => Promise<void>>().mockResolvedValue(undefined);
        const { usePullToRefresh } = await import("app/frontend/hooks/usePullToRefresh");
        renderHook(() => usePullToRefresh({ onRefresh, threshold: 50 }));
        // act it out: finger down at y=100, dragged to y=200, so 100 pixels, past the 50 threshold
        act(() => {
            document.dispatchEvent(
                Object.assign(new Event("touchstart"), { touches: [{ clientY: 100 }] }) as unknown as TouchEvent,
            );
        });
        act(() => {
            document.dispatchEvent(
                Object.assign(new Event("touchmove"), { touches: [{ clientY: 200 }] }) as unknown as TouchEvent,
            );
        });
        act(() => {
            document.dispatchEvent(new Event("touchend"));
        });
        // give the queued promise callbacks a chance to run
        await vi.waitFor(() => expect(onRefresh).toHaveBeenCalledTimes(1));
    });

    it("does not activate when the page is scrolled away from the top", async () => {
        Object.defineProperty(document, "scrollingElement", {
            value: { scrollTop: 40 },
            configurable: true,
        });
        const onRefresh = vi.fn<() => void>();
        const { usePullToRefresh } = await import("app/frontend/hooks/usePullToRefresh");
        renderHook(() => usePullToRefresh({ onRefresh, threshold: 50 }));
        act(() => {
            document.dispatchEvent(
                Object.assign(new Event("touchstart"), { touches: [{ clientY: 100 }] }) as unknown as TouchEvent,
            );
        });
        act(() => {
            document.dispatchEvent(
                Object.assign(new Event("touchmove"), { touches: [{ clientY: 300 }] }) as unknown as TouchEvent,
            );
        });
        act(() => {
            document.dispatchEvent(new Event("touchend"));
        });
        expect(onRefresh).not.toHaveBeenCalled();
    });

    it("does not trigger when pull below threshold", async () => {
        const onRefresh = vi.fn<() => void>();
        const { usePullToRefresh } = await import("app/frontend/hooks/usePullToRefresh");
        renderHook(() => usePullToRefresh({ onRefresh, threshold: 100 }));
        act(() => {
            document.dispatchEvent(
                Object.assign(new Event("touchstart"), { touches: [{ clientY: 100 }] }) as unknown as TouchEvent,
            );
        });
        act(() => {
            document.dispatchEvent(
                Object.assign(new Event("touchmove"), { touches: [{ clientY: 150 }] }) as unknown as TouchEvent,
            );
        });
        act(() => {
            document.dispatchEvent(new Event("touchend"));
        });
        expect(onRefresh).not.toHaveBeenCalled();
    });
});
