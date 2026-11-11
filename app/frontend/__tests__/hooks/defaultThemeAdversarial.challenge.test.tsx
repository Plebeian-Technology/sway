import { act, cleanup, fireEvent, render, renderHook, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const routerPatch = vi.fn<(...args: unknown[]) => unknown>();

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<() => { props: Record<string, unknown> }>(() => ({ props: {} })),
    router: {
        patch: (...args: unknown[]) => routerPatch(...args),
    },
}));

vi.mock("app/frontend/components/ui/select", () => ({
    Select: ({
        value,
        onValueChange,
        children,
    }: {
        value: string;
        onValueChange: (v: string) => void;
        children: React.ReactNode;
    }) => (
        <select data-testid="theme-select" value={value} onChange={(e) => onValueChange(e.target.value)}>
            {children}
        </select>
    ),
    SelectTrigger: () => null,
    SelectValue: () => null,
    SelectContent: ({ children }: { children: React.ReactNode }) => <>{children}</>,
    SelectItem: ({ value, children }: { value: string; children: React.ReactNode }) => (
        <option value={value}>{children}</option>
    ),
}));

import { usePage } from "@inertiajs/react";
import ThemePicker from "app/frontend/components/drawer/ThemePicker";
import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";
import { useTheme } from "app/frontend/hooks/useTheme";
import { THEMES, type ThemeId } from "app/frontend/styles/themes";

const VALID_THEME_IDS = THEMES.map((t) => t.id);

function setPageProps(props: Record<string, unknown>) {
    vi.mocked(usePage).mockReturnValue({ props } as unknown as ReturnType<typeof usePage>);
}

function triggerLastPatchError() {
    const lastCall = routerPatch.mock.calls.at(-1);
    const options = lastCall?.[2] as { onError?: () => void } | undefined;
    options?.onError?.();
}

describe("Adversarial Theme Defaulting — Milestone 7", () => {
    beforeEach(() => {
        routerPatch.mockReset();
        vi.mocked(usePage).mockReset();
        setPageProps({});
        delete document.documentElement.dataset.theme;
        delete document.documentElement.dataset.themeMode;
        document.documentElement.removeAttribute("data-theme");
        document.documentElement.removeAttribute("data-theme-mode");
    });

    afterEach(() => {
        cleanup();
        delete document.documentElement.dataset.theme;
        delete document.documentElement.dataset.themeMode;
        document.documentElement.removeAttribute("data-theme");
        document.documentElement.removeAttribute("data-theme-mode");
    });

    describe("useActiveThemeId adversarial cases", () => {
        it("returns 'sway' when dataset.theme is undefined", () => {
            delete document.documentElement.dataset.theme;
            const { result } = renderHook(() => useActiveThemeId());
            expect(result.current).toBe("sway");
        });

        it("returns 'sway' when dataset.theme is an empty string", () => {
            document.documentElement.dataset.theme = "";
            const { result } = renderHook(() => useActiveThemeId());
            expect(result.current).toBe("sway");
        });

        it("returns 'sway' when dataset.theme is whitespace only", () => {
            document.documentElement.dataset.theme = "   ";
            const { result } = renderHook(() => useActiveThemeId());
            expect(result.current).toBe("sway");
        });

        it.each([
            "not-a-real-theme",
            "SERVICE-MANUAL",
            "Service-Manual",
            "sway_default",
            "dark",
            "light",
            "null",
            "undefined",
            "0",
            "__proto__",
        ])("returns 'sway' when dataset.theme is invalid string: %s", (invalidId) => {
            document.documentElement.dataset.theme = invalidId;
            const { result } = renderHook(() => useActiveThemeId());
            expect(result.current).toBe("sway");
        });

        it.each(VALID_THEME_IDS)("returns exactly '%s' when dataset.theme is a registered valid theme", (validId) => {
            document.documentElement.dataset.theme = validId;
            const { result } = renderHook(() => useActiveThemeId());
            expect(result.current).toBe(validId);
        });

        it("dynamically falls back to 'sway' when valid theme attribute is removed or invalidated", async () => {
            document.documentElement.dataset.theme = "monochrome";
            const { result } = renderHook(() => useActiveThemeId());
            expect(result.current).toBe("monochrome");

            await act(async () => {
                delete document.documentElement.dataset.theme;
            });
            await waitFor(() => expect(result.current).toBe("sway"));

            await act(async () => {
                document.documentElement.dataset.theme = "invalid-value";
            });
            await waitFor(() => expect(result.current).toBe("sway"));
        });
    });

    describe("useTheme adversarial cases", () => {
        it("defaults themeId to 'sway' when page props are completely empty", () => {
            setPageProps({});
            const { result } = renderHook(() => useTheme());
            expect(result.current.themeId).toBe("sway");
        });

        it("defaults themeId to 'sway' when theme prop is null", () => {
            setPageProps({ theme: null });
            const { result } = renderHook(() => useTheme());
            expect(result.current.themeId).toBe("sway");
        });

        it("defaults themeId to 'sway' when theme prop is empty object", () => {
            setPageProps({ theme: {} });
            const { result } = renderHook(() => useTheme());
            expect(result.current.themeId).toBe("sway");
        });

        it("defaults themeId to 'sway' when theme.id is undefined", () => {
            setPageProps({ theme: { id: undefined } });
            const { result } = renderHook(() => useTheme());
            expect(result.current.themeId).toBe("sway");
        });

        it.each(["", "   ", "bogus", "sway_legacy", "SERVICE-MANUAL", "null", "undefined"])(
            "defaults themeId to 'sway' when theme.id is unrecognised value: %s",
            (bogusId) => {
                setPageProps({ theme: { id: bogusId as unknown as ThemeId } });
                const { result } = renderHook(() => useTheme());
                expect(result.current.themeId).toBe("sway");
            },
        );

        it.each(VALID_THEME_IDS)("preserves valid themeId: %s", (validId) => {
            setPageProps({ theme: { id: validId } });
            const { result } = renderHook(() => useTheme());
            expect(result.current.themeId).toBe(validId);
        });

        it("reverts to server themeId ('sway') when optimistic update is rejected", () => {
            setPageProps({ theme: { id: "sway" } });
            document.documentElement.dataset.theme = "sway";
            const { result } = renderHook(() => useTheme());

            act(() => result.current.setThemeId("monochrome"));
            expect(document.documentElement.dataset.theme).toBe("monochrome");

            act(() => triggerLastPatchError());
            expect(document.documentElement.dataset.theme).toBe("sway");
        });
    });

    describe("ThemePicker adversarial cases", () => {
        it("defaults combobox value to 'sway' when no shared props are present", () => {
            setPageProps({});
            render(<ThemePicker />);
            expect(screen.getByTestId("theme-select")).toHaveValue("sway");
        });

        it("defaults combobox value to 'sway' when theme is null", () => {
            setPageProps({ theme: null });
            render(<ThemePicker />);
            expect(screen.getByTestId("theme-select")).toHaveValue("sway");
        });

        it("defaults combobox value to 'sway' when theme.id is invalid", () => {
            setPageProps({ theme: { id: "invalid-theme" as unknown as ThemeId } });
            render(<ThemePicker />);
            expect(screen.getByTestId("theme-select")).toHaveValue("sway");
        });

        it("includes 'Service Manual' among the selectable options", () => {
            setPageProps({});
            render(<ThemePicker />);
            expect(screen.getByRole("option", { name: "Service Manual" })).toBeInTheDocument();
            expect(screen.getByRole("option", { name: "Service Manual" })).toHaveValue("service-manual");
        });

        it("allows switching to 'service-manual' and fires router.patch with preferences.theme_id", () => {
            setPageProps({ theme: { id: "sway" } });
            render(<ThemePicker />);

            fireEvent.change(screen.getByTestId("theme-select"), { target: { value: "service-manual" } });

            expect(document.documentElement.dataset.theme).toBe("service-manual");
            expect(routerPatch).toHaveBeenCalledTimes(1);
            expect(routerPatch).toHaveBeenCalledWith(
                "/users/preferences",
                { preferences: { theme_id: "service-manual" } },
                expect.objectContaining({ only: ["theme"] }),
            );
        });
    });
});
