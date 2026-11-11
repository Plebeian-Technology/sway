import { describe, it, expect, beforeEach } from "vitest";

import { applyThemeFontHref, currentThemeFontHref } from "app/frontend/sway_utils/theme_fonts";

const BALLOT = "https://fonts.googleapis.com/css2?family=Barlow+Semi+Condensed:wght@600;700;800&display=swap";
const CORNERSTORE = "https://fonts.googleapis.com/css2?family=Alfa+Slab+One&display=swap";

function linkCount(): number {
    return document.head.querySelectorAll("link[data-theme-fonts]").length;
}

// Stands in for the <link> the ERB layout writes when the active theme has a
// web font of its own.
function seedServerRenderedLink(href: string) {
    const link = document.createElement("link");
    link.setAttribute("data-theme-fonts", "");
    link.rel = "stylesheet";
    link.href = href;
    document.head.appendChild(link);
}

describe("theme_fonts", () => {
    beforeEach(() => {
        document.head.querySelectorAll("link[data-theme-fonts]").forEach((el) => el.remove());
    });

    describe("currentThemeFontHref", () => {
        it("is undefined when the active theme ships no webfont", () => {
            expect(currentThemeFontHref()).toBeUndefined();
        });

        // Reading link.href through the DOM gives a full absolute URL. The raw
        // attribute is the thing that matches the value the server sent.
        it("reads back the href exactly as the server wrote it", () => {
            seedServerRenderedLink(BALLOT);

            expect(currentThemeFontHref()).toBe(BALLOT);
        });
    });

    describe("applyThemeFontHref", () => {
        it("creates the link when switching from a theme that ships no webfont", () => {
            applyThemeFontHref(BALLOT);

            expect(currentThemeFontHref()).toBe(BALLOT);
            expect(document.head.querySelector("link[data-theme-fonts]")?.getAttribute("rel")).toBe("stylesheet");
        });

        it("re-points the existing link rather than stacking a second one", () => {
            seedServerRenderedLink(BALLOT);

            applyThemeFontHref(CORNERSTORE);

            expect(currentThemeFontHref()).toBe(CORNERSTORE);
            expect(linkCount()).toBe(1);
        });

        // A theme's typefaces must not outlive the theme. Leaving Corner
        // Store's wood type loaded while the default theme is showing is the
        // same kind of bug as never loading it at all.
        it("removes the link when the incoming theme ships no webfont", () => {
            seedServerRenderedLink(CORNERSTORE);

            applyThemeFontHref(undefined);

            expect(currentThemeFontHref()).toBeUndefined();
            expect(linkCount()).toBe(0);
        });

        it("is a no-op when the incoming theme is already the active one", () => {
            seedServerRenderedLink(BALLOT);

            applyThemeFontHref(BALLOT);

            expect(currentThemeFontHref()).toBe(BALLOT);
            expect(linkCount()).toBe(1);
        });

        it("stays quiet when there is nothing to remove", () => {
            expect(() => applyThemeFontHref(undefined)).not.toThrow();
            expect(linkCount()).toBe(0);
        });
    });
});
