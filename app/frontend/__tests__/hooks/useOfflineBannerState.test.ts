import { renderHook, act } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { useOfflineBannerState } from "app/frontend/hooks/useOfflineBannerState";
// oxlint-disable-next-line import/default -- Vite ?raw import returns the file as a string; the underlying module has no default export to check.
import useOfflineBannerStateSource from "app/frontend/hooks/useOfflineBannerState.ts?raw";

describe("useOfflineBannerState", () => {
    it("initial state: hidden when online", () => {
        const { result } = renderHook(() => useOfflineBannerState(true));
        expect(result.current.bannerState).toBe("hidden");
    });

    it("initial state: visible when offline at mount", () => {
        const { result } = renderHook(() => useOfflineBannerState(false));
        expect(result.current.bannerState).toBe("visible");
    });

    it("online → offline transition shows banner", () => {
        const { result, rerender } = renderHook(({ online }) => useOfflineBannerState(online), {
            initialProps: { online: true },
        });
        expect(result.current.bannerState).toBe("hidden");
        rerender({ online: false });
        expect(result.current.bannerState).toBe("visible");
    });

    it("dismissBanner hides visible banner", () => {
        const { result } = renderHook(() => useOfflineBannerState(false));
        expect(result.current.bannerState).toBe("visible");
        act(() => result.current.dismissBanner());
        expect(result.current.bannerState).toBe("hidden");
    });

    it("assertBanner re-shows after dismiss (state=asserted)", () => {
        const { result } = renderHook(() => useOfflineBannerState(false));
        act(() => result.current.dismissBanner());
        expect(result.current.bannerState).toBe("hidden");
        act(() => result.current.assertBanner());
        expect(result.current.bannerState).toBe("asserted");
    });

    it("assertBanner is no-op when online", () => {
        const { result } = renderHook(() => useOfflineBannerState(true));
        act(() => result.current.assertBanner());
        expect(result.current.bannerState).toBe("hidden");
    });

    it("dismissBanner is no-op in asserted state", () => {
        const { result } = renderHook(() => useOfflineBannerState(false));
        act(() => result.current.dismissBanner());
        act(() => result.current.assertBanner());
        expect(result.current.bannerState).toBe("asserted");
        act(() => result.current.dismissBanner());
        expect(result.current.bannerState).toBe("asserted");
    });

    it("offline → online transition hides banner (resets dismissal memory)", () => {
        const { result, rerender } = renderHook(({ online }) => useOfflineBannerState(online), {
            initialProps: { online: false },
        });
        act(() => result.current.dismissBanner());
        act(() => result.current.assertBanner());
        expect(result.current.bannerState).toBe("asserted");
        rerender({ online: true });
        expect(result.current.bannerState).toBe("hidden");
    });

    // @lat: [[frontend-test-infrastructure-notes#useOfflineBannerState: asserting against the hook's own source text]]
    it("uses no useEffect (during-render transition, not an effect)", () => {
        expect(useOfflineBannerStateSource).not.toMatch(/useEffect\(/);
    });
});
