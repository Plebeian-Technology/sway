import { describe, expect, it } from "vitest";

import type { ThemeId } from "app/frontend/styles/themes";

import DefaultBillListLayout from "app/frontend/components/bill/list-layouts/DefaultBillListLayout";
import { billListLayoutFor } from "app/frontend/components/bill/list-layouts/index";

// @lat: [[theme-driven-bill-layout-selection#Testing billLayoutFor against lazy-wrapped layouts]]
describe("billListLayoutFor", () => {
    it("returns a distinct, stable per-theme list layout for themes that register one", () => {
        const registered: ThemeId[] = ["banner", "ballot", "cornerstore", "monochrome", "service-manual", "swiss-grid"];
        const resolved = registered.map((themeId) => billListLayoutFor(themeId));

        for (const layout of resolved) {
            expect(layout).not.toBe(DefaultBillListLayout);
        }
        expect(new Set(resolved).size).toBe(registered.length);
        for (const [index, themeId] of registered.entries()) {
            expect(billListLayoutFor(themeId)).toBe(resolved[index]);
        }
    });

    it("falls back to DefaultBillListLayout for themes without a registered layout", () => {
        const fallbackThemes: ThemeId[] = ["sway"];

        for (const themeId of fallbackThemes) {
            expect(billListLayoutFor(themeId)).toBe(DefaultBillListLayout);
        }
    });
});
