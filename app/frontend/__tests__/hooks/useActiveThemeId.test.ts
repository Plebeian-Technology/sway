import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";

import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";

// @lat: [[theme-tokens#Theme tokens#Why the active theme is watched rather than passed down]]
describe("useActiveThemeId", () => {
    afterEach(() => {
        delete document.documentElement.dataset.theme;
    });

    it("reads the current theme from <html data-theme>", () => {
        document.documentElement.dataset.theme = "ballot";

        const { result } = renderHook(() => useActiveThemeId());

        expect(result.current).toBe("ballot");
    });

    it("falls back to sway when data-theme is absent", () => {
        const { result } = renderHook(() => useActiveThemeId());

        expect(result.current).toBe("sway");
    });

    it("falls back to sway when data-theme is not a registered theme", () => {
        document.documentElement.dataset.theme = "not-a-theme";

        const { result } = renderHook(() => useActiveThemeId());

        expect(result.current).toBe("sway");
    });

    it("re-renders with the new theme when data-theme changes", async () => {
        document.documentElement.dataset.theme = "cornerstore";
        const { result } = renderHook(() => useActiveThemeId());
        expect(result.current).toBe("cornerstore");

        await act(async () => {
            document.documentElement.dataset.theme = "ballot";
        });

        await waitFor(() => expect(result.current).toBe("ballot"));
    });
});
