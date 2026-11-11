import { renderHook, act } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach } from "vitest";

// Hold on to router.patch, so the tests can call the onError it was handed.
const routerPatch = vi.fn<(...args: unknown[]) => unknown>();

vi.mock("@inertiajs/react", () => ({
    usePage: vi.fn<() => { props: unknown }>(() => ({ props: {} })),
    router: {
        patch: (...args: unknown[]) => routerPatch(...args),
    },
}));

import { usePage } from "@inertiajs/react";
import { useTheme } from "app/frontend/hooks/useTheme";

function setUsePageProps(props: Record<string, unknown>) {
    vi.mocked(usePage).mockReturnValue({ props } as unknown as ReturnType<typeof usePage>);
}

// Call the onError that was passed to the most recent router.patch call.
function triggerLastPatchError() {
    const lastCall = routerPatch.mock.calls.at(-1);
    const options = lastCall?.[2] as { onError?: () => void } | undefined;
    options?.onError?.();
}

describe("useTheme — setThemeId (WR-A / WR-B: forward-API for the v1.2 picker)", () => {
    beforeEach(() => {
        routerPatch.mockReset();
        vi.mocked(usePage).mockReset();
        setUsePageProps({});
        document.documentElement.removeAttribute("data-theme");
    });

    // Success path -------------------------------------------------------------

    it("PATCHes /users/preferences with { preferences: { theme_id } } and updates data-theme", () => {
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("ballot"));

        // The handler writes to the page at once, before the server answers.
        expect(document.documentElement.dataset.theme).toBe("ballot");

        expect(routerPatch).toHaveBeenCalledTimes(1);
        const [path, body] = routerPatch.mock.calls[0];
        expect(path).toBe("/users/preferences");
        expect(body).toEqual({ preferences: { theme_id: "ballot" } });
    });

    // Undo on failure — the attribute was already there before the write ------

    it("on server rejection, reverts data-theme to the server-resolved id (props.theme.id)", () => {
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        document.documentElement.dataset.theme = "cornerstore";
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("ballot"));
        expect(document.documentElement.dataset.theme).toBe("ballot");

        // The server rejects the theme_id, so onError must put the saved theme back.
        act(() => triggerLastPatchError());

        // It goes back to the server's theme id, NOT to a value read off the page.
        expect(document.documentElement.dataset.theme).toBe("cornerstore");
    });

    // Undo on failure — there was no attribute at all before the write --------

    it("on server rejection, removes data-theme entirely when it was absent before the write", () => {
        // Nothing was rendered by the server here, so <html> starts with no
        // data-theme attribute.
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        expect(document.documentElement.hasAttribute("data-theme")).toBe(false);
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("ballot"));
        expect(document.documentElement.dataset.theme).toBe("ballot");

        act(() => triggerLastPatchError());

        // The rejected id must NOT stay behind — the attribute is removed.
        expect(document.documentElement.hasAttribute("data-theme")).toBe(false);
    });
});

// @lat: [[theme-font-hrefs#Why the shared theme prop carries the whole font map]]
describe("useTheme — setThemeId swaps the theme webfont", () => {
    const BALLOT_HREF = "https://fonts.example/ballot.css";
    const CORNERSTORE_HREF = "https://fonts.example/cornerstore.css";

    // The server sends this map of font URLs (ThemeHelper::THEME_FONT_HREFS),
    // so Ruby stays the one place they are written down. None of it is spelled
    // out in the TypeScript.
    const FONT_HREFS = { ballot: BALLOT_HREF, cornerstore: CORNERSTORE_HREF };

    function fontLinkHref(): string | null | undefined {
        return document.head.querySelector("link[data-theme-fonts]")?.getAttribute("href");
    }

    function seedServerRenderedLink(href: string) {
        const link = document.createElement("link");
        link.setAttribute("data-theme-fonts", "");
        link.rel = "stylesheet";
        link.href = href;
        document.head.appendChild(link);
    }

    beforeEach(() => {
        routerPatch.mockReset();
        vi.mocked(usePage).mockReset();
        setUsePageProps({});
        document.documentElement.removeAttribute("data-theme");
        document.head.querySelectorAll("link[data-theme-fonts]").forEach((el) => el.remove());
    });

    it("requests the incoming theme's faces in the same handler that flips data-theme", () => {
        setUsePageProps({ theme: { preference: "light", id: "sway", font_hrefs: FONT_HREFS } });
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("cornerstore"));

        // It happens at once: no navigation, no trip to the server, no reload.
        expect(document.documentElement.dataset.theme).toBe("cornerstore");
        expect(fontLinkHref()).toBe(CORNERSTORE_HREF);
    });

    it("drops the outgoing theme's faces when the incoming theme ships none", () => {
        setUsePageProps({ theme: { preference: "light", id: "ballot", font_hrefs: FONT_HREFS } });
        seedServerRenderedLink(BALLOT_HREF);
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("sway"));

        expect(fontLinkHref()).toBeUndefined();
    });

    it("on server rejection, restores the faces of the theme the server actually persisted", () => {
        setUsePageProps({ theme: { preference: "light", id: "ballot", font_hrefs: FONT_HREFS } });
        document.documentElement.dataset.theme = "ballot";
        seedServerRenderedLink(BALLOT_HREF);
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("cornerstore"));
        expect(fontLinkHref()).toBe(CORNERSTORE_HREF);

        act(() => triggerLastPatchError());

        // The lettering must roll back in step with data-theme, or the page
        // shows one theme's colours under another theme's typefaces.
        expect(document.documentElement.dataset.theme).toBe("ballot");
        expect(fontLinkHref()).toBe(BALLOT_HREF);
    });

    it("on server rejection, removes a link it created when there was none before", () => {
        setUsePageProps({ theme: { preference: "light", id: "sway", font_hrefs: FONT_HREFS } });
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("ballot"));
        expect(fontLinkHref()).toBe(BALLOT_HREF);

        act(() => triggerLastPatchError());

        expect(fontLinkHref()).toBeUndefined();
    });

    // A browser running older code, which has not been sent this prop, must
    // still be able to switch themes. The lettering just falls back to the
    // theme's list of fonts already on the device.
    it("still switches the theme when the server sent no font map", () => {
        setUsePageProps({ theme: { preference: "light", id: "sway" } });
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setThemeId("ballot"));

        expect(document.documentElement.dataset.theme).toBe("ballot");
        expect(fontLinkHref()).toBeUndefined();
    });
});

describe("useTheme — setPreference (IN-02: onError revert parity with setThemeId)", () => {
    beforeEach(() => {
        routerPatch.mockReset();
        vi.mocked(usePage).mockReset();
        setUsePageProps({});
        document.documentElement.removeAttribute("data-theme-mode");
        document.documentElement.classList.remove("dark");
    });

    it("PATCHes /users/preferences with { preferences: { theme_mode } } and updates data-theme-mode", () => {
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setPreference("dark"));

        // The handler writes to the page at once, before the server answers.
        expect(document.documentElement.dataset.themeMode).toBe("dark");
        expect(document.documentElement.classList.contains("dark")).toBe(true);

        expect(routerPatch).toHaveBeenCalledTimes(1);
        const [path, body] = routerPatch.mock.calls[0];
        expect(path).toBe("/users/preferences");
        expect(body).toEqual({ preferences: { theme_mode: "dark" } });
    });

    // Undo on failure — the attribute was already there before the write ------

    it("on server rejection, reverts data-theme-mode and .dark to the server-resolved preference", () => {
        // The server settled on "auto" and rendered the mode attribute itself.
        setUsePageProps({ theme: { preference: "auto", id: "cornerstore" } });
        document.documentElement.dataset.themeMode = "auto";
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setPreference("dark"));
        expect(document.documentElement.dataset.themeMode).toBe("dark");
        expect(document.documentElement.classList.contains("dark")).toBe(true);

        // The server rejects the theme_mode, so onError must put the saved mode back.
        act(() => triggerLastPatchError());

        // It goes back to the preference the server settled on, as sent in the props.
        expect(document.documentElement.dataset.themeMode).toBe("auto");
        expect(document.documentElement.classList.contains("dark")).toBe(false);
    });

    // Undo on failure — there was no attribute at all before the write -------

    it("on server rejection, removes data-theme-mode entirely when it was absent before the write", () => {
        // Nothing was rendered by the server here, so <html> starts with no
        // data-theme-mode attribute.
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        expect(document.documentElement.hasAttribute("data-theme-mode")).toBe(false);
        const { result } = renderHook(() => useTheme());

        act(() => result.current.setPreference("dark"));
        expect(document.documentElement.dataset.themeMode).toBe("dark");
        expect(document.documentElement.classList.contains("dark")).toBe(true);

        act(() => triggerLastPatchError());

        // The rejected mode must NOT stay behind — the attribute is removed and
        // the .dark class added a moment earlier is taken off again.
        expect(document.documentElement.hasAttribute("data-theme-mode")).toBe(false);
        expect(document.documentElement.classList.contains("dark")).toBe(false);
    });
});

describe("useTheme — the theme patch asks for one prop back", () => {
    beforeEach(() => {
        routerPatch.mockReset();
        vi.mocked(usePage).mockReset();
        setUsePageProps({ theme: { preference: "light", id: "cornerstore" } });
        document.documentElement.removeAttribute("data-theme");
        document.documentElement.removeAttribute("data-theme-mode");
    });

    // @lat: [[partial-reload-poll-lists#Why an empty only list is not a partial request]]
    it.each([
        ["setThemeId", (t: ReturnType<typeof useTheme>) => t.setThemeId("ballot")],
        ["setPreference", (t: ReturnType<typeof useTheme>) => t.setPreference("dark")],
    ])("%s sends a non-empty only list, so the server treats it as a partial", (_name, call) => {
        const { result } = renderHook(() => useTheme());

        act(() => call(result.current));

        const options = routerPatch.mock.calls.at(-1)?.[2] as { only?: string[] };
        expect(options.only).toEqual(["theme"]);
        expect(options.only).not.toHaveLength(0);
    });
});
