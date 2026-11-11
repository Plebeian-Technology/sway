import { describe, expect, it } from "vitest";

import type { ThemeId } from "app/frontend/styles/themes";

import DefaultBillLayout from "app/frontend/components/bill/layouts/DefaultBillLayout";
import { billLayoutFor } from "app/frontend/components/bill/layouts/index";

// @lat: [[theme-driven-bill-layout-selection#Testing billLayoutFor against lazy-wrapped layouts]]
describe("billLayoutFor", () => {
    it("returns a distinct, stable per-theme layout for themes that register one", () => {
        const registered: ThemeId[] = ["banner", "ballot", "cornerstore", "monochrome", "service-manual", "swiss-grid"];
        const resolved = registered.map((themeId) => billLayoutFor(themeId));

        for (const layout of resolved) {
            expect(layout).not.toBe(DefaultBillLayout);
        }

        // Each registered theme resolves to its OWN layout — no two share one.
        expect(new Set(resolved).size).toBe(registered.length);

        // The same object on every call, since it is a module-level constant,
        // so switching themes and resolving again never rebuilds the layout.
        for (const [i, themeId] of registered.entries()) {
            expect(billLayoutFor(themeId)).toBe(resolved[i]);
        }
    });

    it("falls back to DefaultBillLayout for themes without a registered layout", () => {
        const fallbackThemes: ThemeId[] = ["sway"];

        for (const themeId of fallbackThemes) {
            expect(billLayoutFor(themeId)).toBe(DefaultBillLayout);
        }
    });
});
