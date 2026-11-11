import { describe, expect, it } from "vitest";

import type { ThemeId } from "app/frontend/styles/themes";

import BallotHomeLayout from "app/frontend/components/home/layouts/BallotHomeLayout";
import BannerHomeLayout from "app/frontend/components/home/layouts/BannerHomeLayout";
import CornerstoreHomeLayout from "app/frontend/components/home/layouts/CornerstoreHomeLayout";
import DefaultHomeLayout from "app/frontend/components/home/layouts/DefaultHomeLayout";
import MonochromeHomeLayout from "app/frontend/components/home/layouts/MonochromeHomeLayout";
import ServiceManualHomeLayout from "app/frontend/components/home/layouts/ServiceManualHomeLayout";
import SwissGridHomeLayout from "app/frontend/components/home/layouts/SwissGridHomeLayout";
import { homeLayoutFor } from "app/frontend/components/home/layouts/index";

// @lat: [[home-layout-theme-concepts#Themed home layout design concepts]]
describe("homeLayoutFor", () => {
    it("returns the per-theme home layout for themes that register one", () => {
        expect(homeLayoutFor("banner")).toBe(BannerHomeLayout);
        expect(homeLayoutFor("ballot")).toBe(BallotHomeLayout);
        expect(homeLayoutFor("cornerstore")).toBe(CornerstoreHomeLayout);
        expect(homeLayoutFor("monochrome")).toBe(MonochromeHomeLayout);
        expect(homeLayoutFor("service-manual")).toBe(ServiceManualHomeLayout);
        expect(homeLayoutFor("swiss-grid")).toBe(SwissGridHomeLayout);
    });

    it("falls back to DefaultHomeLayout for themes without a registered layout", () => {
        const fallbackThemes: ThemeId[] = ["sway"];

        for (const themeId of fallbackThemes) {
            expect(homeLayoutFor(themeId)).toBe(DefaultHomeLayout);
        }
    });

    it("does not fall back to DefaultHomeLayout for dedicated readability theme layouts", () => {
        expect(homeLayoutFor("monochrome")).not.toBe(DefaultHomeLayout);
        expect(homeLayoutFor("service-manual")).not.toBe(DefaultHomeLayout);
        expect(homeLayoutFor("swiss-grid")).not.toBe(DefaultHomeLayout);
    });
});
